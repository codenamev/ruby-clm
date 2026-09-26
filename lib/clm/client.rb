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
    LATENCY_HEADER = "x-clm-latency-ms"

    attr_reader :model, :connection

    def initialize(base_url: nil, api_key: nil, model: nil, timeout: nil, config: CLM.config, **connection_options)
      @model = model || config.model
      @connection = Connection.new(
        base_url: base_url || config.base_url, api_key: api_key || config.api_key,
        timeout: timeout || config.request_timeout, retry: config.retry_policy, **connection_options
      )
    end

    # Every question answered against one +state+ (a string, hash or array), in one request.
    #
    # +questions+ maps ids to wire-format questions, as {Questions} builds them.  This is the
    # same +predict(state, questions, **options)+ a ruby-laya client answers, so anything that
    # drives one drives the other.  +temperature+ (server default 1.0) flattens (> 1) or
    # sharpens (< 1) the distributions.
    def predict(state, questions, model: nil, temperature: nil)
      asked = Question.build_all(questions)
      body = { state:, model: model || self.model, temperature:,
               questions: asked.to_h { |id, question| [id.to_s, question.to_h] } }.compact
      response = connection.post("/v1/systemone", body)
      Result.new(model: response.body.fetch("model"), answers: answers_for(asked, response.body.fetch("answers")),
                 usage: Usage.from_h(response.body["usage"]), latency_ms: response.headers[LATENCY_HEADER]&.to_f)
    end
    alias system_one predict

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

    private

    # Server answers keyed by the caller's own ids, so a question asked as :urgency answers as :urgency.
    def answers_for(asked, answers)
      asked.to_h { |id, _| [id, Answer.from_h(answers.fetch(id.to_s))] }
    rescue KeyError => e
      raise Error, "the server did not answer #{e.key.inspect}"
    end
  end
end
