CREATE EXTENSION IF NOT EXISTS "pgcrypto";

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM ('member', 'admin');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'media_status') THEN
        CREATE TYPE media_status AS ENUM ('pending', 'processing', 'ready', 'failed');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'permission') THEN
        CREATE TYPE permission AS ENUM ('view', 'contribute');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'job_type') THEN
        CREATE TYPE job_type AS ENUM ('process_media', 'cleanup');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'job_status') THEN
        CREATE TYPE job_status AS ENUM ('queued', 'running', 'done', 'failed');
    END IF;
END $$;

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION update_user_storage()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE users SET storage_used = storage_used + NEW.size_bytes WHERE id = NEW.owner_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE users SET storage_used = storage_used - OLD.size_bytes WHERE id = OLD.owner_id;
    END IF;

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION update_album_count()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF EXISTS (SELECT 1 FROM media WHERE id = NEW.media_id AND deleted_at IS NULL) THEN
            UPDATE albums SET media_count = media_count + 1 WHERE id = NEW.album_id;
        END IF;
    ELSIF TG_OP = 'DELETE' THEN
        IF EXISTS (SELECT 1 FROM media WHERE id = OLD.media_id AND deleted_at IS NULL) THEN
            UPDATE albums SET media_count = GREATEST(media_count - 1, 0) WHERE id = OLD.album_id;
        END IF;
    END IF;

    RETURN NULL;
END;
$$;

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

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL,
    display_name TEXT NOT NULL,
    avatar_key TEXT,
    role user_role NOT NULL DEFAULT 'member',
    password_hash TEXT NOT NULL,
    storage_used BIGINT NOT NULL DEFAULT 0,
    quota_bytes BIGINT NOT NULL DEFAULT 21474836480,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_lower ON users (lower(email));
CREATE INDEX IF NOT EXISTS idx_users_active ON users (active) WHERE active = true;

CREATE TABLE IF NOT EXISTS media (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    filename TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    size_bytes BIGINT NOT NULL CHECK (size_bytes >= 0),
    width INT,
    height INT,
    duration_secs NUMERIC(10,3),
    original_key TEXT NOT NULL,
    thumb_small_key TEXT,
    thumb_medium_key TEXT,
    thumb_large_key TEXT,
    thumb_poster_key TEXT,
    status media_status NOT NULL DEFAULT 'pending',
    taken_at TIMESTAMPTZ,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_media_owner_uploaded
    ON media (owner_id, uploaded_at DESC, id DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_media_owner_deleted
    ON media (owner_id, deleted_at DESC, id DESC)
    WHERE deleted_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_media_status
    ON media (status)
    WHERE status IN ('pending', 'processing');

CREATE TABLE IF NOT EXISTS albums (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    cover_media_id UUID REFERENCES media(id) ON DELETE SET NULL,
    media_count INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_albums_owner ON albums (owner_id, created_at DESC);

CREATE TABLE IF NOT EXISTS album_media (
    album_id UUID NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
    media_id UUID NOT NULL REFERENCES media(id) ON DELETE CASCADE,
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    added_by UUID NOT NULL REFERENCES users(id),
    PRIMARY KEY (album_id, media_id)
);

CREATE INDEX IF NOT EXISTS idx_album_media_media ON album_media (media_id);

CREATE TABLE IF NOT EXISTS shares (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    album_id UUID NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
    shared_by UUID NOT NULL REFERENCES users(id),
    shared_with UUID NOT NULL,
    permission permission NOT NULL DEFAULT 'view',
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_shares_unique ON shares (album_id, shared_with);
CREATE INDEX IF NOT EXISTS idx_shares_shared_with ON shares (shared_with, album_id);

CREATE TABLE IF NOT EXISTS jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    media_id UUID REFERENCES media(id) ON DELETE CASCADE,
    type job_type NOT NULL,
    status job_status NOT NULL DEFAULT 'queued',
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    error TEXT,
    attempts INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs (status, created_at) WHERE status IN ('queued', 'running');

DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_albums_updated_at ON albums;
CREATE TRIGGER trg_albums_updated_at
    BEFORE UPDATE ON albums
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_media_storage ON media;
CREATE TRIGGER trg_media_storage
    AFTER INSERT OR DELETE ON media
    FOR EACH ROW EXECUTE FUNCTION update_user_storage();

DROP TRIGGER IF EXISTS trg_album_media_count ON album_media;
CREATE TRIGGER trg_album_media_count
    AFTER INSERT OR DELETE ON album_media
    FOR EACH ROW EXECUTE FUNCTION update_album_count();

DROP TRIGGER IF EXISTS trg_media_album_visibility ON media;
CREATE TRIGGER trg_media_album_visibility
    AFTER UPDATE OF deleted_at ON media
    FOR EACH ROW EXECUTE FUNCTION update_album_count_on_media_visibility();
