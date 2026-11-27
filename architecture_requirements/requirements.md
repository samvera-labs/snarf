# Ingest Service - Project Requirements

## Overview
Build a greenfield ingest microservice to replace Hyrax/Hyku ingest functionality. The service will be clean, reliable, performant, and capable of handling data migration from various sources.

---

## Language & Runtime

**Ruby, without Rails.** Expected maintainers are Samvera community developers, so Ruby keeps the contributor pool. Current ingest is slow because of its architecture (per-object Fedora/Solr round trips, one job per item), not because of Ruby; the guardrails below are what deliver Constraint 5.

### Stack
| Concern | Choice |
|---|---|
| Runtime | Current stable MRI Ruby, YJIT enabled |
| HTTP API | Roda on Puma (cluster mode); thin layer over plain-Ruby core |
| Code loading | Zeitwerk over `lib/snarf/` (gem-style: file path = constant path) |
| Developer tooling | `bin/web`, `bin/worker`, `bin/console` (IRB with app loaded); `bin/*` scripts for tasks like migrations (no Rake until needed) |
| Database | Sequel + `sequel_pg`; Sequel migrations; `copy_into` / `multi_insert` / `insert_conflict` for batched, idempotent writes |
| Background jobs | Sidekiq (requires Redis or Valkey 7.2+); enqueued through a thin `Snarf::Jobs.enqueue` wrapper so the backend is swappable |
| Tenant schemas | Stored as JSON Schema; validated with `json_schemer` |
| API param validation | `dry-validation` |
| API contract / docs | Hand-written `openapi.yaml` (spec-first; target OpenAPI 3.0 unless `committee` 3.1 support is confirmed); `committee` middleware for request validation and RSpec response conformance; Swagger UI or Redoc served statically at `/docs` |
| CSV / TSV / JSON | stdlib `csv` (streaming `CSV.foreach`, configurable `col_sep`, encoding transcoding on open); `oj` for JSON |
| HTTP client | Faraday |
| Storage adapters | `aws-sdk-s3` (S3/MinIO, multipart); `rclone` CLI subprocess (OneDrive, Box, others); Globus Transfer API and Fedora 6 (LDP) via Faraday; local filesystem (also covers EFS mounts) |
| Solr | `rsolr`, batched adds with `commitWithin` |
| BagIt | `bagit` gem |
| CLI | Thor |
| Auth / rate limiting | `jwt`; `rack-attack` |
| Logging / metrics | `semantic_logger` (JSON); `prometheus-client`; OpenTelemetry |
| Testing | RSpec, WebMock, FactoryBot; real Postgres, Solr, MinIO via docker compose |
| Linting / static analysis | RuboCop (style, lint, `Security/*` cops) with rubocop-rspec and rubocop-sequel; Reek (code smells) |
| Security scanning | CodeQL (GitHub code scanning; verify it detects Roda/Sequel taint with a planted vulnerability); Semgrep (Ruby rulesets + project rules for JSONB key interpolation, RLS bypass, manifest path traversal, SSRF, CSV formula injection, archive extraction); bundler-audit + Dependabot (weekly version PRs and security updates) |

### Guardrails
- No Rails, ActiveRecord, ActiveFedora, or Hyrax dependencies in the core service.
- Batch every write: Postgres via `COPY`/multi-row upserts, Solr via batched updates. No per-record round trips.
- Jobs operate on chunks of records, not one job per work.
- Postgres is the source of truth for job state; Redis is only a signal:
  - Chunk status lives in Postgres (`pending`, `running`, `done`, `failed`).
  - Enqueue only after the transaction commits.
  - A periodic reconciler re-enqueues chunks stuck in `pending`/`running`, covering Redis loss and crashed pods.
  - Jobs are idempotent, so duplicate signals are harmless.
