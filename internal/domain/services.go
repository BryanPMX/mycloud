package domain

import (
	"context"
	"time"

	"github.com/google/uuid"
)

type SessionStore interface {
	StoreRefreshToken(ctx context.Context, userID uuid.UUID, jti string, ttl time.Duration) error
	ValidateRefreshToken(ctx context.Context, userID uuid.UUID, jti string) (bool, error)
	RevokeRefreshToken(ctx context.Context, userID uuid.UUID, jti string) error
}
