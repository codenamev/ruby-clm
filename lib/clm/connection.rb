# frozen_string_literal: true

require "json"
require "net/http"

module CLM
  # JSON over HTTP with retries and CLM's error mapping, on the standard library.
  #
  # Net::HTTP yields to the fiber scheduler, so requests made inside an Async reactor run
  # concurrently with no extra setup:
  #
  #   Sync do |task|
  #     tickets.map { |t| task.async { client.predict(t, questions) } }.map(&:wait)
  #   end
  #
  # The +transport+ is the seam for tests and in-process backends: anything answering
  # +call(method:, url:, headers:, body:, timeout:)+ with +[status, body, headers]+.
  class Connection
    Response = Data.define(:status, :body, :headers)

    NET_HTTP = lambda do |method:, url:, headers:, body:, timeout:|
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: timeout,
                                          read_timeout: timeout, write_timeout: timeout) do |http|
        request = (method == :get ? Net::HTTP::Get : Net::HTTP::Post).new(uri, headers)
        request.body = body if body
        response = http.request(request)
        [response.code.to_i, response.body.to_s, response.each_header.to_h]
      end
    end

    attr_reader :base_url, :retry_policy

    def initialize(base_url:, api_key: nil, timeout: 300, retry: nil, transport: NET_HTTP,
                   sleeper: ->(seconds) { sleep(seconds) }, random: -> { rand },
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @base_url = base_url.to_s.chomp("/")
      @headers = { "Content-Type" => "application/json", "Accept" => "application/json",
                   "User-Agent" => "ruby-clm/#{VERSION}" }
      @headers["Authorization"] = "Bearer #{api_key}" if api_key
      @timeout = timeout
      @retry_policy = RetryPolicy.from(binding.local_variable_get(:retry))
      @transport = transport
      @sleeper = sleeper
      @random = random
      @clock = clock
    end

    # +path+ is joined to the base URL, unless it is itself a full URL.
    def get(path, timeout: nil)
      request(:get, path, nil, timeout || @timeout)
    end

    def post(path, body)
      request(:post, path, JSON.generate(body), @timeout)
    end

    private

    def request(method, path, body, timeout)
      url = path.start_with?("http://", "https://") ? path : "#{base_url}#{path}"
      status, raw, headers = with_retries { @transport.call(method:, url:, headers: @headers, body:, timeout:) }
      response = Response.new(status:, body: parse(raw, headers), headers: headers.to_h)
      raise error_for(response) unless (200..299).cover?(status)

      response
    end

    def with_retries
      started = @clock.call
      (0..).each do |attempt|
        reply = yield
        return reply unless retry_policy.retryable_status?(reply[0]) && retry?(attempt, started)

        pause(attempt, reply[2])
      rescue StandardError => e
        raise transport_error(e) unless retry_policy.retryable_error?(e) && retry?(attempt, started)

        pause(attempt, {})
      end
    end

    def pause(attempt, headers)
      @sleeper.call(retry_policy.delay(attempt, headers: headers.to_h, random: @random))
    end

    def retry?(attempt, started)
      budget = retry_policy.total_timeout
      attempt < retry_policy.max_retries && (budget.nil? || @clock.call - started < budget)
    end

    def transport_error(error)
      return error if error.is_a?(CLM::Error)

      klass = retry_policy.timeout?(error) ? TimeoutError : ConnectionError
      klass.new("CLM server unreachable at #{base_url}: #{error.message} (#{error.class})")
    end

    def parse(raw, headers)
      type = headers.to_h.find { |name, _| name.to_s.casecmp?("content-type") }&.last.to_s
      type.include?("json") && !raw.empty? ? JSON.parse(raw) : raw
    rescue JSON::ParserError
      raw
    end

    def error_for(response)
      body = response.body
      message = body.is_a?(Hash) ? body.fetch("detail", body) : body
      APIError.for_status(response.status).new(message.to_s, status: response.status, response:)
    end
  end
end
