# frozen_string_literal: true

require "json"
require "rack"

module CLM
  # The CLM System One API as a Rack application.
  #
  #   POST /v1/systemone  {"state", "model", "questions": {id: Question}, "temperature"}
  #                       -> {"model", "answers": {id: Answer}, "usage"}
  #   POST /v1/rank       {"context", "question", "answers": [...]} -> {"model", "ranked": [...]}
  #   GET  /v1/models     -> {"models": [{"name", "description", "release_date"}]}
  #   GET  /health        -> {"ok": true, ...}
  #
  # Question and answer objects follow the TypeSafe wire schema, so a request
  # written for TypeSafe replays here unchanged.  Errors are +{"detail": ...}+ with
  # 401 (bad key), 422 (malformed request or unknown model) or 502 (embedder down).
  #
  #   # config.ru
  #   run CLM::Server.new(CLM::Engine.new, api_key: ENV["CLM_API_KEY"])
  class Server
    LATENCY_HEADER = "x-clm-latency-ms"
    JSON_HEADERS = { "content-type" => "application/json" }.freeze
    CORS_HEADERS = {
      "access-control-allow-origin" => "*", "access-control-allow-methods" => "GET, POST, OPTIONS",
      "access-control-allow-headers" => "*", "access-control-expose-headers" => "X-CLM-Latency-Ms"
    }.freeze
    ROUTES = {
      "/health" => { "GET" => :health },
      "/v1/models" => { "GET" => :models },
      "/v1/systemone" => { "POST" => :system_one },
      "/v1/rank" => { "POST" => :rank }
    }.freeze

    # An error response: +status+ with +{"detail": detail}+.
    class Halt < StandardError
      attr_reader :status

      def initialize(status, detail)
        @status = status
        super(detail)
      end
    end

    attr_reader :engine

    # +cors+ allows browser requests from any origin.  It is off by default: an API
    # key travels in a header the browser would then be free to send from any page.
    def initialize(engine, api_key: nil, cors: false)
      @engine = engine
      @api_key = api_key
      @cors = cors
    end

    def call(env)
      request = Rack::Request.new(env)
      return [204, cors_headers, []] if @cors && request.options?

      status, headers, body = dispatch(request)
      [status, JSON_HEADERS.merge(cors_headers, headers), [JSON.generate(body)]]
    rescue Halt => e
      [e.status, JSON_HEADERS.merge(cors_headers), [JSON.generate(detail: e.message)]]
    end

    private

    def dispatch(request)
      methods = ROUTES.fetch(request.path_info) { raise Halt.new(404, "Not Found") }
      handler = methods.fetch(request.request_method) { raise Halt.new(405, "Method Not Allowed") }
      send(handler, request)
    end

    def cors_headers
      @cors ? CORS_HEADERS : {}
    end

    def health(_request)
      body = { ok: true, embedder: engine.healthy?, models: engine.models.map(&:name), cache: engine.cache&.stats }
      body[:mock] = true if engine.respond_to?(:mock?) && engine.mock?
      [200, {}, body]
    end

    def models(request)
      authorize!(request)
      [200, {}, { models: engine.models.map(&:to_h) }]
    end

    def system_one(request)
      authorize!(request)
      body = json_body(request)
      unless body.is_a?(Hash) && body.key?("state") && body["questions"].is_a?(Hash)
        raise Halt.new(422, "body must be {state, model, questions}")
      end

      timed do
        engine.system_one(body["state"], body["questions"], model: body["model"] || Engine::DEFAULT_MODEL,
                                                            temperature: temperature(body)).to_h
      end
    end

    def rank(request)
      authorize!(request)
      body = json_body(request)
      answers = rank_answers(body)
      model = body["model"] || Engine::DEFAULT_MODEL
      timed do
        ranked = engine.rank(body["context"] || "", answers, question: body["question"], model:,
                                                             temperature: temperature(body))
        { model:, ranked: ranked.map(&:to_h) }
      end
    end

    def rank_answers(body)
      answers = body["answers"] if body.is_a?(Hash)
      raise Halt.new(422, "body must be {context, question, answers: [..]}") unless answers.is_a?(Array) && answers.any?
      raise Halt.new(422, "answers must be non-empty strings") unless answers.all? { _1.is_a?(String) && !_1.empty? }

      answers
    end

    def authorize!(request)
      return unless @api_key
      return if Rack::Utils.secure_compare(request.get_header("HTTP_AUTHORIZATION").to_s, "Bearer #{@api_key}")

      raise Halt.new(401, "invalid API key")
    end

    def json_body(request)
      JSON.parse(request.body.read)
    rescue JSON::ParserError => e
      raise Halt.new(422, "body is not JSON: #{e.message}")
    end

    def temperature(body)
      Float(body.fetch("temperature", 1.0))
    rescue ArgumentError, TypeError
      raise Halt.new(422, "temperature must be a number")
    end

    # Runs the engine, maps its errors to statuses and stamps the server-side latency.
    def timed
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      body = yield
      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
      [200, { LATENCY_HEADER => format("%.1f", elapsed) }, body]
    rescue ModelNotFoundError => e
      raise Halt.new(422, e.message)
    rescue InvalidRequestError => e
      raise Halt.new(422, "invalid request: #{e.message}")
    rescue EmbedderError => e
      raise Halt.new(502, e.message)
    end
  end
end
