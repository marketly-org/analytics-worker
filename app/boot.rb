# frozen_string_literal: true

# This file exists only for ad-hoc local execution / IRB. The real
# entrypoint is `sidekiq -r ./app/sidekiq_init.rb`.

require_relative "sidekiq_init"
require "sidekiq/cli"

Sidekiq::CLI.instance.parse(ARGV)
