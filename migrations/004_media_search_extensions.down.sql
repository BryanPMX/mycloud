DROP INDEX IF EXISTS idx_media_metadata;
DROP INDEX IF EXISTS idx_media_search;
DROP INDEX IF EXISTS idx_media_owner_taken;

ALTER TABLE media
    DROP COLUMN IF EXISTS search_vector;

ALTER TABLE users
    DROP COLUMN IF EXISTS invite_token_expires_at,
    DROP COLUMN IF EXISTS invite_token;

DROP EXTENSION IF EXISTS pg_trgm;
