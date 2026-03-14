package media

import (
	"context"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

const (
	DefaultDownloadURLTTL = time.Hour
	MaxDownloadURLTTL     = 24 * time.Hour
)

type GetMediaDownloadURLQuery struct {
	UserID     uuid.UUID
	MediaID    uuid.UUID
	TTLSeconds int
}

type MediaAssetURLResult struct {
	URL       string
	ExpiresAt time.Time
}

type GetMediaDownloadURLHandler struct {
	userRepo  domain.UserRepository
	mediaRepo domain.MediaReadRepository
	storage   domain.MediaAssetReader
}

func NewGetMediaDownloadURLHandler(
	userRepo domain.UserRepository,
	mediaRepo domain.MediaReadRepository,
	storage domain.MediaAssetReader,
) *GetMediaDownloadURLHandler {
	return &GetMediaDownloadURLHandler{
		userRepo:  userRepo,
		mediaRepo: mediaRepo,
		storage:   storage,
	}
}

func (h *GetMediaDownloadURLHandler) Execute(ctx context.Context, query GetMediaDownloadURLQuery) (*MediaAssetURLResult, error) {
	if query.MediaID == uuid.Nil {
		return nil, domain.ErrInvalidInput
	}

	if _, err := requireActiveUser(ctx, h.userRepo, query.UserID); err != nil {
		return nil, err
	}

	ttl, err := normalizeURLTTL(query.TTLSeconds, DefaultDownloadURLTTL, MaxDownloadURLTTL)
	if err != nil {
		return nil, err
	}

	media, err := h.mediaRepo.FindByIDForUser(ctx, query.MediaID, query.UserID)
	if err != nil {
		return nil, err
	}
	if media.Status != domain.MediaStatusReady {
		return nil, domain.ErrConflict
	}

	exists, err := h.storage.OriginalExists(ctx, media.OriginalKey)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, domain.ErrNotFound
	}

	url, err := h.storage.PresignOriginalDownload(ctx, media.OriginalKey, ttl)
	if err != nil {
		return nil, err
	}

	return &MediaAssetURLResult{
		URL:       url,
		ExpiresAt: time.Now().UTC().Add(ttl),
	}, nil
}

func normalizeURLTTL(rawSeconds int, defaultTTL, maxTTL time.Duration) (time.Duration, error) {
	if rawSeconds == 0 {
		return defaultTTL, nil
	}
	if rawSeconds < 0 {
		return 0, domain.ErrInvalidInput
	}

	ttl := time.Duration(rawSeconds) * time.Second
	if ttl <= 0 || ttl > maxTTL {
		return 0, domain.ErrInvalidInput
	}

	return ttl, nil
}
