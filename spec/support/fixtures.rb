# frozen_string_literal: true

module FixtureHelpers
  TORCH = File.expand_path("../fixtures/torch", __dir__)

  def torch_fixture(name)
    File.join(TORCH, name)
  end

  def torch_expectations
    @torch_expectations ||= JSON.parse(File.read(torch_fixture("expected.json")))
  end
end

RSpec.configure { |config| config.include FixtureHelpers }