- File bytes never pass through API pods; transfers go storage-to-storage.
- Storage adapters implement one small interface so new backends don't touch the core.
- Puma thread-starvation prevention:
  - Sequel `max_connections` ≥ Puma max threads, and ≥ Sidekiq concurrency in workers (Sequel defaults to 4).
  - API requests stay thin: validate, enqueue, read status. Slow work goes to Sidekiq workers.
  - Every outbound call (Solr, storage, Globus, Fedora) has connect/read timeouts; Postgres has `statement_timeout`.
  - Slow clients are buffered by the ingress/reverse proxy, not Puma.
  - Scale with Puma workers (processes) and pods, keeping threads per worker low (~3-5).
  - Expose Puma stats (busy threads, backlog) as metrics.

### Project Layout
File path always matches constant path (`Snarf::Storage::S3` → `lib/snarf/storage/s3.rb`); specs mirror it under `spec/snarf/`.
```
lib/snarf/
  web.rb             # Snarf::Web (Roda app)
  routes/            # Roda hash_branches, one file per resource (not autoloaded)
  operations/        # single-purpose classes (Snarf::Operations::ValidateRecord, ...)
  input/             # CSV, TSV, JSON, BagIt, (future) deposit form
  storage/           # S3, rclone, Globus, Fedora, local
  jobs/              # Sidekiq jobs
  models/            # thin Sequel models
  cli/               # Thor commands
config/
  boot.rb            # bundler, logging, DB, Sidekiq, Zeitwerk
  puma.rb
db/migrate/          # Sequel migrations
openapi.yaml         # API contract
bin/web              # start API
bin/worker           # start Sidekiq
bin/console
```

### Architecture
- **Pattern**: Standalone service, separate from Hyrax/Hyku; ingest is separable from display.
- **Phase 1**: Standalone ingest service with new backend.
- **Phase 2**: Hyrax adapter shipped as a gem loaded inside Hyku, calling Hyrax transactions for dual-write and verification.
- **Phase 3**: Gradual migration off Hyrax.
- **Single deposit is a batch of one**: Keep the pipeline usable for future UI self-deposit.
  - The core pipeline accepts normalized records + file references, never source rows. CSV, TSV, JSON, BagIt, and a future deposit form are input adapters.
  - Works carry a `state` (`draft`, `pending_review`, `published`); batch imports set `published`.

---

## Core Requirements

### Primary Use Cases
1. **Data Migration**: Import CSV metadata + files from hard drives/remote storage
2. **Batch Import**: Process up to 10,000 works in a single batch
3. **Flexible Source Formats**: Support CSV, TSV, JSON exports from various systems

### Scale Requirements
- **Total Capacity**: Handle 1,000,000+ works across all tenants
- **Batch Size**: Support batches of up to 10,000 works
- **File Size Range**: 500 MiB to 2 PiB total per collection
- **Concurrency**: Efficient processing of multiple simultaneous imports

---

## Technical Requirements

### Storage
- **Pluggable Storage Adapters** (interface-based):
  - S3/MinIO (primary)
  - Fedora 6 (for legacy compatibility)
  - EFS (Elastic File System)
  - Globus
  - Local filesystem (for testing/migration)
  - OneDrive
  - Box

### Database
- **Primary Database**: PostgreSQL
- **Schema Design**:
  - Single schema with `tenant_id` column on all tables
  - Row-Level Security (RLS) for multi-tenancy
  - JSONB column for flexible metadata
- **Tables**:
  - `works` (system fields + metadata)
  - `files` (file references)
  - `import_jobs` (tracking)
  - `tenants` (tenant configuration)
  - `tenant_schemas` (per-tenant metadata definitions)
  - `import_errors` (per-record errors: import job, source row, category, field, message; backs `/api/imports/:id/errors`)
  - `audit_events` (who did what, to which tenant, when; written in the same transaction as the change)

### Search
- **Indexing**: Separate Solr cores per tenant
- **Selective Indexing**: Only frequently queried fields go to Solr
- **Standard Fields**: title, creator, description, date_created, etc.
- **Custom Fields**: Stored in PostgreSQL, queryable via DB or Solr (optional)

