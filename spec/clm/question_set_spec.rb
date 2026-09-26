# frozen_string_literal: true

RSpec.describe CLM::QuestionSet do
  describe ".coerce" do
    it "wraps a hash of question objects and wire hashes" do
      set = described_class.coerce(ok: CLM::Noul.new(instructions: "Ok?"),
                                   "level" => { type: "score", criteria: %w[a b] })
      expect(set.ids).to eq([:ok, "level"])
      expect(set["level"]).to be_a(CLM::Score)
    end

    it "evaluates a builder block that takes the set" do
      set = described_class.coerce do |q|
        q.noul :urgency, "Is this urgent?"
        q.noul :spam, "Spam?", true: "Ads", false: "Real mail" # rubocop:disable Lint/BooleanSymbol
        q.choice :team, "Which team?", billing: "Charges", technical: "Bugs"
        q.score :anger, "How angry?", %w[Calm Angry]
      end
      expect(set.to_h).to eq(
        "urgency" => { type: "noul", instructions: "Is this urgent?" },
        "spam" => { type: "noul", instructions: "Spam?", criteria: { "true" => "Ads", "false" => "Real mail" } },
        "team" => { type: "choice", instructions: "Which team?",
                    criteria: { "billing" => "Charges", "technical" => "Bugs" } },
        "anger" => { type: "score", instructions: "How angry?", criteria: %w[Calm Angry] }
      )
    end

    it "evaluates a builder block without an argument in the set's scope" do
      set = described_class.coerce { noul :ok, "Ok?" }
      expect(set.ids).to eq([:ok])
    end

    it "merges a hash and a block" do
      set = described_class.coerce({ a: CLM::Noul.new }) { |q| q.noul :b }
      expect(set.ids).to eq(%i[a b])
    end

    it "refuses an empty set" do
      expect { described_class.coerce({}) }.to raise_error(CLM::InvalidRequestError, /must not be empty/)
    end

    it "refuses a list" do
      expect { described_class.coerce([CLM::Noul.new]) }.to raise_error(CLM::InvalidRequestError, /Hash of id/)
    end
  end

  describe "#rekey" do
    it "maps wire ids back to the caller's ids" do
      set = described_class.new(urgency: CLM::Noul.new, "team" => CLM::Choice.new(criteria: { a: "" }))
      expect(set.rekey("urgency" => 1, "team" => 2)).to eq(urgency: 1, "team" => 2)
    end
  end
end
