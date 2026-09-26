# frozen_string_literal: true

require "numo/narray"

require_relative "vector_cache/pool"

module CLM
  # A memory budget reserved up front for the vectors an agent loop keeps asking about.
  #
  # An agent asks about a changing state but a mostly fixed set of actions, and it
  # often revisits states it has already seen.  Neither their embeddings nor their
  # projections change while the head does not, so they are worth keeping rather
  # than recomputing on every request.
  #
  # The budget is claimed once at start-up, the way vLLM claims its KV cache: a
  # fraction of memory (+0.02+) or an absolute size (+512MiB+).  Pools of different
  # widths are carved out of it (512-d projections for the heads, 4096-d encoder
  # embeddings for the raw ablation), and nothing grows afterwards, so a
  # long-running server cannot drift into an out-of-memory kill.
  #
  # Entries are keyed by a namespace and the text.  The namespace names the head
  # and its generation, so several heads share one cache, and a head that
  # hot-reloads simply stops matching rows its previous weights produced;
  # least-recently-used eviction reclaims them.
  class VectorCache
    DEFAULT_BUDGET = "0.02"
    # Host memory assumed for fractional budgets: a CPU cache is still bounded, it just
    # cannot ask a device driver how much there is.
    ASSUMED_MEMORY = 8 << 30
    ITEM_SIZE = 4 # float32
    UNITS = { "" => 1, "B" => 1, "KB" => 10**3, "MB" => 10**6, "GB" => 10**9,
              "KIB" => 1 << 10, "MIB" => 1 << 20, "GIB" => 1 << 30 }.freeze

    # +0.02+ -> 2% of +total_bytes+; +"512MiB"+ / +"2GB"+ -> that many bytes; +0+ -> off.
    def self.parse_budget(spec, total_bytes = ASSUMED_MEMORY)
      spec = DEFAULT_BUDGET if spec.nil? || spec == ""
      return fraction_of(spec.to_f, total_bytes) if spec.is_a?(Numeric)

      match = /\A\s*(\d*\.?\d+)\s*([A-Za-z]*)\s*\z/.match(spec.to_s) or
        raise ArgumentError, "cache budget #{spec.inspect} is not a fraction (0.02) or a size (512MiB)"
      value = Float(match[1])
      unit = match[2].upcase
      return fraction_of(value, total_bytes) if unit.empty?

      multiplier = UNITS.fetch(unit) do
        raise ArgumentError, "unknown size unit #{match[2].inspect}; use B, KB, MB, GB, KiB, MiB or GiB"
      end
      (value * multiplier).to_i
    end

    def self.fraction_of(value, total_bytes)
      unless (0...1).cover?(value)
        raise ArgumentError, "a bare number is a fraction of memory and must be in [0, 1); " \
                             "give a unit (512MiB) for an absolute size"
      end

      (value * total_bytes).to_i
    end
    private_class_method :fraction_of

    # A cache for +budget+, or nil when the budget is zero.
    def self.build(budget = nil)
      bytes = parse_budget(budget)
      new(bytes) if bytes.positive?
    end

    attr_reader :reserved_bytes, :pools

    def initialize(reserved_bytes)
      @reserved_bytes = reserved_bytes
      @capacity = reserved_bytes / ITEM_SIZE # floats
      @claimed = 0
      @pools = {}
      @mutex = Mutex.new
    end

    def reserved_mb
      (@capacity * ITEM_SIZE / 1e6).round(1)
    end

    # Carves +share+ of the budget into rows of +dim+.  Call at start-up, once per
    # width; returns nil when not even one row fits.
    def reserve(dim, share)
      @mutex.synchronize do
        next @pools[dim] if @pools.key?(dim)

        rows = [(@capacity * share).floor, @capacity - @claimed].min / dim
        next if rows < 1

        @claimed += rows * dim
        @pools[dim] = Pool.new(rows, dim)
      end
    end

    # [texts.size, dim] vectors for +texts+ in +namespace+; the block computes the
    # misses (unique, in order) as a [misses, dim] array.  Widths without a pool
    # bypass the cache.
    def fetch(namespace, dim, texts, &compute)
      pool = @pools[dim] or return compute.call(texts)

      keys = texts.map { "#{namespace}\0#{_1}" }
      missing = @mutex.synchronize { pool.lookup(texts, keys) }
      unless missing.empty?
        vectors = compute.call(missing.values) # outside the lock: this is the slow path
        @mutex.synchronize { pool.store(missing.keys, vectors) }
      end
      # A concurrent request may have evicted a row since it was filled; if so,
      # answer without the cache rather than with someone else's vector.
      @mutex.synchronize { pool.rows(keys) } || compute.call(texts)
    end

    def stats
      pools = @mutex.synchronize { @pools.sort.to_h { |dim, pool| [dim.to_s, pool.stats] } }
      asked = pools.values.sum { _1[:hits] + _1[:misses] }
      hits = pools.values.sum { _1[:hits] }
      { device: "cpu", reserved_mb:, hit_rate: asked.positive? ? (hits.to_f / asked).round(4) : nil, pools: }
    end
  end
end
