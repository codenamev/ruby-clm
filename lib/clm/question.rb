# frozen_string_literal: true

module CLM
  # Behaviour shared by the three typed questions (Noul, Choice and Score).
  #
  # A question turns into one state text for the state head (the state with the
  # question's instructions appended) and a closed set of candidate texts for the
  # action head.  A softmax over CLM's per-candidate scores is the answer.
  module Question
    # Coerces +question+ (a Noul / Choice / Score, or a wire-format hash with a
    # +type+ key) into a question object.
    def self.wrap(question)
      case question
      when Question then question
      when Hash then from_h(question)
      else raise InvalidRequestError, "a question must be a Noul, Choice, Score or Hash, got #{question.class}"
      end
    end

    def self.from_h(hash)
      hash = hash.transform_keys(&:to_s)
      klass = types.fetch(hash["type"].to_s) do
        raise InvalidRequestError, "unknown question type #{hash["type"].inspect}; expected one of #{types.keys}"
      end
      klass.new(instructions: hash["instructions"], criteria: hash["criteria"])
    end

    def self.types
      { "noul" => Noul, "choice" => Choice, "score" => Score }
    end

    def type
      self.class::TYPE
    end

    # The wire format, as TypeSafe's POST /v1/systemone expects it.
    def to_h
      { type:, instructions:, criteria: }
    end

    # What the state head sees: context first, the question last.
    def state_text(state)
      Text.state(state, instructions)
    end

    # The option keys, in answer order.
    def keys
      raise NotImplementedError
    end

    # One text per option key, for the action head.
    def candidates
      raise NotImplementedError
    end

    # The typed answer for per-option +probabilities+ (aligned with #keys).
    def answer(probabilities)
      raise NotImplementedError
    end

    def answer_from_logits(logits)
      answer(Distribution.softmax(logits.map(&:to_f)))
    end

    private

    def instructions_text
      Text.render(instructions).strip
    end

    def distribution(probabilities)
      keys.zip(probabilities.map(&:to_f)).to_h
    end
  end
end
