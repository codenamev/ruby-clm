# frozen_string_literal: true

RSpec.describe CLM::Question do
  describe ".build" do
    it "builds the type the definition names, from string or symbol keys" do
      expect([described_class.build(:a, { "type" => "noul", "instructions" => "Ok?" }),
              described_class.build(:b, { type: :score, criteria: %w[low high] })].map(&:class))
        .to eq([CLM::Question::Noul, CLM::Question::Score])
    end

    it "rejects unknown types and non-hashes, naming the question" do
      expect { described_class.build(:x, { type: "essay" }) }
        .to raise_error(CLM::InvalidRequestError, /question :x: unknown question type "essay"/)
      expect { described_class.build(:x, "Ok?") }.to raise_error(CLM::InvalidRequestError, /got String/)
    end
  end

  describe ".build_all" do
    it "keeps the caller's ids and refuses an empty or non-hash set" do
      expect(described_class.build_all({ ok: CLM::Questions.noul("Ok?") }).keys).to eq([:ok])
      expect { described_class.build_all({}) }.to raise_error(CLM::InvalidRequestError, /must not be empty/)
      expect { described_class.build_all([]) }.to raise_error(CLM::InvalidRequestError, /Hash of id/)
    end
  end

  describe CLM::Question::Noul do
    subject(:question) { CLM::Question.build(:urgent, CLM::Questions.noul("Is this urgent?")) }

    it "embeds the statement itself on both sides by default" do
      expect(question.candidates)
        .to eq(["false: No. This is false: Is this urgent?", "true: Yes. This is true: Is this urgent?"])
    end

    it "uses the given descriptions, and the bare keys without instructions" do
      described = CLM::Question.build(:s, CLM::Questions.noul("Spam?", yes: "Unsolicited ads"))
      expect(described.candidates).to eq(["false: No. This is false: Spam?", "true: Unsolicited ads"])
      expect(CLM::Question.build(:s, { type: "noul" }).candidates).to eq(["false: false", "true: true"])
    end

    it "answers with the probability of true" do
      expect(question.answer([0.25, 0.75])).to have_attributes(probability: 0.75, noul: 0.75)
    end

    it "appends the instructions to the state" do
      expect(question.state_text("Customer: charged twice!")).to eq("Customer: charged twice!\n\nIs this urgent?")
    end
  end

  describe CLM::Question::Choice do
    subject(:question) do
      CLM::Question.build(:team, CLM::Questions.choice("Which team?", billing: "Charges, invoices", technical: nil))
    end

    it "embeds each option's description, or its key when there is none" do
      expect([question.keys, question.candidates]).to eq([%w[billing technical], ["Charges, invoices", "technical"]])
    end

    it "answers with the likeliest option and its confidence" do
      expect(question.answer([0.8, 0.2])).to have_attributes(choice: "billing", confidence: be_within(1e-12).of(0.6))
    end

    it "requires criteria" do
      expect { CLM::Question.build(:t, { type: "choice", criteria: {} }) }
        .to raise_error(CLM::InvalidRequestError, /non-empty 'criteria'/)
    end
  end

  describe CLM::Question::Score do
    subject(:question) do
      CLM::Question.build(:anger, CLM::Questions.score("How angry?", ["Calm", "Frustrated", { v: 1 }]))
    end

    it "keys levels by index and renders structured levels as prose" do
      expect([question.keys, question.candidates]).to eq([%w[0 1 2], ["Calm", "Frustrated", "v: 1"]])
    end

    it "answers with the expected level and a legend" do
      expect(question.answer([0.2, 0.3, 0.5]))
        .to have_attributes(score: be_within(1e-12).of(1.3), legend: { "0" => "Calm", "1" => "Frustrated",
                                                                       "2" => "v: 1" })
    end

    it "needs at least two levels" do
      expect { CLM::Question.build(:s, CLM::Questions.score("How?", ["only"])) }
        .to raise_error(CLM::InvalidRequestError, />= 2 levels/)
    end
  end
end
