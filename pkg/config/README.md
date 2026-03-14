# `pkg/config`

Configuration loading helpers live here.

This directory translates environment variables into application configuration structs.

Current config surface on March 14, 2026 includes:
- core app, JWT, PostgreSQL, Redis, and MinIO settings
- ClamAV socket wiring for the worker virus-scan path
- SMTP host/port/from credentials for invite delivery
- cleanup scheduling cadence for the background worker
