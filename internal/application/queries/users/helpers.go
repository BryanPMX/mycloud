package users

import (
	"context"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

func requireActiveUser(ctx context.Context, userRepo interface {
	FindByID(ctx context.Context, id uuid.UUID) (*domain.User, error)
}, userID uuid.UUID) (*domain.User, error) {
	user, err := userRepo.FindByID(ctx, userID)
	if err != nil {
		return nil, err
	}
	if !user.Active {
		return nil, domain.ErrUnauthorized
	}

	return user, nil
}

func normalizeAvatarURLTTL(rawSeconds int, defaultTTL, maxTTL time.Duration) (time.Duration, error) {
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

func presignAvatarURL(
	ctx context.Context,
	storage domain.AvatarAssetReader,
	avatarKey string,
	ttl time.Duration,
) (*string, error) {
	key := strings.TrimSpace(avatarKey)
	if key == "" {
		return nil, nil
	}

	exists, err := storage.AvatarExists(ctx, key)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, nil
	}

	url, err := storage.PresignAvatar(ctx, key, ttl)
	if err != nil {
		return nil, err
	}

	return &url, nil
}
