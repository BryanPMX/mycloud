# Schema migrations

Migrations are applied in filename order by `scripts/migrate.sh`, using one PostgreSQL connection and advisory lock. Each migration commits its SQL and SHA-256 ledger entry in the same transaction. A repeat run skips matching entries and rejects a changed applied file. An existing installation without a ledger first replays the idempotent original migrations with application writers paused.

| Versions | Change |
| --- | --- |
| `001`–`005` | Original users/media/albums/shares/jobs, comments, favorites, invitations/search and audit log. These applied files remain unchanged. |
| `006` | Durable upload reservations, derivative accounting and deletion outbox. |
| `007` | Durable job claims and recovery leases. |
| `008` | Families, membership, email-bound invitations and chronological feed. |
| `009` | Account-deletion cleanup state. |
| `010` | Quota reconciliation and delayed cleanup for in-flight processing. |
| `011` | Recipient/family-scoped album grants. |
| `012` | Credential versions to invalidate sessions after password changes. |

The migration image packages the exact SQL set for the reviewed release. Preserve applied migrations; add a new migration for later changes. Do not use destructive down migrations on production. Save a matched database/media backup before upgrading, and use the reviewed restore procedure for rollback when necessary. See [deployment](../docs/deployment.md) and [disaster recovery](../docs/disaster-recovery.md).
