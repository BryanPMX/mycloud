# Disaster recovery

## First response

Stop MyCloud writes and identify the failed component. Preserve the old database, MinIO volume/SSD, logs and latest successful backup manifests. Do not initialize an apparently empty mount, format a replacement automatically, prune Docker volumes, delete cloud originals or restore over a live database. Keep administrative services on localhost/Tailscale throughout recovery.

## Missing SSD

The opt-in storage guard must refuse startup. Check the recorded model/serial/by-id/UUID, cabling, power, kernel I/O errors, filesystem mount and SMART data using the existing tooling. Never write the identity marker into an unmounted fallback directory. Stop only MyCloud API/worker/MinIO before filesystem recovery. Reattach/mount the verified device, run the host preflight, then start MinIO and check existing objects before enabling writers. If the device is unreadable, preserve it and restore to a different prepared disk from the independent backup.

## PostgreSQL loss

Use a matched verified archive/media snapshot. Restore into a new empty database/volume, preserve the failed copy and validate schema versions/checksums, account/membership/media/post counts and authorization. Point a private rehearsal API at the restored database first. Reusing an older DB with a newer object store can leave unreferenced objects; inventory them rather than deleting them. Reconcile usage only after originals/metadata are consistent.

## MinIO loss or corruption

Restore current objects and metadata into empty private buckets or a replacement instance. Verify every restored object's SHA-256 and size, then test real photo/video previews and originals through authorized API requests. Historical primary versions are not all separate versions in the application snapshot; use older retained snapshots or a preserved full data-tree copy when necessary. Never make a bucket public to repair previews. A checksum mismatch is an incident requiring another copy, not a reason to waive verification.

## Redis loss

Expect users to log in again. Do not recreate sessions from untrusted tokens. PostgreSQL retains upload reservations, queued jobs and deletion state. The worker periodically rebuilds dispatch hints and recovers expired running leases. Active multipart uploads with valid database sessions can continue; expired/abandoned uploads are cleaned up. Check queue depth, exhausted jobs and reservation/deletion backlogs before declaring recovery.

## Bad release or migration

Pause writers, record current release and take a new forensic backup. Before any new production writes, rolling back to retained images/configuration plus the verified pre-migration DB/object snapshot is straightforward. After new writes, restoring an older DB or switching back to the old MinIO volume can discard those writes; reconcile/copy them first and obtain explicit approval for any unavoidable loss. Migrations deliberately refuse automatic bulk downs. Retain original volumes and restore into new targets when practical.

## Acceptance record

Record failure time, last successful independent backup, restored snapshot date/count/bytes, missing data, actual recovery duration and corrective action. Validate accounts, household membership, private-media denial, originals/previews, new photo/video upload, unsharing, deletion/accounting, readiness and alert delivery. Have a family member verify their own sample library. Only then resume normal writes and update [validation.md](validation.md).
