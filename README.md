## Snarf (down)
snarf: to eat (something) quickly or greedily

Pluggable batch ingest API for postgres, solr, and files.

## Running with Docker

```bash
docker compose up
```

Starts Postgres, Redis, Solr, the API (`web`), and the Sidekiq `worker`. The API is at http://localhost:3000 (`/healthz` for a health check), and the Sidekiq dashboard at http://localhost:3000/jobs (user and password `snarf` in development).

- Code is bind-mounted; restart `web`/`worker` to pick up changes.
- Rebuild after changing `Gemfile` or `Gemfile.lock` (including pulling someone else's change): `docker compose build`. A `Bundler::GemNotFound` on startup means the image is stale.
- Console: `docker compose run --rm web bin/console`
- On Linux, set `UID` and `GID` in `.env` to your own so files created in the container are owned by you.

## Tests and checks

Run locally (Ruby version in `Dockerfile`), or in the container by prefixing with `docker compose run --rm --no-deps web`.

| Check | Command |
|---|---|
| Tests | `bundle exec rspec` |
| Style / lint | `bundle exec rubocop` |
| Code smells | `bundle exec reek .` |
| Vulnerable gems | `bundle exec bundle-audit check --update` |

Tests and linters don't need Postgres, Redis, or Solr running. CI runs all four in the dev image, and builds the production images, on every pull request and push to `main`.

`lib/` must have 100% line and branch coverage. Every `rspec` run writes `coverage/index.html`; the minimum is only enforced when `CI` is set, so running a single spec file locally doesn't fail. To check locally: `CI=1 bundle exec rspec`.

### Security scanning and dependency updates

- **CodeQL** scans Ruby and the workflows on every PR, push to `main`, and weekly. Results are under the repo's Security tab.
- **Semgrep** runs the `p/ruby` rules plus project rules in `.semgrep/`. Each rule has a matching `.rb` file of `# ruleid:` / `# ok:` examples that CI tests. To run locally:

  ```bash
  docker run --rm -v "$PWD:/src" -w /src semgrep/semgrep semgrep scan --config p/ruby --config .semgrep --exclude .semgrep --metrics off
  ```

- **Dependabot** (`.github/dependabot.yml`) opens weekly PRs for gems (minor/patch grouped), GitHub Actions, and Docker images in the `Dockerfile` and `docker-compose.yml`. Keep the `Dockerfile`'s `FROM ruby:` tag literal so Dependabot can update it.

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
| `JOBS_DASHBOARD_USERNAME` | none | Sidekiq dashboard at `/jobs` (basic auth); not mounted unless all three are set |
| `JOBS_DASHBOARD_PASSWORD` | none | |
| `SESSION_SECRET` | none | At least 64 bytes, e.g. `ruby -rsecurerandom -e 'puts SecureRandom.hex(64)'` |
