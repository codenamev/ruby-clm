# frozen_string_literal: true

RSpec.describe CLM::Pickle do
  # pickle.dumps(obj, protocol=N).hex() in CPython 3.11
  let(:dumps) do
    {
      4 => "800495b3000000000000007d94288c0173948c0668c3a96c6c6f948c01629443020001948c0169945d94284b004bff4dffff4a" \
           "ffffffff8a0500000080008a060000000000ff8a09000000000000000040658c016694473ff80000000000008c016e944e8c01" \
           "7494888986948c066e6573746564947d94288c046c697374945d94284b015d94284b024b0365658c057475706c6594284b014b" \
           "024b034b047494758c03736574948f94284b01908c05656d70747994295d947d948794752e",
      2 => "80027d7100285801000000737101580600000068c3a96c6c6f71025801000000627103635f636f646563730a656e636f64650a" \
           "710458020000000001710558060000006c6174696e31710686710752710858010000006971095d710a284b004bff4dffff4aff" \
           "ffffff8a0500000080008a060000000000ff8a0900000000000000004065580100000066710b473ff800000000000058010000" \
           "006e710c4e580100000074710d888986710e58060000006e6573746564710f7d71102858040000006c69737471115d7112284b" \
           "015d7113284b024b03656558050000007475706c657114284b014b024b034b047471157558030000007365747116635f5f6275" \
           "696c74696e5f5f0a7365740a71175d71184b016185711952711a5805000000656d707479711b295d711c7d711d87711e752e"
    }.transform_values { [_1].pack("H*") }
  end

  let(:expected) do
    { "s" => "héllo", "b" => "\x00\x01".b, "i" => [0, 255, 65_535, -1, 2**31, -2**40, 2**70], "f" => 1.5,
      "n" => nil, "t" => [true, false], "nested" => { "list" => [1, [2, 3]], "tuple" => [1, 2, 3, 4] },
      "set" => Set[1], "empty" => [[], [], {}] }
  end

  # What protocol 2 needs to spell bytes and sets.
  let(:find_class) do
    lambda do |mod, name|
      case [mod, name]
      when %w[_codecs encode] then ->(str, _encoding) { str.encode(Encoding::ISO_8859_1).b }
      when %w[__builtin__ set] then ->(items) { Set.new(items) }
      else raise CLM::Pickle::UnpicklingError, "#{mod}.#{name}"
      end
    end
  end

  it "reads protocol 4 without any globals" do
    expect(described_class.load(dumps[4])).to eq(expected)
  end

  it "reads protocol 2, resolving globals through find_class" do
    expect(described_class.load(dumps[2], find_class:)).to eq(expected)
  end

  it "decodes strings as UTF-8 and bytes as binary" do
    result = described_class.load(dumps[4])
    expect([result["s"].encoding, result["b"].encoding]).to eq([Encoding::UTF_8, Encoding::BINARY])
  end

  it "freezes tuples" do
    expect(described_class.load(dumps[4])["nested"]["tuple"]).to be_frozen
  end

  it "shares memoised objects" do
    shared = described_class.load(["80027d71002858010000006171015d71024b016158010000006271036802752e"].pack("H*"))
    expect(shared["a"]).to be(shared["b"])
  end

  it "refuses globals by default" do
    od = ["800263636f6c6c656374696f6e730a4f726465726564446963740a71002952710158010000006171024b01732e"].pack("H*")
    expect { described_class.load(od) }
      .to raise_error(CLM::Pickle::UnpicklingError, "global collections.OrderedDict is not allowed")
  end

  it "builds allowed globals with REDUCE" do
    od = ["80049529000000000000008c0b636f6c6c656374696f6e73948c0b4f726465726564446963749493942952948c0161944b01732e"]
         .pack("H*")
    expect(described_class.load(od, find_class: ->(*) { -> { {} } })).to eq("a" => 1)
  end

  it "reports truncated data" do
    expect { described_class.load(dumps[4][0, 40]) }.to raise_error(CLM::Pickle::UnpicklingError, /truncated/)
  end

  it "reports unsupported opcodes" do
    expect { described_class.load("\x80\x02I1\n.") }
      .to raise_error(CLM::Pickle::UnpicklingError, "unsupported pickle opcode 0x49")
  end

  it "requires persistent_load for persistent ids" do
    expect { described_class.load("\x80\x02K\x01Q.") }.to raise_error(CLM::Pickle::UnpicklingError, /persistent/)
    expect(described_class.load("\x80\x02K\x01Q.", persistent_load: ->(pid) { pid * 10 })).to eq(10)
  end
end
