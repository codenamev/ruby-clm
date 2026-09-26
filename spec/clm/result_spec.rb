# frozen_string_literal: true

RSpec.describe CLM::Result do
  subject(:result) do
    described_class.new(model: "clm-latest", answers: { urgent: CLM::Answer::Noul.new(probability: 0.8) },
                        usage: CLM::Usage.new(billing_units: 1, input_tokens: 12, output_tokens: 0))
  end

  it "reads an answer by symbol, string or method" do
    expect([result[:urgent], result["urgent"], result.urgent].map(&:probability)).to eq([0.8, 0.8, 0.8])
  end

  it "names the questions it has when asked for one it does not" do
    expect { result[:nope] }.to raise_error(KeyError, /no question :nope in this result; asked: \[:urgent\]/)
    expect { result.nope }.to raise_error(NoMethodError)
  end

  it "enumerates its answers" do
    expect(result.map { |id, answer| [id, answer.type] }).to eq([[:urgent, "noul"]])
  end

  it "renders the wire payload" do
    expect(result.to_h).to eq("model" => "clm-latest", "answers" => { "urgent" => { "type" => "noul", "noul" => 0.8 } },
                              "usage" => { "billing_units" => 1, "input_tokens" => 12, "output_tokens" => 0 })
    expect(result.input_tokens).to eq(12)
  end
end
