# frozen_string_literal: true

RSpec.describe CLM::Distribution do
  describe ".softmax" do
    it "normalises to a probability distribution" do
      probs = described_class.softmax([1.0, 2.0, 3.0])
      expect(probs).to contain_exactly(be_within(1e-6).of(0.0900306), be_within(1e-6).of(0.2447285),
                                       be_within(1e-6).of(0.6652410))
      expect(probs.sum).to be_within(1e-12).of(1.0)
    end

    it "is stable for large logits" do
      expect(described_class.softmax([1000.0, 1000.0])).to eq([0.5, 0.5])
    end
  end

  describe ".confidence" do
    it "is the top probability minus the mean of the rest" do
      expect(described_class.confidence([0.7, 0.2, 0.1])).to be_within(1e-12).of(0.55)
    end

    it "is 1 for a single option and 0 for a uniform distribution" do
      expect([described_class.confidence([1.0]), described_class.confidence([0.5, 0.5])]).to eq([1.0, 0.0])
    end
  end
end
