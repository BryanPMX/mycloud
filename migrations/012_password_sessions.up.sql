-- Existing tokens omit av and therefore remain version zero until a password change.
ALTER TABLE users ADD COLUMN IF NOT EXISTS auth_version bigint NOT NULL DEFAULT 0 CHECK (auth_version >= 0);
