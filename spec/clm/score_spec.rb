# frozen_string_literal: true

RSpec.describe CLM::Score do
  subject(:question) { described_class.new(instructions: "How angry?", criteria: ["Calm", "Frustrated", { v: 1 }]) }

  it "keys levels by index" do
    expect(question.keys).to eq(%w[0 1 2])
  end

  it "renders structured levels as prose" do
    expect(question.candidates).to eq(["Calm", "Frustrated", "v: 1"])
  end

  it "answers with the expected level and a legend" do
    expect(question.answer([0.2, 0.3, 0.5]))
      .to have_attributes(score: be_within(1e-12).of(1.3), label: "2", level: "v: 1",
                          legend: { "0" => "Calm", "1" => "Frustrated", "2" => "v: 1" })
  end

  it "needs at least two levels" do
    expect { described_class.new(criteria: ["only"]) }.to raise_error(CLM::InvalidRequestError, />= 2 levels/)
  end
end
