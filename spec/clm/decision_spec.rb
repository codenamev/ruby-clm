# frozen_string_literal: true

RSpec.describe CLM::Decision do
  let(:client) { FakeClient.new }
  let(:triage) do
    Class.new(described_class) do
      choice :department, "Which team should handle this?", billing: "invoices", technical: "outages"
      score :urgency, "How urgent is this?", levels: ["not urgent", "soon", "critical"]
      noul :churn_risk, "Does the customer threaten to cancel?", yes: "They say they will leave"
    end
  end

  it "declares its questions in the wire format, in order" do
    expect(triage.questions).to eq(
      department: CLM::Questions.choice("Which team should handle this?", billing: "invoices", technical: "outages"),
      urgency: CLM::Questions.score("How urgent is this?", ["not urgent", "soon", "critical"]),
      churn_risk: CLM::Questions.noul("Does the customer threaten to cancel?", yes: "They say they will leave")
    )
  end

  describe ".decide" do
    subject(:decision) { triage.decide("Customer: I was billed twice, fix it or I leave", client:) }

    it "asks every question in one call" do
      decision
      expect(client.calls).to contain_exactly(include(state: "Customer: I was billed twice, fix it or I leave",
                                                      questions: triage.questions, options: {}))
    end

    it "reads each answer by name, with a predicate for every noul" do
      expect([decision.department == :billing, decision.department.billing?, decision.urgency.label,
              decision.churn_risk?]).to eq([true, true, "soon", true])
    end

    it "keeps the result and its wire payload" do
      expect([decision[:urgency], decision.model, decision.to_h.keys])
        .to match([decision.urgency, "fake", %w[model answers usage]])
    end

    it "uses the shared client by default" do
      CLM.configure { |c| c.client = client }
      triage.decide("state")
      expect(client.calls.size).to eq(1)
    end
  end

  describe ".model" do
    it "pins the served model, and subclasses inherit it with the questions" do
      pinned = Class.new(triage) { model "clm-raw" }
      child = Class.new(pinned) { noul :spam, "Is this spam?" }
      child.decide("state", client:)
      expect(client.calls.last[:options]).to eq(model: "clm-raw")
      expect(child.questions.keys).to eq(%i[department urgency churn_risk spam])
      expect(triage.questions.keys).not_to include(:spam)
    end
  end

  describe ".define" do
    it "builds a decision from a question hash, keeping its ids" do
      shipped = described_class.define({ "refund" => { "type" => "noul", "instructions" => "Money back?" } },
                                       model: "clm-latest")
      decision = shipped.decide("I want my money back", client:)
      expect([decision.refund?, decision["refund"].probability, shipped.model]).to eq([true, 0.8, "clm-latest"])
    end
  end

  it "shows its answers when inspected" do
    stub_const("TicketTriage", triage)
    expect(triage.decide("s", client:).inspect)
      .to eq("#<TicketTriage department=billing urgency=1.00 of 2 (soon) churn_risk=80.0%>")
  end
end
