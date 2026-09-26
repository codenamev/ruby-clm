# frozen_string_literal: true

module CLM
  # A model a CLM server (or engine) can answer with, as listed by GET /v1/models.
  class ModelInfo < Data.define(:name, :description, :release_date)
    def self.from_h(hash)
      hash = hash.transform_keys(&:to_s)
      new(name: hash.fetch("name"), description: hash["description"], release_date: hash["release_date"])
    end
  end
end
