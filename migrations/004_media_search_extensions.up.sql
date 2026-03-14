CREATE EXTENSION IF NOT EXISTS "pg_trgm";

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS invite_token TEXT,
    ADD COLUMN IF NOT EXISTS invite_token_expires_at TIMESTAMPTZ;

ALTER TABLE media
    ADD COLUMN IF NOT EXISTS search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('english', filename || ' ' || coalesce(metadata->>'title', ''))
    ) STORED;

CREATE INDEX IF NOT EXISTS idx_media_owner_taken
    ON media (owner_id, taken_at DESC NULLS LAST, id DESC)
    WHERE deleted_at IS NULL AND taken_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_media_search
    ON media USING GIN (search_vector);

CREATE INDEX IF NOT EXISTS idx_media_metadata
    ON media USING GIN (metadata);
