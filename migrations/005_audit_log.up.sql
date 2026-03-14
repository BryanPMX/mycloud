CREATE TABLE IF NOT EXISTS audit_log (
    id BIGSERIAL PRIMARY KEY,
    actor_id UUID REFERENCES users(id),
    action TEXT NOT NULL,
    target_id UUID,
    meta JSONB NOT NULL DEFAULT '{}'::jsonb,
    ip_address INET,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_actor
    ON audit_log (actor_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_target
    ON audit_log (target_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_action
    ON audit_log (action, created_at DESC);
