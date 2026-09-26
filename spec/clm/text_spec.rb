# frozen_string_literal: true

RSpec.describe CLM::Text do
  describe ".render" do
    it "passes strings through and stringifies scalars" do
      expect([nil, "hi", :sym, 3, 1.5, true, false].map { described_class.render(_1) })
        .to eq(["", "hi", "sym", "3", "1.5", "true", "false"])
    end

    it "renders a hash as key: value fields separated by blank lines" do
      expect(described_class.render({ "user" => "ada", "age" => 36 })).to eq("user: ada\n\nage: 36")
    end

    it "indents nested structures and keeps key order" do
      state = { user: { name: "ada", tags: %w[vip new] }, cart: [], note: nil }
      expect(described_class.render(state))
        .to eq("user:\n  name: ada\n  tags:\n    - vip\n    - new\n\ncart: \n\nnote: ")
    end

    it "renders an array as - item lines, nesting hashes below a bare dash" do
      expect(described_class.render(["a", { b: 1, c: 2 }])).to eq("- a\n-\n  b: 1\n  c: 2")
    end
  end

  describe ".state" do
    it "puts the context first and the question last" do
      expect(described_class.state({ ticket: "refund?" }, "Is this urgent?"))
        .to eq("ticket: refund?\n\nIs this urgent?")
    end

    it "drops whichever part is blank" do
      expect([described_class.state("  ", "Q?"), described_class.state("ctx", nil)]).to eq(["Q?", "ctx"])
    end
  end
end
