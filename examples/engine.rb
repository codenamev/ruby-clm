# frozen_string_literal: true

# The in-process engine: no clm-serve, just the Qwen3-8B encoder and a head.
#
#   vllm serve Qwen/Qwen3-8B --served-model-name qwen3-8b --runner pooling --max-model-len 2048 --port 8090
#   bundle exec ruby examples/engine.rb   # downloads the reference head on first run

require "clm"

engine = CLM::Engine.new(checkpoint: CLM::Hub.download)

engine.rank("What causes tides on Earth?", ["The Moon's gravitational pull.", "Photosynthesis in plants."])
      .each { |r| puts "#{r.rank}. #{r.candidate} (#{r.prob.round(3)})" }

answer = engine.system_one({ ticket: "Refund still missing after 3 weeks", plan: "enterprise" }) do |q|
  q.choice :next_step, "What should support do next?",
           escalate: "Escalate to a billing specialist", refund: "Issue the refund now",
           wait: "Ask the customer to wait"
end
puts answer[:next_step].choice
