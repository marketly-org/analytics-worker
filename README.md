# analytics-worker

Background worker for the **Marketly** analytics warehouse.

Consumes `order.*` and `payment.*` events from Sidekiq queues, writes
them into the analytics Postgres warehouse, and maintains a rolling
inventory-velocity counter used by the catalog team to spot trending
products.

## Stack

- **Ruby 3.3** + **Sidekiq 7**
- Redis (broker + distributed locks), Postgres (warehouse)

## Queues

| Queue | Worker | Description |
|-------|--------|-------------|
| `orders` | `OrderWorker` | Persist order event, bump inventory velocity |
| `payments` | `PaymentWorker` | Persist payment event, adjust velocity on refund |
| `default` | (misc) | Catch-all |

## Local development

```bash
bundle install
bundle exec sidekiq -C config/sidekiq.yml -r ./app/sidekiq_init.rb
```

## Tests

```bash
bundle exec rspec spec --format documentation
```

## Configuration

| Env var | Default | Description |
|---------|---------|-------------|
| `REDIS_URL` | `redis://localhost:6379/1` | Redis broker URL |
| `POSTGRES_HOST` | `localhost` | Warehouse host |
| `SIDEKIQ_CONCURRENCY` | `10` | Worker threads per process |
| `HEALTH_PORT` | `8080` | HTTP health server port |
