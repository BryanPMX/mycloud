package media

import (
	"context"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

const (
	DefaultThumbURLTTL = 5 * time.Minute
	MaxThumbURLTTL     = time.Hour
)

type GetMediaThumbURLQuery struct {
	UserID     uuid.UUID
	MediaID    uuid.UUID
	Size       string
	TTLSeconds int
}

type GetMediaThumbURLHandler struct {
	userRepo  domain.UserRepository
	mediaRepo domain.MediaReadRepository
	storage   domain.MediaAssetReader
}

func NewGetMediaThumbURLHandler(
	userRepo domain.UserRepository,
	mediaRepo domain.MediaReadRepository,
	storage domain.MediaAssetReader,
) *GetMediaThumbURLHandler {
	return &GetMediaThumbURLHandler{
		userRepo:  userRepo,
		mediaRepo: mediaRepo,
		storage:   storage,
	}
}

func (h *GetMediaThumbURLHandler) Execute(ctx context.Context, query GetMediaThumbURLQuery) (*MediaAssetURLResult, error) {
	if query.MediaID == uuid.Nil {
		return nil, domain.ErrInvalidInput
	}

	if _, err := requireActiveUser(ctx, h.userRepo, query.UserID); err != nil {
		return nil, err
	}

	ttl, err := normalizeURLTTL(query.TTLSeconds, DefaultThumbURLTTL, MaxThumbURLTTL)
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

	key, err := thumbKeyForSize(media, query.Size)
	if err != nil {
		return nil, err
	}

	exists, err := h.storage.ThumbnailExists(ctx, key)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, domain.ErrNotFound
	}

	url, err := h.storage.PresignThumbnail(ctx, key, ttl)
	if err != nil {
		return nil, err
	}

	return &MediaAssetURLResult{
		URL:       url,
		ExpiresAt: time.Now().UTC().Add(ttl),
	}, nil
}

func thumbKeyForSize(media *domain.Media, size string) (string, error) {
	switch strings.ToLower(strings.TrimSpace(size)) {
	case "", "medium":
		if media.ThumbKeys.Medium == "" {
			return "", domain.ErrNotFound
		}
		return media.ThumbKeys.Medium, nil
	case "small":
		if media.ThumbKeys.Small == "" {
			return "", domain.ErrNotFound
		}
		return media.ThumbKeys.Small, nil
	case "large":
		if media.ThumbKeys.Large == "" {
			return "", domain.ErrNotFound
		}
		return media.ThumbKeys.Large, nil
	case "poster":
		if media.ThumbKeys.Poster == "" {
			return "", domain.ErrNotFound
		}
		return media.ThumbKeys.Poster, nil
	default:
		return "", domain.ErrInvalidInput
	}
}
