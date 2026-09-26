# frozen_string_literal: true

RSpec.describe CLM::Questions do
  describe ".choice" do
    it "takes labels as keywords" do
      expect(described_class.choice("Which team?", billing: "invoices", technical: "outages"))
        .to eq("type" => "choice", "instructions" => "Which team?",
               "criteria" => { "billing" => "invoices", "technical" => "outages" })
    end

    it "takes a hash for labels that are not keywords, and a list for labels without descriptions" do
      expect(described_class.choice("Intent?", { "card lost" => "the card is gone" })["criteria"])
        .to eq("card lost" => "the card is gone")
      expect(described_class.choice("Tone?", %w[formal casual])["criteria"]).to eq("formal" => nil, "casual" => nil)
    end

    it "refuses criteria that are neither" do
      expect { described_class.choice("Tone?", "formal") }.to raise_error(ArgumentError, /Hash or an Array/)
    end
  end

  it "builds a score from ordered levels" do
    expect(described_class.score("How urgent?", %w[low high]))
      .to eq("type" => "score", "instructions" => "How urgent?", "criteria" => %w[low high])
  end

  describe ".noul" do
    it "leaves out criteria when neither end is described" do
      expect(described_class.noul("Is this spam?")).to eq("type" => "noul", "instructions" => "Is this spam?")
    end

    it "describes the ends with yes: and no:" do
      expect(described_class.noul("Spam?", yes: "Unsolicited ads")["criteria"]).to eq("true" => "Unsolicited ads")
    end
  end
end
