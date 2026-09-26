# frozen_string_literal: true

require "logger"
require "zeitwerk"

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

    def loader
      @loader ||= Zeitwerk::Loader.for_gem.tap do |loader|
        loader.inflector.inflect("clm" => "CLM", "cli" => "CLI")
      end
    end
  end
end

CLM.loader.setup
require_relative "clm/error"
