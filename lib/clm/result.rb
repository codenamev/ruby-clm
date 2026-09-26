# frozen_string_literal: true

module CLM
  # Everything one request produced: an answer per question, keyed by the ids the caller
  # asked with, plus the model that answered, the token usage and (from a server) the latency.
  #
  #   result[:department]     # => #<CLM::Answer::Choice billing 93.9%>
  #   result["department"]    # the same answer: symbol and string ids are interchangeable
  #   result.department       # and so is reading it as a method
  class Result
    include Enumerable

    attr_reader :model, :answers, :usage, :latency_ms

    def initialize(answers:, model: nil, usage: Usage.new, latency_ms: nil)
      @answers = answers
      @model = model
      @usage = usage
      @latency_ms = latency_ms
    end

    # The answer to +id+, asked under a symbol or a string.
    def [](id)
      answers.fetch(id) do
        answers.fetch(id.to_s) do
          answers.fetch(id.to_s.to_sym) do
            raise KeyError, "no question #{id.inspect} in this result; asked: #{answers.keys.inspect}"
          end
        end
      end
    end

    # Answers are readable by name: +result.department+ is +result[:department]+.
    def method_missing(name, *args)
      return super unless args.empty? && answered?(name)

      self[name]
    end

    def respond_to_missing?(name, include_private = false)
      answered?(name) || super
    end

    def answered?(id)
      [id, id.to_s, id.to_s.to_sym].any? { answers.key?(_1) }
    end

    def each(&)
      answers.each(&)
    end

    def input_tokens = usage.input_tokens

    # The wire payload POST /v1/systemone returns.
    def to_h
      { "model" => model, "answers" => answers.to_h { |id, answer| [id.to_s, answer.to_h] },
        "usage" => usage.to_h.transform_keys(&:to_s) }
    end

    def to_json(*)
      to_h.to_json(*)
    end

    def inspect
      "#<CLM::Result #{answers.map { |id, answer| "#{id}=#{answer}" }.join(" ")}>"
    end
  end
end
