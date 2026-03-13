package domain

import (
	"time"

	"github.com/google/uuid"
)

type Event interface {
	EventName() string
	OccurredAt() time.Time
}

type MediaProcessingRequested struct {
	MediaID   uuid.UUID
	When      time.Time
	OwnerID   uuid.UUID
	ObjectKey string
}

func (e MediaProcessingRequested) EventName() string {
	return "media.processing_requested"
}

func (e MediaProcessingRequested) OccurredAt() time.Time {
	return e.When
}
