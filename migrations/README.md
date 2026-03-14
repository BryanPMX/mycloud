# `migrations`

Database schema migrations live here.

Current migration set on March 14, 2026:
- `001_initial_schema` creates `users`, `media`, `albums`, `album_media`, `shares`, and `jobs`, plus the storage/accounting and album visibility triggers
- `002_comments` adds soft-deletable media comments
- `003_favorites` adds per-user media favorites
- `004_media_search_extensions` adds invite-token columns, `pg_trgm`, `search_vector`, and the media search/timeline indexes
- `005_audit_log` adds append-only audit storage for invite and admin actions

Keep migrations versioned, append-only, and paired with rollback files where possible.
