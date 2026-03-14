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

type UserProfileRepository interface {
	FindByID(ctx context.Context, id uuid.UUID) (*User, error)
	UpdateProfile(ctx context.Context, id uuid.UUID, displayName string) (*User, error)
	UpdateAvatarKey(ctx context.Context, id uuid.UUID, avatarKey string) (*User, error)
}

type AdminRepository interface {
	ListUsers(ctx context.Context) ([]*User, error)
	CreateOrRefreshInvite(ctx context.Context, params InviteUserParams, audit *AuditLog) (*User, error)
	FindInviteByTokenHash(ctx context.Context, tokenHash string) (*User, error)
	AcceptInvite(ctx context.Context, params AcceptInviteParams, audit *AuditLog) (*User, error)
	UpdateUser(ctx context.Context, params AdminUpdateUserParams, audit *AuditLog) (*User, error)
	GetSystemStats(ctx context.Context) (*SystemStats, error)
}

type MediaRepository interface {
	Create(ctx context.Context, media *Media) error
	FindByID(ctx context.Context, id uuid.UUID) (*Media, error)
	FindByIDForUser(ctx context.Context, id, userID uuid.UUID) (*Media, error)
	ListVisibleToUser(ctx context.Context, userID uuid.UUID, opts ListMediaOptions) (MediaPage, error)
	ListByAlbum(ctx context.Context, albumID uuid.UUID, opts ListMediaOptions) (MediaPage, error)
	UpdateStatus(ctx context.Context, id uuid.UUID, status MediaStatus) error
	ApplyProcessingResult(ctx context.Context, id uuid.UUID, result MediaProcessingResult) error
}

type MediaReadRepository interface {
	FindByIDForUser(ctx context.Context, id, userID uuid.UUID) (*Media, error)
	SearchVisibleToUser(ctx context.Context, userID uuid.UUID, opts SearchMediaOptions) (MediaPage, error)
}

type MediaTrashRepository interface {
	FindByIDIncludingDeleted(ctx context.Context, id uuid.UUID) (*Media, error)
	FindOwnedByUserIncludingDeleted(ctx context.Context, id, userID uuid.UUID) (*Media, error)
	ListTrashedOwnedByUser(ctx context.Context, userID uuid.UUID, opts ListTrashOptions) (MediaPage, error)
	SoftDelete(ctx context.Context, id uuid.UUID, deletedAt time.Time) error
	Restore(ctx context.Context, id uuid.UUID) error
	HardDelete(ctx context.Context, id uuid.UUID) error
	HardDeleteAllTrashedOwnedByUser(ctx context.Context, ownerID uuid.UUID) ([]*Media, error)
}

type AlbumRepository interface {
	Create(ctx context.Context, album *Album) error
	FindByID(ctx context.Context, id uuid.UUID) (*Album, error)
	FindByIDVisibleToUser(ctx context.Context, id, userID uuid.UUID) (*Album, error)
	ListOwnedByUser(ctx context.Context, userID uuid.UUID) ([]*Album, error)
	ListSharedWithUser(ctx context.Context, userID uuid.UUID) ([]*Album, error)
	Update(ctx context.Context, album *Album) error
	Delete(ctx context.Context, id uuid.UUID) error
	HasMedia(ctx context.Context, albumID, mediaID uuid.UUID) (bool, error)
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

type FavoriteRepository interface {
	Create(ctx context.Context, favorite *Favorite) error
	Delete(ctx context.Context, userID, mediaID uuid.UUID) error
	ListMediaIDsByUser(ctx context.Context, userID uuid.UUID, mediaIDs []uuid.UUID) ([]uuid.UUID, error)
}

type JobRepository interface {
	Create(ctx context.Context, job *Job) error
	FindByID(ctx context.Context, id uuid.UUID) (*Job, error)
	FindLatestByMediaAndType(ctx context.Context, mediaID uuid.UUID, jobType JobType) (*Job, error)
	MarkRunning(ctx context.Context, id uuid.UUID, startedAt time.Time) error
	MarkDone(ctx context.Context, id uuid.UUID, completedAt time.Time) error
	MarkFailed(ctx context.Context, id uuid.UUID, message string, completedAt time.Time) error
}
