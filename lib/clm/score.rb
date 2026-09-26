# frozen_string_literal: true

module CLM
  # Rate on an ordered rubric; the answer is the expected level plus a distribution.
  #
  #   CLM::Score.new(instructions: "How frustrated is the customer?",
  #                  criteria: ["Calm", "Frustrated", "Very angry"])
  class Score < Data.define(:instructions, :criteria)
    include Question

    TYPE = "score"

    def initialize(criteria:, instructions: nil)
      unless criteria.is_a?(Array) && criteria.size >= 2
        raise InvalidRequestError, "score question needs 'criteria' as an ordered list of >= 2 levels"
      end

      super(instructions:, criteria: criteria.dup.freeze)
    end

    def keys
      criteria.each_index.map(&:to_s)
    end

    def candidates
      criteria.map { Text.render(_1) }
    end

    def answer(probabilities)
      dist = distribution(probabilities)
      ScoreAnswer.new(score: dist.values.each_with_index.sum { |p, level| p * level },
                      confidence: Distribution.confidence(dist.values), legend:, probabilities: dist)
    end

    # Level index => rubric text.
    def legend
      keys.zip(criteria.map { _1.is_a?(String) ? _1 : Text.render(_1) }).to_h
    end
  end
end
