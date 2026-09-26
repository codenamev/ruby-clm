# frozen_string_literal: true

module CLM
  # The answers to one System One request, keyed by the caller's question ids.
  #
  #   response[:department].choice   # => "billing"
  #   response.usage.input_tokens    # => 38
  class SystemOneResponse < Data.define(:model, :answers, :usage, :latency_ms)
    def initialize(model:, answers:, usage: Usage.new, latency_ms: nil)
      super
    end

    def [](id)
      answers[id]
    end

    def to_h
      { model:, answers: answers.to_h { |id, answer| [id.to_s, answer.to_h] }, usage: usage.to_h }
    end
  end
end
