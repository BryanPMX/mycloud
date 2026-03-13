package domain

import (
	"time"

	"github.com/google/uuid"
)

// Comment captures discussion attached to a media item.
type Comment struct {
	ID        uuid.UUID
	MediaID   uuid.UUID
	UserID    uuid.UUID
	Body      string
	CreatedAt time.Time
	DeletedAt *time.Time
}
