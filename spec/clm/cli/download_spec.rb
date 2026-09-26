# frozen_string_literal: true

RSpec.describe CLM::CLI::Download do
  it "prints the path of the downloaded checkpoint" do
    out = StringIO.new
    allow(CLM::Hub).to receive(:download).and_return("/tmp/x.pt")
    described_class.new(%w[--repo me/heads --file h.pt --dest /tmp --force], out:).run
    expect(CLM::Hub).to have_received(:download).with(repo: "me/heads", filename: "h.pt", dest_dir: "/tmp", force: true)
    expect(out.string).to eq("/tmp/x.pt\n")
  end
end
