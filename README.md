## Snarf (down)
snarf: to eat (something) quickly or greedily

Pluggable batch ingest API for postgres, solr, and files.

## Running with Docker

```bash
docker compose up
```

Starts Postgres, Redis, Solr, the API (`web`), and the Sidekiq `worker`. The API is at http://localhost:3000 (`/healthz` for a health check).

- Code is bind-mounted; restart `web`/`worker` to pick up changes.
- Rebuild after changing `Gemfile` or `Gemfile.lock`: `docker compose build`
- Console: `docker compose run --rm web bin/console`
- On Linux, set `UID` and `GID` in `.env` to your own so files created in the container are owned by you.

## Tests and checks

Run locally (Ruby version in `Dockerfile`), or in the container by prefixing with `docker compose run --rm --no-deps web`.

| Check | Command |
|---|---|
| Tests | `bundle exec rspec` |
| Style / lint | `bundle exec rubocop` |
| Code smells | `bundle exec reek` |
| Vulnerable gems | `bundle exec bundle-audit check --update` |

Tests and linters don't need Postgres, Redis, or Solr running.

## Production images

One `Dockerfile`, one target per process. Images contain production gems only and run as the non-root `snarf` user.

```bash
docker build --target web -t ghcr.io/samvera-labs/snarf-web:TAG .
```

```bash
docker build --target worker -t ghcr.io/samvera-labs/snarf-worker:TAG .
```

## Configuration

| Variable | Default | Notes |
|---|---|---|
| `APP_ENV` | `development` | `production` in production images |
| `DATABASE_URL` | `postgres://localhost/snarf_<APP_ENV>` | Required in production |
| `REDIS_URL` | `redis://localhost:6379` | Used by Sidekiq |
| `DB_POOL` | `5` | Keep ≥ `PUMA_THREADS` and Sidekiq concurrency (default 5) |
| `PUMA_THREADS` | `3` | Threads per Puma process |
| `WEB_CONCURRENCY` | `0` | Puma worker processes; `0` runs a single process |
| `PORT` | `3000` | |
| `LOG_LEVEL` | `info` | |
| `LOG_FORMAT` | `json` | `color` for readable dev logs |
