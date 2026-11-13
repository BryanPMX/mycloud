# Deployment and operation

## Ownership and verified environment

The owner runs all commands on `server-hp`. This repository change does not SSH to the server, format disks, change unrelated workloads or automatically adopt the SSD.

Observed deployment: project `mycloud`, containers `mycloud-api-1`, `mycloud-worker-1`, PostgreSQL, Redis, ClamAV and pinned MinIO; current MinIO volume `mycloud_minio_data`. Networks are `mycloud_mycloud_internal` and `nginx-proxy-manager_default`. NPM was `172.18.0.4`; Prometheus uses host networking. Administrative listeners were verified on loopback. Preserve Minecraft and all unrelated containers/networks.

## Review and build gates

GitHub Go CI runs formatting, vet, race tests, the official vulnerability scanner and real dependency-backed integration tests. Flutter CI runs locked dependency resolution, analysis, tests and a production web build. Publishing waits for both reusable workflows, builds API/worker/migrate/backup for amd64/arm64 and pushes immutable `sha-FULL_COMMIT` tags to GHCR. The existing main-branch Portainer webhook remains, but do not merge this rollout until the backup/maintenance plan is ready. A configured `latest` deployment may redeploy immediately after merge.

Go is pinned to patched 1.26.11; core builder/runtime image manifests are pinned. Flutter/Vercel use 3.35.4 and the lockfile. Dependency updates must rerun the checks; see [Go release history](https://go.dev/doc/devel/release) and the [Go vulnerability database](https://pkg.go.dev/vuln/).

Use `deploy/portainer-stack.npm.yml` for production. This primary file publishes diagnostics only on `127.0.0.1:19090/19091` for the existing host-network Prometheus. It defaults to `MYCLOUD_MINIO_STORAGE_FILE=storage/minio-volume.yml`, preserving the current named volume. SSD selection is separately gated by [storage.md](storage.md). Do not change the production Compose project name or remove volumes.

## PostgreSQL runtime and migration credentials

Production uses two PostgreSQL connections:

| Variable | Purpose |
| --- | --- |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` | Existing PostgreSQL container/admin identity (`mycloud`); preserve both values. |
| `DATABASE_MIGRATION_URL` | Privileged schema/migration owner connection (`mycloud`); mapped only to the migrator's `DATABASE_URL`. |
| `DATABASE_URL` | Least-privilege API/worker connection (`mycloud_app`) after the staged cutover. |

Both production Compose files reject absent or empty `DATABASE_MIGRATION_URL`. The migrator binary still consumes `DATABASE_URL`; it receives no variable named `DATABASE_MIGRATION_URL`. API/worker keep their existing `DATABASE_URL` mapping and receive no migration URL variable. PostgreSQL initialization/ownership, application code and migrations are unchanged. MinIO root/app separation is independent and unchanged.

The owner has already created and verified the runtime role manually. Role creation, grants and credential rotation remain operator-managed; this repository does not perform them. The runtime role needs application DML, sequence and function access, but **no access to `public.schema_migrations`, no schema CREATE rights, no object ownership and no ability to assume the owner role**. See [the runtime privilege boundary](security.md#postgresql-identities). After future migrations, the operator must ensure new application objects receive the necessary runtime grants without exposing the ledger.

After review, perform this separate manual cutover through the existing Portainer stack:

1. Preserve the current admin `DATABASE_URL`, private configuration and rollback records securely. Add `DATABASE_MIGRATION_URL` with that **same current admin URL**. Preserve `POSTGRES_USER` / `POSTGRES_PASSWORD` and all unrelated settings; do not print URLs, put them in shell history or paste them into chat/Git.
2. Deploy the reviewed Compose wiring while `DATABASE_URL` still points to admin. Keep the current reviewed images, project, storage, MinIO settings, networking, ports and resource limits. Validate privately with `docker compose --env-file PRIVATE_ENV -f deploy/portainer-stack.npm.yml config --quiet`; never print a real rendered configuration.
3. Verify that the migrator exits zero and API/worker are healthy, including `/health/ready`. Do not proceed if migration or readiness fails.
4. Replace **only `DATABASE_URL`** with the already-prepared `mycloud_app` connection. Keep `DATABASE_MIGRATION_URL` on the preserved admin connection and keep PostgreSQL container variables unchanged. URL-encode credential characters as required; example files contain fake values only.
5. Redeploy and verify separation privately: API/worker connect as `mycloud_app`, the migrator connects as `mycloud`, API/worker environments have no migration URL, and the runtime cannot access `schema_migrations` or create schema objects. Verify readiness and disposable-media upload, processing, preview/read and deletion. Source configuration tests do not prove live role grants or successful cutover.

For rollback, replace `DATABASE_URL` with the preserved admin URL and redeploy API/worker using the reviewed wiring. Keep `DATABASE_MIGRATION_URL`, `POSTGRES_USER` / `POSTGRES_PASSWORD` and existing data unchanged. **Do not remove the runtime role during rollback.** Investigate and correct its grants separately before retrying. A source rollback alone does not restore an environment value.

For local development, copy the new `DATABASE_MIGRATION_URL` entry into the private `.env` before using the updated Compose file. `.env.example` uses the same development `mycloud` identity for both URLs because no separate local runtime role is created. API/worker retain the shared development env file; production uses explicit per-service environments. The local migrator explicitly overrides its container `DATABASE_URL` from `DATABASE_MIGRATION_URL`. Direct invocation of `scripts/migrate.sh` still requires an explicitly supplied owner connection as `DATABASE_URL`; the isolated integration/restore fixtures use their fixed synthetic owner and never load production credentials.

## MinIO credential separation

`MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` belong only to MinIO administration. Both production Compose files require them explicitly and refuse absent or empty values. API/worker retain `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY` for a separate least-privilege application identity; the Compose change does not create users, rotate credentials or prove a live cutover.

The owner reports that the dedicated application identity has already passed manual bucket/object/multipart/version checks and cannot perform MinIO administration. Preserve that identity and its policy; do not run administrative bucket bootstrap with it. `scripts/init-minio.sh` requires root variables for administrative setup. Do not rerun bootstrap as part of this existing-production credential cutover.

After code review, the owner performs this separate manual operation:

1. Preserve the **current** MinIO root values, image identifiers, environment and rollback information privately. Populate the new root variables with those same preserved values before changing the app variables. Do not rotate root credentials or put any real secret in Git, chat or logs.
2. Adopt the reviewed Compose wiring with both root variables populated. Keep the existing app values until MinIO is healthy under the unchanged root identity, or prepare both credential sets together before one controlled apply. Never apply the former coupled Compose file after replacing the app values: it would change MinIO's root identity.
3. Replace **only** `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY` in Portainer with the already-created application identity. Keep images, storage selection, project/volumes, networks, ports and limits unchanged. Recreate only MinIO/API/worker as required by the environment change; do not perform a full-stack migration or remove volumes.
4. Verify MinIO health and API/worker readiness. With disposable test media, verify upload, original read, preview and deletion. Verify Prometheus `mycloud-api` and `mycloud-worker` targets remain `UP=1`; an unconfigured target is an unmet acceptance check.
5. Retain the preserved root values and rollback records. If reverting to the former coupled Compose wiring, restore its original app/root environment together; reverting only the YAML would assign the new application values to root.

The local `.env` development stack also requires separate root variables, but continues to load its shared development env file. Production uses explicit per-service variables. No server action or credential change follows merely from editing or validating these files. Validate with public placeholders for repository tests; use `config --quiet` privately for a future production review without printing the rendered secrets.

## First rollout on the current named volume

1. Review the audit, diff and CI. Record exact current image digests, stack/Portainer settings and existing bucket policies/versioning. Back up configuration privately with mode 0600. Never paste full container environments.
2. Verify independent media backup availability. Pause uploads and let active uploads complete. Count outstanding legacy Redis upload-session keys without printing values. New upload reservations live in PostgreSQL; a legacy Redis-only in-flight upload cannot resume across the cutover. Wait/drain or explicitly cancel it with its owner's knowledge.
3. Take a maintenance window, stop only MyCloud API/worker, and capture a matched database and media backup. Verify and rehearse restore before considering cloud cancellation. Retain old images/configuration and `mycloud_minio_data`.
4. Set `IMAGE_TAG=sha-FULL_REVIEWED_COMMIT`; use the **same tag** for API, worker, migrate and backup. Keep MinIO `ghcr.io/bryanpmx/minio:RELEASE.2025-09-07T16-13-09Z`. Set production HTTPS endpoints, a strong JWT secret, `ALLOWED_ORIGINS=https://mynube.live,https://www.mynube.live` and the trusted NPM proxy address. Re-check NPM's IP after recreation. `MINIO_REGION` defaults to `us-east-1`; it must match the existing MinIO region.
5. Validate the composed configuration with `docker compose --env-file PRIVATE_ENV -f deploy/portainer-stack.npm.yml config --quiet`. This validates without printing credentials. **Keep `MYCLOUD_MINIO_STORAGE_FILE=storage/minio-volume.yml` for this first rollout.**
6. Redeploy through the existing Portainer/GHCR model during the window. The one-shot migrator must succeed before new API/worker start. Migrations run transactionally, maintain checksums and hold a PostgreSQL advisory lock. The first ledger bootstrap replays the existing idempotent migrations, then applies the new versions. Keep writers stopped during this first cutover.
7. Confirm container readiness, HTTPS `/health` and `/health/ready`, successful WebSocket reconnect, a new test photo/video upload, original/preview download, private outsider denial, household invitation/feed, unsharing, trash/restore and test-asset permanent deletion. Check per-user usage and pending cleanup. Never use existing family originals as deletion test fixtures.
8. Resume family access, monitor worker/DB/storage metrics and logs, and keep rollback copies. Production is accepted only after the owner records these checks and family user acceptance.

## Reverse proxy

Proxy only `api.mynube.live` to `mycloud-api:8080` and `minio.mynube.live` to `mycloud-minio:9000`, over public HTTPS. Enable WebSockets for the API. Configure the object proxy for 5 MiB multipart parts (`client_max_body_size 6m`) and sufficient read/send timeouts; do not expose the console through a proxy. Forward/overwrite client-IP headers correctly; Cloudflare client-IP trust requires its known ingress chain, not arbitrary request headers. Never proxy port 9090 or administrative services.

The console remains `127.0.0.1:9001` through SSH/Tailscale. Remove old public console/NPM administrative proxy hosts if present. The apex redirects to `www`, so CORS must explicitly allow both owned application origins: `https://mynube.live` and `https://www.mynube.live`. Verify the actual browser hostname after redirects; preview deployments use demo data rather than production credentials. Client URLs use path routing; configure the web host to serve `index.html` for `/login`, `/accept`, `/media`, `/feed`, `/albums`, `/profile` and `/admin`. Invitation tokens remain in the URL fragment; previous hash-route bookmarks are accepted. Verify a browser upload/download with actual HTTPS hosts, because local tests do not prove NPM/Cloudflare configuration.

## Portainer storage selection

The inventoried Git-stack editor can change the repository reference and environment but has no additional-files field. The primary NPM Compose file therefore uses standard `extends` to select a versioned storage component from the same Git checkout. This keeps the existing Compose path and project. Leave `MYCLOUD_MINIO_STORAGE_FILE` unset or set it to `storage/minio-volume.yml` until migration. After the verified offline copy, installed host guard and UUID preflight, select `storage/minio-ssd.yml` and supply `MYCLOUD_STORAGE_UUID`. The SSD component refuses a missing UUID and mounts only existing host paths. Do not detach the stack from Git.

The optional `.monitoring.yml` and `.ssd.yml` files remain available for Compose CLI deployments; Portainer’s primary NPM file does not require adding them.

## Monitoring integration

Merge jobs from `monitoring/prometheus.yml` and rules from `monitoring/alerts.yml` into the **existing** Prometheus configuration; preserve all other scrape jobs, exporters and Alertmanager settings. Targets are host loopback `127.0.0.1:19090` (API) and `19091` (worker). Back up monitoring config first, validate it with the existing Prometheus `promtool`, and reload using its established mechanism. Import `monitoring/dashboards/familycloud-overview.json` into the existing Grafana and select its existing Prometheus datasource. Verify targets, readiness gauges, dashboard panels and a controlled test alert. Metrics existing in source is not proof that production scraping/alert delivery works.

## Resources and maintenance

Defaults: API 1 CPU/512 MiB; worker 1 CPU/1536 MiB with 640 MiB temporary workspace; ClamAV 1 CPU/4 GiB and two scan threads; PostgreSQL 1 CPU/768 MiB; Redis 0.5 CPU/512 MiB (128 MiB dataset, no eviction); MinIO 1 CPU/1 GiB (768 MiB Go soft target). These ceilings total 8.25 GiB, not a reservation. The observed host has 15 GiB RAM and runs other applications; inspect actual peak memory/CPU and adjust MyCloud limits conservatively without altering others. Worker concurrency remains one. Container health failure reports dependency loss; permanent job/reservation/deletion state stays in PostgreSQL and recovers when dependencies return.

For storage drift, use `reconcile-storage` read-only, then an explicitly write-paused `--apply` as documented. For disk loss or restore, use [disaster-recovery.md](disaster-recovery.md). Never use `docker compose down -v`, Docker volume pruning, or destructive down migrations on production.

## Fresh installation and iPhone distribution

After migration into a genuinely empty database, the backup image includes `bootstrap-admin --email YOUR_EMAIL --password-stdin --confirm-empty-installation`. Pipe a password from a secure hidden prompt; never put it in a command argument or chat. It refuses any existing user, creates the first admin/private family, and never resets existing accounts. Existing deployments skip this entirely. Admin-issued invitations then create individual accounts.

The native minimum is iOS 15, matching the installed release Xcode SDK. Flutter keeps `live.mynube.app` identifiers and existing Apple team configuration. Build with `flutter build ios --release --no-codesign` for compilation verification; physical-device Photos picker, secure storage, background interruptions, media playback, accessibility and TestFlight signing still require the owner's device/account acceptance. Uploads are chunked and recover safely on connection errors; **OS-managed background upload/resume after app termination is not implemented**. Keep the app open while uploading and reselect interrupted files when asked. Do not advertise automatic background photo backup. App Store review/privacy forms/screenshots/signing and a release archive remain a separate acceptance gate.

## Owner-managed account setup

The backup image includes `account-setup --email EMAIL --name NAME --role admin|member --quota-gib 20 --create`. It creates only the explicitly named missing account and verifies an existing one without duplicating or changing it. Passwords enter through stdin from a hidden terminal prompt, never an argument/environment variable or this repository. The helper uses the existing private PostgreSQL network and requires an explicit `DATABASE_URL`.

For an authorized existing-account password reset, first save a fresh private database rollback archive and stop only MyCloud API writers. Supply `--reset-existing-password`, `ACCOUNT_SETUP_WRITES_PAUSED=yes` and the private Redis URL; the helper preserves existing identity, role, quota and media and refuses role/inactive mismatches. It revokes refresh sessions and increments credential version when available. Resume the API using the reviewed image and privately verify both logins. Remove the transient private environment file; retain the rollback archive. User-requested live account identifiers/passwords are not embedded in these instructions.

For the inventoried `server-hp` deployment, [setup-accounts-server.sh](../scripts/setup-accounts-server.sh) wraps this procedure for one existing administrator and one member. It takes their email/name pairs as arguments, pulls the already validated account-tool image by digest, prompts once through `/dev/tty`, backs up PostgreSQL while the API is paused, performs only the named account operations and checks both logins through the private Docker address. It refuses a different host, stopped API or missing private configuration. A failure resumes the API and removes the transient configuration; the private rollback archive remains in the operator’s home directory. Download the script from an immutable reviewed commit and verify its SHA-256 before running it. The legacy API can still honor an already-issued access token until its configured expiry; the new release enforces credential versions on each request.
