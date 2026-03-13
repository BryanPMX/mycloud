package domain

import (
	"time"

	"github.com/google/uuid"
)

type MediaStatus string

const (
	MediaStatusPending    MediaStatus = "pending"
	MediaStatusProcessing MediaStatus = "processing"
	MediaStatusReady      MediaStatus = "ready"
	MediaStatusFailed     MediaStatus = "failed"
)

type ThumbKeys struct {
	Small  string
	Medium string
	Large  string
	Poster string
}

// Media represents a photo or video stored by the platform.
type Media struct {
	ID           uuid.UUID
	OwnerID      uuid.UUID
	Filename     string
	MimeType     string
	SizeBytes    int64
	Width        int
	Height       int
	DurationSecs float64
	OriginalKey  string
	ThumbKeys    ThumbKeys
	Status       MediaStatus
	TakenAt      *time.Time
	UploadedAt   time.Time
	DeletedAt    *time.Time
	Metadata     map[string]any
}

type ListMediaOptions struct {
	Cursor string
	Limit  int
}

type MediaPage struct {
	Items      []*Media
	NextCursor string
	Total      int
}
