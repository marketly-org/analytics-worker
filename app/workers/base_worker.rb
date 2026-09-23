# frozen_string_literal: true

require "sidekiq"
require_relative "../lock/distributed_lock"

module Analytics
  module Workers
    # Base class for all analytics workers. Provides shared helpers:
    #
    #   * +lock+ — the shared distributed-lock instance
    #   * +db+   — checks out a Postgres connection for a block
    #   * +logger+ — structured logger
    #
    # Workers implement +#perform+ themselves. Structured start/finish
    # logging is wired via Sidekiq server middleware in +boot.rb+.
    class BaseWorker
      include Sidekiq::Job

      class << self
        def lock
          Analytics::Lock::LOCK
        end
      end

      def lock
        self.class.lock
      end

      def logger
        Analytics::LOGGER
      end

      def db(&block)
        Analytics::DB.with(&block)
      end
    end
  end
end
