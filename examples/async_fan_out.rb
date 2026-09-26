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

client = CLM::Client.new
triage = CLM::QuestionSet.build do |q|
  q.noul :urgent, "Is this urgent?"
  q.choice :team, "Which team should handle this?",
           billing: "Charges, invoices, refunds", technical: "Bugs, crashes and outages", sales: "Plans and upgrades"
end

Sync do
  barrier = Async::Barrier.new
  semaphore = Async::Semaphore.new(8, parent: barrier) # at most 8 requests in flight

  results = TICKETS.map do |ticket|
    semaphore.async { [ticket, client.system_one(ticket, triage)] }
  end.map(&:wait)

  results.each do |ticket, response|
    flag = response[:urgent].true? ? "URGENT" : "      "
    puts "#{flag} #{response[:team].choice.ljust(9)} #{ticket}"
  end
ensure
  barrier.stop
end
