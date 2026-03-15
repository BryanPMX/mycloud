package domain

import (
	"context"
	"io"
	"time"

	"github.com/google/uuid"
)

type SessionStore interface {
	StoreRefreshToken(ctx context.Context, userID uuid.UUID, jti string, ttl time.Duration) error
	ValidateRefreshToken(ctx context.Context, userID uuid.UUID, jti string) (bool, error)
	RevokeRefreshToken(ctx context.Context, userID uuid.UUID, jti string) error
	RevokeAllForUser(ctx context.Context, userID uuid.UUID) error
}

type StorageService interface {
	InitiateUpload(ctx context.Context, key, mimeType string) (string, error)
	PresignUploadPart(ctx context.Context, key, uploadID string, partNum int, ttl time.Duration) (string, error)
	CompleteUpload(ctx context.Context, key, uploadID string, parts []CompletedPart) error
	AbortUpload(ctx context.Context, key, uploadID string) error
	UploadExists(ctx context.Context, key string) (bool, error)
	DeleteUpload(ctx context.Context, key string) error
	OpenUpload(ctx context.Context, key string) (io.ReadCloser, error)
	PromoteUpload(ctx context.Context, key string) error
}

type MediaProcessingStorage interface {
	OpenOriginal(ctx context.Context, key string) (io.ReadCloser, error)
	UploadThumbnail(ctx context.Context, key, mimeType string, body io.Reader, size int64) error
}

type AvatarStorage interface {
	UploadAvatar(ctx context.Context, key, mimeType string, body io.Reader, size int64) error
	DeleteAvatar(ctx context.Context, key string) error
}

type AvatarAssetReader interface {
	PresignAvatar(ctx context.Context, key string, ttl time.Duration) (string, error)
	AvatarExists(ctx context.Context, key string) (bool, error)
}

type MediaAssetReader interface {
	PresignOriginalDownload(ctx context.Context, key string, ttl time.Duration) (string, error)
	PresignThumbnail(ctx context.Context, key string, ttl time.Duration) (string, error)
	OriginalExists(ctx context.Context, key string) (bool, error)
	ThumbnailExists(ctx context.Context, key string) (bool, error)
}

type MediaAssetCleaner interface {
	DeleteMediaAssets(ctx context.Context, media *Media) error
}

type UploadSessionStore interface {
	SaveUploadSession(ctx context.Context, session UploadSession, ttl time.Duration) error
	GetUploadSession(ctx context.Context, mediaID uuid.UUID) (*UploadSession, error)
	DeleteUploadSession(ctx context.Context, mediaID uuid.UUID) error
}

type MediaKeyBuilder interface {
	BuildMediaObjectKey(ownerID, mediaID uuid.UUID, filename, mimeType string, now time.Time) string
	BuildThumbKeys(mediaID uuid.UUID, mimeType string) ThumbKeys
}

type AvatarKeyBuilder interface {
	BuildAvatarObjectKey(userID uuid.UUID, mimeType string, now time.Time) string
}

type JobQueue interface {
	Enqueue(ctx context.Context, job *Job) error
	Dequeue(ctx context.Context, timeout time.Duration) (*Job, error)
}

type VirusScanner interface {
	ScanReader(ctx context.Context, r io.Reader) (clean bool, threat string, err error)
}

type MediaProcessor interface {
	Process(ctx context.Context, media *Media) (MediaProcessingResult, error)
}

type MediaProgressPublisher interface {
	PublishMediaProgress(ctx context.Context, event MediaProgressEvent) error
}

type MediaProgressSubscriber interface {
	SubscribeMediaProgress(ctx context.Context, handler func(MediaProgressEvent)) error
}

type InviteEmail struct {
	AppName     string
	To          string
	DisplayName string
	InviteURL   string
	ExpiresAt   time.Time
}

type InviteEmailSender interface {
	SendInviteEmail(ctx context.Context, invite InviteEmail) error
}
