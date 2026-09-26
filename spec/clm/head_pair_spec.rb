# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe CLM::HeadPair do
  let(:inputs) { Numo::SFloat.cast(torch_expectations["inputs"]) }

  %w[gelu_depth2 silu_layernorm_residual relu_bfloat16 gelu_float16].each do |name|
    context "with the #{name} checkpoint" do
      subject(:pair) { described_class.new(name, torch_fixture("#{name}.pt")) }

      let(:expected) { torch_expectations["cases"][name] }

      it "projects states like PyTorch" do
        expect(pair.project_states(inputs).to_a.flatten)
          .to match(expected["states"].flatten.map { be_within(1e-5).of(_1) })
      end

      it "projects actions like PyTorch" do
        expect(pair.project_actions(inputs).to_a.flatten)
          .to match(expected["actions"].flatten.map { be_within(1e-5).of(_1) })
      end

      it "reads the scale, projection width and parameter count" do
        expect(pair).to have_attributes(scale: be_within(1e-4).of(expected["scale"]),
                                        projection_dim: expected["projection_dim"],
                                        n_params: expected["n_params"], hidden_size: 16)
      end
    end
  end

  describe "hot reloading" do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, "head.pt").tap { FileUtils.cp(torch_fixture("gelu_depth2.pt"), _1) } }

    after { FileUtils.remove_entry(dir) }

    it "reloads when the checkpoint changes and bumps the generation" do
      pair = described_class.new("clm-latest", path)
      expect(pair.namespace).to eq("clm-latest@1")
      FileUtils.cp(torch_fixture("relu_bfloat16.pt"), path)
      File.utime(Time.now + 5, Time.now + 5, path)
      expect([pair.namespace, pair.cfg["activation"]]).to eq(["clm-latest@2", "relu"])
    end

    it "does not reload an unchanged file" do
      pair = described_class.new("clm-latest", path)
      2.times { pair.ensure_loaded }
      expect(pair.generation).to eq(1)
    end
  end

  it "raises CheckpointError for a missing file" do
    expect { described_class.new("x", "/nope.pt").scale }.to raise_error(CLM::CheckpointError, /does not exist/)
  end

  it "raises CheckpointError for a torch file that is not a CLM checkpoint" do
    expect { described_class.new("x", torch_fixture("tensors.pt")).scale }
      .to raise_error(CLM::CheckpointError, /not a CLM checkpoint: missing "cfg"|has no cfg/)
  end
end
