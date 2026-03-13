# 04 — Database Design (PostgreSQL)

---

## 1. Design Principles

- **UUIDs everywhere** — no sequential integer IDs that leak record counts or enable enumeration attacks.
- **Soft deletes with user-visible Trash** — media has a `deleted_at` column. Items stay restorable for 30 days before cleanup permanently removes them.
- **Quota counts Trash** — `users.storage_used` changes only on insert and hard delete. Moving an item to Trash does not free quota.
- **Denormalized counters** — `albums.media_count` is maintained by triggers and excludes trashed media from visible album counts.
- **JSONB for flexible metadata** — EXIF data and video codec information are stored in `media.metadata` as JSONB. Indexed for common queries (taken_at from EXIF).
- **Keyset pagination** — indexes are designed to support `(uploaded_at, id)` and `(taken_at, id)` cursor-based pagination.
- **Row-level security** — enforced in application code (repository layer), not at the Postgres level, to keep the DB portable. The repository `FindByIDForUser` method always includes `AND (owner_id = $userID OR id IN (SELECT media_id FROM album_media am JOIN shares s ON s.album_id = am.album_id WHERE s.shared_with IN ($userID, uuid_nil) AND (s.expires_at IS NULL OR s.expires_at > NOW())))`.
- **Best-effort queueing** — Redis `LPUSH`/`BRPOP` is the actual job delivery path. The `jobs` table is retained for operator visibility, retries, and reconciliation.

---

## 2. Full Schema

