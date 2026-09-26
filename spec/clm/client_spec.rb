# frozen_string_literal: true

RSpec.describe CLM::Client do
  subject(:client) { described_class.new(base_url: "http://clm.test/", api_key: "sekrit") }

  def json(body, status: 200, headers: {})
    { status:, body: JSON.generate(body), headers: { "Content-Type" => "application/json" }.merge(headers) }
  end

  describe "#system_one" do
    let(:answers) do
      { "urgency" => { "type" => "noul", "noul" => 0.41022 },
        "department" => { "type" => "choice", "choice" => "billing", "confidence" => 0.87756,
                          "probabilities" => { "billing" => 0.93878, "technical" => 0.06122 } } }
    end

    before do
      stub_request(:post, "http://clm.test/v1/systemone")
        .to_return(json({ model: "clm-latest", answers:, usage: { billing_units: 2, input_tokens: 38,
                                                                  output_tokens: 0 } },
                        headers: { "X-CLM-Latency-Ms" => "58.1" }))
    end

    it "posts the state and wire-format questions with the bearer key" do
      client.system_one("charged twice", { urgency: CLM::Noul.new(instructions: "Urgent?") }, temperature: 0.5)
      expect(WebMock).to have_requested(:post, "http://clm.test/v1/systemone")
        .with(headers: { "Authorization" => "Bearer sekrit" },
              body: { state: "charged twice", model: "clm-latest", temperature: 0.5,
                      questions: { urgency: { type: "noul", instructions: "Urgent?" } } })
    end

    it "returns typed answers keyed like the questions" do
      response = client.system_one("charged twice") do |q|
        q.noul :urgency, "Urgent?"
        q.choice "department", "Which team?", billing: "Charges", technical: "Bugs"
      end
      expect(response[:urgency].noul).to eq(0.41022)
      expect(response["department"]).to have_attributes(choice: "billing", probabilities: include("billing" => 0.93878))
      expect(response).to have_attributes(model: "clm-latest", latency_ms: 58.1)
      expect(response.usage).to eq(CLM::Usage.new(billing_units: 2, input_tokens: 38, output_tokens: 0))
    end
  end

  describe "#rank" do
    it "returns rankings best first" do
      stub_request(:post, "http://clm.test/v1/rank")
        .with(body: { context: "Tides?", answers: %w[Moon Plants], model: "clm-latest" })
        .to_return(json({ model: "clm-latest", ranked: [{ rank: 1, candidate: "Moon", prob: 0.99 },
                                                        { rank: 2, candidate: "Plants", prob: 0.01 }] }))
      expect(client.rank("Tides?", %w[Moon Plants]).map(&:to_h))
        .to eq([{ rank: 1, candidate: "Moon", prob: 0.99 }, { rank: 2, candidate: "Plants", prob: 0.01 }])
    end
  end

  describe "#models" do
    it "lists the served models" do
      stub_request(:get, "http://clm.test/v1/models")
        .to_return(json({ models: [{ name: "clm-latest", description: "CLM", release_date: "2026-09-19" }] }))
      expect(client.models).to eq([CLM::ModelInfo.new(name: "clm-latest", description: "CLM",
                                                      release_date: "2026-09-19")])
    end
  end

  describe "#healthy?" do
    it "is true when the server says ok" do
      stub_request(:get, "http://clm.test/health").to_return(json({ ok: true }))
      expect(client).to be_healthy
    end

    it "is false when the server is down" do
      stub_request(:get, "http://clm.test/health").to_raise(Errno::ECONNREFUSED)
      expect(client).not_to be_healthy
    end
  end

  describe "errors" do
    it "raises the status's error class with the server's detail" do
      stub_request(:post, "http://clm.test/v1/systemone").to_return(json({ detail: "invalid API key" }, status: 401))
      expect { client.system_one("s", { ok: CLM::Noul.new }) }
        .to raise_error(CLM::UnauthorizedError, "401: invalid API key") { expect(_1.status).to eq(401) }
    end

    it "maps a 502 to BadGatewayError" do
      stub_request(:post, "http://clm.test/v1/rank").to_return(json({ detail: "embedder unreachable" }, status: 502))
      expect { client.rank("c", ["a"]) }.to raise_error(CLM::BadGatewayError, /embedder unreachable/)
    end

    it "retries a 503 before giving up" do
      stub = stub_request(:get, "http://clm.test/v1/models").to_return(json({ detail: "busy" }, status: 503))
      expect { client.models }.to raise_error(CLM::ServiceUnavailableError)
      expect(stub).to have_been_requested.times(3)
    end

    it "raises ConnectionError when the server is unreachable" do
      stub_request(:get, "http://clm.test/v1/models").to_raise(Errno::ECONNREFUSED)
      expect { client.models }.to raise_error(CLM::ConnectionError, %r{unreachable at http://clm.test})
    end

    it "validates questions before sending anything" do
      expect { client.system_one("s", {}) }.to raise_error(CLM::InvalidRequestError)
    end
  end

  describe "CLM.system_one" do
    it "uses the global configuration" do
      CLM.configure { |c| c.base_url = "http://global.test" }
      stub_request(:post, "http://global.test/v1/systemone")
        .to_return(json({ model: "clm-latest", answers: { "ok" => { type: "noul", noul: 0.9 } } }))
      expect(CLM.system_one("s") { |q| q.noul :ok }[:ok].noul).to eq(0.9)
    end
  end
end
