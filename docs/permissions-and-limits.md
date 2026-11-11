# Permissions and limits

## Accounts and privacy

| Role | Allowed | Boundaries |
| --- | --- | --- |
| Account administrator | Invite/manage accounts, adjust quotas, deactivate accounts, view service statistics | Cannot bypass private media/album/feed authorization or delete another person’s originals |
| Circle owner | Invite/remove circle members, manage their circle | Does not own or gain access to members’ unshared vaults |
| Circle member | Use their own vault and share their own media into a joined circle | Cannot join without an invitation, modify another circle, delete another owner’s originals or remove another author’s post |

Knowing an object ID/key does not grant access. Buckets stay private. API checks use current database membership, account status and credential version. A previously issued signed URL remains a bearer link until its short expiry; revocation prevents new URLs. Normal downloads/previews default to five minutes, with an enforced fifteen-minute maximum.

Accounts have separate byte accounting and quotas. Trash continues to count until its objects finish deleting; upload reservations and derivatives count too. The initial requested household uses **20 GiB per account** (21,474,836,480 bytes), with an administrator and a member. Real account names, email addresses and passwords are intentionally absent from this public runbook.

## Storage and processing

- Maximum original upload: **512 MiB per file**. Multipart parts normally use 5 MiB.
- Worker concurrency: **one** processing job. FFmpeg uses at most two threads, bounded allocation/output, pixel limits and command deadlines.
- Image inspection: **100 megapixels** maximum; originals remain unchanged and optimized previews are separate.
- Profile photos: **5 MiB** maximum.
- The SSD is about 931.5 GiB before filesystem overhead/reservation. Account quotas are logical limits, not a guarantee that all disk space is available. Watch physical disk capacity separately.

## Server RAM and CPU

These are reviewed **release configuration limits**, not verified live limits until deployment. The owner’s inventory found the current API/worker/ClamAV unrestricted.

| Container | RAM maximum | CPU maximum |
| --- | --- | --- |
| API | 512 MiB | 1 |
| Worker | 1,536 MiB | 1 |
| ClamAV | 4 GiB | 1 |
| PostgreSQL | 768 MiB | 1 |
| Redis | 512 MiB | 0.5 |
| MinIO | 1 GiB | 1 |

The RAM ceilings sum to **8.25 GiB**; they are maximums, not preallocated reservations. Worker temporary storage is inside its RAM cap. MinIO has a 768 MiB Go soft memory target; Redis caps dataset memory at 128 MiB with `noeviction` to leave room for persistence and avoid silently dropping sessions. The migration helper is transient and capped separately at 256 MiB.

The host has about 15 GiB and runs other workloads. Check actual peak RSS, CPU, swap and disk pressure after rollout. Change only MyCloud’s environment limits; do not tune unrelated containers to compensate. A single SSD and retained rollback volume do not replace an independently monitored backup destination.

Selling storage is a later product decision. Billing, metering, commercial tenancy guarantees and marketing are not implemented claims in this personal-vault release.
