# frozen_string_literal: true

RSpec.describe CLM::Answer do
  describe ".from_h" do
    it "parses noul answers" do
      expect(described_class.from_h({ "type" => "noul", "noul" => 0.41 })).to eq(CLM::NoulAnswer.new(noul: 0.41))
    end

    it "parses choice answers" do
      answer = described_class.from_h({ "type" => "choice", "choice" => "billing", "confidence" => 0.9,
                                        "probabilities" => { "billing" => 0.95, "technical" => 0.05 } })
      expect(answer).to have_attributes(choice: "billing", confidence: 0.9,
                                        probabilities: { "billing" => 0.95, "technical" => 0.05 })
    end

    it "parses score answers" do
      answer = described_class.from_h({ type: "score", score: 1.5, confidence: 0.2,
                                        legend: { "0" => "Calm", "1" => "Angry" },
                                        probabilities: { "0" => 0.4, "1" => 0.6 } })
      expect(answer).to have_attributes(score: 1.5, level: "Angry", label: "1")
    end

    it "rejects unknown types" do
      expect { described_class.from_h({ "type" => "essay" }) }.to raise_error(CLM::Error, /unknown answer type/)
    end
  end

  describe "#to_h" do
    it "writes the type first, as the server does" do
      expect(CLM::NoulAnswer.new(noul: 0.5).to_h).to eq(type: "noul", noul: 0.5)
      expect(CLM::ScoreAnswer.new(score: 1.0, confidence: 0.1, legend: {}, probabilities: {}).to_h.keys)
        .to eq(%i[type score confidence legend probabilities])
    end
  end

  describe CLM::NoulAnswer do
    it "is true when at least even odds" do
      expect([described_class.new(noul: 0.5).yes?, described_class.new(noul: 0.49).true?]).to eq([true, false])
    end
  end
end
