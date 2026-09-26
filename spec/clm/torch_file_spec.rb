# frozen_string_literal: true

RSpec.describe CLM::TorchFile do
  subject(:tensors) { described_class.load(torch_fixture("tensors.pt")) }

  it "rebuilds contiguous tensors with their shape" do
    expect(tensors["shared_a"]).to be_a(Numo::SFloat)
    expect(tensors["shared_a"].shape).to eq([4, 6])
    expect(tensors["shared_b"].to_a).to eq([12, 13, 14, 15, 16, 17])
  end

  it "materialises non-contiguous views" do
    expect(tensors["transposed"].to_a).to eq(Array.new(6) { |i| Array.new(4) { |j| (j * 6) + i } })
    expect(tensors["sliced"].to_a).to eq([[6, 8, 10], [12, 14, 16]])
  end

  it "returns 0-d tensors as numbers" do
    expect(tensors["scalar"]).to eq(2.5)
  end

  it "decodes integer, double and bool storages" do
    expect([tensors["long"].class, tensors["long"].to_a]).to eq([Numo::Int64, [1, -2, 3]])
    expect(tensors["double"][0]).to eq(1.0 / 3)
    expect(tensors["flags"].to_a).to eq([1, 0])
  end

  it "widens float16 to float32, including subnormals and infinities" do
    expect(tensors["half"].to_a).to eq([0.0, 1.0, -2.5, 65_504.0, 2.0**-24, Float::INFINITY])
  end

  it "widens bfloat16 to float32" do
    expect(tensors["bf16"].to_a).to eq([1.0, -3.140625, 1.0002555517425873e+30])
  end

  it "keeps plain Python values" do
    expect(tensors["meta"]).to eq("name" => "x", "sizes" => [1, 2])
  end

  it "reads a state_dict saved as an OrderedDict" do
    checkpoint = described_class.load(torch_fixture("gelu_depth2.pt"))
    expect(checkpoint["state_head"].keys).to eq(%w[inp.weight inp.bias out.weight out.bias])
    expect(checkpoint["state_head"]["inp.weight"].shape).to eq([8, 16])
  end

  it "refuses globals a checkpoint never needs" do
    path = torch_fixture("tensors.pt")
    loader = described_class.new(path)
    expect { loader.send(:find_class, "os", "system") }.to raise_error(CLM::CheckpointError, /os.system/)
  end

  it "rejects files that are not torch archives" do
    expect { described_class.load(__FILE__) }.to raise_error(CLM::CheckpointError, /not a torch.save zip archive/)
  end
end
