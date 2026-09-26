# frozen_string_literal: true

module CLM
  # The answer to a Choice: the likeliest option key, how clearly it won, and the
  # full distribution over option keys.
  class ChoiceAnswer < Data.define(:choice, :confidence, :probabilities)
    include Answer

    TYPE = "choice"

    def label
      choice
    end
  end
end
