# frozen_string_literal: true

RSpec.describe CLM::CLI::Serve do
  let(:out) { StringIO.new }
  let(:env) { { "CLM_EMB_URL" => FakeEmbeddings::EMBEDDINGS_URL } }
  let(:launched) { [] }
  let(:launcher) { ->(app, host:, port:) { launched << [app, host, port] } }

  def serve(*argv, env: self.env)
    described_class.new(argv, env:, out:, launcher:)
  end

  before do
    stub_embeddings
    stub_request(:get, "http://encoder.test/v1/models").to_return(status: 200, body: "{}")
  end

  it "parses the upstream flags" do
    cli = serve("--port", "9000", "--host", "127.0.0.1", "--emb-model", "m", "--max-tokens", "8192",
                "--model", "a=/a.pt", "--model", "b=/b.pt", "--action-cache", "0", "--no-ui", "--cors",
                "--no-download").parse!
    expect(cli.options).to include(port: 9000, host: "127.0.0.1", emb_model: "m", max_tokens: 8192,
                                   models: { "a" => "/a.pt", "b" => "/b.pt" }, action_cache: "0", ui: false,
                                   cors: true, download: false)
  end

  it "reads its defaults from the environment" do
    cli = serve(env: env.merge("CLM_PORT" => "9100", "CLM_ACTION_CACHE" => "64MiB")).parse!
    expect(cli.options).to include(port: 9100, action_cache: "64MiB", emb_url: FakeEmbeddings::EMBEDDINGS_URL)
  end

  it "rejects --model without a path" do
    expect { serve("--model", "broken").parse! }.to raise_error(OptionParser::InvalidArgument, /NAME=PATH/)
  end

  it "serves the given checkpoint and prints where" do
    serve("--ckpt", torch_fixture("gelu_depth2.pt"), "--action-cache", "1MB", "--port", "9001").run
    app, host, port = launched.first
    expect([app, host, port]).to match([be_a(CLM::Server), "0.0.0.0", 9001])
    expect(out.string).to include("[clm] models [\"clm-latest\", \"clm-raw\"] on cpu",
                                  "(qwen3-8b) up; auth off", "vector cache 1.0 MB reserved on cpu (",
                                  "[clm] POST http://0.0.0.0:9001/v1/systemone",
                                  "[clm] playground http://localhost:9001/")
  end

  it "downloads the reference head when no checkpoint is given" do
    allow(CLM::Hub).to receive(:download).and_return(torch_fixture("gelu_depth2.pt"))
    serve("--action-cache", "0").run
    expect(CLM::Hub).to have_received(:download)
    expect(out.string).to include("vector cache off")
  end

  it "refuses to start without any checkpoint" do
    expect { serve("--no-download", env: env.merge("CLM_CKPT_DIR" => "/nonexistent")).run }
      .to raise_error(CLM::Error, /no checkpoint/)
  end
end
