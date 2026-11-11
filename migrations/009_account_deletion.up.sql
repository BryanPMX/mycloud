CREATE TABLE avatar_deletions (
 object_key text PRIMARY KEY,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE users ADD COLUMN deletion_requested_at timestamptz;
