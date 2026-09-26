# frozen_string_literal: true

# A client double answering predict(state, questions, **options) the way a CLM::Client or
# CLM::Engine does, recording what it was asked.  Every noul is 0.8, the first choice option
# wins at 0.9, and every score sits on level 1.
class FakeClient
  attr_reader :calls

  def initialize
    @calls = []
  end

  def predict(state, questions, **options)
    @calls << { state:, questions:, options: }
    answers = CLM::Question.build_all(questions).transform_values { |question| answer(question) }
    CLM::Result.new(model: options.fetch(:model, "fake"), answers:)
  end

  private

  def answer(question)
    count = question.keys.size
    question.answer(case question.type
                    when "noul" then [0.2, 0.8]
                    when "choice" then [0.9, *Array.new(count - 1) { 0.1 / (count - 1) }]
                    else Array.new(count) { |level| level == 1 ? 1.0 : 0.0 }
                    end)
  end
end
