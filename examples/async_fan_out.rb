# frozen_string_literal: true

# CLM is a System One model: answers come back in milliseconds, so an agent asks
# many of them.  Client calls yield to the fiber scheduler, so inside an Async
# reactor they run concurrently with no threads and no extra configuration.

require "async"
require "async/barrier"
require "async/semaphore"
require "clm"

TICKETS = [
  "My card was charged twice for the same order.",
  "The app crashes whenever I open settings.",
  "Can I upgrade to the team plan mid-cycle?",
  "Password reset emails never arrive."
].freeze

class Triage < CLM::Decision
  noul :urgent, "Is this urgent?"
  choice :team, "Which team should handle this?",
         billing: "Charges, invoices, refunds", technical: "Bugs, crashes and outages", sales: "Plans and upgrades"
end

Sync do
  barrier = Async::Barrier.new
  semaphore = Async::Semaphore.new(8, parent: barrier) # at most 8 requests in flight

  decisions = TICKETS.map { |ticket| semaphore.async { [ticket, Triage.decide(ticket)] } }.map(&:wait)

  decisions.each do |ticket, triage|
    puts "#{triage.urgent? ? "URGENT" : "      "} #{triage.team.to_s.ljust(9)} #{ticket}"
  end
ensure
  barrier.stop
end
