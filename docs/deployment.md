# Deployment and operation

## Ownership and verified environment

The owner runs all commands on `server-hp`. This repository change does not SSH to the server, format disks, change unrelated workloads or automatically adopt the SSD.

Observed deployment: project `mycloud`, containers `mycloud-api-1`, `mycloud-worker-1`, PostgreSQL, Redis, ClamAV and pinned MinIO; current MinIO volume `mycloud_minio_data`. Networks are `mycloud_mycloud_internal` and `nginx-proxy-manager_default`. NPM was `172.18.0.4`; Prometheus uses host networking. Administrative listeners were verified on loopback. Preserve Minecraft and all unrelated containers/networks.

## Review and build gates

GitHub Go CI runs formatting, vet, race tests, the official vulnerability scanner and real dependency-backed integration tests. Flutter CI runs locked dependency resolution, analysis, tests and a production web build. Publishing waits for both reusable workflows, builds API/worker/migrate/backup for amd64/arm64 and pushes immutable `sha-FULL_COMMIT` tags to GHCR. The existing main-branch Portainer webhook remains, but do not merge this rollout until the backup/maintenance plan is ready. A configured `latest` deployment may redeploy immediately after merge.

Go is pinned to patched 1.26.11; core builder/runtime image manifests are pinned. Flutter/Vercel use 3.35.4 and the lockfile. Dependency updates must rerun the checks; see [Go release history](https://go.dev/doc/devel/release) and the [Go vulnerability database](https://pkg.go.dev/vuln/).

Use `deploy/portainer-stack.npm.yml` for production. This primary file publishes diagnostics only on `127.0.0.1:19090/19091` for the existing host-network Prometheus. It defaults to `MYCLOUD_MINIO_STORAGE_FILE=storage/minio-volume.yml`, preserving the current named volume. SSD selection is separately gated by [storage.md](storage.md). Do not change the production Compose project name or remove volumes.

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
