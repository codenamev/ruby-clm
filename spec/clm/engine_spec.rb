# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe CLM::Engine do
  subject(:engine) { described_class.new(embedder:, checkpoint: torch_fixture("gelu_depth2.pt"), action_cache: 0) }

  let(:embedder) { CLM::Embedder.new(url: FakeEmbeddings::EMBEDDINGS_URL) }
  let(:reference) { JSON.parse(File.read(torch_fixture("expected_engine.json"))) }

  before { stub_embeddings }

  # Wire-format answers compared number by number, within float32 noise.
  def match_answers(expected)
    match(expected.transform_values do |answer|
      answer.to_h { |key, value| [key.to_sym, approximately(value)] }
    end)
  end

  def approximately(value)
    case value
    when Float then be_within(2e-5).of(value)
    when Hash then match(value.transform_values { approximately(_1) })
    else eq(value)
    end
  end

  def wire(response)
    response.answers.transform_values(&:to_h)
  end

  %w[gelu_depth2 silu_layernorm_residual].each do |name|
    context "with the #{name} head" do
      subject(:engine) { described_class.new(embedder:, checkpoint: torch_fixture("#{name}.pt"), action_cache: 0) }

      let(:expected) { reference["cases"][name] }

      it "answers like the Python engine" do
        response = engine.system_one(reference["state"], reference["questions"])
        expect(wire(response)).to match_answers(expected["answer"]["answers"])
        expect(response.model).to eq("clm-latest")
      end

      it "applies the temperature like the Python engine" do
        response = engine.system_one(reference["state"], reference["questions"], temperature: 0.5)
        expect(wire(response)).to match_answers(expected["cool"])
      end

      it "answers the raw ablation like the Python engine" do
        response = engine.system_one(reference["state"], reference["questions"], model: "clm-raw")
        expect(wire(response)).to match_answers(expected["raw"])
      end

      it "ranks like the Python engine" do
        context, answers = reference["rank"]
        expect(engine.rank(context, answers).map(&:to_h))
          .to match(expected["rank"].map { |r| r.transform_keys(&:to_sym).merge(prob: approximately(r["prob"])) })
      end
    end
  end

  describe "#system_one" do
    it "keys answers by the caller's ids and counts usage" do
      response = engine.system_one("Customer: charged twice!") do |q|
        q.noul :urgency, "Is this urgent?"
        q.choice :team, "Which team?", billing: "Charges", technical: "Bugs"
      end
      expect(response.answers.keys).to eq(%i[urgency team])
      expect(response.usage).to have_attributes(billing_units: 2, output_tokens: 0, input_tokens: be_positive)
    end

    it "spends no encoder tokens on texts it has already embedded" do
      engine.system_one("state") { |q| q.noul :ok, "Ok?" }
      expect(engine.system_one("state") { |q| q.noul :ok, "Ok?" }.usage.input_tokens).to eq(0)
    end

    it "rejects unknown models" do
      expect { engine.system_one("s", { ok: CLM::Noul.new }, model: "gpt") }
        .to raise_error(CLM::ModelNotFoundError, /unknown model "gpt"; available: \["clm-latest", "clm-raw"\]/)
    end

    it "rejects temperatures outside (0, 100]" do
      [0, 101, "hot"].each do |temperature|
        expect { engine.system_one("s", { ok: CLM::Noul.new }, temperature:) }
          .to raise_error(CLM::InvalidRequestError, /temperature must be/)
      end
    end

    it "rejects empty and malformed questions" do
      expect { engine.system_one("s", {}) }.to raise_error(CLM::InvalidRequestError, /must not be empty/)
      expect { engine.system_one("s", { x: { type: "score", criteria: ["one"] } }) }
        .to raise_error(CLM::InvalidRequestError, />= 2 levels/)
    end
  end

  describe "the vector cache" do
    subject(:cached) do
      described_class.new(embedder:, checkpoint: torch_fixture("gelu_depth2.pt"), action_cache: "1MB")
    end

    it "gives the same answers as the uncached engine" do
      uncached = JSON.parse(JSON.generate(wire(engine.system_one(reference["state"], reference["questions"]))))
      2.times do
        expect(wire(cached.system_one(reference["state"], reference["questions"]))).to match_answers(uncached)
      end
    end

    it "reserves projection and raw pools and counts hits" do
      2.times { cached.system_one("state") { |q| q.noul :ok, "Ok?" } }
      expect(cached.cache.stats[:pools].keys).to eq(%w[4 16])
      expect(cached.cache.stats[:pools]["4"]).to include(hits: 3, misses: 3)
    end
  end

  describe "#models" do
    it "lists clm-latest first, other heads sorted, and clm-raw last" do
      engine = described_class.new(embedder:, checkpoint: torch_fixture("gelu_depth2.pt"), action_cache: 0,
                                   models: { "zeta" => torch_fixture("relu_bfloat16.pt"),
                                             alpha: torch_fixture("gelu_float16.pt") })
      expect(engine.models.map(&:name)).to eq(%w[clm-latest alpha zeta clm-raw])
      expect(engine.models.find { _1.name == "zeta" }.description)
        .to eq("Projection-head checkpoint relu_bfloat16.pt")
    end

    it "serves every checkpoint in a directory under its file stem" do
      Dir.mktmpdir do |dir|
        %w[gelu_depth2 relu_bfloat16 gelu_float16].each { FileUtils.cp(torch_fixture("#{_1}.pt"), dir) }
        engine = described_class.new(embedder:, checkpoint: File.join(dir, "gelu_depth2.pt"), checkpoint_dir: dir,
                                     action_cache: 0)
        expect(engine.models.map(&:name)).to eq(%w[clm-latest gelu_float16 relu_bfloat16 clm-raw])
      end
    end

    it "serves only the raw ablation without checkpoints" do
      engine = described_class.new(embedder:, checkpoint: nil, action_cache: 0,
                                   config: CLM::Configuration.new("CLM_CKPT_DIR" => "/nonexistent"))
      expect(engine.models.map(&:name)).to eq(%w[clm-raw])
      expect(engine.rank("Tides?", %w[Moon Sun], model: "clm-raw").map(&:rank)).to eq([1, 2])
    end
  end
end
