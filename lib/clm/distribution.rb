# frozen_string_literal: true

module CLM
  # The arithmetic that turns per-candidate logits into an answer distribution.
  module Distribution
    module_function

    # Numerically stable softmax of +logits+.
    def softmax(logits)
      max = logits.max
      exps = logits.map { |logit| Math.exp(logit - max) }
      total = exps.sum
      exps.map { |e| e / total }
    end

    # TypeSafe-style confidence: the top probability minus the mean of the rest,
    # clamped to [0, 1].  A single option is always fully confident.
    def confidence(probabilities)
      return 1.0 if probabilities.size < 2

      top = probabilities.each_index.max_by { |i| probabilities[i] }
      rest = probabilities.reject.with_index { |_, i| i == top }
      (probabilities[top] - (rest.sum / rest.size)).clamp(0.0, 1.0)
    end
  end
end
