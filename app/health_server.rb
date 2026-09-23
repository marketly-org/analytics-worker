# frozen_string_literal: true

# Tiny embedded HTTP health server for k8s probes.
#
# Sidekiq itself does not serve HTTP, so we run a stdlib WEBrick
# listener in a background thread. It exposes:
#
#   GET /health  — process is alive (always 200 once booted)
#   GET /ready   — Redis is reachable (200) or not (503)
#
# The server is bound to 0.0.0.0:8080 by default.

require "webrick"
require "json"

module Analytics
  class HealthServer
    attr_reader :server

    def initialize(port: ENV.fetch("HEALTH_PORT", "8080").to_i)
      @server = WEBrick::HTTPServer.new(
        Port: port,
        BindAddress: "0.0.0.0",
        Logger: WEBrick::Log.new(File::NULL),
        AccessLog: []
      )
      mount_routes
    end

    def mount_routes
      @server.mount_proc("/health") do |_req, res|
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(status: "ok", service: "analytics-worker")
      end

      @server.mount_proc("/ready") do |_req, res|
        res["Content-Type"] = "application/json"
        if redis_ok?
          res.body = JSON.generate(status: "ready")
        else
          res.status = 503
          res.body = JSON.generate(status: "not_ready")
        end
      end
    end

    def start_async
      @thread = Thread.new { @server.start }
      self
    end

    def stop
      @server&.shutdown
      @thread&.join(2)
    end

    private

    def redis_ok?
      Analytics::REDIS.with { |c| c.call("PING") }
      true
    rescue StandardError
      false
    end
  end
end
