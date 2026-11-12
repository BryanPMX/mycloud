# Security and privacy

## Authentication

Passwords use bcrypt cost 12. Access JWTs require HS256, the configured issuer, expiration/issued-at timestamps and matching nonzero subject/user IDs. Access lifetime defaults to 15 minutes. Redis atomically rotates refresh sessions; concurrent replay cannot mint two replacements. Current active status and role are read from PostgreSQL on protected HTTP and WebSocket handshakes, so deactivated accounts and revoked admin roles cannot rely on stale JWT claims.

Web cookies are HttpOnly, Secure in production and SameSite Strict. Native tokens use Flutter secure storage; web tokens are not persisted in local storage. API CORS permits only configured origins and rejects other browser origins. Invitation secrets use hashed 256-bit tokens, expire and are consumed once. New account invitation links put the token in the URL fragment; legacy query links remain accepted. Referrers and API/object responses use no-referrer/no-store policies.

The Flutter client serializes uploads, bounds chunks, and ties queued/in-flight work and retried requests to the originating account. Signing out cancels continuation under another account. Interrupted OS picker selections require choosing files again rather than automatically assigning them to a later account. Refresh outages preserve valid stored credentials; revoked sessions are cleared.

## Object authorization

The database is the authorization source. Private keys contain UUIDs/date/extension, not names or emails. Knowing a key is insufficient. Read URLs require current ownership or a valid household/album share and ready, nontrashed status. Defaults are five minutes; original URLs cannot exceed fifteen minutes. A previously issued bearer URL can remain usable until expiry after unsharing; immediate revocation requires an authenticated streaming proxy, which is deliberately not added here.

Only owners mutate/delete their media and manage their albums/posts. Account-admin authority does not bypass these rules. Negative SQL/HTTP tests cover outsider/admin access, recipient restrictions, expired/replayed invitations, private originals, ownership, membership removal, quota races and deletion outages.

Buckets are private. Startup refuses unreviewed bucket policies. MinIO root credentials (`MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`) are administrative only, including the bucket-bootstrap helper. API/worker use a dedicated least-privilege application identity through `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY`; production Compose passes no root variables to those services. Required application permissions include object/multipart operations, version listing/deletion for permanent cleanup, bucket existence/policy reads. The operator must validate the identity's policy before cutover, including denial of MinIO administration. Backup credentials should be separate and read-only, with list/get/metadata/policy inspection permissions. Never grant anonymous reads or commit real credentials. See the [manual credential cutover](deployment.md#minio-credential-separation); source validation alone does not verify live separation.

## Upload controls

Names are bounded and reject traversal separators/control characters. MIME allowlisting is independent of byte-signature validation. Completed size must match the reservation and remain within 512 MiB. A valid header alone does not mark media ready: scanning and bounded decoding must succeed. ClamAV fails closed when unconfigured/unavailable. The Debian image is configured for 512 MiB streams/files, 768 MiB aggregate scans, excess-limit alerts, two threads and nonconcurrent database reload. See [ClamAV's container configuration](https://github.com/Cisco-Talos/clamav-docker/blob/main/clamav/README-debian.md) and [scan-limit behavior](https://docs.clamav.net/manual/Usage/Scanning.html).

At NPM's **MinIO object** proxy, keep HTTPS and add `client_max_body_size 6m;` for the 5 MiB multipart protocol, while leaving download responses unrestricted. API request bodies are capped at 5 MiB. Do not disable scanning, quota enforcement or private buckets to work around a failed file.

## Network and operations

`server-hp` inspection on 10 November confirmed Grafana 3000, Portainer 8000/9443, Prometheus 9090, Alertmanager 9093, NPM administration 81 and MinIO console 9001 on loopback. Preserve that posture. Loopback publishing does not authorize an NPM proxy for an administrative port: remove any old public console/admin proxy and DNS record. Never proxy diagnostics publicly. Preserve SSH/Tailscale and unrelated workloads.

Set `TRUSTED_PROXIES=172.18.0.4/32` for the observed NPM address; re-check after NPM recreation. NPM must overwrite forwarded-client-IP headers; if Cloudflare fronts it, configure Cloudflare's trusted ingress before trusting its client IP header. Empty proxy configuration trusts no forwarded headers. Rate limits are per API process; this private deployment uses one API instance.

API/worker run as UID 10001, with read-only roots, private tmpfs, dropped capabilities and resource limits. ClamAV retains its normal startup/database permissions. Docker build contexts exclude credentials, runtime data, client build output and unrelated local files.

Structured logs contain route templates/status/timing, not request bodies, passwords, tokens, signed URLs or original media. Diagnostics use bounded labels without personal identifiers. Never paste `.env`, full container inspections, dumps or invitation links into public logs. Rotate any real credential discovered in Git history; deleting a file alone does not revoke it.

## Password changes

`POST /api/v1/users/me/password` requires the current password and a different new password with at least 12 characters and at most 72 UTF-8 bytes. It changes only the authenticated account. A compare-and-swap update increments a database credential version, invalidating earlier access and refresh tokens on their next authentication check even during a Redis outage. The Profile flow signs the current client out after success. Passwords and hashes are never returned or logged. Existing version-zero sessions remain compatible until the account changes its password.

The server-owner `account-setup` helper reads a password only from stdin. Creating a specifically named account requires `--create`; resetting an existing password additionally requires `--reset-existing-password`, stopped API writers and `ACCOUNT_SETUP_WRITES_PAUSED=yes`. It preserves existing identity, role, quota and media, refuses inactive or role-mismatched accounts, and revokes refresh sessions. On the legacy API, previously issued access tokens expire under its existing short lifetime; the upgraded API enforces credential versions immediately. Run account setup from a hidden terminal prompt and remove the temporary private environment file afterward.
