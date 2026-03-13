package domain

import (
	"time"

	"github.com/google/uuid"
)

// Favorite models a user's bookmark of a media item.
type Favorite struct {
	UserID    uuid.UUID
	MediaID   uuid.UUID
	CreatedAt time.Time
}
