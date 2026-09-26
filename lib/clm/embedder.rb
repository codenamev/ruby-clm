# frozen_string_literal: true

require "base64"
require "numo/narray"

module CLM
  # The encoder side: an OpenAI-compatible /v1/embeddings endpoint (a vLLM pooling
  # server) plus an LRU cache of L2-normalised embeddings.
  #
  # The reference head expects Qwen3-8B with last-token pooling:
  #
  #   vllm serve Qwen/Qwen3-8B --served-model-name qwen3-8b --runner pooling \
  #        --enable-prefix-caching --max-model-len 2048 --port 8090
  #
  # Cache misses are sent in batches; the batches of one call run concurrently
  # (up to +concurrency+ at a time) as Async tasks.
  class Embedder
    # [n, hidden_size] L2-normalised embeddings, and the encoder tokens spent on cache misses.
    Result = Data.define(:vectors, :tokens)

    attr_reader :url, :model, :max_tokens, :batch_size, :cache_size

    def initialize(url: nil, model: nil, max_tokens: nil, cache_size: 200_000, batch_size: 32, concurrency: 4,
                   api_key: nil, timeout: nil, config: CLM.config)
      @url = url || config.embedder_url
      @model = model || config.embedder_model
      @max_tokens = max_tokens || config.embedder_max_tokens
      @cache_size = cache_size
      @batch_size = batch_size
      @concurrency = concurrency
      @connection = Connection.new(base_url: @url, api_key: api_key || config.embedder_api_key,
                                   timeout: timeout || config.request_timeout, retry: config.retry_policy)
      @cache = {}
      @mutex = Mutex.new
    end

    def embed(texts)
      vectors = {}
      misses = lookup(texts, vectors)
      tokens = fetch_all(misses).sum do |chunk, embedded, spent|
        store(chunk, embedded, vectors)
        spent
      end
      Result.new(vectors: stack(texts.map { vectors.fetch(_1) }), tokens:)
    end

    # Whether the embedding server answers GET /v1/models.
    def healthy?
      @connection.get(url.sub(%r{/v1/.*\z}, "/v1/models"), timeout: 5)
      true
    rescue Error
      false
    end

    def cached
      @mutex.synchronize { @cache.size }
    end

    def self.normalize(vector)
      vector / (Math.sqrt((vector**2).sum) + 1e-12)
    end

    private

    # Fills +vectors+ with cache hits (refreshing their recency); returns the unique misses.
    def lookup(texts, vectors)
      @mutex.synchronize do
        texts.uniq.reject do |text|
          next false unless @cache.key?(text)

          vectors[text] = @cache[text] = @cache.delete(text)
        end
      end
    end

    def store(chunk, embedded, vectors)
      @mutex.synchronize do
        chunk.zip(embedded) { |text, vector| vectors[text] = @cache[text] = vector }
        @cache.delete(@cache.first.first) while @cache.size > cache_size
      end
    end

    def fetch_all(texts)
      Concurrently.map(texts.each_slice(batch_size).to_a, limit: @concurrency) { fetch(_1) }
    end

    # -> [texts, [normalised vector per text], prompt tokens]
    def fetch(texts)
      body = { model:, input: texts, encoding_format: "base64", truncate_prompt_tokens: max_tokens }.compact
      json = @connection.post("", body).body
      [texts, vectors_from(json, texts.size), Integer(json.dig("usage", "prompt_tokens") || 0)]
    rescue APIError => e
      raise EmbedderError, "embedder error #{e.status}: #{e.message.delete_prefix("#{e.status}: ")[0, 300]}"
    rescue ConnectionError => e
      raise EmbedderError, "embedder unreachable at #{url}: #{e.message}"
    rescue KeyError, TypeError, NoMethodError => e
      raise EmbedderError, "embedder at #{url} sent a malformed response: #{e.message}"
    end

    def vectors_from(json, count)
      vectors = Array.new(count)
      json.fetch("data").each { vectors[_1.fetch("index")] = self.class.normalize(decode(_1.fetch("embedding"))) }
      return vectors if vectors.none?(&:nil?)

      raise EmbedderError, "embedder at #{url} returned #{vectors.compact.size} of #{count} embeddings"
    end

    def decode(embedding)
      if embedding.is_a?(String)
        Numo::SFloat.from_binary(Base64.decode64(embedding))
      else
        Numo::SFloat.cast(embedding)
      end
    end

    def stack(vectors)
      return Numo::SFloat.zeros(0, 0) if vectors.empty?

      Numo::SFloat.vstack(vectors.map { _1.reshape(1, _1.size) })
    end
  end
end
