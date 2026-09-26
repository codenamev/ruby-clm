# frozen_string_literal: true

require "json"
require "logger"

require_relative "clm/version"
require_relative "clm/error"

# Contrastive Language Models: a System One model that scores candidate actions
# against a state.  Ask typed questions (noul / choice / score) and get answer
# distributions back, from a CLM server or from the in-process engine.
#
#   CLM.configure { |c| c.base_url = "http://127.0.0.1:8700" }
#
#   response = CLM.system_one("Customer: my invoice was charged twice!") do |q|
#     q.noul :urgency, "Is this urgent?"
#   end
#   response[:urgency].noul # => 0.41
module CLM
  class << self
    # Yields the global configuration for mutation.
    def configure
      yield config
    end

    def config
      @config ||= Configuration.new
    end

    # Restores every setting to its default (mostly useful in tests).
    def reset!
      @config = nil
    end

    # A new HTTP client for the CLM System One API.
    def client(**)
      Client.new(**)
    end

    # One request to the configured server: every question answered against +state+.
    def system_one(...)
      client.system_one(...)
    end

    # Rank free-form candidates against +context+ on the configured server.
    def rank(...)
      client.rank(...)
    end

    def logger
      config.logger
    end
  end

  # Plain Ruby, loaded up front.
  %w[configuration text distribution question noul choice score question_set answer noul_answer
     choice_answer score_answer usage system_one_response ranking model_info].each do |file|
    require_relative "clm/#{file}"
  end

  # Loaded on first use, so a client-only program never pays for Numo, rubyzip, Async or Rack.
  autoload :Connection, "clm/connection"
  autoload :Client, "clm/client"
  autoload :Concurrently, "clm/concurrently"
  autoload :Pickle, "clm/pickle"
  autoload :TorchFile, "clm/torch_file"
  autoload :Head, "clm/head"
  autoload :HeadPair, "clm/head_pair"
  autoload :Hub, "clm/hub"
  autoload :Embedder, "clm/embedder"
  autoload :VectorCache, "clm/vector_cache"
  autoload :Engine, "clm/engine"
  autoload :MockEngine, "clm/mock_engine"
  autoload :Server, "clm/server"
  autoload :CLI, "clm/cli"
end
