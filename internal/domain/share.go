package domain

import (
	"time"

	"github.com/google/uuid"
)

type Permission string

const (
	PermissionView       Permission = "view"
	PermissionContribute Permission = "contribute"
)

// Share grants album access to another user or the whole family.
type Share struct {
	ID         uuid.UUID
	AlbumID    uuid.UUID
	SharedBy   uuid.UUID
	SharedWith uuid.UUID
	Permission Permission
	ExpiresAt  *time.Time
	CreatedAt  time.Time
}