```sql
-- ── Extensions ───────────────────────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS "pgcrypto";  -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pg_trgm";   -- trigram index for search

-- ── Enums ────────────────────────────────────────────────────────────────

CREATE TYPE user_role AS ENUM ('member', 'admin');
CREATE TYPE media_status AS ENUM ('pending', 'processing', 'ready', 'failed');
CREATE TYPE permission AS ENUM ('view', 'contribute');
CREATE TYPE job_type AS ENUM ('process_media', 'cleanup', 'virus_scan');
CREATE TYPE job_status AS ENUM ('queued', 'running', 'done', 'failed');

-- ── Users ────────────────────────────────────────────────────────────────

CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           TEXT NOT NULL UNIQUE,
    display_name    TEXT NOT NULL,
    avatar_key      TEXT,                            -- MinIO object key, nullable
    role            user_role NOT NULL DEFAULT 'member',
    password_hash   TEXT NOT NULL,                   -- bcrypt, never returned to clients
    storage_used    BIGINT NOT NULL DEFAULT 0,        -- bytes, maintained by trigger
    quota_bytes     BIGINT NOT NULL DEFAULT 21474836480, -- 20 GB default
    active          BOOLEAN NOT NULL DEFAULT true,
    invite_token    TEXT,                            -- one-time invite token (hashed)
    invite_token_expires_at TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at   TIMESTAMPTZ
);

CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_active ON users (active) WHERE active = true;

-- ── Media ────────────────────────────────────────────────────────────────

CREATE TABLE media (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id        UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    filename        TEXT NOT NULL,
    mime_type       TEXT NOT NULL,
    size_bytes      BIGINT NOT NULL,
    width           INT,                             -- pixels, null until processed
    height          INT,                             -- pixels, null until processed
    duration_secs   NUMERIC(10, 3),                 -- null for images
    original_key    TEXT NOT NULL,                  -- MinIO key in fc-originals bucket
    thumb_small_key  TEXT,                           -- 320px webp
    thumb_medium_key TEXT,                           -- 800px webp
    thumb_large_key  TEXT,                           -- 1920px webp
    thumb_poster_key TEXT,                           -- video poster frame
    status          media_status NOT NULL DEFAULT 'pending',
    taken_at        TIMESTAMPTZ,                     -- from EXIF, null if unavailable
    uploaded_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ,                     -- soft delete
    metadata        JSONB NOT NULL DEFAULT '{}',     -- EXIF, codec info, etc.
    -- full-text search vector, updated by trigger
    search_vector   TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english', filename || ' ' || coalesce(metadata->>'title', ''))
    ) STORED
);

-- Ownership + status + soft-delete (most queries filter on these)
CREATE INDEX idx_media_owner_uploaded
    ON media (owner_id, uploaded_at DESC, id DESC)
    WHERE deleted_at IS NULL;

-- Same, but sorted by taken_at (EXIF date) — for timeline view
CREATE INDEX idx_media_owner_taken
    ON media (owner_id, taken_at DESC NULLS LAST, id DESC)
    WHERE deleted_at IS NULL AND taken_at IS NOT NULL;

-- Trash view
CREATE INDEX idx_media_owner_deleted
    ON media (owner_id, deleted_at DESC, id DESC)
    WHERE deleted_at IS NOT NULL;

-- Pending/processing jobs lookup
CREATE INDEX idx_media_status
    ON media (status)
    WHERE status IN ('pending', 'processing');

-- Full-text search
CREATE INDEX idx_media_search ON media USING GIN (search_vector);

-- JSONB metadata queries (e.g. filter by camera make)
CREATE INDEX idx_media_metadata ON media USING GIN (metadata);

-- Storage accounting trigger
CREATE OR REPLACE FUNCTION update_user_storage()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE users SET storage_used = storage_used + NEW.size_bytes WHERE id = NEW.owner_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE users SET storage_used = storage_used - OLD.size_bytes WHERE id = OLD.owner_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_media_storage
    AFTER INSERT OR DELETE ON media
    FOR EACH ROW EXECUTE FUNCTION update_user_storage();

-- Auto-update updated_at (applied to all tables below too)
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

-- ── Albums ───────────────────────────────────────────────────────────────

CREATE TABLE albums (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id        UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    name            TEXT NOT NULL,
    description     TEXT NOT NULL DEFAULT '',
    cover_media_id  UUID REFERENCES media(id) ON DELETE SET NULL,
    media_count     INT NOT NULL DEFAULT 0,          -- maintained by trigger
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_albums_owner ON albums (owner_id, created_at DESC);

CREATE TRIGGER trg_albums_updated_at
    BEFORE UPDATE ON albums
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ── Album–Media join table ────────────────────────────────────────────────

CREATE TABLE album_media (
    album_id   UUID NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
    media_id   UUID NOT NULL REFERENCES media(id) ON DELETE CASCADE,
    added_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    added_by   UUID NOT NULL REFERENCES users(id),
    PRIMARY KEY (album_id, media_id)
);

CREATE INDEX idx_album_media_media ON album_media (media_id);

-- Maintain albums.media_count
CREATE OR REPLACE FUNCTION update_album_count()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF EXISTS (SELECT 1 FROM media WHERE id = NEW.media_id AND deleted_at IS NULL) THEN
            UPDATE albums SET media_count = media_count + 1 WHERE id = NEW.album_id;
        END IF;
    ELSIF TG_OP = 'DELETE' THEN
        IF EXISTS (SELECT 1 FROM media WHERE id = OLD.media_id AND deleted_at IS NULL) THEN
            UPDATE albums SET media_count = media_count - 1 WHERE id = OLD.album_id;
        END IF;
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_album_media_count
    AFTER INSERT OR DELETE ON album_media
    FOR EACH ROW EXECUTE FUNCTION update_album_count();

-- Adjust visible album counts when media moves into or out of Trash
CREATE OR REPLACE FUNCTION update_album_count_on_media_visibility()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
        UPDATE albums a
        SET media_count = GREATEST(a.media_count - 1, 0)
        FROM album_media am
        WHERE am.album_id = a.id
          AND am.media_id = NEW.id;
    ELSIF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
        UPDATE albums a
        SET media_count = a.media_count + 1
        FROM album_media am
        WHERE am.album_id = a.id
          AND am.media_id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_media_album_visibility
    AFTER UPDATE OF deleted_at ON media
    FOR EACH ROW EXECUTE FUNCTION update_album_count_on_media_visibility();

-- ── Shares ───────────────────────────────────────────────────────────────

-- uuid_nil = '00000000-0000-0000-0000-000000000000' = shared with all family
CREATE TABLE shares (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    album_id     UUID NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
    shared_by    UUID NOT NULL REFERENCES users(id),
    shared_with  UUID NOT NULL,                      -- user ID or uuid_nil for family-wide
    permission   permission NOT NULL DEFAULT 'view',
    expires_at   TIMESTAMPTZ,                        -- null = never expires
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_shares_unique
    ON shares (album_id, shared_with);              -- one share per album per recipient

CREATE INDEX idx_shares_shared_with
    ON shares (shared_with, album_id)
    WHERE expires_at IS NULL OR expires_at > NOW();

-- ── Favorites ────────────────────────────────────────────────────────────

CREATE TABLE favorites (
    user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    media_id  UUID NOT NULL REFERENCES media(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, media_id)
);

CREATE INDEX idx_favorites_user ON favorites (user_id, created_at DESC);

-- ── Comments ─────────────────────────────────────────────────────────────

CREATE TABLE comments (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    media_id   UUID NOT NULL REFERENCES media(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    body       TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ                          -- soft-delete
);

CREATE INDEX idx_comments_media ON comments (media_id, created_at ASC) WHERE deleted_at IS NULL;

-- ── Background Jobs ───────────────────────────────────────────────────────

CREATE TABLE jobs (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    media_id     UUID REFERENCES media(id) ON DELETE CASCADE,
    type         job_type NOT NULL,
    status       job_status NOT NULL DEFAULT 'queued',
    payload      JSONB NOT NULL DEFAULT '{}',       -- operational metadata; Redis remains the live queue
    error        TEXT,
    attempts     INT NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at   TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

CREATE INDEX idx_jobs_status ON jobs (status, created_at) WHERE status IN ('queued', 'running');
CREATE INDEX idx_jobs_media  ON jobs (media_id);

-- ── Audit Log (append-only) ───────────────────────────────────────────────

CREATE TABLE audit_log (
    id         BIGSERIAL PRIMARY KEY,               -- sequential for chronological ordering
    actor_id   UUID REFERENCES users(id),
    action     TEXT NOT NULL,                       -- e.g. "media.delete", "share.create"
    target_id  UUID,                                -- affected resource ID
    meta       JSONB NOT NULL DEFAULT '{}',         -- before/after values, context
    ip_address INET,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_actor  ON audit_log (actor_id, created_at DESC);
CREATE INDEX idx_audit_target ON audit_log (target_id, created_at DESC);
CREATE INDEX idx_audit_action ON audit_log (action, created_at DESC);
```

