# frozen_string_literal: true

module CLM
  # The questions of one System One request, keyed by the ids the caller chose.
  #
  # Build one from a hash of questions (objects or wire-format hashes):
  #
  #   CLM::QuestionSet.new(urgency: CLM::Noul.new(instructions: "Is this urgent?"))
  #
  # or with the builder:
  #
  #   CLM::QuestionSet.build do |q|
  #     q.noul :urgency, "Is this urgent?"
  #     q.choice :department, "Which team should handle this?", billing: "Charges, refunds", technical: "Bugs"
  #     q.score :frustration, "How frustrated is the customer?", ["Calm", "Frustrated", "Very angry"]
  #   end
  class QuestionSet
    include Enumerable

    # A QuestionSet from whatever a caller passed: a set, a hash, and/or a builder block.
    def self.coerce(questions = nil, &)
      set = questions.is_a?(QuestionSet) ? questions : new(questions || {})
      set.instance_exec(set, &) if block_given?
      raise InvalidRequestError, "questions must not be empty" if set.empty?

      set
    end

    def self.build(&)
      coerce(&)
    end

    def initialize(questions = {})
      raise InvalidRequestError, "questions must be a Hash of id => question" unless questions.respond_to?(:each_pair)

      @questions = {}
      questions.each_pair { |id, question| add(id, question) }
    end

    def add(id, question)
      @questions[id] = Question.wrap(question)
      self
    end
    alias []= add

    def noul(id, instructions = nil, **criteria)
      add(id, Noul.new(instructions:, criteria: criteria.empty? ? nil : criteria))
    end

    def choice(id, instructions = nil, criteria = nil, **options)
      add(id, Choice.new(instructions:, criteria: criteria || options))
    end

    def score(id, instructions, levels)
      add(id, Score.new(instructions:, criteria: levels))
    end

    def [](id)
      @questions[id]
    end

    def each(&)
      return enum_for(:each) unless block_given?

      @questions.each(&)
      self
    end

    def ids
      @questions.keys
    end

    def size
      @questions.size
    end

    def empty?
      @questions.empty?
    end

    # The wire format: string ids => question hashes.
    def to_h
      @questions.to_h { |id, question| [id.to_s, question.to_h] }
    end

    # Re-keys a wire-format +{"id" => value}+ hash by the caller's own ids, so a
    # question asked as +:urgency+ is answered as +:urgency+.
    def rekey(by_wire_id)
      ids.to_h { |id| [id, by_wire_id.fetch(id.to_s) { by_wire_id.fetch(id) }] }
    end
  end
end
