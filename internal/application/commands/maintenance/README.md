# `internal/application/commands/maintenance`

Maintenance commands live here.

This package currently owns the scheduled cleanup flow that purges expired trash rows, deletes expired shares, and triggers best-effort MinIO asset cleanup for permanently removed media.
