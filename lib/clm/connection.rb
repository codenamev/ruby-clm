# frozen_string_literal: true

require "faraday"
require "faraday/retry"

module CLM
  # A JSON-over-HTTP connection with retries and CLM's error mapping.
  #
  # The default adapter is Net::HTTP, which yields to the fiber scheduler, so many
  # requests made inside an Async reactor run concurrently with no extra setup:
  #
  #   Async do |task|
  #     tickets.map { |t| task.async { client.system_one(t, questions) } }.map(&:wait)
  #   end
  class Connection
    RETRY_EXCEPTIONS = [Faraday::ConnectionFailed, Faraday::RetriableResponse, Errno::ECONNREFUSED,
                        Errno::ECONNRESET].freeze
    RETRY_STATUSES = [503].freeze

    attr_reader :base_url

    def initialize(base_url:, api_key: nil, timeout: 300, max_retries: 2, retry_interval: 0.1,
                   adapter: Faraday.default_adapter)
      @base_url = base_url.to_s.chomp("/")
      @faraday = Faraday.new(@base_url) do |f|
        f.options.timeout = timeout
        f.headers["Authorization"] = "Bearer #{api_key}" if api_key
        f.request :json
        f.request :retry, max: max_retries, interval: retry_interval, backoff_factor: 2,
                          methods: %i[get post], exceptions: RETRY_EXCEPTIONS, retry_statuses: RETRY_STATUSES
        f.response :json, content_type: /\bjson$/
        f.adapter(*Array(adapter))
      end
    end

    def get(path, timeout: nil)
      request(:get, path, nil, timeout)
    end

    def post(path, body)
      request(:post, path, body, nil)
    end

    private

    def request(method, path, body, timeout)
      response = @faraday.run_request(method, path, body, nil) do |req|
        req.options.timeout = timeout if timeout
      end
      raise error_for(response) unless response.success?

      response
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
      raise ConnectionError, "CLM server unreachable at #{base_url}: #{e.message}"
    end

    def error_for(response)
      body = response.body
      message = body.is_a?(Hash) ? body.fetch("detail", body) : body
      APIError.for_status(response.status).new(message.to_s, status: response.status, response:)
    end
  end
end
