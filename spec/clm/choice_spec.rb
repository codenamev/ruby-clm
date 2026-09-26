# frozen_string_literal: true

RSpec.describe CLM::Choice do
  subject(:question) do
    described_class.new(instructions: "Which team?", criteria: { billing: "Charges, invoices", technical: nil })
  end

  it "normalises option keys to strings" do
    expect(question.keys).to eq(%w[billing technical])
  end

  it "embeds each option's description, or its key when there is none" do
    expect(question.candidates).to eq(["Charges, invoices", "technical"])
  end

  it "answers with the likeliest option and its confidence" do
    expect(question.answer([0.8, 0.2]))
      .to have_attributes(choice: "billing", confidence: be_within(1e-12).of(0.6),
                          probabilities: { "billing" => 0.8, "technical" => 0.2 })
  end

  it "requires non-empty criteria" do
    expect { described_class.new(criteria: {}) }.to raise_error(CLM::InvalidRequestError, /non-empty 'criteria'/)
  end

  it "serialises to the wire format" do
    expect(question.to_h).to eq(type: "choice", instructions: "Which team?",
                                criteria: { "billing" => "Charges, invoices", "technical" => nil })
  end
end
