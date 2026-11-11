package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yourorg/mycloud/internal/domain"
)

type UploadSessionStore struct{ db *pgxpool.Pool }

func NewUploadSessionStore(db *pgxpool.Pool) *UploadSessionStore { return &UploadSessionStore{db: db} }
func (s *UploadSessionStore) SaveUploadSession(ctx context.Context, session domain.UploadSession, ttl time.Duration) error {
	if session.SizeBytes <= 0 || session.SizeBytes > domain.MaxUploadSizeBytes || ttl <= 0 {
		return domain.ErrInvalidInput
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var used, quota int64
	var active bool
	if err = tx.QueryRow(ctx, `SELECT storage_used, quota_bytes, active FROM users WHERE id=$1 FOR UPDATE`, session.OwnerID).Scan(&used, &quota, &active); err != nil {
		return err
	}
	if !active {
		return domain.ErrUnauthorized
	}
	var reserved int64
	if err = tx.QueryRow(ctx, `SELECT COALESCE(sum(s.reserved_bytes),0) FROM upload_sessions s WHERE owner_id=$1 AND NOT EXISTS(SELECT 1 FROM media m WHERE m.id=s.media_id)`, session.OwnerID).Scan(&reserved); err != nil {
		return err
	}
	bytes := session.SizeBytes + domain.DerivativeBudgetBytes
	if bytes > quota-used-reserved {
		return domain.ErrQuotaExceeded
	}
	payload, err := json.Marshal(session)
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `INSERT INTO upload_sessions(media_id,owner_id,reserved_bytes,session,expires_at) VALUES($1,$2,$3,$4,now()+$5::interval)`, session.MediaID, session.OwnerID, bytes, payload, ttl.String())
	if err != nil {
		return err
	}
	return tx.Commit(ctx)
}
func (s *UploadSessionStore) GetUploadSession(ctx context.Context, id uuid.UUID) (*domain.UploadSession, error) {
	var payload []byte
	err := s.db.QueryRow(ctx, `SELECT session FROM upload_sessions WHERE media_id=$1 AND expires_at>now()`, id).Scan(&payload)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	var session domain.UploadSession
	if err = json.Unmarshal(payload, &session); err != nil {
		return nil, err
	}
	return &session, nil
}
func (s *UploadSessionStore) DeleteUploadSession(ctx context.Context, id uuid.UUID) error {
	_, err := s.db.Exec(ctx, `DELETE FROM upload_sessions WHERE media_id=$1`, id)
	return err
}
