# frozen_string_literal: true

module CLM
  # A yes/no question; the answer is the probability that the statement is true.
  #
  #   CLM::Noul.new(instructions: "Is this urgent?")
  #   CLM::Noul.new(instructions: "Is this spam?", criteria: { true: "Unsolicited ads", false: "A real message" })
  class Noul < Data.define(:instructions, :criteria)
    include Question

    TYPE = "noul"
    KEYS = %w[false true].freeze

    def initialize(instructions: nil, criteria: nil)
      criteria = criteria.transform_keys(&:to_s).freeze if criteria.is_a?(Hash)
      super
    end

    def to_h
      criteria.nil? || criteria.empty? ? { type:, instructions: } : super
    end

    def keys
      KEYS
    end

    # Each side is embedded as "true: ..." / "false: ...", with the statement
    # itself as the description when none is given.
    def candidates
      KEYS.map { |key| "#{key}: #{Text.render(description(key))}" }
    end

    def answer(probabilities)
      NoulAnswer.new(noul: distribution(probabilities).fetch("true"))
    end

    private

    def description(key)
      given = criteria[key] if criteria.is_a?(Hash)
      return given unless given.nil? || given == ""
      return key if instructions_text.empty?

      key == "true" ? "Yes. This is true: #{instructions_text}" : "No. This is false: #{instructions_text}"
    end
  end
end
