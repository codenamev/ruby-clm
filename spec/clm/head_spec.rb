# frozen_string_literal: true

RSpec.describe CLM::Head do
  def linear(weight, bias)
    CLM::Head::Linear.new(weight_t: Numo::SFloat.cast(weight).transpose.dup, bias: Numo::SFloat.cast(bias))
  end

  it "applies input -> activation -> output" do
    head = described_class.new(input: linear([[1, 0], [0, 1]], [0, 0]), output: linear([[1, 1]], [0.5]),
                               activation: "relu")
    expect(head.call([[2.0, -3.0]]).to_a).to eq([[2.5]])
  end

  it "adds residual connections around inner blocks" do
    identity = linear([[1, 0], [0, 1]], [0, 0])
    head = described_class.new(input: identity, hidden: [identity], norms: [nil], output: identity,
                               activation: "relu", residual: true)
    expect(head.call([[1.0, -1.0]]).to_a).to eq([[2.0, 0.0]])
  end

  it "uses the exact (erf) GELU" do
    x = Numo::SFloat[-1.0, 0.0, 1.0]
    expect(described_class::ACTIVATIONS["gelu"].call(x).to_a)
      .to match([be_within(1e-6).of(-0.158655), 0.0, be_within(1e-6).of(0.841345)])
  end

  it "rejects unknown activations" do
    expect { described_class.new(input: nil, output: nil, activation: "tanh") }
      .to raise_error(CLM::CheckpointError, /unknown activation "tanh"/)
  end

  it "reports missing weights" do
    expect { described_class.from_state_dict({}, depth: 2) }.to raise_error(CLM::CheckpointError, /inp.weight/)
  end
end