---

## 3. Key Queries

### Keyset Pagination (Media Timeline)

```sql
-- First page (sort by uploaded_at DESC, id DESC for tie-breaking)
SELECT *
FROM   media
WHERE  owner_id = $1
  AND  deleted_at IS NULL
ORDER  BY uploaded_at DESC, id DESC
LIMIT  51; -- fetch 1 extra to detect if there's a next page

-- Subsequent pages (cursor = base64(uploaded_at || id))
SELECT *
FROM   media
WHERE  owner_id = $1
  AND  deleted_at IS NULL
  AND  (uploaded_at, id) < ($cursor_uploaded_at, $cursor_id) -- keyset predicate
ORDER  BY uploaded_at DESC, id DESC
LIMIT  51;
```

This is efficient because `idx_media_owner_uploaded` covers all three predicates.

### Trash Listing

```sql
SELECT *
FROM   media
WHERE  owner_id = $1
  AND  deleted_at IS NOT NULL
ORDER  BY deleted_at DESC, id DESC
LIMIT  51;
```

### Authorization-Aware Media Fetch

```sql
-- FindByIDForUser: returns media only if user owns it OR has an active share
SELECT m.*
FROM   media m
WHERE  m.id = $media_id
  AND  m.deleted_at IS NULL
  AND (
    m.owner_id = $user_id
    OR EXISTS (
      SELECT 1
      FROM   album_media am
      JOIN   shares s ON s.album_id = am.album_id
      WHERE  am.media_id = m.id
        AND  s.shared_with IN ($user_id, '00000000-0000-0000-0000-000000000000')
        AND  (s.expires_at IS NULL OR s.expires_at > NOW())
    )
  );
```

### Storage Usage Per User (Admin Dashboard)

```sql
SELECT
    u.id,
    u.display_name,
    u.email,
    u.storage_used,              -- maintained by trigger, no COUNT needed
    u.quota_bytes,
    ROUND(100.0 * u.storage_used / NULLIF(u.quota_bytes, 0), 1) AS pct_used,
    COUNT(m.id) AS media_count
FROM   users u
LEFT JOIN media m ON m.owner_id = u.id AND m.deleted_at IS NULL
GROUP  BY u.id
ORDER  BY u.storage_used DESC;
```

### Full-Text Search

```sql
-- Uses the GIN index on search_vector
SELECT *
FROM   media
WHERE  owner_id = $user_id
  AND  deleted_at IS NULL
  AND  search_vector @@ plainto_tsquery('english', $query)
ORDER  BY ts_rank(search_vector, plainto_tsquery('english', $query)) DESC,
          uploaded_at DESC
LIMIT  $limit;
```

---

## 4. Migrations

