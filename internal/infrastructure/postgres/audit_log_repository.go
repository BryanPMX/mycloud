package postgres

import (
	"context"
	"encoding/json"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/yourorg/mycloud/internal/domain"
)

type AuditLogRepository struct {
	db *pgxpool.Pool
}

func NewAuditLogRepository(db *pgxpool.Pool) *AuditLogRepository {
	return &AuditLogRepository{db: db}
}

func (r *AuditLogRepository) Create(ctx context.Context, entry *domain.AuditLog) error {
	payload, err := json.Marshal(entry.Meta)
	if err != nil {
		return err
	}

	var ipAddress any
	if entry.IPAddress != nil {
		ipAddress = entry.IPAddress.String()
	}

	const query = `
		INSERT INTO audit_log (actor_id, action, target_id, meta, ip_address, created_at)
		VALUES ($1, $2, $3, $4, $5, $6)
	`

	_, err = r.db.Exec(ctx, query, entry.ActorID, entry.Action, entry.TargetID, payload, ipAddress, entry.CreatedAt)
	return err
}
