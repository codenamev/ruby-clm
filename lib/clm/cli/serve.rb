# frozen_string_literal: true

require "async"
require "optparse"

module CLM
  module CLI
    # clm-serve: the System One API and playground on Falcon.
    #
    #   clm-serve --port 8700 --emb-url http://127.0.0.1:8090/v1/embeddings
    #   export CLM_API_KEY=...   # optional; then requests need "Authorization: Bearer <key>"
    class Serve
      # Starts +app+ on Falcon inside the current Async reactor and returns the
      # server task; many servers (or clients) can share one reactor.
      def self.start(app, host:, port:)
        require "falcon"
        require "async/http/endpoint"
        endpoint = Async::HTTP::Endpoint.parse("http://#{host}:#{port}")
        Falcon::Server.new(Falcon::Server.rack_middleware(app, cache: false), endpoint).run
      end

      # Stops a server task by stopping what it waits on (its accept loops, and
      # their connections), so it finishes on its own instead of being cancelled
      # mid-wait.
      def self.stop(task)
        task.children.each(&:stop) if task.children?
        task.wait
      end

      # Runs +app+ on Falcon until interrupted.
      FALCON = ->(app, host:, port:) { Sync { start(app, host:, port:).wait } }

      attr_reader :options

      def initialize(argv, env: ENV, out: $stdout, launcher: FALCON)
        @argv = argv
        @env = env
        @out = out
        @launcher = launcher
        @config = Configuration.new(env)
        @options = defaults
      end

      def run
        parse!
        engine = build_engine
        app = Server.new(engine, api_key: @env["CLM_API_KEY"], cors: options[:cors], ui: options[:ui])
        banner(engine)
        @launcher.call(app, host: options[:host], port: options[:port])
      rescue Interrupt
        log "stopped"
      end

      def parse!
        parser.parse!(@argv)
        self
      end

      def build_engine
        checkpoint = options[:checkpoint] || (Hub.download(dest_dir: @config.checkpoint_dir) if options[:download])
        embedder = Embedder.new(url: options[:emb_url], model: options[:emb_model], max_tokens: options[:max_tokens],
                                config: @config)
        engine = Engine.new(embedder:, checkpoint:, checkpoint_dir: options[:checkpoint_dir], models: options[:models],
                            action_cache: options[:action_cache], config: @config)
        return engine unless engine.heads.empty?

        raise Error, "no checkpoint: pass --ckpt or let clm-serve download the reference head"
      end

      private

      def defaults
        { host: "0.0.0.0", port: Integer(@env.fetch("CLM_PORT", 8700)), emb_url: @config.embedder_url,
          emb_model: @config.embedder_model, max_tokens: @config.embedder_max_tokens, checkpoint: @config.checkpoint,
          checkpoint_dir: nil, models: {}, action_cache: @config.action_cache, download: true, ui: true, cors: false }
      end

      def parser # rubocop:disable Metrics/AbcSize -- one line per flag
        OptionParser.new do |opts|
          opts.banner = "Usage: clm-serve [options]\n\nServe the CLM System One API (and its playground) on Falcon.\n\n"
          opts.on("--host HOST", "interface to bind (default: 0.0.0.0)") { options[:host] = _1 }
          opts.on("--port PORT", Integer, "port (default: 8700, CLM_PORT)") { options[:port] = _1 }
          opts.on("--emb-url URL", "the encoder's /v1/embeddings endpoint (CLM_EMB_URL)") { options[:emb_url] = _1 }
          opts.on("--emb-model NAME", "the encoder's served model name (CLM_EMB_MODEL)") { options[:emb_model] = _1 }
          opts.on("--max-tokens N", Integer, "truncate texts to N tokens before embedding (the encoder's " \
                                             "max-model-len; CLM_EMB_MAX_TOKENS)") { options[:max_tokens] = _1 }
          opts.on("--ckpt PATH", "checkpoint served as clm-latest (default: the reference head in " \
                                 "#{@config.checkpoint_dir}, downloaded if missing; CLM_CKPT)") do |path|
            options[:checkpoint] = path
          end
          opts.on("--ckpt-dir DIR", "also serve every *.pt in DIR under its file stem") do |dir|
            options[:checkpoint_dir] = dir
          end
          opts.on("--model NAME=PATH", "serve an extra checkpoint as NAME (repeatable)") { add_model(_1) }
          opts.on("--action-cache BUDGET", "memory reserved at start-up for reused state and action vectors: a " \
                                           "fraction (0.02, the default) or a size (512MiB); 0 disables it " \
                                           "(CLM_ACTION_CACHE)") { options[:action_cache] = _1 }
          opts.on("--no-download", "fail instead of downloading the reference head") { options[:download] = false }
          opts.on("--no-ui", "do not serve the playground at /") { options[:ui] = false }
          opts.on("--cors", "allow browser requests from any origin (needed to drive this server from a " \
                            "playground served elsewhere)") { options[:cors] = true }
        end
      end

      def add_model(spec)
        name, path = spec.split("=", 2)
        raise OptionParser::InvalidArgument, "--model expects NAME=PATH, got #{spec.inspect}" if path.to_s.empty?

        options[:models][name] = path
      end

      def banner(engine)
        log "models #{engine.models.map(&:name)} on cpu"
        log "embedder #{options[:emb_url]} (#{options[:emb_model]}) " \
            "#{engine.healthy? ? "up" : "NOT REACHABLE"}; auth #{@env["CLM_API_KEY"] ? "on" : "off"}"
        log cache_line(engine.cache)
        log "POST http://#{options[:host]}:#{options[:port]}/v1/systemone"
        log "playground http://#{display_host}:#{options[:port]}/" if options[:ui]
      end

      def cache_line(cache)
        return "vector cache off" unless cache

        pools = cache.stats[:pools].values.map { "#{delimit(_1[:capacity])}x#{_1[:dim]}d" }
        "vector cache #{cache.reserved_mb} MB reserved on cpu (#{pools.join(" + ")})"
      end

      def delimit(number)
        number.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
      end

      def display_host
        ["0.0.0.0", "::"].include?(options[:host]) ? "localhost" : options[:host]
      end

      def log(message)
        @out.puts "[clm] #{message}"
        @out.flush
      end
    end
  end
end
