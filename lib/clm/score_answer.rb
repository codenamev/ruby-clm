# frozen_string_literal: true

module CLM
  # The answer to a Score: the expected level index (0..levels-1), how clearly the
  # likeliest level won, a legend of level index => rubric text, and the distribution.
  class ScoreAnswer < Data.define(:score, :confidence, :legend, :probabilities)
    include Answer

    TYPE = "score"

    # The rubric text of the likeliest level.
    def level
      legend[label]
    end
  end
end
