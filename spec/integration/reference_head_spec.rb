# frozen_string_literal: true

require "digest"

# The released head (Contrastive-LM/CLM-v0.1-8B) against what PyTorch computes with it.
# Opt-in: runs only when the head is cached locally (clm-download), since CI does not
# fetch 72 MB.  spec/fixtures/torch/generate_reference.py records the expectations.
RSpec.describe "the reference head" do # rubocop:disable RSpec/DescribeClass
  let(:path) { File.join(CLM::Configuration.new.checkpoint_dir, CLM::Hub::FILENAME) }
  let(:reference) { JSON.parse(File.read(torch_fixture("reference_head.json"))) }
  let(:pair) { CLM::HeadPair.new("clm-latest", path) }
  let(:inputs) do
    rows = Array.new(reference["rows"]) do |i|
      CLM::Embedder.normalize(Numo::NMath.sin(Numo::DFloat.new(pair.hidden_size).seq(1) * ((i + 1) * 0.001)))
    end
    Numo::SFloat.cast(rows)
  end

  before do
    skip "the reference head is not cached at #{path}; run clm-download" unless File.exist?(path)
    if Digest::SHA256.file(path).hexdigest != reference["checkpoint_sha256"]
      skip "#{path} is not the checkpoint the reference outputs were recorded with"
    end
  end

  it "loads the released architecture" do
    expect(pair).to have_attributes(scale: reference["scale"], projection_dim: reference["projection_dim"],
                                    n_params: reference["n_params"])
  end

  it "projects states like PyTorch" do
    expect(pair.project_states(inputs).to_a.flatten)
      .to match(reference["states"].flatten.map { be_within(1e-5).of(_1) })
  end

  it "projects actions like PyTorch" do
    expect(pair.project_actions(inputs).to_a.flatten)
      .to match(reference["actions"].flatten.map { be_within(1e-5).of(_1) })
  end
end
