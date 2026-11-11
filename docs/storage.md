# Storage and SSD migration

## Verified server inventory

The owner inspected `server-hp` on 10 November 2026. The internal Toshiba disk has an ext4 root logical volume. Current MinIO storage is Docker volume `mycloud_minio_data`, source `/var/lib/docker/volumes/mycloud_minio_data/_data`.

The external device is **Crucial CT1000X10SSD9**, serial ending **662C** (full serial retained in the owner’s private inventory), 931.5 GiB usable. Read-only inspection of its former exFAT partition (UUID E4A2-01BF) found two files, approximately 1 MiB. The owner archived them on the internal disk, compared the archive with the source, recorded its SHA-256, and explicitly approved formatting only the existing large partition.

The owner performed that approved format on 10 November 2026 (11 November UTC). The new ext4 filesystem UUID is **4dcf77a1-cf9c-43da-ad18-4fe11443034f**. It is mounted by UUID at `/srv/mycloud-data`; fstab was backed up before editing, and the write/read/identity-marker checks passed. The 16 MiB first partition and internal OS disk were untouched.

**The live MinIO volume has not yet been switched.** Keep `mycloud_minio_data` until migration and rollback verification finish. Device letters are observations, never persistent identifiers. No independent long-term media backup target is available yet.

## Preparation gate

Before any destructive disk command, verify model/serial/by-id/UUID again, no mounted partitions/open device users/container use, and a verified archive of the two existing files on another physical disk. Obtain explicit approval identifying the partition and loss of its exFAT contents. Prefer formatting only the existing large partition as ext4; repartitioning is unnecessary unless inspection shows another requirement. Do not touch the internal disk. Do not include a format command in unattended installation.

After approved preparation, record the **new** filesystem UUID. Mount at `/srv/mycloud-data` with a UUID-based `/etc/fstab` entry such as:

```fstab
UUID=PREPARED_EXT4_UUID /srv/mycloud-data ext4 defaults,nosuid,nodev,noexec,nofail,x-systemd.device-timeout=15s 0 2
```

Back up fstab before editing. Verify `mountpoint`, `findmnt` UUID/filesystem and a write/read check before creating `/srv/mycloud-data/minio`, `staging` or the identity marker. Write the prepared UUID into `/srv/mycloud-data/.mycloud-volume` **only after this check**. A backup directory on this same SSD is not an independent backup.

## Missing-mount protection

Run `scripts/storage-preflight.sh` with `/etc/mycloud/storage.env`. It requires an actual mount, matching UUID, Linux filesystem, identity marker and MinIO directory. The optional systemd preflight uses `RequiresMountsFor` without changing Docker's global service or other stacks.

`deploy/portainer-stack.ssd.yml` is an opt-in override. Its bind mounts use `create_host_path: false`; the data directory, identity file and installed guard must already exist. The guard runs inside MinIO on **every** container start, including Docker restarts, and refuses a missing/mismatched marker or unwritable data path. This prevents a missing SSD from silently becoming a root-filesystem directory. The host preflight proves the marker belongs to the expected mounted filesystem. Never copy that marker into the root filesystem's fallback directory.

A disappearing device produces I/O failure in the existing mount namespace; do not force-unmount an active MinIO disk. Stop only MyCloud writers/MinIO, restore the device/mount, rerun preflight, then restart. Verify this failure mode in an isolated rehearsal before adopting the SSD.

## Controlled migration

1. Preserve the two SSD files and verify their archive. Prepare/mount only after explicit approval.
2. Back up Portainer stack/environment/NPM configuration privately. Record exact running image digests, bucket versioning and object inventories.
3. Take a maintenance window. Stop API/worker writes and verify uploads/jobs are drained or accounted for. Keep old storage untouched.
4. Prefer an offline copy of the **entire** stopped MinIO data tree, including hidden `.minio.sys` metadata and all object versions, to the prepared SSD. Use `rsync -aHAX --numeric-ids SOURCE/ DESTINATION/` while MinIO is stopped. Never use `--delete` against the source. A live filesystem copy of MinIO data is not a consistent migration.
5. Run a second checksum comparison, for example `rsync -aHAXnc --numeric-ids SOURCE/ DESTINATION/`, and ensure no unexpected differences. Record object/current-version counts and checksums using the application backup manifest or a private MinIO client inventory.
6. Install the guard/preflight and configure the prepared UUID. Apply the SSD override to **only** MyCloud; preserve Compose project/volume names. Validate configuration without printing secrets.
7. Start MinIO and check health, then API/worker. Verify existing photo/video downloads, previews, new uploads, scoped family feed, unsharing and test-asset deletion. Never delete original family media as a migration test.
8. Test missing-mount refusal in an isolated equivalent configuration. Monitor disk/SMART, physical capacity and processing errors.
9. Retain `mycloud_minio_data` intact until the owner accepts migration and a separate verified backup/restore. Revert the override to use the old copy if verification fails **before new writes**. After new writes, stop and reconcile copies before rollback; blindly reverting would lose those writes.

## Quota reconciliation

Run the backup image's `reconcile-storage` command without flags first, with private DB/MinIO configuration. It measures tracked originals/staging/derivatives, reports missing ready originals and drift, and does not alter data. A missing ready original requires restoration/investigation, not automatic row deletion.

During a maintenance window with API/worker stopped, set `RECONCILE_WRITES_PAUSED=yes` and use `reconcile-storage --apply`. It atomically updates actual sizes and recomputes usage including deletion outbox charges, preserving quotas; over-quota users cannot add files. Original media ownership never changes. Preserve inventories and investigate unreferenced objects separately; never blindly remove them to make counters match.
