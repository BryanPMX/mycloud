package domain

import (
	"time"

	"github.com/google/uuid"
)

// Album groups media for organization and sharing.
type Album struct {
	ID           uuid.UUID
	OwnerID      uuid.UUID
	Name         string
	Description  string
	CoverMediaID *uuid.UUID
	MediaCount   int
	CreatedAt    time.Time
	UpdatedAt    time.Time
}
