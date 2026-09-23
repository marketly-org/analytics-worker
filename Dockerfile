# syntax=docker/dockerfile:1.6

# ---- Build stage ----
FROM ruby:3.3-slim AS builder

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock* ./
RUN bundle config set without "development test" \
    && bundle install --jobs 4 --retry 3

COPY . .

# ---- Runtime stage ----
FROM ruby:3.3-slim AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq5 ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -r app && useradd -r -g app -d /app app

WORKDIR /app

COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --from=builder /app /app

USER app

EXPOSE 8080

ENV HEALTH_PORT=8080
ENV REDIS_URL=redis://redis:6379/1
ENV RACK_ENV=production

CMD ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml", "-r", "./app/sidekiq_init.rb"]
