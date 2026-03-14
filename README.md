# MyCloud

This repository now contains both the design set and the current implemented backend slices for MyCloud.

Current backend slice:
- PostgreSQL schema for `users`, `media`, `albums`, `album_media`, `shares`, `comments`, `favorites`, `jobs`, and `audit_log`
- JWT access/refresh auth with Redis-backed refresh session rotation and invite acceptance
- MinIO wiring for direct multipart uploads
- Redis-backed `process_media` job enqueue plus worker promotion/scan flow
- admin user list/invite/update/deactivate endpoints and admin system stats
- album list/create/detail/update/delete, album-media add/remove, and album share management
- comment persistence plus media comment list/create/delete endpoints
- media favorites on `GET /media` and `GET /albums/:id/media`, plus favorite/unfavorite endpoints
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/logout`
- `POST /api/v1/auth/invite/accept`
- `GET /api/v1/users/me`
- `GET /api/v1/media`
- `POST /api/v1/media/:id/favorite`
- `DELETE /api/v1/media/:id/favorite`
- `GET /api/v1/albums`
- `POST /api/v1/albums`
- `GET /api/v1/albums/:id`
- `PATCH /api/v1/albums/:id`
- `DELETE /api/v1/albums/:id`
- `GET /api/v1/albums/:id/media`
- `POST /api/v1/albums/:id/media`
- `DELETE /api/v1/albums/:id/media/:mediaId`
- `GET /api/v1/albums/:id/shares`
- `POST /api/v1/albums/:id/shares`
- `DELETE /api/v1/albums/:id/shares/:shareId`
- `GET /api/v1/media/:id/comments`
- `POST /api/v1/media/:id/comments`
- `DELETE /api/v1/media/:id/comments/:commentId`
- `GET /api/v1/admin/users`
- `POST /api/v1/admin/users/invite`
- `PATCH /api/v1/admin/users/:id`
- `DELETE /api/v1/admin/users/:id`
- `GET /api/v1/admin/stats`
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
