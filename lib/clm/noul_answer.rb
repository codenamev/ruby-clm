# frozen_string_literal: true

module CLM
  # The answer to a Noul: +noul+ is the probability that the statement is true.
  class NoulAnswer < Data.define(:noul)
    include Answer

    TYPE = "noul"

    def probabilities
      { "false" => 1.0 - noul, "true" => noul }
    end

    def label
      true? ? "true" : "false"
    end

    # Whether the statement is more likely true than not.
    def true?
      noul >= 0.5
    end
    alias yes? true?
  end
end
