# frozen_string_literal: true

RSpec.describe CLM::Noul do
  subject(:question) { described_class.new(instructions: "Is this urgent?") }

  it "serialises without criteria when none are given" do
    expect(question.to_h).to eq(type: "noul", instructions: "Is this urgent?")
  end

  it "embeds the statement itself on both sides by default" do
    expect(question.candidates)
      .to eq(["false: No. This is false: Is this urgent?", "true: Yes. This is true: Is this urgent?"])
  end

  it "uses the given descriptions" do
    q = described_class.new(instructions: "Spam?", criteria: { "true" => "Unsolicited ads", "false" => "" })
    expect(q.candidates).to eq(["false: No. This is false: Spam?", "true: Unsolicited ads"])
  end

  it "falls back to the bare keys without instructions" do
    expect(described_class.new.candidates).to eq(["false: false", "true: true"])
  end

  it "answers with the probability of true" do
    answer = question.answer([0.25, 0.75])
    expect(answer).to have_attributes(noul: 0.75, label: "true", probabilities: { "false" => 0.25, "true" => 0.75 })
  end

  it "appends the instructions to the state" do
    expect(question.state_text("Customer: charged twice!")).to eq("Customer: charged twice!\n\nIs this urgent?")
  end
end
