# frozen_string_literal: true

require "numo/narray"

module CLM
  # One projection head: an MLP from an encoder embedding to the contrastive space,
  #
  #   hidden -> width -> (width -> width) * (depth - 2) -> projection_dim
  #
  # with an activation after every hidden layer and optional LayerNorm / residual
  # connections on the inner blocks.  This is +clm.heads.make_head+ in Numo.
  #
  # Matrix products go through Numo::NArray#dot, which uses BLAS when numo-linalg is
  # loaded (+require "numo/linalg/autoloader"+) and plain C loops otherwise.
  class Head
    HIDDEN_SIZE = 4096 # Qwen3-8B hidden size (the encoder embedding width)
    PROJECTION_DIM = 512

    Linear = Data.define(:weight_t, :bias) do
      def call(x) = x.dot(weight_t) + bias
      def in_features = weight_t.shape.first
      def out_features = weight_t.shape.last
      def n_params = weight_t.size + bias.size
    end

    LayerNorm = Data.define(:weight, :bias, :eps) do
      def call(x)
        centered = x - x.mean(axis: -1, keepdims: true)
        variance = (centered**2).mean(axis: -1, keepdims: true)
        (centered / Numo::NMath.sqrt(variance + eps) * weight) + bias
      end

      def n_params = weight.size + bias.size
    end

    ACTIVATIONS = {
      "gelu" => ->(x) { x * 0.5 * (1 + Numo::NMath.erf(x / Math.sqrt(2))) }, # exact, as nn.GELU()
      "relu" => ->(x) { x * x.gt(0).cast_to(x.class) },
      "silu" => ->(x) { x / (1 + Numo::NMath.exp(-x)) }
    }.freeze

    attr_reader :input, :hidden, :norms, :output, :activation, :residual

    # Builds a head from a PyTorch state dict (+inp.*+, +hidden.N.*+, +norms.N.*+, +out.*+).
    def self.from_state_dict(state_dict, depth:, activation: "gelu", layernorm: false, residual: false)
      linear = lambda do |prefix|
        weight = state_dict.fetch("#{prefix}.weight") { raise CheckpointError, "state dict has no #{prefix}.weight" }
        Linear.new(weight_t: Numo::SFloat.cast(weight).transpose.dup,
                   bias: Numo::SFloat.cast(state_dict.fetch("#{prefix}.bias")))
      end
      inner = (0...(depth - 2)).to_a
      norms = inner.map do |i|
        next unless layernorm

        LayerNorm.new(weight: Numo::SFloat.cast(state_dict.fetch("norms.#{i}.weight")),
                      bias: Numo::SFloat.cast(state_dict.fetch("norms.#{i}.bias")), eps: 1e-5)
      end
      new(input: linear.call("inp"), hidden: inner.map { linear.call("hidden.#{_1}") }, norms:,
          output: linear.call("out"), activation:, residual:)
    rescue KeyError => e
      raise CheckpointError, "state dict is missing #{e.key}"
    end

    def initialize(input:, output:, hidden: [], norms: [], activation: "gelu", residual: false)
      @input = input
      @hidden = hidden
      @norms = norms
      @output = output
      @activation = ACTIVATIONS.fetch(activation.to_s) do
        raise CheckpointError, "unknown activation #{activation.inspect}; expected one of #{ACTIVATIONS.keys}"
      end
      @residual = residual
    end

    # [n, hidden_size] embeddings -> [n, projection_dim] projections (not normalised).
    def call(x)
      x = @activation.call(input.call(Numo::SFloat.cast(x)))
      hidden.zip(norms).each do |linear, norm|
        h = linear.call(x)
        h = @activation.call(norm ? norm.call(h) : h)
        x = residual ? x + h : h
      end
      output.call(x)
    end

    def hidden_size = input.in_features
    def projection_dim = output.out_features

    def n_params
      [input, *hidden, *norms.compact, output].sum(&:n_params)
    end
  end
end
