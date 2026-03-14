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

type MediaProgressEventType string

const (
	MediaProgressStarted  MediaProgressEventType = "processing_started"
	MediaProgressComplete MediaProgressEventType = "processing_complete"
	MediaProgressFailed   MediaProgressEventType = "processing_failed"
)

type MediaProgressEvent struct {
	Type       MediaProgressEventType `json:"type"`
	MediaID    uuid.UUID              `json:"media_id"`
	OwnerID    uuid.UUID              `json:"owner_id"`
	Status     string                 `json:"status,omitempty"`
	Reason     string                 `json:"reason,omitempty"`
	ThumbURLs  ThumbKeys              `json:"thumb_urls,omitempty"`
	OccurredOn time.Time              `json:"occurred_on"`
}
