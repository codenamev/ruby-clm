# frozen_string_literal: true

RSpec.describe CLM do
  it "has a version number" do
    expect(CLM::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  it "eager loads every file without errors" do
    expect { described_class.loader.eager_load(force: true) }.not_to raise_error
  end

  describe ".configure" do
    it "yields the global configuration" do
      described_class.configure { |c| c.base_url = "http://clm.test" }
      expect(described_class.config.base_url).to eq("http://clm.test")
    end
  end

  describe ".reset!" do
    it "restores the defaults" do
      described_class.configure { |c| c.model = "custom" }
      described_class.reset!
      expect(described_class.config.model).to eq("clm-latest")
    end
  end
end
