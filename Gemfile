source "https://rubygems.org"

ruby "3.3.12"

# Background job processing
gem "sidekiq", "~> 7.3"
gem "redis-client", "~> 0.22"

# Postgres access
gem "pg", "~> 1.5"
gem "connection_pool", "~> 2.4"

# JSON parsing
gem "json", "~> 2.7"

# Logging
gem "logger", "~> 1.6"

# Environment loading
gem "dotenv", "~> 3.1", groups: [:development, :test]

group :test do
  gem "rspec", "~> 3.13"
  gem "rack", "~> 3.0"
  gem "mock_redis", "~> 0.42"
end
