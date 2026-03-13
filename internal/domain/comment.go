package domain

import (
	"time"

	"github.com/google/uuid"
)

type CommentAuthor struct {
	ID          uuid.UUID
	DisplayName string
	AvatarKey   string
}

// Comment captures discussion attached to a media item.
type Comment struct {
	ID        uuid.UUID
	MediaID   uuid.UUID
	UserID    uuid.UUID
	Author    CommentAuthor
	Body      string
	CreatedAt time.Time
	DeletedAt *time.Time
}
