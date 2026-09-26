# frozen_string_literal: true

module CLM
  class VectorCache
    # One width of vector inside the cache: a fixed number of rows, least recently
    # used first out.  Not thread-safe on its own; VectorCache holds the lock.
    class Pool
      attr_reader :dim, :capacity, :hits, :misses, :evictions

      def initialize(rows, dim)
        @buffer = Numo::SFloat.zeros(rows, dim)
        @dim = dim
        @capacity = rows
        @slots = {} # key => row, in recency order
        @free = (0...rows).to_a.reverse
        @hits = @misses = @evictions = 0
      end

      # Refreshes the keys that are present; returns the missing ones as {key => text}.
      def lookup(texts, keys)
        missing = {}
        texts.zip(keys) do |text, key|
          if (slot = @slots.delete(key))
            @slots[key] = slot
            @hits += 1
          elsif !missing.key?(key)
            missing[key] = text
          end
        end
        @misses += missing.size
        missing
      end

      def store(keys, vectors)
        keys.each_with_index { |key, i| @buffer[claim(key), true] = vectors[i, true] }
      end

      # A copy of the rows for +keys+, or nil if any of them is no longer cached.
      def rows(keys)
        slots = keys.map { @slots[_1] }
        return if slots.include?(nil)

        @buffer[slots, true].dup
      end

      def used
        @slots.size
      end

      def stats
        asked = hits + misses
        { dim:, capacity:, used:, reserved_mb: (capacity * dim * ITEM_SIZE / 1e6).round(1), hits:, misses:,
          evictions:, hit_rate: asked.positive? ? (hits.to_f / asked).round(4) : nil }
      end

      private

      def claim(key)
        slot = @slots.delete(key)
        slot ||= @free.pop
        unless slot
          lru_key, slot = @slots.first
          @slots.delete(lru_key)
          @evictions += 1
        end
        @slots[key] = slot
      end
    end
  end
end
