# frozen_string_literal: true

require "clm"
require "webmock/rspec"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.order = :random
  Kernel.srand config.seed

  config.before do
    CLM.reset!
    CLM.config.retry_policy = { backoff_initial: 0.0 } # retry as in production, without the waits
  end
end
