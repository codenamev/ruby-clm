# frozen_string_literal: true

require "rack/test"

RSpec.describe CLM::MockEngine do
  include Rack::Test::Methods

  subject(:engine) { described_class.new }

  let(:app) { CLM::Server.new(engine) }

  it "answers typed questions from character n-grams" do
    response = engine.system_one("The invoice was charged twice") do |q|
      q.choice :topic, "What is this about?", billing: "an invoice charged twice", weather: "sunny skies"
    end
    expect(response[:topic].choice).to eq("billing")
    expect(response.usage.input_tokens).to be_positive
  end

  it "ranks lexically closer candidates higher" do
    expect(engine.rank("moon tides", ["the moon causes tides", "photosynthesis"]).first.candidate)
      .to eq("the moon causes tides")
  end

  it "answers the raw model flatter" do
    ask = ->(model) { engine.system_one("tea", { x: CLM::Choice.new(criteria: { a: "tea", b: "car" }) }, model:) }
    expect(ask.call("clm-raw")[:x].confidence).to be < ask.call("clm-latest")[:x].confidence
  end

  it "flags itself as a mock on /health" do
    get "/health"
    expect(JSON.parse(last_response.body)).to include("ok" => true, "mock" => true, "embedder" => true,
                                                      "models" => %w[clm-latest clm-raw])
  end

  it "labels its models as mocks" do
    expect(engine.models.map(&:description)).to all(start_with("MOCK"))
  end

  context "when broken" do
    subject(:engine) { described_class.new(broken: true) }

    it "answers 502 like an unreachable encoder" do
      post "/v1/rank", JSON.generate(context: "c", answers: %w[a b])
      expect(last_response.status).to eq(502)
      expect(JSON.parse(last_response.body)["detail"]).to include("--broken mode")
    end
  end
end
