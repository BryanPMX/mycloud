# Implementation plan

## Critical

1. Preserve existing production storage and MinIO pin; branch work; protect build contexts and admin boundaries.
2. Fix owner-only mutations, JWT/session replay, trusted proxies and request limits. Add negative regression tests.
3. Introduce transactional, checksummed migration ledger (bootstrap existing idempotent migrations safely), then durable quota reservations and deletion retry state.
4. Validate actual upload size/signature, bound processing, recover durable jobs and prevent concurrent claims.

## Product completion

- Preserve Flutter gallery, upload progress, albums and comments.
- Complete private library/explicit sharing, account management, chronological family posting and secure membership using existing account invitations where sound.
- Never reassign media ownership when sharing. Removing posts leaves originals; media deletion removes references.
- Remove implementation-status copy from consumer screens and verify accessibility and iOS behavior.

## Security

- Test owner/member/outsider/inactive/admin boundaries at application and PostgreSQL layers.
- Keep buckets private and administration on loopback/Tailscale. Audit tracked secrets without printing contents.
- Restrict JWT algorithms, atomically consume refresh sessions, use current account roles, and scope proxy trust.

## Storage

- Reserve uploads atomically; reconcile quota from persistent media/reservations and record derivative usage policy.
- Add read-only server inventory script. Owner supplies disk identity and mount evidence.
- Provide opt-in UUID mount/systemd/preflight/Compose guard. Do not switch the live named volume automatically.
- Migration depends on server inspection, a maintenance window, a verified copy, and any required destructive-operation approval. Retain old data.

## Infrastructure and observability

- Real CI tests gate image publishing; use deliberate release tags, health/readiness, non-root runtime, bounded worker resources and graceful shutdown.
- Add private metrics for the existing Prometheus/Grafana/Alertmanager, with bounded labels. Existing monitoring must be configured and verified by the owner on the server.

## Testing and backups

- Run Go tests/race/vet, Flutter analyze/tests/build and Compose validation.
- Add opt-in isolated PostgreSQL/Redis/MinIO integration verification and restore rehearsal. Never use production databases or delete live media in tests.
- Fail closed on failed backups; private archives, retention, manifest/checksums, separate media copy, scheduled backup examples.
- Restore test and actual off-disk backup evidence are release gates, not documentation-only claims.

## Documentation and deployment

- Maintain architecture, security, storage, backup/restore, deployment, disaster recovery and validation runbooks.
- Owner runs server commands; provide exact reversible instructions and rollback points. Production rollout depends on successful tests, config/database backup, reviewed migration and successful health/media checks.
- Do not cancel paid storage until migration, independent backups, restore test, monitoring and family acceptance all pass.

## Later enhancements

Push notifications, reactions beyond existing comments, advanced search, automatic transcoding, and large-scale multi-household hosting must not delay privacy/reliability. Native background upload guarantees and App Store submission require device/signing validation.
