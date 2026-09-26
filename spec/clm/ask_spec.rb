# frozen_string_literal: true

RSpec.describe CLM::Ask do
  let(:client) { FakeClient.new }

  it "chains questions and answers them in one call" do
    result = CLM.ask("I want my money back", client:)
                .choice(:tone, "Which tone?", %w[calm annoyed furious])
                .noul(:refund, "Do they want money back?")
                .decide
    expect([result.tone == :calm, result[:refund].probability, client.calls.size]).to eq([true, 0.8, 1])
    expect(client.calls.last[:questions].keys).to eq(%i[tone refund])
  end

  it "passes the model and other options through" do
    CLM.ask("s", client:, temperature: 0.5).using("clm-raw").score(:urgency, "How urgent?", levels: %w[low high])
       .decide
    expect(client.calls.last[:options]).to eq(temperature: 0.5, model: "clm-raw")
  end

  it "refuses to decide without a question" do
    expect { CLM.ask("s", client:).decide }.to raise_error(ArgumentError, /at least one question/)
  end
end
