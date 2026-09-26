# frozen_string_literal: true

module CLM
  # One typed question, validated, with the texts the heads see and the answer it produces.
  #
  # A question arrives in the wire format, with String or Symbol keys:
  #
  #   { "type" => "choice", "instructions" => "...", "criteria" => { "billing" => "invoices" } }
  #   { type: :score, instructions: "...", criteria: ["not urgent", "soon", "urgent"] }
  #   { type: :noul, instructions: "..." }
  #
  # Each type knows its option keys, the candidate text per option for the action head, and how
  # to turn a distribution over those options into its {Answer}, so nothing downstream switches
  # on the type again.
  class Question
    attr_reader :id, :instructions, :criteria

    def self.types
      { "noul" => Noul, "choice" => Choice, "score" => Score }
    end

    # The question +definition+ describes; raises InvalidRequestError when it cannot be answered.
    def self.build(id, definition)
      return definition if definition.is_a?(Question)
      unless definition.is_a?(Hash)
        raise InvalidRequestError, "question #{id.inspect}: definition must be a Hash, got #{definition.class}"
      end

      definition = definition.transform_keys(&:to_s)
      klass = types.fetch(definition["type"].to_s) do
        raise InvalidRequestError, "question #{id.inspect}: unknown question type #{definition["type"].inspect}; " \
                                   "expected one of #{types.keys}"
      end
      klass.new(id, definition["instructions"], definition["criteria"])
    end

    # Every question of a request, keyed as the caller keyed them.
    def self.build_all(questions)
      unless questions.respond_to?(:each_pair)
        raise InvalidRequestError, "questions must be a Hash of id => question, got #{questions.class}"
      end
      raise InvalidRequestError, "questions must not be empty" if questions.empty?

      questions.to_h { |id, definition| [id, build(id, definition)] }
    end

    def initialize(id, instructions, criteria)
      @id = id
      @instructions = instructions
      @criteria = normalize(criteria)
    end

    def type
      self.class::TYPE
    end

    # The wire format, as POST /v1/systemone takes it.
    def to_h
      { "type" => type, "instructions" => instructions, "criteria" => criteria }.compact
    end

    # What the state head sees: context first, the question last.
    def state_text(state)
      Text.state(state, instructions)
    end

    def keys = raise(NotImplementedError)
    def candidates = raise(NotImplementedError)
    def answer(probabilities) = raise(NotImplementedError)

    def answer_from_logits(logits)
      answer(Distribution.softmax(logits.map(&:to_f)))
    end

    private

    def normalize(criteria) = criteria

    def instructions_text
      Text.render(instructions).strip
    end

    def distribution(probabilities)
      keys.zip(probabilities.map(&:to_f)).to_h
    end

    # The probability that a statement holds.  Each side is embedded as "true: ..." /
    # "false: ...", with the statement itself as the description when none is given.
    class Noul < Question
      TYPE = "noul"
      KEYS = %w[false true].freeze

      def keys = KEYS

      def candidates
        KEYS.map { |key| "#{key}: #{Text.render(description(key))}" }
      end

      def answer(probabilities)
        Answer::Noul.new(probability: distribution(probabilities).fetch("true"))
      end

      private

      def normalize(criteria)
        criteria.to_h { |key, value| [key.to_s, value] }.freeze if criteria.is_a?(Hash) && !criteria.empty?
      end

      def description(key)
        given = criteria[key] if criteria
        return given unless given.nil? || given == ""
        return key if instructions_text.empty?

        key == "true" ? "Yes. This is true: #{instructions_text}" : "No. This is false: #{instructions_text}"
      end
    end

    # One label from a set.  The action head embeds each option's own text: its description
    # when one is given, else its key, so a candidate reaches the encoder exactly as written.
    class Choice < Question
      TYPE = "choice"

      def keys = criteria.keys

      def candidates
        criteria.map { |key, description| description.nil? || description == "" ? key : Text.render(description) }
      end

      def answer(probabilities)
        dist = distribution(probabilities)
        Answer::Choice.new(choice: dist.max_by { |_, p| p }.first, probabilities: dist,
                           confidence: Distribution.confidence(dist.values))
      end

      private

      def normalize(criteria)
        criteria = criteria.to_h { |label| [label, nil] } if criteria.is_a?(Array)
        unless criteria.is_a?(Hash) && !criteria.empty?
          raise InvalidRequestError, "question #{id.inspect}: choice question needs a non-empty 'criteria' object"
        end

        criteria.to_h { |key, value| [key.to_s, value] }.freeze
      end
    end

    # A position on ordered levels, lowest first; the answer is the expected level.
    class Score < Question
      TYPE = "score"

      def keys = criteria.each_index.map(&:to_s)
      def candidates = criteria.map { Text.render(_1) }

      def answer(probabilities)
        dist = distribution(probabilities)
        Answer::Score.new(score: dist.values.each_with_index.sum { |p, level| p * level }, legend:,
                          probabilities: dist, confidence: Distribution.confidence(dist.values))
      end

      # Level index => rubric text.
      def legend
        keys.zip(criteria.map { _1.is_a?(String) ? _1 : Text.render(_1) }).to_h
      end

      private

      def normalize(criteria)
        unless criteria.is_a?(Array) && criteria.size >= 2
          raise InvalidRequestError,
                "question #{id.inspect}: score question needs 'criteria' as an ordered list of >= 2 levels"
        end

        criteria.dup.freeze
      end
    end
  end
end
