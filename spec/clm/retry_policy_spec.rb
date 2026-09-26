# frozen_string_literal: true

RSpec.describe CLM::RetryPolicy do
  subject(:policy) { described_class.new }

  it "follows ruby_decision_model's defaults, without a total budget" do
    expect(policy).to have_attributes(max_retries: 2, backoff_initial: 0.5, backoff_max: 5.0, backoff_jitter: 0.25,
                                      max_retry_after: 60.0, total_timeout: nil)
  end

  it "retries 408, 429 and 5xx only" do
    expect([408, 429, 500, 503, 599, 400, 404, 422].map { policy.retryable_status?(_1) })
      .to eq([true, true, true, true, true, false, false, false])
  end

  it "retries connection failures and timeouts" do
    expect([Errno::ECONNREFUSED.new, Net::ReadTimeout.new, ArgumentError.new].map { policy.retryable_error?(_1) })
      .to eq([true, true, false])
  end

  describe "#delay" do
    it "backs off exponentially up to the cap, with jitter taken off" do
      expect((0..4).map { policy.delay(_1, random: -> { 0.0 }) }).to eq([0.5, 1.0, 2.0, 4.0, 5.0])
      expect(policy.delay(0, random: -> { 1.0 })).to eq(0.375)
    end

    it "honours retry-after-ms, then Retry-After, capped at max_retry_after" do
      expect(policy.delay(0, headers: { "retry-after-ms" => "250", "Retry-After" => "9" })).to eq(0.25)
      expect(policy.delay(0, headers: { "Retry-After" => "3" })).to eq(3.0)
      expect(policy.delay(0, headers: { "retry-after" => "600" })).to eq(60.0)
    end

    it "reads an HTTP-date Retry-After" do
      expect(policy.delay(0, headers: { "retry-after" => (Time.now + 30).httpdate })).to be_within(2).of(30)
    end
  end

  describe ".from" do
    it "takes a policy, overrides or nil" do
      expect([described_class.from(policy), described_class.from(nil), described_class.from("max_retries" => 0)]
               .map(&:max_retries)).to eq([2, 2, 0])
    end

    it "rejects anything else and invalid values" do
      expect { described_class.from(3) }.to raise_error(CLM::ConfigurationError, /RetryPolicy or a Hash/)
      expect { described_class.new(max_retries: -1) }.to raise_error(CLM::ConfigurationError, /max_retries/)
      expect { described_class.new(backoff_jitter: 2) }.to raise_error(CLM::ConfigurationError, /between 0 and 1/)
    end
  end
end
