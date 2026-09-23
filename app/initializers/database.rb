# frozen_string_literal: true

require "redis-client"
require "pg"
require "connection_pool"
require "logger"

module Analytics
  # Global logger for the worker processes.
  LOGGER = Logger.new($stdout, level: ENV.fetch("LOG_LEVEL", "INFO"))

  # Redis connection pool shared by the distributed-lock helpers and
  # any other application-level Redis use. Sidekiq owns its own pool
  # internally for job state.
  REDIS = ConnectionPool.new(size: ENV.fetch("REDIS_POOL_SIZE", "10").to_i, timeout: 2) do
    RedisClient.config(
      url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"),
      timeout: 1.0,
      reconnect_attempts: 2
    ).new_client
  end

  # Postgres connection pool. Workers check out a connection for the
  # duration of a job and return it on completion.
  DB = ConnectionPool.new(size: ENV.fetch("DB_POOL", "10").to_i, timeout: 5) do
    PG.connect(
      host: ENV.fetch("POSTGRES_HOST", "localhost"),
      port: ENV.fetch("POSTGRES_PORT", "5432").to_i,
      user: ENV.fetch("POSTGRES_USER", "marketly"),
      password: ENV.fetch("POSTGRES_PASSWORD", ""),
      dbname: ENV.fetch("POSTGRES_DB", "marketly_analytics")
    )
  end
end
