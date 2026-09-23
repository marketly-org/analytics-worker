# frozen_string_literal: true

# Required by Sidekiq via `sidekiq -r ./app/sidekiq_init.rb`.
#
# Boots the Redis/PG pools, loads all workers + models, and wires
# Sidekiq server lifecycle hooks to start/stop the embedded HTTP
# health server alongside the Sidekiq process.

require_relative "initializers/database"
require_relative "lock/distributed_lock"
require_relative "models/order"
require_relative "health_server"
require_relative "workers/base_worker"
require_relative "workers/order_worker"
require_relative "workers/payment_worker"

# Start the health server when Sidekiq boots, stop it on shutdown.
health_server = nil

Sidekiq.configure_server do |_config|
  health_server = Analytics::HealthServer.new.start_async
  Analytics::LOGGER.info("boot" => "health-server",
                         "port" => ENV.fetch("HEALTH_PORT", "8080"))
end

at_exit do
  health_server&.stop
  Analytics::LOGGER.info("shutdown" => "analytics-worker")
end

Analytics::LOGGER.info("boot" => "analytics-worker",
                       "queues" => %w[orders payments default])
