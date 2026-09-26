# frozen_string_literal: true

module CLM
  # Pick one option; the answer is a distribution over the +criteria+ keys.
  #
  #   CLM::Choice.new(instructions: "Which team should handle this?",
  #                   criteria: { billing: "Charges, invoices, refunds", technical: "Bugs and outages" })
  class Choice < Data.define(:instructions, :criteria)
    include Question

    TYPE = "choice"

    def initialize(criteria:, instructions: nil)
      unless criteria.is_a?(Hash) && !criteria.empty?
        raise InvalidRequestError, "choice question needs a non-empty 'criteria' object"
      end

      super(instructions:, criteria: criteria.transform_keys(&:to_s).freeze)
    end

    def keys
      criteria.keys
    end

    # The option's own text: its description when one is given, else its key.
    # Nothing is prefixed, so a candidate reaches the encoder exactly as written.
    def candidates
      criteria.map { |key, description| description.nil? || description == "" ? key : Text.render(description) }
    end

    def answer(probabilities)
      dist = distribution(probabilities)
      ChoiceAnswer.new(choice: dist.max_by { |_, p| p }.first,
                       confidence: Distribution.confidence(dist.values), probabilities: dist)
    end
  end
end
