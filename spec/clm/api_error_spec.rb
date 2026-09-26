# frozen_string_literal: true

RSpec.describe CLM::APIError do
  describe ".for_status" do
    it "maps the statuses the server documents" do
      expect([401, 422, 502, 503].map { described_class.for_status(_1) })
        .to eq([CLM::UnauthorizedError, CLM::UnprocessableEntityError, CLM::BadGatewayError,
                CLM::ServiceUnavailableError])
    end

    it "falls back to ServerError for other 5xx and APIError otherwise" do
      expect([500, 404].map { described_class.for_status(_1) }).to eq([CLM::ServerError, described_class])
    end
  end

  it "prefixes the message with the status" do
    expect(described_class.new("invalid API key", status: 401).message).to eq("401: invalid API key")
  end
end
