# frozen_string_literal: true

# Ask typed questions about a state, against a running clm-serve.
#
#   bundle exec ruby examples/quickstart.rb   # CLM_BASE_URL defaults to http://127.0.0.1:8700

require "clm"

# Declare a decision once, ask it of every state.
class TicketTriage < CLM::Decision
  noul :urgent, "Is this urgent?"
  choice :department, "Which team should handle this?",
         billing: "Charges, invoices, refunds", technical: "Bugs and outages"
  score :frustration, "How frustrated is the customer?", levels: ["Calm", "Frustrated", "Very angry"]
end

triage = TicketTriage.decide("Customer: my invoice was charged twice and nobody answers the phone!")

puts triage.urgent?                          # the statement is more likely true than not
puts triage.urgent.probability               # probability the statement is true
puts triage.department == :billing           # a choice stands in for its label
p triage.department.probabilities            # {"billing" => 0.93878, "technical" => 0.06122}
puts triage.frustration.score                # expected level, 0..2
puts triage.frustration.label                # the most likely level's rubric text
puts "#{triage.usage.input_tokens} encoder tokens in #{triage.result.latency_ms} ms"

# Questions not worth a class:
refund = CLM.ask("Please just send the money back.").noul(:refund, "Do they want money back?").decide
puts refund[:refund].probability

# Rank free-form candidates: best-of-N answers, tool names, next moves.
CLM.rank("What causes tides on Earth?",
         ["The Moon's gravitational pull.", "Photosynthesis in plants.", "Because the Earth is round."])
   .each { |r| puts "#{r.rank}. #{r.candidate} (#{r.prob.round(3)})" }
