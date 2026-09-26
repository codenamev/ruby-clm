# frozen_string_literal: true

RSpec::Matchers.define_negated_matcher :not_output, :output

RSpec.describe CLM::Concurrently do
  it "maps in order" do
    expect(described_class.map([3, 1, 2]) { _1 * 10 }).to eq([30, 10, 20])
  end

  it "runs the items concurrently" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    described_class.map([0.05] * 4) { sleep(_1) }
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 0.15
  end

  it "limits how many run at once" do
    running = peak = 0
    described_class.map([0.01] * 6, limit: 2) do |delay|
      peak = [peak, running += 1].max
      sleep(delay)
      running -= 1
    end
    expect(peak).to eq(2)
  end

  it "raises the first failure in the caller without logging the others" do
    expect { described_class.map([1, 2, 3]) { raise ArgumentError, "bad #{_1}" if _1 > 1 } }
      .to raise_error(ArgumentError, "bad 2")
      .and(not_output(/unhandled exception/).to_stderr_from_any_process)
  end

  it "reuses the caller's reactor" do
    Sync do |task|
      expect(described_class.map([1, 2]) { Async::Task.current.parent }).to all(be(task))
    end
  end
end
