# frozen_string_literal: true

RSpec.describe CLM::Question do
  describe ".wrap" do
    it "passes question objects through" do
      question = CLM::Noul.new(instructions: "Ok?")
      expect(described_class.wrap(question)).to be(question)
    end

    it "builds questions from wire-format hashes with string or symbol keys" do
      expect(described_class.wrap({ "type" => "choice", "instructions" => "Pick", "criteria" => { "a" => "A" } }))
        .to eq(CLM::Choice.new(instructions: "Pick", criteria: { a: "A" }))
      expect(described_class.wrap({ type: :score, criteria: %w[low high] }))
        .to eq(CLM::Score.new(criteria: %w[low high]))
    end

    it "rejects unknown types" do
      expect { described_class.wrap({ type: "essay" }) }
        .to raise_error(CLM::InvalidRequestError, /unknown question type "essay"/)
    end

    it "rejects things that are not questions" do
      expect { described_class.wrap("Ok?") }.to raise_error(CLM::InvalidRequestError, /got String/)
    end
  end
end
