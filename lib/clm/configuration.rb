# frozen_string_literal: true

module CLM
  # Global settings, seeded from the same environment variables the Python
  # package reads so that a deployment configures both the same way.
  #
  #   CLM.configure do |config|
  #     config.base_url = "https://clm.internal"
  #     config.api_key  = ENV.fetch("CLM_API_KEY")
  #   end
  class Configuration
    DEFAULT_BASE_URL = "http://127.0.0.1:8700"
    DEFAULT_MODEL = "clm-latest"
    DEFAULT_EMBEDDER_URL = "http://127.0.0.1:8090/v1/embeddings"
    DEFAULT_EMBEDDER_MODEL = "qwen3-8b"
    DEFAULT_EMBEDDER_MAX_TOKENS = 2048

    # Client
    attr_accessor :base_url, :api_key, :model, :request_timeout, :max_retries, :retry_interval
    # Engine / server
    attr_accessor :embedder_url, :embedder_model, :embedder_max_tokens, :embedder_api_key,
                  :checkpoint, :checkpoint_dir, :action_cache
    attr_writer :logger

    def initialize(env = ENV)
      @base_url = env.fetch("CLM_BASE_URL", DEFAULT_BASE_URL)
      @api_key = env["CLM_API_KEY"]
      @model = DEFAULT_MODEL
      @request_timeout = 300
      @max_retries = 2
      @retry_interval = 0.1

      @embedder_url = env.fetch("CLM_EMB_URL", DEFAULT_EMBEDDER_URL)
      @embedder_model = env.fetch("CLM_EMB_MODEL", DEFAULT_EMBEDDER_MODEL)
      @embedder_max_tokens = Integer(env.fetch("CLM_EMB_MAX_TOKENS", DEFAULT_EMBEDDER_MAX_TOKENS))
      @embedder_api_key = env["CLM_EMB_API_KEY"]
      @checkpoint = env["CLM_CKPT"]
      @checkpoint_dir = env.fetch("CLM_CKPT_DIR") { File.join(Dir.home, ".cache", "clm") }
      @action_cache = env["CLM_ACTION_CACHE"]
      @log_level = env.fetch("CLM_LOG_LEVEL", "info")
    end

    def logger
      @logger ||= Logger.new($stderr, level: @log_level, progname: "clm")
    end
  end
end
