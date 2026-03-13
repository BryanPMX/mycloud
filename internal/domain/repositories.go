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
	FindByID(ctx context.Context, id uuid.UUID) (*Media, error)
	FindByIDForUser(ctx context.Context, id, userID uuid.UUID) (*Media, error)
	ListVisibleToUser(ctx context.Context, userID uuid.UUID, opts ListMediaOptions) (MediaPage, error)
	UpdateStatus(ctx context.Context, id uuid.UUID, status MediaStatus) error
	ApplyProcessingResult(ctx context.Context, id uuid.UUID, result MediaProcessingResult) error
}

type AlbumRepository interface {
	Create(ctx context.Context, album *Album) error
	FindByID(ctx context.Context, id uuid.UUID) (*Album, error)
	ListOwnedByUser(ctx context.Context, userID uuid.UUID) ([]*Album, error)
	ListSharedWithUser(ctx context.Context, userID uuid.UUID) ([]*Album, error)
	AddMedia(ctx context.Context, albumID, mediaID, addedBy uuid.UUID) (bool, error)
	RemoveMedia(ctx context.Context, albumID, mediaID uuid.UUID) error
}

type ShareRepository interface {
	Create(ctx context.Context, share *Share) error
	FindByID(ctx context.Context, id uuid.UUID) (*Share, error)
	ListActiveByAlbum(ctx context.Context, albumID uuid.UUID) ([]*Share, error)
	Delete(ctx context.Context, id uuid.UUID) error
}

type CommentRepository interface {
	Create(ctx context.Context, comment *Comment) error
	FindByID(ctx context.Context, id uuid.UUID) (*Comment, error)
	ListByMedia(ctx context.Context, mediaID uuid.UUID) ([]*Comment, error)
	SoftDelete(ctx context.Context, id uuid.UUID, deletedAt time.Time) error
}

type JobRepository interface {
	Create(ctx context.Context, job *Job) error
	FindByID(ctx context.Context, id uuid.UUID) (*Job, error)
	FindLatestByMediaAndType(ctx context.Context, mediaID uuid.UUID, jobType JobType) (*Job, error)
	MarkRunning(ctx context.Context, id uuid.UUID, startedAt time.Time) error
	MarkDone(ctx context.Context, id uuid.UUID, completedAt time.Time) error
	MarkFailed(ctx context.Context, id uuid.UUID, message string, completedAt time.Time) error
}
