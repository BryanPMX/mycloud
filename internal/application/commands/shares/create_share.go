package shares

import (
	"context"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type CreateShareCommand struct {
	UserID     uuid.UUID
	AlbumID    uuid.UUID
	SharedWith *uuid.UUID
	Permission string
	ExpiresAt  *time.Time
}

type CreateShareHandler struct {
	userRepo  domain.UserRepository
	albumRepo domain.AlbumRepository
	shareRepo domain.ShareRepository
}

func NewCreateShareHandler(
	userRepo domain.UserRepository,
	albumRepo domain.AlbumRepository,
	shareRepo domain.ShareRepository,
) *CreateShareHandler {
	return &CreateShareHandler{
		userRepo:  userRepo,
		albumRepo: albumRepo,
		shareRepo: shareRepo,
	}
}

func (h *CreateShareHandler) Execute(ctx context.Context, command CreateShareCommand) (*domain.Share, error) {
	if command.AlbumID == uuid.Nil {
		return nil, domain.ErrInvalidInput
	}

	user, err := requireActiveUser(ctx, h.userRepo, command.UserID)
	if err != nil {
		return nil, err
	}

	album, err := h.albumRepo.FindByID(ctx, command.AlbumID)
	if err != nil {
		return nil, err
	}
	if album.OwnerID != user.ID && !user.IsAdmin() {
		return nil, domain.ErrForbidden
	}

	permission := domain.Permission(command.Permission)
	if permission == "" {
		permission = domain.PermissionView
	}
	switch permission {
	case domain.PermissionView, domain.PermissionContribute:
	default:
		return nil, domain.ErrInvalidInput
	}

	sharedWith := uuid.Nil
	var recipient *domain.ShareRecipient
	if command.SharedWith != nil {
		if *command.SharedWith == uuid.Nil || *command.SharedWith == album.OwnerID {
			return nil, domain.ErrInvalidInput
		}

		recipientUser, err := h.userRepo.FindByID(ctx, *command.SharedWith)
		if err != nil {
			return nil, err
		}
		if !recipientUser.Active {
			return nil, domain.ErrInvalidInput
		}

		sharedWith = recipientUser.ID
		recipient = &domain.ShareRecipient{
			ID:          recipientUser.ID,
			DisplayName: recipientUser.DisplayName,
			AvatarKey:   recipientUser.AvatarKey,
		}
	} else {
		recipient = &domain.ShareRecipient{
			ID:          uuid.Nil,
			DisplayName: "Entire family",
		}
	}

	if command.ExpiresAt != nil && !command.ExpiresAt.After(time.Now().UTC()) {
		return nil, domain.ErrInvalidInput
	}

	share := &domain.Share{
		ID:         uuid.New(),
		AlbumID:    album.ID,
		SharedBy:   user.ID,
		SharedWith: sharedWith,
		Recipient:  recipient,
		Permission: permission,
		ExpiresAt:  command.ExpiresAt,
		CreatedAt:  time.Now().UTC(),
	}
	if err := h.shareRepo.Create(ctx, share); err != nil {
		return nil, err
	}

	return share, nil
}
