# `cmd/worker`

This is the background worker entry point.

It boots PostgreSQL, Redis, MinIO, and the ClamAV adapter, schedules recurring cleanup jobs, and drains the Redis-backed job queue to process pending media uploads.

Keep this directory limited to startup wiring for queue consumption and media-processing pipelines.
