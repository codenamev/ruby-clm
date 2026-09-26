# frozen_string_literal: true

module CLM
  # The inference engine: a state plus typed questions in, answer distributions
  # out, no HTTP server needed.  It answers the same calls as CLM::Client.
  #
  #   engine = CLM::Engine.new # embedder at CLM_EMB_URL, the reference head
  #   engine.predict(state, { ok: CLM::Questions.noul("Is this fine?") })[:ok].probability
  #   engine.rank("What causes tides?", ["The Moon's gravity.", "Photosynthesis."])
  #
  # For each question the state (with the question's instructions appended) goes
  # through the state head and every option's text through the action head; the
  # softmax over +scale * cosine+ is the answer.  +clm-raw+ skips the heads
  # (cosine in the encoder's own space) as an ablation.
  class Engine
    DEFAULT_MODEL = "clm-latest"
    RAW_MODEL = "clm-raw"
    RAW_SCALE = 100.0
    RAW_SHARE = 0.125 # of the vector cache, for the raw ablation's wider vectors
    RELEASE = "2026-09-19"
    DESCRIPTIONS = {
      DEFAULT_MODEL => "Contrastive language model: Qwen3-8B encoder + trained projection heads",
      RAW_MODEL => "Ablation: cosine in the raw encoder embedding space, no projection head"
    }.freeze

    attr_reader :embedder, :heads, :cache

    # +checkpoint+ is served as clm-latest (default: CLM_CKPT, else the downloaded
    # reference head); every *.pt in +checkpoint_dir+ is served under its file stem;
    # +models+ adds {name => path} more.  +action_cache+ is the vector cache budget
    # (see VectorCache.parse_budget; 0 turns it off).
    def initialize(embedder: nil, checkpoint: nil, checkpoint_dir: nil, models: {}, action_cache: nil,
                   config: CLM.config)
      @embedder = embedder || Embedder.new(config:)
      @heads = load_heads(checkpoint || Hub.default_checkpoint(config), checkpoint_dir, models)
      @cache = reserve(action_cache || config.action_cache)
    end

    def models
      names = [(DEFAULT_MODEL if heads.key?(DEFAULT_MODEL)), *(heads.keys - [DEFAULT_MODEL]).sort, RAW_MODEL]
      names.compact.map do |name|
        description = DESCRIPTIONS.fetch(name) { "Projection-head checkpoint #{File.basename(heads[name].path)}" }
        ModelInfo.new(name:, description:, release_date: RELEASE)
      end
    end

    def model?(name)
      name == RAW_MODEL || heads.key?(name)
    end

    # Every question answered against one +state+; see Client#predict.
    def predict(state, questions, model: nil, temperature: nil)
      model ||= DEFAULT_MODEL
      temperature = validate_temperature(temperature || 1.0)
      head = resolve(model)
      set = Question.build_all(questions)
      tokens = 0
      state_vectors, candidate_vectors, scale = vectors(head, set.map { |_, q| q.state_text(state) },
                                                        set.flat_map { |_, q| q.candidates }) { tokens += _1 }
      Result.new(model:, answers: score(set, state_vectors, candidate_vectors, scale / temperature),
                 usage: Usage.new(billing_units: set.size, input_tokens: tokens, output_tokens: 0))
    end
    alias system_one predict

    # Ranks free-form +answers+ against +context+ (plus an optional +question+),
    # best first.  The state head sees +context + question+, the action head sees
    # each answer verbatim.
    def rank(context, answers, question: nil, model: nil, temperature: nil)
      answers = Array(answers)
      choice = Questions.choice(question, answers.each_with_index.to_h { |a, i| [i.to_s, a] })
      probabilities = predict(context, { rank: choice }, model:, temperature:)[:rank].probabilities
      probabilities.sort_by { |_, p| -p }.each_with_index.map do |(index, prob), position|
        Ranking.new(rank: position + 1, candidate: answers[Integer(index)], prob:)
      end
    end

    def healthy?
      embedder.healthy?
    end

    private

    def load_heads(checkpoint, checkpoint_dir, models)
      heads = {}
      heads[DEFAULT_MODEL] = HeadPair.new(DEFAULT_MODEL, checkpoint) if checkpoint
      directory_checkpoints(checkpoint_dir, except: checkpoint).each do |path|
        heads[File.basename(path, ".pt")] ||= HeadPair.new(File.basename(path, ".pt"), path)
      end
      models.each { |name, path| heads[name.to_s] = HeadPair.new(name.to_s, path) }
      heads.each_value(&:ensure_loaded)
    end

    def directory_checkpoints(dir, except:)
      return [] unless dir

      Dir[File.join(dir, "*.pt")].reject { except && File.expand_path(_1) == File.expand_path(except) }
    end

    # Claims the vector cache up front, so its cost is paid at start-up or not at all.
    # Projections get most of it; the raw ablation's much wider vectors get an eighth.
    def reserve(budget)
      cache = VectorCache.build(budget) or return
      heads.values.map(&:projection_dim).uniq.sort.each do |dim|
        cache.reserve(dim, dim == raw_dim ? RAW_SHARE : 1.0 - RAW_SHARE)
      end
      cache.reserve(raw_dim, RAW_SHARE) # clm-raw works in the encoder's own space
      cache
    end

    def raw_dim
      @raw_dim ||= heads.values.first&.hidden_size || Head::HIDDEN_SIZE
    end

    def resolve(model)
      return if model == RAW_MODEL

      heads.fetch(model) do
        raise ModelNotFoundError, "unknown model #{model.inspect}; available: #{models.map(&:name)}"
      end.ensure_loaded
    end

    def validate_temperature(temperature)
      temperature = Float(temperature)
      return temperature if temperature.positive? && temperature <= 100

      raise InvalidRequestError, "temperature must be in (0, 100]"
    rescue ArgumentError, TypeError
      raise InvalidRequestError, "temperature must be a number"
    end

    # State and candidate vectors, from the cache where possible.  The two sides
    # are embedded concurrently; +spent+ is called with the tokens of each miss.
    def vectors(head, states, candidates, &spent)
      sides = if head
                [["#{head.namespace}/state", head.method(:project_states), states],
                 ["#{head.namespace}/action", head.method(:project_actions), candidates]]
              else
                [["raw/state", nil, states], ["raw/action", nil, candidates]]
              end
      dim = head ? head.projection_dim : raw_dim
      Concurrently.map(sides) { |namespace, project, texts| cached(namespace, dim, texts, project, &spent) }
                  .push(head ? head.scale : RAW_SCALE)
    end

    def cached(namespace, dim, texts, project, &spent)
      compute = lambda do |missing|
        result = embedder.embed(missing)
        spent.call(result.tokens)
        project ? project.call(result.vectors) : result.vectors
      end
      cache ? cache.fetch(namespace, dim, texts, &compute) : compute.call(texts)
    end

    def score(set, state_vectors, candidate_vectors, scale)
      offset = 0
      set.each_with_index.to_h do |(id, question), i|
        count = question.candidates.size
        cosines = candidate_vectors[offset...(offset + count), true].dot(state_vectors[i, true])
        offset += count
        [id, question.answer_from_logits((cosines * scale).to_a)]
      end
    end
  end
end
