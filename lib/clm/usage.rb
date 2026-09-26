# frozen_string_literal: true

module CLM
  # What a request cost: one billing unit per question, and the encoder tokens
  # spent on texts that were not already cached.
  class Usage < Data.define(:billing_units, :input_tokens, :output_tokens)
    def initialize(billing_units: 0, input_tokens: nil, output_tokens: nil)
      super
    end

    def self.from_h(hash)
      hash = (hash || {}).transform_keys(&:to_s)
      new(billing_units: Integer(hash["billing_units"] || 0), input_tokens: hash["input_tokens"],
          output_tokens: hash["output_tokens"])
    end
  end
end
