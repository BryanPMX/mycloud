# Isolated validation stack

All credentials here are public **test fixtures**, never production credentials. Services publish only on loopback: PostgreSQL 55439, Redis 56389, MinIO 59039, API 58039 and diagnostics 59049/59059. The database must be named `mycloud_validation`; real SQL/E2E tests refuse a different database, and E2E also requires the exact host/port plus explicit acknowledgement.

```sh
docker compose -f tests/integration/compose.yml up -d --wait postgres redis minio
docker compose -f tests/integration/compose.yml run --rm migrate
docker compose -f tests/integration/compose.yml run --rm migrate
export MYCLOUD_TEST_DATABASE_URL='postgres://validation:validation-only-local@127.0.0.1:55439/mycloud_validation?sslmode=disable'
export MYCLOUD_TEST_REDIS_URL='redis://127.0.0.1:56389/0'
export MYCLOUD_TEST_MINIO_ENDPOINT=127.0.0.1:59039
go test -count=1 -race -tags=integration ./internal/infrastructure/...
docker compose -f tests/integration/compose.yml up -d --build --wait api worker
MYCLOUD_E2E=isolated-local-stack go test -count=1 -tags=e2e -timeout=4m ./tests/e2e
```

The complete acceptance test resets **only this checked validation database**, creates synthetic accounts/photos/video, and exercises actual API/MinIO/ClamAV/FFmpeg processing, originals/previews, private buckets, household invitations/feed, scoped album grants, outsider/admin denial, unsharing, trash/restore and account deletion. It requires host `ffmpeg` for the generated MP4. An optional public HEIC fixture can be supplied through `MYCLOUD_TEST_HEIC_FIXTURE`; do not use personal media in CI. Restart the validation API before repeating E2E within fifteen minutes so the real login limiter's previous test attempts do not exhaust its five-attempt window.

Dependency-backed Go commands use `-count=1` because cached Go results do not verify a newly created database, object store or application container. The separate PostgreSQL restore rehearsal waits for final TCP readiness; the image's temporary Unix-socket initialization server is not an acceptance-ready database.

Do not run SQL integration tests concurrently with the active worker/E2E reset: SQL tests deliberately create synthetic metadata without real object files. Pause worker before re-running those tests, or recreate the isolated stack. Both Go and Flutter tests have negative account-boundary coverage; the client additionally tests account switching during an in-flight upload and transient refresh failure.

The media backup test creates isolated private source/rehearsal buckets, verifies hard-link reuse, restores real bytes/content type/metadata, rejects nonempty targets, and detects corruption/unsafe manifests. PostgreSQL restore is rehearsed separately with `backup-postgres` and `restore-postgres` against a new empty database. Never substitute production URLs or volumes.

Cleanup is intentionally scoped to this generated stack:

```sh
docker compose -f tests/integration/compose.yml down -v
```

Never use that cleanup command with production Compose files. Physical iPhone/HTTPS proxy/production restore and alert delivery remain separate owner acceptance checks.
