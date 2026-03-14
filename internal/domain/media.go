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
	TrashRetentionWindow              = 30 * 24 * time.Hour
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
	IsFavorite   bool
	TakenAt      *time.Time
	UploadedAt   time.Time
	DeletedAt    *time.Time
	Metadata     map[string]any
}

type ListMediaOptions struct {
	Cursor        string
	Limit         int
	FavoritesOnly bool
}

type SearchMediaOptions struct {
	Query  string
	Cursor string
	Limit  int
}

type ListTrashOptions struct {
	Cursor string
	Limit  int
}

type MediaPage struct {
	Items      []*Media
	NextCursor string
	Total      int
}

type CompletedPart struct {
	PartNumber int
	ETag       string
}

type UploadSession struct {
	MediaID   uuid.UUID
	OwnerID   uuid.UUID
	Filename  string
	MimeType  string
	SizeBytes int64
	ObjectKey string
	UploadID  string
	CreatedAt time.Time
}

type MediaProcessingResult struct {
	Width        int
	Height       int
	DurationSecs float64
	TakenAt      *time.Time
	ThumbKeys    ThumbKeys
	Metadata     map[string]any
}

func (m Media) PurgesAt() *time.Time {
	if m.DeletedAt == nil {
		return nil
	}

	value := m.DeletedAt.Add(TrashRetentionWindow)
	return &value
}