Migrations are plain SQL files, numbered sequentially. Use `golang-migrate` to apply them.

```bash
# Install migrate
go install -tags 'postgres' github.com/golang-migrate/migrate/v4/cmd/migrate@latest

# Apply all pending migrations
migrate -path ./migrations -database "$DATABASE_URL" up

# Roll back the most recent migration
migrate -path ./migrations -database "$DATABASE_URL" down 1
```

Migration file naming: `NNN_description.up.sql` and `NNN_description.down.sql`.

### Example: 001_initial_schema.up.sql

The file above is the initial schema. The corresponding `.down.sql`:

```sql
-- 001_initial_schema.down.sql
DROP TABLE IF EXISTS audit_log CASCADE;
DROP TABLE IF EXISTS jobs CASCADE;
DROP TABLE IF EXISTS comments CASCADE;
DROP TABLE IF EXISTS favorites CASCADE;
DROP TABLE IF EXISTS shares CASCADE;
DROP TABLE IF EXISTS album_media CASCADE;
DROP TABLE IF EXISTS albums CASCADE;
DROP TABLE IF EXISTS media CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP FUNCTION IF EXISTS update_user_storage CASCADE;
DROP FUNCTION IF EXISTS update_album_count CASCADE;
DROP FUNCTION IF EXISTS update_album_count_on_media_visibility CASCADE;
DROP FUNCTION IF EXISTS set_updated_at CASCADE;
DROP TYPE IF EXISTS job_status CASCADE;
DROP TYPE IF EXISTS job_type CASCADE;
DROP TYPE IF EXISTS permission CASCADE;
DROP TYPE IF EXISTS media_status CASCADE;
DROP TYPE IF EXISTS user_role CASCADE;
DROP EXTENSION IF EXISTS pg_trgm;
DROP EXTENSION IF EXISTS pgcrypto;
```

---

## 5. PostgreSQL Repository Implementation (excerpt)

