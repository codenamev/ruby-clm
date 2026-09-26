# frozen_string_literal: true

module CLM
  # HTTP client for the CLM System One API, shaped like TypeSafe's SDK.
  #
  #   client = CLM::Client.new # CLM_BASE_URL (default http://127.0.0.1:8700), CLM_API_KEY
  #
  #   response = client.system_one("Customer: my invoice was charged twice!") do |q|
  #     q.noul :urgency, "Is this urgent?"
  #     q.choice :department, "Which team should handle this?",
  #              billing: "Charges, invoices, refunds", technical: "Bugs and outages"
  #   end
  #   response[:department].choice # => "billing"
  #
  # The in-process CLM::Engine answers the same calls without a server.
  class Client
    LATENCY_HEADER = "X-CLM-Latency-Ms"

    attr_reader :model, :connection

    def initialize(base_url: nil, api_key: nil, model: nil, timeout: nil, config: CLM.config, **connection_options)
      @model = model || config.model
      @connection = Connection.new(
        base_url: base_url || config.base_url, api_key: api_key || config.api_key,
        timeout: timeout || config.request_timeout, max_retries: config.max_retries,
        retry_interval: config.retry_interval, **connection_options
      )
    end

    # Every question answered against one +state+ (a string, hash or array), in one request.
    #
    # +questions+ is a hash of id => question (Noul / Choice / Score objects or
    # wire-format hashes) and/or a QuestionSet builder block.  +temperature+
    # (server default 1.0) flattens (> 1) or sharpens (< 1) the distributions.
    def system_one(state, questions = nil, model: nil, temperature: nil, &)
      set = QuestionSet.coerce(questions, &)
      body = { state:, model: model || self.model, questions: set.to_h, temperature: }.compact
      response = connection.post("/v1/systemone", body)
      json = response.body
      SystemOneResponse.new(
        model: json.fetch("model"),
        answers: set.rekey(json.fetch("answers").transform_values { Answer.from_h(_1) }),
        usage: Usage.from_h(json["usage"]),
        latency_ms: response.headers[LATENCY_HEADER]&.to_f
      )
    end

    # Ranks free-form +answers+ against +context+ (plus an optional +question+), best first.
    def rank(context, answers, question: nil, model: nil, temperature: nil)
      body = { context:, question:, answers: Array(answers), model: model || self.model, temperature: }.compact
      connection.post("/v1/rank", body).body.fetch("ranked").map { Ranking.from_h(_1) }
    end

    def models
      connection.get("/v1/models").body.fetch("models").map { ModelInfo.from_h(_1) }
    end

    # Whether the server answers /health with ok (never raises).
    def healthy?
      connection.get("/health", timeout: 5).body.then { _1.is_a?(Hash) && _1["ok"] == true }
    rescue Error
      false
    end
  end
end
