# frozen_string_literal: true

RSpec.describe CLM::Connection do
  let(:sleeps) { [] }
  let(:replies) { [] }
  let(:requests) { [] }
  let(:transport) do
    lambda do |**request|
      requests << request
      reply = replies.shift
      reply.is_a?(Exception) ? raise(reply) : reply
    end
  end

  def connection(**options)
    described_class.new(base_url: "http://clm.test/", api_key: "k", transport:, sleeper: sleeps.method(:<<),
                        random: -> { 0.0 }, **options)
  end

  def json(status, body, headers = {})
    [status, JSON.generate(body), { "content-type" => "application/json" }.merge(headers)]
  end

  it "posts JSON with the bearer key and parses the JSON reply" do
    replies << json(200, { ok: true })
    response = connection.post("/v1/systemone", { state: "s" })
    expect(response).to have_attributes(status: 200, body: { "ok" => true })
    expect(requests.first).to include(method: :post, url: "http://clm.test/v1/systemone", body: '{"state":"s"}',
                                      headers: include("Authorization" => "Bearer k"))
  end

  it "uses a full URL as given" do
    replies << [200, "", {}]
    connection.get("http://other.test/v1/models", timeout: 5)
    expect(requests.first).to include(url: "http://other.test/v1/models", timeout: 5)
  end

  it "retries a retryable status, honouring Retry-After" do
    replies.push(json(503, { detail: "busy" }, "retry-after" => "2"), json(200, {}))
    expect(connection.get("/health").status).to eq(200)
    expect(sleeps).to eq([2.0])
  end

  it "gives up after max_retries and raises the status's error" do
    replies.push(*Array.new(3) { json(429, { detail: "slow down" }) })
    expect { connection.get("/health") }.to raise_error(CLM::RateLimitedError, "429: slow down")
    expect(sleeps).to eq([0.5, 1.0])
  end

  it "retries a connection failure, then reports the server unreachable" do
    replies.push(Errno::ECONNREFUSED.new, Errno::ECONNREFUSED.new)
    expect { connection(retry: { max_retries: 1 }).get("/health") }
      .to raise_error(CLM::ConnectionError, %r{unreachable at http://clm.test})
    expect(requests.size).to eq(2)
  end

  it "reports a timeout as TimeoutError" do
    replies << Net::ReadTimeout.new
    expect { connection(retry: { max_retries: 0 }).get("/health") }.to raise_error(CLM::TimeoutError)
  end

  it "stops retrying once the total budget is spent" do
    clock = [0.0, 10.0].each
    replies.push(json(503, {}), json(200, {}))
    conn = connection(retry: { total_timeout: 5 }, clock: -> { clock.next })
    expect { conn.get("/health") }.to raise_error(CLM::ServiceUnavailableError)
  end

  it "does not retry a client error" do
    replies << json(422, { detail: "bad" })
    expect { connection.get("/health") }.to raise_error(CLM::UnprocessableEntityError)
    expect(requests.size).to eq(1)
  end
end
