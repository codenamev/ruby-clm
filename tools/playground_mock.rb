#!/usr/bin/env ruby
# frozen_string_literal: true

# Run the playground without a GPU: for working on the UI, not for measuring anything.
#
# This serves the real CLM::Server (so the routes, the static files and the answer
# schema are exactly what clm-serve exposes) against a fake encoder: character
# n-gram feature hashing instead of Qwen3-8B, and no projection head.  The server
# reports {"mock": true} on /health and the page shows a warning banner.
#
#   bundle exec ruby tools/playground_mock.rb --port 8700   # then open http://localhost:8700/
#   bundle exec ruby tools/playground_mock.rb --broken      # pretend the encoder is down (502s)
#
# For real answers, serve the encoder and run clm-serve; see the README.

require "optparse"
require_relative "../lib/clm"

options = { host: "127.0.0.1", port: 8700, broken: false, cors: false }
OptionParser.new do |opts|
  opts.banner = "Usage: tools/playground_mock.rb [options]"
  opts.on("--host HOST") { options[:host] = _1 }
  opts.on("--port PORT", Integer) { options[:port] = _1 }
  opts.on("--broken", "simulate an unreachable encoder (502s)") { options[:broken] = true }
  opts.on("--cors") { options[:cors] = true }
end.parse!

app = CLM::Server.new(CLM::MockEngine.new(broken: options[:broken]), api_key: ENV.fetch("CLM_API_KEY", nil),
                                                                     cors: options[:cors])
puts "[mock] FAKE ENCODER — numbers are meaningless; playground at http://#{options[:host]}:#{options[:port]}/"
CLM::CLI::Serve::FALCON.call(app, host: options[:host], port: options[:port])
