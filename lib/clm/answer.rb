# frozen_string_literal: true

module CLM
  # Behaviour shared by the typed answers (NoulAnswer, ChoiceAnswer and ScoreAnswer).
  module Answer
    # Parses a wire-format answer hash.
    def self.from_h(hash)
      hash = hash.transform_keys(&:to_s)
      case hash["type"].to_s
      when "noul" then NoulAnswer.new(noul: Float(hash.fetch("noul")))
      when "choice" then ChoiceAnswer.new(choice: hash.fetch("choice"), confidence: Float(hash.fetch("confidence")),
                                          probabilities: probabilities_from(hash))
      when "score" then ScoreAnswer.new(score: Float(hash.fetch("score")), confidence: Float(hash.fetch("confidence")),
                                        legend: hash.fetch("legend", {}).transform_keys(&:to_s),
                                        probabilities: probabilities_from(hash))
      else raise Error, "unknown answer type #{hash["type"].inspect}"
      end
    end

    def self.probabilities_from(hash)
      hash.fetch("probabilities").to_h { |key, p| [key.to_s, Float(p)] }
    end
    private_class_method :probabilities_from

    def type
      self.class::TYPE
    end

    # The wire format, with +type+ first as the server writes it.
    def to_h
      { type:, **super }
    end

    # The most likely option key: the choice, the likeliest score level, or "true"/"false".
    def label
      probabilities.max_by { |_, p| p }.first
    end
  end
end
