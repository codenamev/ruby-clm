# frozen_string_literal: true

require "tmpdir"

RSpec.describe CLM::Hub do
  let(:dir) { Dir.mktmpdir }
  let(:resolve) { "https://huggingface.co/Contrastive-LM/CLM-v0.1-8B/resolve/main" }

  after { FileUtils.remove_entry(dir) }

  describe ".download" do
    before { stub_request(:head, "#{resolve}/config.json").to_return(status: 200) }

    it "follows the Hub's redirect to the file and saves it" do
      stub_request(:get, "#{resolve}/CLM_v0.1-8B.pt")
        .to_return(status: 302, headers: { "Location" => "https://cdn.test/blob?sig=1" })
      stub_request(:get, "https://cdn.test/blob?sig=1").to_return(status: 200, body: "weights")
      path = described_class.download(dest_dir: dir, token: nil)
      expect([path, File.read(path)]).to eq([File.join(dir, "CLM_v0.1-8B.pt"), "weights"])
      expect(WebMock).to have_requested(:head, "#{resolve}/config.json")
    end

    it "sends HF_TOKEN to the Hub only" do
      stub_request(:get, "#{resolve}/CLM_v0.1-8B.pt")
        .with(headers: { "Authorization" => "Bearer hf_x" })
        .to_return(status: 302, headers: { "Location" => "https://cdn.test/b" })
      cdn = stub_request(:get, "https://cdn.test/b").to_return(body: "w")
      described_class.download(dest_dir: dir, token: "hf_x")
      expect(cdn.with { |req| !req.headers.key?("Authorization") }).to have_been_requested
    end

    it "skips files that are already there unless forced" do
      File.write(File.join(dir, "CLM_v0.1-8B.pt"), "old")
      expect(File.read(described_class.download(dest_dir: dir))).to eq("old")
      stub_request(:get, "#{resolve}/CLM_v0.1-8B.pt").to_return(body: "new")
      expect(File.read(described_class.download(dest_dir: dir, force: true, token: nil))).to eq("new")
    end

    it "raises DownloadError and leaves no partial file on failure" do
      stub_request(:get, "#{resolve}/CLM_v0.1-8B.pt").to_return(status: 404)
      expect { described_class.download(dest_dir: dir, token: nil) }
        .to raise_error(CLM::Hub::DownloadError, /404/)
      expect(Dir.children(dir)).to be_empty
    end

    it "still downloads when the download counter is unreachable" do
      stub_request(:head, "#{resolve}/config.json").to_raise(SocketError)
      stub_request(:get, "#{resolve}/CLM_v0.1-8B.pt").to_return(body: "w")
      expect(File.read(described_class.download(dest_dir: dir, token: nil))).to eq("w")
    end
  end

  describe ".default_checkpoint" do
    let(:config) { CLM::Configuration.new("CLM_CKPT_DIR" => dir) }

    it "is nil when nothing was downloaded" do
      expect(described_class.default_checkpoint(config)).to be_nil
    end

    it "finds the reference head in the checkpoint directory" do
      File.write(File.join(dir, "CLM_v0.1-8B.pt"), "")
      expect(described_class.default_checkpoint(config)).to eq(File.join(dir, "CLM_v0.1-8B.pt"))
    end

    it "prefers CLM_CKPT when it exists" do
      config.checkpoint = torch_fixture("gelu_depth2.pt")
      expect(described_class.default_checkpoint(config)).to eq(torch_fixture("gelu_depth2.pt"))
    end
  end
end
