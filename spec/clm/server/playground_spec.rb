# frozen_string_literal: true

require "rack/test"

RSpec.describe CLM::Server::Playground do
  include Rack::Test::Methods

  let(:app) { CLM::Server.new(instance_double(CLM::Engine)) }

  it "serves the page with cache-busting asset stamps" do
    get "/"
    expect(last_response.status).to eq(200)
    expect(last_response.headers)
      .to include("content-type" => "text/html; charset=utf-8", "cache-control" => "no-cache")
    expect(last_response.body).to match(/href="app\.css\?v=\h+"/).and match(/src="app\.js\?v=\h+"/)
  end

  it "serves the assets for revalidation" do
    get "/app.js?v=abc"
    expect(last_response.status).to eq(200)
    expect(last_response.headers).to include("cache-control" => "no-cache", "content-type" => include("javascript"))
    get "/app.js", {}, { "HTTP_IF_MODIFIED_SINCE" => last_response.headers["last-modified"] }
    expect(last_response.status).to eq(304)
  end

  it "generates Ruby snippets rather than Python" do
    get "/app.js"
    expect(last_response.body).to include("CLM.ask(").and include(%(require "clm"))
  end

  it "serves nothing else from disk" do
    get "/../server.rb"
    expect(last_response.status).to eq(404)
  end

  context "without the UI" do
    let(:app) { CLM::Server.new(instance_double(CLM::Engine), ui: false) }

    it "answers 404 at /" do
      get "/"
      expect(last_response.status).to eq(404)
    end
  end
end
