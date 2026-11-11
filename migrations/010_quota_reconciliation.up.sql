-- Retain expired reservations until physical cleanup succeeds.
-- Delay cleanup of processing assets beyond the worker's maximum lease so an
-- in-flight processor cannot recreate derivatives after deletion acknowledgement.
ALTER TABLE media_deletions ADD COLUMN not_before timestamptz NOT NULL DEFAULT (now()+interval '12 minutes');
CREATE OR REPLACE FUNCTION update_user_storage()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE account users%ROWTYPE; reserved bigint; delta bigint;
BEGIN
 IF TG_OP = 'DELETE' THEN
  INSERT INTO media_deletions(media_id, owner_id, charged_bytes, original_key,
   thumb_small_key, thumb_medium_key, thumb_large_key, thumb_poster_key, mime_type, not_before)
  VALUES (OLD.id, OLD.owner_id, OLD.size_bytes + OLD.derivative_bytes, OLD.original_key,
   OLD.thumb_small_key, OLD.thumb_medium_key, OLD.thumb_large_key, OLD.thumb_poster_key, OLD.mime_type, CASE WHEN OLD.status IN ('pending','processing') THEN now()+interval '12 minutes' ELSE now() END)
  ON CONFLICT (media_id) DO NOTHING;
  RETURN NULL;
 END IF;
 SELECT * INTO account FROM users WHERE id = NEW.owner_id FOR UPDATE;
 IF TG_OP = 'INSERT' THEN
  delta := NEW.size_bytes + NEW.derivative_bytes;
 ELSE
  IF NEW.owner_id <> OLD.owner_id THEN
   RAISE EXCEPTION 'Media ownership is immutable';
  END IF;
  delta := NEW.size_bytes + NEW.derivative_bytes - OLD.size_bytes - OLD.derivative_bytes;
 END IF;
 SELECT COALESCE(sum(s.reserved_bytes),0) INTO reserved FROM upload_sessions s
 WHERE s.owner_id = NEW.owner_id AND s.media_id <> NEW.id
 AND NOT EXISTS (SELECT 1 FROM media m WHERE m.id = s.media_id);
 IF delta > 0 AND current_setting('mycloud.storage_reconcile', true) IS DISTINCT FROM 'on' AND (NOT account.active OR delta > account.quota_bytes - account.storage_used - reserved) THEN
  RAISE EXCEPTION 'Storage quota exceeded' USING ERRCODE = '23514', CONSTRAINT = 'user_storage_quota';
 END IF;
 UPDATE users SET storage_used = storage_used + delta WHERE id = NEW.owner_id;
 RETURN NULL;
END;
$$;
