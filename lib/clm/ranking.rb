# frozen_string_literal: true

module CLM
  # One candidate's place in a ranking: 1-based +rank+, the +candidate+ text and its probability.
  class Ranking < Data.define(:rank, :candidate, :prob)
    def self.from_h(hash)
      hash = hash.transform_keys(&:to_s)
      new(rank: Integer(hash.fetch("rank")), candidate: hash.fetch("candidate"), prob: Float(hash.fetch("prob")))
    end
  end
end