### Multi-Tenancy
- **Approach**: Single database, single schema with tenant isolation
- **Isolation Method**: PostgreSQL Row-Level Security (RLS)
- **Tenant Identification**: `tenant_id` column + RLS policies
- **Admin Access**: Special role to bypass RLS for reporting/migration

### Data Model
- **Fixed Fields** (indexed, queryable):
  - `id` (UUID)
  - `tenant_id`
  - `title` (required)
  - `admin_set_id`
  - `member_ids` (array)
  - `state` (`draft`, `pending_review`, `published`)
  - `created_at`
  - `updated_at`
- **Standard Metadata** (JSONB, common across tenants):
  - description
  - creator
  - subject
  - date_created
  - publisher
  - language
  - rights
  - etc.
- **Custom Metadata** (JSONB, tenant-specific):
  - Flexible key-value storage
  - Schema defined per tenant
  - Zero data loss from source systems

---

## Functional Requirements

### Ingest Pipeline
1. **File Transfer**: 
   - Support files already on hard drives
   - Generate manifests of transferred files with checksums
   - Verify file integrity (hash verification optional for large imports)

2. **CSV Processing**:
   - Parse CSV/TSV files with configurable delimiters
   - Handle large files with streaming (no full memory load)
   - Support UTF-8 and other common encodings

3. **Schema Mapping**:
   - Map source CSV columns to internal data model
   - Support per-tenant schema definitions
   - Handle data type transformations (string, array, date, number)

4. **Validation**:
   - Required field validation
   - Data type validation
   - File existence checks
   - Custom validation rules per tenant

5. **Error Handling**:
   - Detailed error messages for each failed record
   - Partial success support (import what works, report errors)
   - Error categorization (validation, file missing, etc.)
   - Per-record errors stored in `import_errors`; structured application logs for debugging

6. **Indexing**:
   - Write to PostgreSQL (all data)
   - Index to Solr (selected fields)
   - Support for dynamic field addition

### Metadata Flexibility
- **Schema Definition**: Per-tenant metadata schema
- **Flexible Storage**: All source metadata preserved
- **Query Support**: 
  - Full-text search on indexed fields
  - Exact match queries
  - Faceting/filtering on custom fields
- **Display**: Support display of custom fields (from PostgreSQL or Solr)

### API
- **REST API**: For programmatic imports
  - POST /api/imports (start import)
  - GET /api/imports/:id (check status)
  - GET /api/imports/:id/results (detailed results)
  - GET /api/imports/:id/errors (error details)
- **Authentication**: API keys or JWT
- **Rate Limiting**: Prevent abuse
- **Pagination**: For large result sets
- **Documentation**: OpenAPI spec is the source of truth; browsable docs at `/docs`

### CLI
- **Command Line Interface**: For batch operations
  - `ingest import --metadata metadata.csv --files manifest.csv --tenant princeton`
  - `ingest status --job-id xxx`
  - `ingest list --tenant princeton`

### Hyrax Integration (Phase 2)
- **Valkyrie Adapter**: Transform normalized data to Valkyrie format
- **Migration Support**: Import from Hyrax exports
- **Dual-Write Mode**: Write to both new backend and Hyrax during transition
- **Verification**: Compare data between systems

---

## Non-Functional Requirements

### Performance
- **Memory**: Efficient for large imports (streaming, batching)
- **Concurrency**: Handle multiple simultaneous imports
- **Throughput**: Process 10,000 works in reasonable time (< 1 hour)
- **Latency**: Near real-time for small imports

### Reliability
- **Resumable**: Support for retrying failed imports
- **Idempotent**: Re-running an import doesn't create duplicates
- **Consistent**: Data integrity across PostgreSQL and Solr
- **Durable**: No data loss on failures

