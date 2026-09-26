# frozen_string_literal: true

RSpec.describe CLM::Answer do
  describe CLM::Answer::Choice do
    subject(:answer) do
      described_class.new(choice: "billing", probabilities: { "billing" => 0.9, "technical" => 0.1 }, confidence: 0.8)
    end

    it "stands in for its label" do
      expect([answer == :billing, answer == "technical", answer.to_sym, answer.to_s])
        .to eq([true, false, :billing, "billing"])
    end

    it "answers a predicate for every offered label" do
      expect([answer.billing?, answer.technical?, answer.respond_to?(:billing?)]).to eq([true, false, true])
      expect { answer.sales? }.to raise_error(NoMethodError)
    end

    it "reports the probability of the choice or of any label" do
      expect([answer.probability, answer.probability(:technical)]).to eq([0.9, 0.1])
      expect { answer.probability(:sales) }.to raise_error(KeyError, /no option :sales/)
    end

    it "renders the wire payload" do
      expect(answer.to_h).to eq("type" => "choice", "choice" => "billing",
                                "probabilities" => { "billing" => 0.9, "technical" => 0.1 }, "confidence" => 0.8)
    end
  end

  describe CLM::Answer::Score do
    subject(:answer) do
      described_class.new(score: 1.4, legend: { "0" => "calm", "1" => "annoyed", "2" => "furious" },
                          probabilities: { "0" => 0.1, "1" => 0.4, "2" => 0.5 }, confidence: 0.2)
    end

    it "labels the rubric level nearest the expected score" do
      expect([answer.label, answer.levels, answer.to_f]).to eq(["annoyed", 3, 1.4])
    end

    it "compares against a number or a level's text" do
      expect([answer == 1.4, answer == "annoyed", answer == :calm]).to eq([true, true, false]) # rubocop:disable Lint/FloatComparison
    end
  end

  describe CLM::Answer::Noul do
    subject(:answer) { described_class.new(probability: 0.7) }

    it "reads as the probability, and as true past a threshold" do
      expect([answer.noul, answer.true?, answer.true?(0.8), answer.false?(0.8), answer == true])
        .to eq([0.7, true, false, true, true])
    end

    it "reports both sides and renders the wire payload without a confidence" do
      expect(answer.probabilities).to match("false" => be_within(1e-12).of(0.3), "true" => 0.7)
      expect(answer.to_h).to eq("type" => "noul", "noul" => 0.7)
    end
  end

  describe ".from_h" do
    it "parses every wire answer, with string or symbol keys" do
      wire = [{ "type" => "noul", "noul" => 0.41 },
              { type: "choice", choice: "billing", confidence: 0.9, probabilities: { billing: 0.95, other: 0.05 } },
              { "type" => "score", "score" => 1.5, "confidence" => 0.2,
                "legend" => { "0" => "Calm", "1" => "Angry" }, "probabilities" => { "0" => 0.4, "1" => 0.6 } }]
      answers = wire.map { described_class.from_h(_1) }
      expect(answers.map(&:class)).to eq([CLM::Answer::Noul, CLM::Answer::Choice, CLM::Answer::Score])
      expect(answers.map(&:to_s)).to eq(["41.0%", "billing", "1.50 of 1 (Angry)"])
    end

    it "rejects unknown types" do
      expect { described_class.from_h({ "type" => "essay" }) }.to raise_error(CLM::Error, /unknown answer type/)
    end
  end
end
