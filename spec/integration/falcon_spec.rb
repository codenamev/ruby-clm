# frozen_string_literal: true

require "socket"

# The whole stack over real sockets: CLM::Client -> Falcon -> CLM::Server ->
# CLM::Engine -> (stubbed) encoder, all fibers in one Async reactor.
RSpec.describe "clm-serve on Falcon" do # rubocop:disable RSpec/DescribeClass
  let(:port) { TCPServer.open("127.0.0.1", 0) { _1.addr[1] } }
  let(:engine) do
    CLM::Engine.new(embedder: CLM::Embedder.new(url: FakeEmbeddings::EMBEDDINGS_URL),
                    checkpoint: torch_fixture("gelu_depth2.pt"), action_cache: 0)
  end
  let(:client) { CLM::Client.new(base_url: "http://127.0.0.1:#{port}", api_key: "sekrit") }

  before do
    WebMock.disable_net_connect!(allow_localhost: true)
    stub_embeddings
    stub_request(:get, "http://encoder.test/v1/models").to_return(status: 200, body: "{}")
  end

  after { WebMock.disable_net_connect! }

  def with_server
    Sync do |task|
      app = CLM::Server.new(engine, api_key: "sekrit")
      server = CLM::CLI::Serve.start(app, host: "127.0.0.1", port:)
      task.sleep(0.01) until client.healthy?
      yield task
    ensure
      CLM::CLI::Serve.stop(server) if server
    end
  end

  it "answers System One requests through the HTTP client" do
    with_server do
      response = client.system_one("Customer: my invoice was charged twice!") do |q|
        q.noul :urgency, "Is this urgent?"
        q.choice :team, "Which team?", billing: "Charges, invoices, refunds", technical: "Bugs and outages"
      end
      expect(response.answers.keys).to eq(%i[urgency team])
      expect(response.latency_ms).to be_a(Float)
      expect(response[:team].probabilities.values.sum).to be_within(1e-6).of(1.0)
    end
  end

  it "serves concurrent requests from Async tasks" do
    with_server do |task|
      contexts = ["Tides?", "Seasons?", "Eclipses?"]
      rankings = contexts.map { |c| task.async { client.rank(c, ["The Moon.", "The Sun."]) } }.map(&:wait)
      expect(rankings.map(&:size)).to eq([2, 2, 2])
    end
  end

  it "maps server errors to client exceptions" do
    with_server do
      expect { client.system_one("s", { ok: CLM::Noul.new }, model: "gpt") }
        .to raise_error(CLM::UnprocessableEntityError, /unknown model "gpt"/)
    end
  end
end
