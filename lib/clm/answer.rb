# frozen_string_literal: true

module CLM
  # One question's answer.
  #
  # Each type reads as a Ruby value (a noul as its probability, a choice as its label, a score as
  # its rubric level) and renders the TypeSafe wire payload through {#to_h}.  Where an answer is
  # reduced to one discrete label, the rules are upstream CLM's +schema.label_of+.
  class Answer
    attr_reader :type, :confidence

    # Parses a wire-format answer hash.
    def self.from_h(hash)
      hash = hash.transform_keys(&:to_s)
      case hash["type"].to_s
      when "noul" then Noul.new(probability: Float(hash.fetch("noul")))
      when "choice" then Choice.new(choice: hash.fetch("choice"), probabilities: probabilities(hash),
                                    confidence: Float(hash.fetch("confidence")))
      when "score" then Score.new(score: Float(hash.fetch("score")), probabilities: probabilities(hash),
                                  legend: hash.fetch("legend", {}).transform_keys(&:to_s),
                                  confidence: Float(hash.fetch("confidence")))
      else raise Error, "unknown answer type #{hash["type"].inspect}"
      end
    end

    def self.probabilities(hash)
      hash.fetch("probabilities").to_h { |key, p| [key.to_s, Float(p)] }
    end
    private_class_method :probabilities

    def initialize(type:, confidence:)
      @type = type
      @confidence = confidence
    end

    # The wire payload, with +type+ first as the server writes it.
    def to_h
      { "type" => type, **payload, "confidence" => confidence }.compact
    end

    def inspect = "#<#{self.class.name} #{summary}>"
    def to_s = summary

    private

    def payload = raise(NotImplementedError)
    def summary = raise(NotImplementedError)

    # The top label of a choice question, with a probability per option.
    class Choice < Answer
      attr_reader :choice, :probabilities

      def initialize(choice:, probabilities:, confidence:)
        super(type: "choice", confidence:)
        @choice = choice
        @probabilities = probabilities
      end

      # The probability of the chosen label, or of +label+ when one is given.
      def probability(label = choice)
        probabilities.fetch(label.to_s) do
          raise KeyError, "no option #{label.inspect}; this question offered #{probabilities.keys.inspect}"
        end
      end

      # The chosen label stands in for itself, so a call site reads as the decision it is:
      #
      #   answer == :billing # => true
      #   answer.billing?    # => true
      def ==(other)
        case other
        when Symbol, String then choice.to_s == other.to_s
        when Answer::Choice then choice == other.choice
        else super
        end
      end
      alias eql? ==

      def hash = [self.class, choice].hash
      def to_sym = choice.to_sym
      def to_s = choice.to_s

      # +answer.billing?+ for any label this question offered.
      def method_missing(name, *args)
        return super unless name.end_with?("?") && args.empty? && offered?(name.to_s.delete_suffix("?"))

        choice.to_s == name.to_s.delete_suffix("?")
      end

      def respond_to_missing?(name, include_private = false)
        (name.end_with?("?") && offered?(name.to_s.delete_suffix("?"))) || super
      end

      def offered?(label)
        probabilities.key?(label.to_s)
      end

      private

      def payload = { "choice" => choice, "probabilities" => probabilities }
      def summary = format("%<choice>s %<p>.1f%%", choice:, p: probability * 100)
    end

    # The expected level of a score question on its ordered rubric.
    class Score < Answer
      attr_reader :score, :legend, :probabilities

      def initialize(score:, legend:, probabilities:, confidence:)
        super(type: "score", confidence:)
        @score = score
        @legend = legend
        @probabilities = probabilities
      end

      # The rubric text of the most likely level, as upstream's +label_of+ picks it (ties go to
      # the lower level).  It can differ from the level nearest +score+ when the answer is
      # split: 0.5 on "calm" and 0.5 on "furious" labels "calm", though the expected level is 1.
      def label
        level = probabilities.max_by { |_, p| p }.first
        legend.fetch(level, level)
      end

      def to_f = score
      def levels = legend.length

      # Compare against a level index or its text.
      def ==(other)
        case other
        when Numeric then score == other
        when Symbol, String then label.to_s == other.to_s
        when Answer::Score then score == other.score
        else super
        end
      end

      private

      def payload = { "score" => score, "legend" => legend, "probabilities" => probabilities }
      def summary = format("%<score>.2f of %<top>d (%<label>s)", score:, top: legend.length - 1, label:)
    end

    # The probability that a noul statement holds.
    class Noul < Answer
      attr_reader :probability
      alias noul probability

      def initialize(probability:)
        super(type: "noul", confidence: nil)
        @probability = probability
      end

      # True when the statement's probability reaches +threshold+; at the default 0.5 this is
      # upstream's +label_of+, so an even answer reads as true.
      def true?(threshold = 0.5)
        probability >= threshold
      end

      def false?(threshold = 0.5) = !true?(threshold)
      def to_f = probability

      # Both sides of the statement, as the other answer types report theirs.
      def probabilities
        { "false" => 1.0 - probability, "true" => probability }
      end

      def ==(other)
        case other
        when true, false then true? == other
        when Numeric then probability == other
        when Answer::Noul then probability == other.probability
        else super
        end
      end

      private

      def payload = { "noul" => probability }
      def summary = format("%.1f%%", probability * 100)
    end
  end
end