### Security
- **Authentication**: Secure API access
- **Authorization**: Tenant isolation via RLS
- **Input Validation**: Prevent injection attacks
- **Audit Logging**: Track all import activities in the `audit_events` table (not application logs)

### Testing
- **Framework**: RSpec
- **Coverage**: 100% line and branch coverage of `lib/` (SimpleCov), enforced in CI
- **Types**: Unit tests, integration tests, end-to-end tests
- **Fixtures**: Test data for various scenarios
- **Mocking**: Mock external services for fast, reliable tests

### Error Reporting
- **Client-Facing**: Clear, actionable error messages
- **Logs**: Structured logs for debugging
- **Alerts**: Notifications for critical failures
- **Metrics**: Track import success/failure rates

### Logging
- **Where things go**:
  - Application logs (debugging/ops): `semantic_logger`, JSON to stdout, collected by the cluster. Disposable.
  - Per-record import errors: `import_errors` table.
  - Audit trail: `audit_events` table.
- **One logger**: Sequel, Sidekiq, Puma, and Roda request logs all routed through `semantic_logger`; async appender so logging never blocks request threads.
- **Context**: Every job and request tagged with `tenant_id`, `import_job_id`, and `request_id`; `X-Request-Id` passed into Sidekiq job args to correlate API calls with background work.
- **Per-class loggers**: `include SemanticLogger::Loggable`; `measure_*` for timing batches.
- **Never log**: metadata values (may contain PII; log record IDs/row numbers instead), API keys, JWTs, presigned URLs, storage tokens.
- **Sequel**: slow queries at `warn` via `log_warn_duration`; full SQL only at `debug`, off in production.
- **Levels**: `error` needs a human; `warn` degraded but continuing; `info` lifecycle events; `debug` everything else.

### Deployment
- **Containerization**: Docker(? - docker images, not necessarily docker containers); separate API (Puma) and worker (Sidekiq) processes from one image
- **Orchestration**: Kubernetes
- **Configuration**: Environment variables, config files, kubernetes secrets injected via 1password
- **Scaling**: Horizontal scaling for workers, vertical scaling for cluster
- **Monitoring**: Health checks, metrics endpoint

---

## Integration Requirements

### External Systems
- **PostgreSQL**: Primary metadata storage
- **Solr**: Search index
- **Redis / Valkey 7.2+**: Sidekiq job signals (not a source of truth)
- **S3**: Primary file storage
- **Fedora 6**: Legacy compatibility
- **EFS**: Alternative file storage
- **Globus**: Alternative file storage/transfer
- **Hyrax Database**: For migration adapter (read-only)
- **OneDrive**: Commonly used at Universities
- **Other Systems**: Other systems commonly used by Universities for file storage and sharing?
- **Box**: Commonly used at Universities

### Data Formats
- **Input**: CSV, TSV, JSON, BagIt (phase 2?)
- **Output**: PostgreSQL records, Solr documents, roundtrippable CSV/TSV/JSON/BagIt - an export should be able to be imported and result in the same objects as were exported.
- **File Manifests**: CSV with file paths and checksums

---

## Constraints

1. **Zero Data Loss**: All source metadata must be preserved
2. **Backward Compatibility**: Must support migration from Hyrax/Hyku
3. **Flexibility**: Must accommodate various institution-specific schemas
4. **Approachability**: Code must be maintainable by junior developers
5. **Performance**: Must be significantly faster than current Ruby-based ingest

---

## Out of Scope (For Now)

- Display/UI layer (can integrate with existing Blacklight)
- Self-deposit UI for scholars
- Derivative generation (thumbnails, JP2K)
- Full text extraction
- User management/Authentication system (reuse existing)

---

## Success Criteria

1. Successfully migrate a test tenant from Hyrax to new system
2. Import 10,000 works in under 1 hour
3. Zero data loss during migration
4. All custom fields preserved and queryable
5. Clear error messages for failed imports
6. Easy for library staff to run imports themselves
