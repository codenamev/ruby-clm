# frozen_string_literal: true

require "net/http"
require "openssl"
require "time"

module CLM
  # When and how long to wait before retrying a request, following ruby_decision_model's policy
  # (and through it the Typesafe SDKs): two retries after the first attempt, exponential backoff
  # from 0.5s capped at 5s with up to 25% jitter taken off, Retry-After honoured up to 60s.
  #
  # Unlike that policy there is no total budget by default: a CLM request that ranks thousands
  # of candidates against a cold encoder can legitimately take longer than 30 seconds.
  #
  #   CLM::Client.new(retry: { max_retries: 5, total_timeout: 60 })
  class RetryPolicy < Data.define(:max_retries, :backoff_initial, :backoff_max, :backoff_jitter, :http_statuses,
                                  :respect_retry_after, :max_retry_after, :retry_connection_errors,
                                  :retry_timeouts, :total_timeout)
    DEFAULT_STATUSES = ([408, 429] + (500..599).to_a).freeze
    TIMEOUT_EXCEPTIONS = [Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout].freeze
    CONNECTION_EXCEPTIONS = [Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ECONNABORTED, Errno::EHOSTUNREACH,
                             Errno::ENETUNREACH, Errno::EPIPE, SocketError, IOError, OpenSSL::SSL::SSLError].freeze

    def initialize(max_retries: 2, backoff_initial: 0.5, backoff_max: 5.0, backoff_jitter: 0.25,
                   http_statuses: DEFAULT_STATUSES, respect_retry_after: true, max_retry_after: 60.0,
                   retry_connection_errors: true, retry_timeouts: true, total_timeout: nil)
      super
      validate!
    end

    # A RetryPolicy, a Hash of overrides, or nil for the defaults.
    def self.from(value)
      case value
      when RetryPolicy then value
      when nil then new
      when Hash then new(**value.transform_keys(&:to_sym))
      else raise ConfigurationError, "retry must be a RetryPolicy or a Hash of overrides, got #{value.class}"
      end
    end

    def retryable_status?(status)
      http_statuses.include?(status)
    end

    def timeout?(error)
      TIMEOUT_EXCEPTIONS.any? { error.is_a?(_1) }
    end

    def connection_failure?(error)
      CONNECTION_EXCEPTIONS.any? { error.is_a?(_1) }
    end

    def retryable_error?(error)
      return retry_timeouts if timeout?(error)

      connection_failure?(error) && retry_connection_errors
    end

    # Seconds to wait before retry number +attempt+ (0 for the first retry): the server's
    # Retry-After when it sent one, otherwise the jittered backoff.  +random+ returns 0...1.
    def delay(attempt, headers: {}, random: -> { rand })
      hinted = retry_after(headers) if respect_retry_after
      return [hinted, max_retry_after].min if hinted

      base = [backoff_initial * (2**attempt), backoff_max].min
      [base * (1.0 - (backoff_jitter * random.call)), 0.0].max
    end

    # retry-after-ms (preferred) or Retry-After, in seconds or as an HTTP date; nil when absent.
    def retry_after(headers)
      headers = headers.to_h { |name, value| [name.to_s.downcase, Array(value).first] }
      milliseconds = Float(headers["retry-after-ms"], exception: false)
      return milliseconds / 1000.0 if milliseconds&.>=(0)

      seconds_from(headers["retry-after"])
    end

    private

    def seconds_from(value)
      return if value.nil?

      seconds = Float(value, exception: false)
      return seconds if seconds&.>=(0)

      [Time.httpdate(value) - Time.now, 0.0].max
    rescue ArgumentError
      nil
    end

    def validate!
      problem = retries_problem || durations_problem || jitter_problem
      raise ConfigurationError, problem if problem
    end

    def retries_problem
      "max_retries must be a non-negative Integer, got #{max_retries.inspect}" unless
        max_retries.is_a?(Integer) && max_retries >= 0
    end

    def durations_problem
      durations = { backoff_initial:, backoff_max:, max_retry_after:, total_timeout: total_timeout || 0 }
      name, value = durations.find { |_, duration| !duration?(duration) }
      "#{name} must be a finite non-negative number, got #{value.inspect}" if name
    end

    def jitter_problem
      "backoff_jitter must be between 0 and 1, got #{backoff_jitter.inspect}" unless
        duration?(backoff_jitter) && backoff_jitter <= 1
    end

    def duration?(value)
      value.is_a?(Numeric) && value.finite? && value >= 0
    end
  end
end
