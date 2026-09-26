# frozen_string_literal: true

RSpec.describe CLM::Configuration do
  subject(:config) { described_class.new(env) }

  context "with an empty environment" do
    let(:env) { {} }

    it "uses the upstream defaults" do
      expect(config).to have_attributes(
        base_url: "http://127.0.0.1:8700", api_key: nil, model: "clm-latest",
        embedder_url: "http://127.0.0.1:8090/v1/embeddings", embedder_model: "qwen3-8b",
        embedder_max_tokens: 2048, checkpoint: nil, action_cache: nil
      )
    end

    it "keeps checkpoints under ~/.cache/clm" do
      expect(config.checkpoint_dir).to eq(File.join(Dir.home, ".cache", "clm"))
    end
  end

  context "with CLM_* variables set" do
    let(:env) do
      { "CLM_BASE_URL" => "http://clm:1", "CLM_API_KEY" => "secret", "CLM_EMB_URL" => "http://emb/v1/embeddings",
        "CLM_EMB_MODEL" => "m", "CLM_EMB_MAX_TOKENS" => "8192", "CLM_CKPT" => "/x.pt",
        "CLM_CKPT_DIR" => "/heads", "CLM_ACTION_CACHE" => "512MiB" }
    end

    it "reads them" do
      expect(config).to have_attributes(
        base_url: "http://clm:1", api_key: "secret", embedder_url: "http://emb/v1/embeddings",
        embedder_model: "m", embedder_max_tokens: 8192, checkpoint: "/x.pt",
        checkpoint_dir: "/heads", action_cache: "512MiB"
      )
    end
  end
end
