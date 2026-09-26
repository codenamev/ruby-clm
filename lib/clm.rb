# frozen_string_literal: true

require "json"
require "logger"

require_relative "clm/version"
require_relative "clm/error"

# Contrastive Language Models: a System One model that scores candidate actions against a
# state.  Ask typed questions (noul / choice / score) and get answer distributions back, from
# a CLM server or from the in-process engine.
#
#   CLM.configure { |c| c.base_url = "http://127.0.0.1:8700" }
#
#   class TicketTriage < CLM::Decision
#     noul :urgent, "Is this urgent?"
#     choice :department, "Which team should handle this?", billing: "invoices", technical: "outages"
#   end
#
#   TicketTriage.decide("Customer: my invoice was charged twice!").urgent? # => false
#   CLM.ask(email).noul(:refund, "Do they want money back?").decide[:refund].probability
module CLM
  class << self
    # Yields the global configuration for mutation; the shared client is rebuilt from it.
    def configure
      yield config
      @client = nil
    end

    def config
      @config ||= Configuration.new
    end

    # Restores every setting to its default (mostly useful in tests).
    def reset!
      @config = nil
      @client = nil
    end

    # The shared client: +config.client+ when one is set (an {Engine}, a {Client}, or anything
    # answering +predict(state, questions, **options)+), else a {Client} for +config.base_url+.
    def client
      @client ||= config.client || Client.new(config:)
    end

    # Questions about +state+, built inline and answered by {Ask#decide}.
    #
    #   CLM.ask(email).noul(:refund, "Do they want money back?").decide[:refund].probability
    def ask(state, **)
      Ask.new(state, **)
    end

    # Every question answered against +state+ by the shared client.
    def predict(...)
      client.predict(...)
    end

    # Rank free-form candidates against +context+ with the shared client.
    def rank(...)
      client.rank(...)
    end

    def logger
      config.logger
    end
  end

  # Plain Ruby, loaded up front.
  %w[configuration text distribution questions question answer usage result ranking model_info decision
     ask].each do |file|
    require_relative "clm/#{file}"
  end

  # Loaded on first use, so a client-only program never pays for Numo, rubyzip, Async or Rack.
  autoload :RetryPolicy, "clm/retry_policy"
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