```go
// internal/infrastructure/postgres/media_repository.go
package postgres

import (
    "context"
    "encoding/base64"
    "encoding/json"
    "fmt"
    "strings"
    "time"

    "github.com/google/uuid"
    "github.com/jmoiron/sqlx"
    "github.com/yourorg/familycloud/internal/domain"
)

type mediaRow struct {
    ID             string          `db:"id"`
    OwnerID        string          `db:"owner_id"`
    Filename       string          `db:"filename"`
    MimeType       string          `db:"mime_type"`
    SizeBytes      int64           `db:"size_bytes"`
    Width          *int            `db:"width"`
    Height         *int            `db:"height"`
    DurationSecs   *float64        `db:"duration_secs"`
    OriginalKey    string          `db:"original_key"`
    ThumbSmallKey  *string         `db:"thumb_small_key"`
    ThumbMediumKey *string         `db:"thumb_medium_key"`
    ThumbLargeKey  *string         `db:"thumb_large_key"`
    ThumbPosterKey *string         `db:"thumb_poster_key"`
    Status         string          `db:"status"`
    TakenAt        *time.Time      `db:"taken_at"`
    UploadedAt     time.Time       `db:"uploaded_at"`
    Metadata       []byte          `db:"metadata"`
}

func (r mediaRow) toDomain() (*domain.Media, error) {
    id, _ := uuid.Parse(r.ID)
    ownerID, _ := uuid.Parse(r.OwnerID)
    var meta map[string]any
    _ = json.Unmarshal(r.Metadata, &meta)

    m := &domain.Media{
        ID:          id,
        OwnerID:     ownerID,
        Filename:    r.Filename,
        MimeType:    r.MimeType,
        SizeBytes:   r.SizeBytes,
        OriginalKey: r.OriginalKey,
        Status:      domain.MediaStatus(r.Status),
        TakenAt:     r.TakenAt,
        UploadedAt:  r.UploadedAt,
        Metadata:    meta,
    }
    if r.Width != nil  { m.Width = *r.Width }
    if r.Height != nil { m.Height = *r.Height }
    if r.DurationSecs != nil { m.DurationSecs = *r.DurationSecs }
    m.ThumbKeys = domain.ThumbKeys{
        Small:  derefStr(r.ThumbSmallKey),
        Medium: derefStr(r.ThumbMediumKey),
        Large:  derefStr(r.ThumbLargeKey),
        Poster: derefStr(r.ThumbPosterKey),
    }
    return m, nil
}

type PostgresMediaRepository struct{ db *sqlx.DB }

func NewMediaRepository(db *sqlx.DB) *PostgresMediaRepository {
    return &PostgresMediaRepository{db: db}
}

func (r *PostgresMediaRepository) List(ctx context.Context, ownerID uuid.UUID, opts domain.ListOptions) (domain.MediaPage, error) {
    var sb strings.Builder
    args := []any{ownerID}

    sb.WriteString(`
        SELECT id, owner_id, filename, mime_type, size_bytes, width, height,
               duration_secs, original_key, thumb_small_key, thumb_medium_key,
               thumb_large_key, thumb_poster_key, status, taken_at, uploaded_at, metadata
        FROM media
        WHERE owner_id = $1 AND deleted_at IS NULL
    `)

    // Cursor predicate
    if opts.Cursor != "" {
        cursorAt, cursorID, err := decodeCursor(opts.Cursor)
        if err == nil {
            args = append(args, cursorAt, cursorID)
            fmt.Fprintf(&sb, " AND (uploaded_at, id) < ($%d, $%d)", len(args)-1, len(args))
        }
    }

    // MIME filter
    if len(opts.MimeTypes) > 0 {
        placeholders := make([]string, len(opts.MimeTypes))
        for i, mt := range opts.MimeTypes {
            args = append(args, mt+"%")
            placeholders[i] = fmt.Sprintf("mime_type LIKE $%d", len(args))
        }
        sb.WriteString(" AND (" + strings.Join(placeholders, " OR ") + ")")
    }

    // Date range
    if opts.DateFrom != nil {
        args = append(args, opts.DateFrom)
        fmt.Fprintf(&sb, " AND taken_at >= $%d", len(args))
    }
    if opts.DateTo != nil {
        args = append(args, opts.DateTo)
        fmt.Fprintf(&sb, " AND taken_at <= $%d", len(args))
    }

    sb.WriteString(" ORDER BY uploaded_at DESC, id DESC")

    limit := opts.Limit
    if limit <= 0 || limit > 100 { limit = 50 }
    args = append(args, limit+1) // fetch 1 extra to detect next page
    fmt.Fprintf(&sb, " LIMIT $%d", len(args))

    var rows []mediaRow
    if err := r.db.SelectContext(ctx, &rows, sb.String(), args...); err != nil {
        return domain.MediaPage{}, err
    }

    var nextCursor string
    if len(rows) > limit {
        rows = rows[:limit]
        last := rows[len(rows)-1]
        nextCursor = encodeCursor(last.UploadedAt, last.ID)
    }

    items := make([]*domain.Media, 0, len(rows))
    for _, row := range rows {
        m, _ := row.toDomain()
        items = append(items, m)
    }

    return domain.MediaPage{Items: items, NextCursor: nextCursor}, nil
}

// Helpers
func encodeCursor(t time.Time, id string) string {
    b, _ := json.Marshal(map[string]any{"t": t, "id": id})
    return base64.URLEncoding.EncodeToString(b)
}

func decodeCursor(s string) (time.Time, string, error) {
    b, err := base64.URLEncoding.DecodeString(s)
    if err != nil { return time.Time{}, "", err }
    var m map[string]any
    if err := json.Unmarshal(b, &m); err != nil { return time.Time{}, "", err }
    t, _ := time.Parse(time.RFC3339Nano, m["t"].(string))
    return t, m["id"].(string), nil
}

func derefStr(s *string) string {
    if s == nil { return "" }
    return *s
}
```

---

## 6. Connection Pool Configuration

```go
// internal/infrastructure/postgres/pool.go
package postgres

import (
    "context"
    "time"

    "github.com/jackc/pgx/v5/pgxpool"
    "github.com/jmoiron/sqlx"
    "github.com/jackc/pgx/v5/stdlib"
)

func NewPool(databaseURL string) *sqlx.DB {
    config, err := pgxpool.ParseConfig(databaseURL)
    if err != nil { panic(err) }

    config.MaxConns         = 25              // tuned for 16 GB server
    config.MinConns         = 5
    config.MaxConnLifetime  = 30 * time.Minute
    config.MaxConnIdleTime  = 5 * time.Minute
    config.HealthCheckPeriod = 1 * time.Minute

    pool, err := pgxpool.NewWithConfig(context.Background(), config)
    if err != nil { panic(err) }

    // Wrap in sqlx for struct scanning
    db := sqlx.NewDb(stdlib.OpenDBFromPool(pool), "pgx")
    return db
}
```
