# frozen_string_literal: true

module CLM
  # A decision built inline, for the questions not worth a class, as +Laya.ask+ builds one.
  #
  #   answers = CLM.ask(email)
  #                .choice(:department, "Which team?", billing: "invoices", technical: "outages")
  #                .noul(:refund, "Do they want money back?")
  #                .decide
  #
  #   answers.department == :billing # => true
  #   answers[:refund].probability   # => 0.856
  #
  # Each call returns the builder, so the chain reads as the question set it is. {#decide} asks
  # them all in one request and hands back the {Result}.
  class Ask
    attr_reader :state, :questions

    def initialize(state, client: nil, **options)
      @state = state
      @client = client
      @options = options
      @questions = {}
    end

    def choice(name, instructions, criteria = nil, **labels)
      add(name, Questions.choice(instructions, criteria, **labels))
    end

    def score(name, instructions, levels:)
      add(name, Questions.score(instructions, levels))
    end

    def noul(name, instructions, yes: nil, no: nil)
      add(name, Questions.noul(instructions, yes:, no:))
    end

    # Answer with a specific served model rather than the default.
    def using(model)
      @options = @options.merge(model:)
      self
    end

    # Answer every question asked so far, in one request.
    def decide
      raise InvalidRequestError, "ask at least one question before calling decide" if questions.empty?

      (@client || CLM.client).predict(state, questions, **@options)
    end

    def inspect
      "#<CLM::Ask #{questions.keys.inspect}>"
    end

    private

    def add(name, question)
      @questions[name] = question
      self
    end
  end
end
