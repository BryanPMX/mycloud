package users

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type ListDirectoryQuery struct {
	UserID uuid.UUID
}

type ListDirectoryEntry struct {
	ID          uuid.UUID
	DisplayName string
	AvatarURL   *string
}

type ListDirectoryHandler struct {
	userRepo domain.UserDirectoryRepository
	storage  domain.AvatarAssetReader
}

func NewListDirectoryHandler(
	userRepo domain.UserDirectoryRepository,
	storage domain.AvatarAssetReader,
) *ListDirectoryHandler {
	return &ListDirectoryHandler{
		userRepo: userRepo,
		storage:  storage,
	}
}

func (h *ListDirectoryHandler) Execute(ctx context.Context, query ListDirectoryQuery) ([]ListDirectoryEntry, error) {
	if _, err := requireActiveUser(ctx, h.userRepo, query.UserID); err != nil {
		return nil, err
	}

	users, err := h.userRepo.ListActiveUsers(ctx)
	if err != nil {
		return nil, err
	}

	items := make([]ListDirectoryEntry, 0, len(users))
	for _, user := range users {
		avatarURL, err := presignAvatarURL(ctx, h.storage, user.AvatarKey, DefaultAvatarURLTTL)
		if err != nil {
			return nil, err
		}

		items = append(items, ListDirectoryEntry{
			ID:          user.ID,
			DisplayName: user.DisplayName,
			AvatarURL:   avatarURL,
		})
	}

	return items, nil
}
