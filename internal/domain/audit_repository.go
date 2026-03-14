package domain

import "context"

type AuditLogRepository interface {
	Create(ctx context.Context, entry *AuditLog) error
}
