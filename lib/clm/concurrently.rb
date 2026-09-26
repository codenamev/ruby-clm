# frozen_string_literal: true

require "async"
require "async/semaphore"

module CLM
  # Fan-out over Async tasks with plain-Ruby semantics: results come back in
  # order and the first failure is raised in the caller.
  #
  # It works inside or outside a reactor (Sync reuses the current one), so the
  # engine and embedder fan out whether they run in a script or under Falcon.
  module Concurrently
    module_function

    # Maps +items+ through the block, one task per item (at most +limit+ at a time).
    def map(items, limit: nil, &block)
      return items.map(&block) if items.size <= 1

      Sync do |task|
        spawner = limit ? Async::Semaphore.new(limit, parent: task) : task
        tasks = items.map { |item| spawner.async { capture { block.call(item) } } }
        tasks.map { unwrap(_1.wait) }
      end
    end

    # Failures are returned rather than raised, so a failing task is never
    # reported as unhandled while its siblings are still being waited on.
    def capture
      [true, yield]
    rescue StandardError => e
      [false, e]
    end

    def unwrap((ok, value))
      ok ? value : raise(value)
    end
    private_class_method :capture, :unwrap
  end
end
