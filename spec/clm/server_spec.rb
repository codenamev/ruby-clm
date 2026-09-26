# frozen_string_literal: true

require "rack/test"

RSpec.describe CLM::Server do
  include Rack::Test::Methods

  let(:embedder) { CLM::Embedder.new(url: FakeEmbeddings::EMBEDDINGS_URL) }
  let(:engine) { CLM::Engine.new(embedder:, checkpoint: torch_fixture("gelu_depth2.pt"), action_cache: 0) }
  let(:server_options) { {} }
  let(:app) { described_class.new(engine, **server_options) }
  let(:questions) do
    { urgency: { type: "noul", instructions: "Is this urgent?" },
      team: { type: "choice", instructions: "Which team?", criteria: { billing: "Charges", technical: "Bugs" } } }
  end

  before do
    stub_embeddings
    stub_request(:get, "http://encoder.test/v1/models").to_return(status: 200, body: "{}")
  end

  def post_json(path, body, headers = {})
    post path, body.is_a?(String) ? body : JSON.generate(body), { "CONTENT_TYPE" => "application/json" }.merge(headers)
  end

  def json
    JSON.parse(last_response.body)
  end

  describe "POST /v1/systemone" do
    it "answers every question with the engine" do
      post_json "/v1/systemone", { state: "Customer: charged twice!", questions: }
      expect(last_response.status).to eq(200)
      expect(json).to include("model" => "clm-latest", "usage" => include("billing_units" => 2))
      expect(json["answers"].keys).to eq(%w[urgency team])
      expect(json["answers"]["team"]).to include("type" => "choice", "choice" => be_a(String))
    end

    it "stamps the server-side latency" do
      post_json "/v1/systemone", { state: "Customer: charged twice!", questions: }
      expect(last_response.headers["X-CLM-Latency-Ms"]).to match(/\A\d+\.\d\z/)
    end

    it "round-trips through the HTTP client" do
      post_json "/v1/systemone", { state: "s", questions:, temperature: 0.5 }
      client_view = CLM::Answer.from_h(json["answers"]["urgency"])
      expect(client_view).to eq(engine.system_one("s", questions, temperature: 0.5)[:urgency])
    end

    it "refuses bodies without state or questions" do
      post_json "/v1/systemone", { state: "s" }
      expect([last_response.status, json]).to eq([422, { "detail" => "body must be {state, model, questions}" }])
    end

    it "refuses bodies that are not JSON" do
      post_json "/v1/systemone", "{nope"
      expect([last_response.status, json["detail"]]).to match([422, /\Abody is not JSON/])
    end

    it "refuses malformed questions" do
      post_json "/v1/systemone", { state: "s", questions: { x: { type: "essay" } } }
      expect([last_response.status, json["detail"]]).to match([422, /\Ainvalid request: unknown question type/])
    end

    it "refuses unknown models and bad temperatures" do
      post_json "/v1/systemone", { state: "s", questions:, model: "gpt" }
      expect([last_response.status, json["detail"]]).to match([422, /\Aunknown model "gpt"/])
      post_json "/v1/systemone", { state: "s", questions:, temperature: "hot" }
      expect([last_response.status, json["detail"]]).to eq([422, "temperature must be a number"])
    end

    it "answers 502 when the embedder is down" do
      stub_request(:post, FakeEmbeddings::EMBEDDINGS_URL).to_raise(Errno::ECONNREFUSED)
      post_json "/v1/systemone", { state: "s", questions: }
      expect([last_response.status, json["detail"]]).to match([502, /embedder unreachable/])
    end
  end

  describe "POST /v1/rank" do
    it "ranks the answers best first" do
      post_json "/v1/rank", { context: "What causes tides?", answers: ["The Moon.", "Plants."] }
      expect(json["model"]).to eq("clm-latest")
      expect(json["ranked"].map { _1["rank"] }).to eq([1, 2])
      expect(json["ranked"].sum { _1["prob"] }).to be_within(1e-6).of(1.0)
    end

    it "refuses empty or non-string answers" do
      post_json "/v1/rank", { context: "c", answers: [] }
      expect(json["detail"]).to eq("body must be {context, question, answers: [..]}")
      post_json "/v1/rank", { context: "c", answers: ["ok", ""] }
      expect([last_response.status, json["detail"]]).to eq([422, "answers must be non-empty strings"])
    end
  end

  describe "GET /v1/models" do
    it "lists the engine's models" do
      get "/v1/models"
      expect(json["models"].map { _1["name"] }).to eq(%w[clm-latest clm-raw])
      expect(json["models"].first).to include("release_date" => "2026-09-19")
    end
  end

  describe "GET /health" do
    it "reports the embedder, models and cache" do
      get "/health"
      expect(json).to eq("ok" => true, "embedder" => true, "models" => %w[clm-latest clm-raw], "cache" => nil)
    end
  end

  context "with an API key" do
    let(:server_options) { { api_key: "sekrit" } }

    it "requires the bearer key on the API" do
      get "/v1/models"
      expect([last_response.status, json]).to eq([401, { "detail" => "invalid API key" }])
      get "/v1/models", {}, { "HTTP_AUTHORIZATION" => "Bearer sekrit" }
      expect(last_response.status).to eq(200)
    end

    it "leaves /health open" do
      get "/health"
      expect(last_response.status).to eq(200)
    end
  end

  context "with CORS" do
    let(:server_options) { { cors: true } }

    it "answers preflight requests and exposes the latency header" do
      options "/v1/systemone"
      expect(last_response.status).to eq(204)
      expect(last_response.headers).to include("access-control-allow-origin" => "*",
                                               "access-control-expose-headers" => "X-CLM-Latency-Ms")
    end
  end

  it "sends no CORS headers by default" do
    get "/health"
    expect(last_response.headers).not_to include("access-control-allow-origin")
  end

  it "answers 404 and 405 like FastAPI" do
    get "/nope"
    expect([last_response.status, json]).to eq([404, { "detail" => "Not Found" }])
    get "/v1/systemone"
    expect([last_response.status, json]).to eq([405, { "detail" => "Method Not Allowed" }])
  end
end
