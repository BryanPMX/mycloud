-- Reservations live in PostgreSQL so Redis restarts cannot discard quota state.
CREATE TABLE upload_sessions (
 media_id uuid PRIMARY KEY,
 owner_id uuid NOT NULL REFERENCES users(id),
 reserved_bytes bigint NOT NULL CHECK (reserved_bytes > 0),
 session jsonb NOT NULL,
 expires_at timestamptz NOT NULL
);
CREATE INDEX upload_sessions_owner ON upload_sessions(owner_id);
CREATE INDEX upload_sessions_expiry ON upload_sessions(expires_at);
ALTER TABLE media ADD COLUMN derivative_bytes bigint NOT NULL DEFAULT 0 CHECK (derivative_bytes >= 0);

-- Keep object keys and quota charges until physical deletion succeeds.
CREATE TABLE media_deletions (
 media_id uuid PRIMARY KEY,
 owner_id uuid NOT NULL REFERENCES users(id),
 charged_bytes bigint NOT NULL,
 original_key text NOT NULL,
 thumb_small_key text,
 thumb_medium_key text,
 thumb_large_key text,
 thumb_poster_key text,
 mime_type text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION update_user_storage()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE account users%ROWTYPE; reserved bigint; delta bigint;
BEGIN
 IF TG_OP = 'DELETE' THEN
  INSERT INTO media_deletions(media_id, owner_id, charged_bytes, original_key,
   thumb_small_key, thumb_medium_key, thumb_large_key, thumb_poster_key, mime_type)
  VALUES (OLD.id, OLD.owner_id, OLD.size_bytes + OLD.derivative_bytes, OLD.original_key,
   OLD.thumb_small_key, OLD.thumb_medium_key, OLD.thumb_large_key, OLD.thumb_poster_key, OLD.mime_type)
  ON CONFLICT (media_id) DO NOTHING;
  RETURN NULL;
 END IF;
 SELECT * INTO account FROM users WHERE id = NEW.owner_id FOR UPDATE;
 IF TG_OP = 'INSERT' THEN
  delta := NEW.size_bytes + NEW.derivative_bytes;
 ELSE
  IF NEW.owner_id <> OLD.owner_id OR NEW.size_bytes <> OLD.size_bytes THEN
   RAISE EXCEPTION 'Media ownership and original size are immutable';
  END IF;
  delta := NEW.derivative_bytes - OLD.derivative_bytes;
 END IF;
 SELECT COALESCE(sum(s.reserved_bytes),0) INTO reserved FROM upload_sessions s
 WHERE s.owner_id = NEW.owner_id AND s.media_id <> NEW.id AND s.expires_at > now()
 AND NOT EXISTS (SELECT 1 FROM media m WHERE m.id = s.media_id);
 IF delta > 0 AND (NOT account.active OR delta > account.quota_bytes - account.storage_used - reserved) THEN
  RAISE EXCEPTION 'Storage quota exceeded' USING ERRCODE = '23514', CONSTRAINT = 'user_storage_quota';
 END IF;
 UPDATE users SET storage_used = storage_used + delta WHERE id = NEW.owner_id;
 RETURN NULL;
END;
$$;
DROP TRIGGER trg_media_storage ON media;
CREATE TRIGGER trg_media_storage AFTER INSERT OR DELETE OR UPDATE OF derivative_bytes, owner_id, size_bytes ON media
 FOR EACH ROW EXECUTE FUNCTION update_user_storage();
