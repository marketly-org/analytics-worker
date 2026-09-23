# frozen_string_literal: true

require "logger"
require "sidekiq"

# spec_helper pulls in the lock helper + models WITHOUT booting the
# real Redis/Postgres pools (which would break CI). We define minimal
# stubs for Analytics::REDIS / Analytics::DB / Analytics::LOGGER first
# so the lock helper can construct its singleton at load time. Tests
# that exercise a worker stub out Analytics::DB and the lock layer
# explicitly (see spec/workers/).

class FakePool # :nodoc:
  def with
    yield(Object.new)
  end
end

module Analytics
  REDIS = FakePool.new
  DB = FakePool.new
  LOGGER = Logger.new(File::NULL)
end

require_relative "../app/lock/distributed_lock"
require_relative "../app/models/order"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.mock_with :rspec do |m|
    m.syntax = :expect
  end
  config.disable_monkey_patching!
  config.order = :random
end
