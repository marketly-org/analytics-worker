# frozen_string_literal: true

require "securerandom"

module Analytics
  module Lock
    # A simple Redis-backed distributed lock using SET NX PX.
    #
    # This is NOT a full Redlock implementation — it is a single-node
    # Redis lock sufficient for the analytics-worker's needs (the
    # worker pool shares one Redis). The lock auto-expires after `ttl_ms`
    # so a crashed worker cannot hold a lock forever.
    class DistributedLock
      class LockError < StandardError; end

      def initialize(redis: Analytics::REDIS, ttl_ms: 30_000, retry_ms: 100, max_wait_ms: 5_000)
        @redis = redis
        @ttl_ms = ttl_ms
        @retry_ms = retry_ms
        @max_wait_ms = max_wait_ms
      end

      # Acquire a single lock, blocking until acquired or until
      # +max_wait_ms+ elapses (in which case LockError is raised).
      def acquire(name)
        token = SecureRandom.hex(16)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) + @max_wait_ms
        loop do
          ok = @redis.with { |c| c.set("lock:#{name}", token, nx: true, px: @ttl_ms) }
          return token if ok

          if Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) >= deadline
            raise LockError, "could not acquire lock '#{name}' within #{@max_wait_ms}ms"
          end
          sleep(@retry_ms / 1000.0)
        end
      end

      # Release a lock we hold. Uses a Lua CAS check so we never
      # release a lock that has already expired and been re-acquired
      # by someone else.
      RELEASE_SCRIPT = <<~LUA.freeze
        if redis.call("get", KEYS[1]) == ARGV[1] then
          return redis.call("del", KEYS[1])
        else
          return 0
        end
      LUA

      def release(name, token)
        @redis.with { |c| c.eval(RELEASE_SCRIPT, keys: ["lock:#{name}"], argv: [token]) }
      end

      # Acquire +name+, yield to the caller, and always release.
      def with_lock(name)
        token = acquire(name)
        begin
          yield
        ensure
          release(name, token)
        end
      end

      # Acquire a list of locks IN ORDER, yield, and release in reverse
      # order. If any lock in the chain cannot be acquired, all
      # previously-acquired locks are released and LockError is raised.
      #
      # Callers MUST pass the same lock list in the same order for any
      # set of overlapping resources, otherwise two workers can
      # deadlock: worker A holds lock 1 waiting for lock 2, worker B
      # holds lock 2 waiting for lock 1.
      def with_locks(*names)
        acquired = []
        begin
          names.each do |n|
            acquired << [n, acquire(n)]
          end
          yield
        ensure
          acquired.reverse_each do |(n, token)|
            release(n, token)
          end
        end
      end
    end

    # A single shared lock instance for the worker pool.
    LOCK = DistributedLock.new
  end
end
