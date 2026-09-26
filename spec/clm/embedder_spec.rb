# frozen_string_literal: true

RSpec.describe CLM::Embedder do
  subject(:embedder) { described_class.new(url: FakeEmbeddings::EMBEDDINGS_URL, batch_size: 2) }

  before { CLM.config.retry_interval = 0 }

  describe "#embed" do
    let!(:stub) { stub_embeddings }

    it "returns L2-normalised vectors in input order" do
      result = embedder.embed(%w[alpha beta])
      expected = %w[alpha beta].map { |t| described_class.normalize(Numo::DFloat.cast(FakeEmbeddings.vector(t, 16))) }
      expect(result.vectors.shape).to eq([2, 16])
      expect(result.vectors.to_a.flatten).to match(expected.flat_map(&:to_a).map { be_within(1e-5).of(_1) })
    end

    it "asks for base64 floats truncated to max_tokens" do
      embedder.embed(["alpha"])
      expect(WebMock).to have_requested(:post, FakeEmbeddings::EMBEDDINGS_URL)
        .with(body: { model: "qwen3-8b", input: ["alpha"], encoding_format: "base64", truncate_prompt_tokens: 2048 })
    end

    it "sends misses in batches and counts their tokens" do
      result = embedder.embed(%w[a bb ccc dddd e])
      expect(stub).to have_been_requested.times(3)
      expect(result.tokens).to eq(11)
    end

    it "serves repeated texts from the cache, spending no tokens" do
      embedder.embed(%w[alpha beta])
      result = embedder.embed(%w[beta alpha beta])
      expect(stub).to have_been_requested.once
      expect([result.tokens, result.vectors.shape]).to eq([0, [3, 16]])
    end

    it "evicts the least recently used text beyond cache_size" do
      small = described_class.new(url: FakeEmbeddings::EMBEDDINGS_URL, cache_size: 2)
      small.embed(%w[a b])
      small.embed(%w[a]) # refresh a
      small.embed(%w[c]) # evicts b
      small.embed(%w[a])
      expect(small.cached).to eq(2)
      expect(stub).to have_been_requested.twice
      small.embed(%w[b])
      expect(stub).to have_been_requested.times(3)
    end
  end

  it "accepts float-list embeddings" do
    stub_embeddings(base64: false)
    expect(embedder.embed(["x"]).vectors.shape).to eq([1, 16])
  end

  it "raises EmbedderError when the encoder is down" do
    stub_request(:post, FakeEmbeddings::EMBEDDINGS_URL).to_raise(Errno::ECONNREFUSED)
    expect { embedder.embed(["x"]) }.to raise_error(CLM::EmbedderError, %r{unreachable at http://encoder.test})
  end

  it "raises EmbedderError on an error status" do
    stub_request(:post, FakeEmbeddings::EMBEDDINGS_URL).to_return(status: 400, body: "context too long")
    expect { embedder.embed(["x"]) }.to raise_error(CLM::EmbedderError, "embedder error 400: context too long")
  end

  it "raises EmbedderError when embeddings are missing" do
    stub_request(:post, FakeEmbeddings::EMBEDDINGS_URL)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: JSON.generate(data: []))
    expect { embedder.embed(["x"]) }.to raise_error(CLM::EmbedderError, /returned 0 of 1 embeddings/)
  end

  describe "#healthy?" do
    it "checks the server's model list" do
      stub_request(:get, "http://encoder.test/v1/models").to_return(status: 200, body: "{}")
      expect(embedder).to be_healthy
    end

    it "is false when the server is down" do
      stub_request(:get, "http://encoder.test/v1/models").to_raise(Errno::ECONNREFUSED)
      expect(embedder).not_to be_healthy
    end
  end
end
