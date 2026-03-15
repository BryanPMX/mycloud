package users

import (
	"context"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

const (
	DefaultAvatarURLTTL = 5 * time.Minute
	MaxAvatarURLTTL     = time.Hour
)

type GetAvatarURLQuery struct {
	RequestUserID uuid.UUID
	TargetUserID  uuid.UUID
	TTLSeconds    int
}

type AvatarURLResult struct {
	URL       string
	ExpiresAt time.Time
}

type GetAvatarURLHandler struct {
	userRepo domain.UserRepository
	storage  domain.AvatarAssetReader
}

func NewGetAvatarURLHandler(
	userRepo domain.UserRepository,
	storage domain.AvatarAssetReader,
) *GetAvatarURLHandler {
	return &GetAvatarURLHandler{
		userRepo: userRepo,
		storage:  storage,
	}
}

func (h *GetAvatarURLHandler) Execute(ctx context.Context, query GetAvatarURLQuery) (*AvatarURLResult, error) {
	if query.TargetUserID == uuid.Nil {
		return nil, domain.ErrInvalidInput
	}

	if _, err := requireActiveUser(ctx, h.userRepo, query.RequestUserID); err != nil {
		return nil, err
	}

	ttl, err := normalizeAvatarURLTTL(query.TTLSeconds, DefaultAvatarURLTTL, MaxAvatarURLTTL)
	if err != nil {
		return nil, err
	}

	target, err := h.userRepo.FindByID(ctx, query.TargetUserID)
	if err != nil {
		return nil, err
	}
	if !target.Active {
		return nil, domain.ErrNotFound
	}
	if strings.TrimSpace(target.AvatarKey) == "" {
		return nil, domain.ErrNotFound
	}

	url, err := presignAvatarURL(ctx, h.storage, target.AvatarKey, ttl)
	if err != nil {
		return nil, err
	}
	if url == nil {
		return nil, domain.ErrNotFound
	}

	return &AvatarURLResult{
		URL:       *url,
		ExpiresAt: time.Now().UTC().Add(ttl),
	}, nil
}
