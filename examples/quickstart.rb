# frozen_string_literal: true

# Ask typed questions about a state, against a running clm-serve.
#
#   bundle exec ruby examples/quickstart.rb   # CLM_BASE_URL defaults to http://127.0.0.1:8700

require "clm"

client = CLM::Client.new

response = client.system_one("Customer: my invoice was charged twice and nobody answers the phone!") do |q|
  q.noul :urgency, "Is this urgent?"
  q.choice :department, "Which team should handle this?",
           billing: "Charges, invoices, refunds", technical: "Bugs and outages"
  q.score :frustration, "How frustrated is the customer?", ["Calm", "Frustrated", "Very angry"]
end

puts response[:urgency].noul                # probability the statement is true
puts response[:department].choice           # "billing"
p response[:department].probabilities       # {"billing" => 0.93878, "technical" => 0.06122}
puts response[:frustration].score           # expected level, 0..2
puts response[:frustration].level           # the likeliest level's rubric text
puts "#{response.usage.input_tokens} tokens in #{response.latency_ms} ms"

# The same request as TypeSafe-style wire hashes replays unchanged:
client.system_one("The build is red again.", { flaky: { type: "noul", instructions: "Is this a flaky test?" } })

# Rank free-form candidates: best-of-N answers, tool names, next moves.
client.rank("What causes tides on Earth?",
            ["The Moon's gravitational pull.", "Photosynthesis in plants.", "Because the Earth is round."])
      .each { |r| puts "#{r.rank}. #{r.candidate} (#{r.prob.round(3)})" }
