# frozen_string_literal: true

RSpec.describe CLM::VectorCache do
  describe ".parse_budget" do
    it "reads a bare number as a fraction of memory" do
      expect([described_class.parse_budget("0.5", 1000), described_class.parse_budget(0.25, 1000)]).to eq([500, 250])
    end

    it "defaults to 2% of memory" do
      expect([described_class.parse_budget(nil, 1000), described_class.parse_budget("", 1000)]).to eq([20, 20])
    end

    it "reads sizes with decimal and binary units, case-insensitively" do
      expect(%w[512MiB 2GB 1.5kib 10b].map { described_class.parse_budget(_1) })
        .to eq([512 << 20, 2_000_000_000, 1536, 10])
    end

    it "treats 0 as off" do
      expect(described_class.parse_budget("0")).to eq(0)
      expect(described_class.build(0)).to be_nil
    end

    it "rejects fractions of 1 or more, unknown units and garbage" do
      expect { described_class.parse_budget("2") }.to raise_error(ArgumentError, /must be in \[0, 1\)/)
      expect { described_class.parse_budget("3TB") }.to raise_error(ArgumentError, /unknown size unit "TB"/)
      expect { described_class.parse_budget("lots") }.to raise_error(ArgumentError, /not a fraction/)
    end
  end

  describe "#reserve" do
    subject(:cache) { described_class.new(4 * 100) } # room for 100 floats

    it "carves rows of a width from a share of the budget" do
      pool = cache.reserve(10, 0.5)
      expect([pool.capacity, pool.dim]).to eq([5, 10])
    end

    it "never hands out more than the budget" do
      cache.reserve(10, 0.9)
      expect(cache.reserve(4, 0.9).capacity).to eq(2)
      expect(cache.reserve(3, 0.5)).to be_nil
    end

    it "returns the existing pool for a width" do
      expect(cache.reserve(10, 0.5)).to be(cache.reserve(10, 0.1))
    end
  end

  describe "#fetch" do
    subject(:cache) { described_class.new(4 * 2 * 3).tap { _1.reserve(2, 1.0) } } # 3 rows of 2

    let(:computed) { [] }

    def vectors_for(texts)
      computed << texts
      Numo::SFloat.cast(texts.map { |t| [t.ord, t.size] })
    end

    def fetch(texts, namespace: "head@1")
      cache.fetch(namespace, 2, texts) { vectors_for(_1) }
    end

    it "computes misses once, deduplicated, and serves hits from the cache" do
      expect(fetch(%w[a b a]).to_a).to eq([[97, 1], [98, 1], [97, 1]])
      expect(fetch(%w[b a]).to_a).to eq([[98, 1], [97, 1]])
      expect(computed).to eq([%w[a b]])
    end

    it "keys entries by namespace" do
      fetch(%w[a])
      fetch(%w[a], namespace: "head@2")
      expect(computed).to eq([%w[a], %w[a]])
    end

    it "evicts the least recently used row" do
      fetch(%w[a b c])
      fetch(%w[a])    # refresh a
      fetch(%w[d])    # evicts b
      fetch(%w[a c d])
      fetch(%w[b])
      expect(computed).to eq([%w[a b c], %w[d], %w[b]])
      expect(cache.pools[2].evictions).to eq(2)
    end

    it "answers without the cache when a request needs more rows than it holds" do
      expect(fetch(%w[a b c d]).to_a).to eq([[97, 1], [98, 1], [99, 1], [100, 1]])
      expect(computed.last).to eq(%w[a b c d])
    end

    it "bypasses widths without a pool" do
      expect(cache.fetch("h", 7, %w[x]) { :computed }).to eq(:computed)
    end

    it "reports hits, misses and occupancy" do
      fetch(%w[a b])
      fetch(%w[a])
      expect(cache.stats).to include(device: "cpu", hit_rate: 0.3333)
      expect(cache.stats[:pools]["2"]).to include(capacity: 3, used: 2, hits: 1, misses: 2, evictions: 0)
    end
  end
end
