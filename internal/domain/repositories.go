package domain

import (
	"context"
	"time"

	"github.com/google/uuid"
)

type UserRepository interface {
	FindByID(ctx context.Context, id uuid.UUID) (*User, error)
	FindByEmail(ctx context.Context, email string) (*User, error)
	UpdateLastLogin(ctx context.Context, id uuid.UUID, lastLoginAt time.Time) error
}

type MediaRepository interface {
	Create(ctx context.Context, media *Media) error
	FindByIDForUser(ctx context.Context, id, userID uuid.UUID) (*Media, error)
	ListVisibleToUser(ctx context.Context, userID uuid.UUID, opts ListMediaOptions) (MediaPage, error)
}
