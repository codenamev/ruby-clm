# frozen_string_literal: true

module CLM
  # The state head and action head of one checkpoint, hot-reloaded when the file changes.
  #
  # A CLM checkpoint (as trained by the upstream +train/finetune.py+) is a
  # +torch.save+ dict with +state_head+ / +action_head+ state dicts, +logit_scale+
  # (the log of the InfoNCE inverse temperature) and +cfg+ (+width+, +depth+,
  # optional +projection_dim+, +activation+, +layernorm+, +residual+).  The score of
  # a (state, candidate) pair is +scale * cos(state_head(s), action_head(c))+.
  class HeadPair
    MAX_SCALE = 100.0

    attr_reader :name, :path, :generation, :cfg

    def initialize(name, path)
      @name = name
      @path = path.to_s
      @mtime = nil
      @generation = 0 # bumped on every (re)load; stamps cached projections
      @mutex = Mutex.new
    end

    # Loads the checkpoint, or reloads it when the file changed since the last load.
    def ensure_loaded
      @mutex.synchronize do
        mtime = File.mtime(path)
        load! unless mtime == @mtime
        @mtime = mtime
      end
      self
    rescue Errno::ENOENT
      raise CheckpointError, "checkpoint #{path} does not exist"
    end

    def state_head = loaded(:@state_head)
    def action_head = loaded(:@action_head)
    def scale = loaded(:@scale)

    def projection_dim
      action_head.projection_dim
    end

    def hidden_size
      action_head.hidden_size
    end

    # L2-normalised projections of [n, hidden_size] state embeddings.
    def project_states(embeddings)
      normalize(state_head.call(embeddings))
    end

    # L2-normalised projections of [n, hidden_size] candidate embeddings.
    def project_actions(embeddings)
      normalize(action_head.call(embeddings))
    end

    # Identity of these exact weights, for cache keys.
    def namespace
      ensure_loaded
      "#{name}@#{generation}"
    end

    def n_params
      state_head.n_params + action_head.n_params
    end

    def self.normalize(x)
      norms = Numo::NMath.sqrt((x**2).sum(axis: -1, keepdims: true))
      x / norms.clip(1e-12, Float::INFINITY)
    end

    private

    def normalize(x) = self.class.normalize(x)

    def loaded(ivar)
      ensure_loaded
      instance_variable_get(ivar)
    end

    def load!
      checkpoint = TorchFile.load(path)
      cfg = checkpoint.fetch("cfg") { raise CheckpointError, "#{path} has no cfg" }.transform_keys(&:to_s)
      options = { depth: Integer(cfg.fetch("depth")), activation: cfg.fetch("activation", "gelu"),
                  layernorm: cfg.fetch("layernorm", false), residual: cfg.fetch("residual", false) }
      @state_head = Head.from_state_dict(checkpoint.fetch("state_head"), **options)
      @action_head = Head.from_state_dict(checkpoint.fetch("action_head"), **options)
      @scale = [Math.exp(scalar(checkpoint.fetch("logit_scale"))), MAX_SCALE].min
      @cfg = cfg
      @generation += 1
    rescue KeyError => e
      raise CheckpointError, "#{path} is not a CLM checkpoint: missing #{e.key.inspect}"
    end

    def scalar(value)
      Float(value.is_a?(Numo::NArray) ? value.to_a.flatten.first : value)
    end
  end
end
