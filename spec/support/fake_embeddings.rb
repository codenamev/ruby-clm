# frozen_string_literal: true

# A WebMock stand-in for a vLLM /v1/embeddings server: every text gets a
# deterministic (unnormalised) vector, and one prompt token per character.
module FakeEmbeddings
  EMBEDDINGS_URL = "http://encoder.test/v1/embeddings"

  def self.vector(text, dim)
    Array.new(dim) { |i| Math.sin((text.sum + 1) * (i + 1)) * (1 + text.size) }
  end

  def stub_embeddings(dim: 16, base64: true, url: EMBEDDINGS_URL)
    stub_request(:post, url).to_return do |request|
      body = JSON.parse(request.body)
      data = body["input"].each_with_index.map do |text, index|
        vector = FakeEmbeddings.vector(text, dim)
        { index:, embedding: base64 ? Base64.strict_encode64(vector.pack("e*")) : vector }
      end
      { status: 200, headers: { "Content-Type" => "application/json" },
        body: JSON.generate(data: data.reverse, usage: { prompt_tokens: body["input"].sum(&:size) }) }
    end
  end
end

RSpec.configure { |config| config.include FakeEmbeddings }
