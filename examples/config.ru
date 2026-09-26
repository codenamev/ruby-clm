# frozen_string_literal: true

# Serve the API with any Rack server:
#
#   bundle exec falcon serve --bind http://localhost:8700 --config examples/config.ru
#   bundle exec rackup examples/config.ru -p 8700
#
# clm-serve does the same with flags; this is for hosting CLM inside your own stack.

require "clm"

engine = CLM::Engine.new(checkpoint: ENV.fetch("CLM_CKPT") { CLM::Hub.download })
run CLM::Server.new(engine, api_key: ENV.fetch("CLM_API_KEY", nil))
