package users

import (
	"bytes"
	"context"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
	pkgmime "github.com/yourorg/mycloud/pkg/mime"
)

const MaxAvatarBytes = 5 * 1024 * 1024

type UpdateProfileCommand struct {
	UserID      uuid.UUID
	DisplayName string
}

type UpdateProfileHandler struct {
	userRepo domain.UserProfileRepository
}

func NewUpdateProfileHandler(userRepo domain.UserProfileRepository) *UpdateProfileHandler {
	return &UpdateProfileHandler{userRepo: userRepo}
}

func (h *UpdateProfileHandler) Execute(ctx context.Context, command UpdateProfileCommand) (*domain.User, error) {
	if command.UserID == uuid.Nil {
		return nil, domain.ErrInvalidInput
	}

	displayName := strings.TrimSpace(command.DisplayName)
	if displayName == "" {
		return nil, domain.ErrInvalidInput
	}

	if _, err := requireActiveUser(ctx, h.userRepo, command.UserID); err != nil {
		return nil, err
	}

	return h.userRepo.UpdateProfile(ctx, command.UserID, displayName)
}

type UpdateAvatarCommand struct {
	UserID   uuid.UUID
	MimeType string
	Content  []byte
}

type UpdateAvatarHandler struct {
	userRepo   domain.UserProfileRepository
	storage    domain.AvatarStorage
	keyBuilder domain.AvatarKeyBuilder
}

func NewUpdateAvatarHandler(
	userRepo domain.UserProfileRepository,
	storage domain.AvatarStorage,
	keyBuilder domain.AvatarKeyBuilder,
) *UpdateAvatarHandler {
	return &UpdateAvatarHandler{
		userRepo:   userRepo,
		storage:    storage,
		keyBuilder: keyBuilder,
	}
}

func (h *UpdateAvatarHandler) Execute(ctx context.Context, command UpdateAvatarCommand) (*domain.User, error) {
	if command.UserID == uuid.Nil {
		return nil, domain.ErrInvalidInput
	}

	mimeType := strings.ToLower(strings.TrimSpace(command.MimeType))
	if !pkgmime.IsAllowedImage(mimeType) {
		return nil, domain.ErrUnsupportedMIME
	}
	if size := len(command.Content); size == 0 || size > MaxAvatarBytes {
		return nil, domain.ErrInvalidInput
	}

	user, err := requireActiveUser(ctx, h.userRepo, command.UserID)
	if err != nil {
		return nil, err
	}

	key := h.keyBuilder.BuildAvatarObjectKey(user.ID, mimeType, time.Now().UTC())
	if err := h.storage.UploadAvatar(ctx, key, mimeType, bytes.NewReader(command.Content), int64(len(command.Content))); err != nil {
		return nil, err
	}

	updatedUser, err := h.userRepo.UpdateAvatarKey(ctx, user.ID, key)
	if err != nil {
		_ = h.storage.DeleteAvatar(ctx, key)
		return nil, err
	}

	if previousKey := strings.TrimSpace(user.AvatarKey); previousKey != "" && previousKey != key {
		_ = h.storage.DeleteAvatar(ctx, previousKey)
	}

	return updatedUser, nil
}

func requireActiveUser(ctx context.Context, userRepo domain.UserProfileRepository, userID uuid.UUID) (*domain.User, error) {
	user, err := userRepo.FindByID(ctx, userID)
	if err != nil {
		return nil, err
	}
	if !user.Active {
		return nil, domain.ErrUnauthorized
	}

	return user, nil
}
