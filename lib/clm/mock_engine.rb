# frozen_string_literal: true

require "zlib"

module CLM
  # An engine with a fake encoder, for working on the playground without a GPU;
  # never for measuring anything.
  #
  # Texts are embedded as hashed character 3/4-grams and there is no projection
  # head, so the answers are lexical-overlap noise, not CLM predictions.  The
  # server reports +"mock": true+ on /health and the playground shows a warning
  # banner, so nobody mistakes a screenshot of it for a result.
  class MockEngine < Engine
    SCALE = 28.0

    # Character n-gram feature hashing, L2-normalised; deterministic across runs.
    class Embedder
      DIM = 512

      attr_reader :url

      def initialize(broken: false)
        @broken = broken
        @url = "mock://n-gram"
      end

      def embed(texts)
        if @broken
          raise EmbedderError, "embedder unreachable at #{Configuration::DEFAULT_EMBEDDER_URL}: " \
                               "Connection refused (this is the mock's --broken mode)"
        end

        vectors = Numo::SFloat.cast(texts.map { features(_1) })
        CLM::Embedder::Result.new(vectors:, tokens: texts.sum { [1, _1.size / 4].max })
      end

      def healthy?
        !@broken
      end

      private

      def features(text)
        counts = Array.new(DIM, 0.0)
        padded = " #{text.downcase.split.join(" ")} "
        [3, 4].each do |n|
          (0..(padded.size - n)).each { |i| counts[Zlib.crc32(padded[i, n]) % DIM] += 1 }
        end
        norm = Math.sqrt(counts.sum { _1 * _1 })
        norm.zero? ? counts : counts.map { _1 / norm }
      end
    end

    def initialize(broken: false)
      super(embedder: Embedder.new(broken:), checkpoint: nil, action_cache: 0,
            config: Configuration.new("CLM_CKPT_DIR" => File::NULL))
    end

    def mock?
      true
    end

    def models
      [ModelInfo.new(name: DEFAULT_MODEL, description: "MOCK — character n-grams, not a contrastive language model",
                     release_date: RELEASE),
       ModelInfo.new(name: RAW_MODEL, description: "MOCK — the same n-grams without the (absent) projection head",
                     release_date: RELEASE)]
    end

    def model?(name)
      [DEFAULT_MODEL, RAW_MODEL].include?(name)
    end

    private

    # Both models answer from the n-grams; the "raw" one flatter, like the real ablation.
    def resolve(model)
      return model if model?(model)

      raise ModelNotFoundError, "unknown model #{model.inspect}; available: #{models.map(&:name)}"
    end

    def vectors(model, states, candidates, &spent)
      [states, candidates].map do |texts|
        embedder.embed(texts).tap { spent.call(_1.tokens) }.vectors
      end.push(model == DEFAULT_MODEL ? SCALE : SCALE * 0.45)
    end
  end
end
