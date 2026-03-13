# MyCloud

This repository now contains both the design set and the first implemented backend slice for MyCloud.

Current backend slice:
- PostgreSQL schema for `users`, `media`, `albums`, `album_media`, `shares`, and `jobs`
- JWT access/refresh auth with Redis-backed refresh session rotation
- MinIO wiring for direct multipart uploads
- Redis-backed `process_media` job enqueue plus worker promotion/scan flow
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/logout`
- `GET /api/v1/users/me`
- `GET /api/v1/media`
- `POST /api/v1/media/upload/init`
- `POST /api/v1/media/upload/:id/part-url`
- `POST /api/v1/media/upload/:id/complete`
- `GET /health`

Use the numbered design docs for architecture and implementation status:
- [00-README.md](/Users/bryanpmx/Documents/Projects/mycloud/00-README.md) for the document index and status summary
- [03-api-reference.md](/Users/bryanpmx/Documents/Projects/mycloud/03-api-reference.md) for API status
- [04-database.md](/Users/bryanpmx/Documents/Projects/mycloud/04-database.md) for schema status
- [06-auth-security.md](/Users/bryanpmx/Documents/Projects/mycloud/06-auth-security.md) for auth/security status
- [09-subsystems-file-architecture.md](/Users/bryanpmx/Documents/Projects/mycloud/09-subsystems-file-architecture.md) for implementation order and current subsystem state
