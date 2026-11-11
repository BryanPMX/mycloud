# Validation and release gates — 10 November 2026

## Evidence completed during implementation

- Baseline Go tests and Flutter analysis passed before changes.
- Real isolated PostgreSQL tests passed for private-media ownership/recipient/expiration boundaries, concurrent quota reservations, derivative accounting, trash accounting, durable deletion during a simulated storage outage, atomic job claims and crash-window recovery.
- Household/feed SQL tests passed for outsider/global-admin denial, email-bound and replay-proof invitations, ownership, unsharing and membership revocation. Account-deletion tests verified identity removal and retained object cleanup state.
- Thirty-one Flutter tests passed, including responsive iOS/Android/desktop/tablet/320px layouts, light/dark themes, larger text, reduced motion, existing account/collection/comment/profile smoke tests and tests preventing queued files from continuing under a different account and preserving sessions through transient refresh failure.
- Go race tests passed after fixing pre-existing test races caused by parallel mutation of Gin's global mode. JWT tests cover algorithm/identity rejection and quota tests cover overflow/negative inputs.
- Media snapshots were created/restored against real local MinIO, with byte, MIME and user-metadata verification; corruption, undeclared buckets and nonempty restore targets were rejected.
- Script regressions verified failed database dumps do not report success and missing/mismatched SSD identity refuses MinIO startup.
- Production Compose and combined monitoring/SSD configuration validated without deployment. Hardened API/worker Docker images built with the patched toolchain and correct native target architecture. Final production Flutter web, unsigned iPhone release and Android release APK compilation passed; the native minimum is iOS 15 to match the installed release SDK.
- `govulncheck` initially found 47 reachable reports in the old toolchain/dependencies. Fixed net/text/Redis/pgx dependencies removed the original reachable reports. A final rescan caught newly published GO-2026-6859 in Go 1.26.10; the toolchain and pinned build images were updated to Go 1.26.11. See the [Go patch release](https://go.dev/doc/devel/release#go1.26.11). Vulnerability scans do not certify every OS/package/image or future release.
- The complete local API/worker/MinIO/ClamAV acceptance test passed with generated PNG/MP4 and a public libheif HEIC fixture. It verified previews, unchanged original bytes, anonymous denial, family invitation/feed, scoped album sharing, outsider/global-admin denial, unsharing, membership removal, trash/restore, account deletion and private low-cardinality metrics. Sensitive authenticated actions now have their own equally strict limiter, so joining a family does not consume login attempts.

## Server evidence supplied by the owner

- `server-hp`: 15 GiB RAM; MyCloud MinIO uses `mycloud_minio_data` on the internal disk.
- Crucial CT1000X10SSD9, serial ending 662C, 931.5 GiB. Its two existing files were archived and compared with the read-only source, with SHA-256 recorded privately. The owner explicitly approved and performed formatting of only the large exFAT partition. New ext4 UUID 4dcf77a1-cf9c-43da-ad18-4fe11443034f is mounted by UUID at /srv/mycloud-data, with fstab backup and successful write/read/identity checks. MinIO still uses its original named volume.
- NPM network/address: `nginx-proxy-manager_default`, `172.18.0.4`. MyCloud internal network: `mycloud_mycloud_internal`. Existing Prometheus uses host networking.
- `ss` verified loopback listeners for Grafana, Portainer, Prometheus, Alertmanager, NPM administration and MinIO console. Public proxy-host rules and actual HTTPS browser operation still require rollout verification.

## Pending owner acceptance

- Guarded storage adoption, missing-mount rehearsal and non-destructive MinIO migration, retaining old storage. Preservation, explicit preparation approval and UUID mount checks are complete.
- Independent media backup target (the owner confirms none is currently available), installed/monitored schedule and a successful restore rehearsal using actual production data. Configuration/container records and a structurally checked PostgreSQL rollback archive were saved privately on the server.
- Reviewed PR/CI, immutable GHCR release, backed-up configuration/database, controlled Portainer deployment and production readiness/media/authorization tests.
- Existing Prometheus/Grafana/Alertmanager integration verified live, including a controlled alert and backup-age signal.
- Physical iPhone picker, secure session restoration, originals/playback, interrupted upload behavior, accessibility, TestFlight signing and family user acceptance. Native OS background upload after termination and App Store submission are not implemented/accepted claims.

**Do not call the overall project production-ready or cancel existing cloud storage until these gates pass.**

## Final local verification

- `go vet ./...` and `go test -race ./...` passed; final real-dependency integration race tests passed, including scoped sharing and credential-version migration.
- Flutter analysis found no issues; all 31 tests passed. Production web, unsigned iOS release and Android release APK builds passed. Physical device/signing is still pending.
- All 12 migrations applied and the repeat run passed without changes. API, worker, migration and backup Docker images built successfully.
- A paired backup from the isolated acceptance stack restored PostgreSQL into a new empty database: 4 synthetic users, 3 real processed media assets, 11 migrations. Media snapshots restored into separate buckets with byte/content-type/metadata verification. This proves the recovery tooling locally, not production disaster readiness.
- Final `govulncheck` on Go 1.26.11 reported zero reachable vulnerabilities, with one unused package and two unused module findings. This is not an OS/image audit.
- Gitleaks scanned 34 existing commits and the staged source. Its only historical match is the public RFC 6455 example nonce in a WebSocket test; that exact fingerprint is documented as a false positive. No production credential finding was found.
- Local script checks rejected a failed PostgreSQL dump and missing/mismatched SSD identity.

No unexecuted server, device or production action is marked passed.

## Vault redesign

The owner requested a substantial Instagram/Pinterest-inspired personal-vault redesign after reviewing the earlier client. The final client replaces dashboard chrome with a photographic masonry vault, a private circle feed, cover-led collections, responsive navigation, custom Mynube branding and bundled fonts/sample assets. Browser inspection verified the welcome screen, vault, circle and collections at 390×844 and the desktop vault at 1440×1000. Screenshots are local review artifacts; demo photography never appears as production user data. See [design-system.md](design-system.md).

Physical iPhone/Android hardware, real Photos selection, production HTTPS media playback, distribution signing and family acceptance are still pending. The Android artifact is a build verification, not an approved store release.

The owner verified that the currently running API, worker and ClamAV have Docker memory/CPU limits set to zero (unlimited). The new limits in the deployment files are not active until rollout. Public HTTPS `/health` returned 200 via Cloudflare, while the initial public Python login returned 403 and direct private login returned 401 for the requested temporary credential. A public curl request subsequently returned the normal JSON 401 authentication response, confirming route reachability from that client. Account setup and public login acceptance remain pending; no password is stored in this repository.

The completed local E2E test additionally verified wrong-current-password rejection, successful password change, rejection of previous access/refresh tokens, and successful login with the replacement password. Account helper creation, repeat verification and guarded password reset passed using synthetic local accounts.

Cold-start route regression tests verify fragment-based invitation links, direct Profile links after sign-in and previous hash bookmarks. The web entry point uses path URLs with preserved fragments; Vercel rewrites cover `/accept` and `/feed`. The immutable backend images for `c39bde465b9a01771b6cab5d06e392cc5a01fde2` passed GitHub validation and published for amd64/arm64 without triggering Portainer. The subsequent routing commit changes only the client, host rewrites and this evidence.
