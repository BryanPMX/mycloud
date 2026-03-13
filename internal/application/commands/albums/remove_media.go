package albums

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type RemoveMediaCommand struct {
	UserID  uuid.UUID
	AlbumID uuid.UUID
	MediaID uuid.UUID
}

type RemoveMediaHandler struct {
	userRepo  domain.UserRepository
	albumRepo domain.AlbumRepository
}

func NewRemoveMediaHandler(userRepo domain.UserRepository, albumRepo domain.AlbumRepository) *RemoveMediaHandler {
	return &RemoveMediaHandler{
		userRepo:  userRepo,
		albumRepo: albumRepo,
	}
}

func (h *RemoveMediaHandler) Execute(ctx context.Context, command RemoveMediaCommand) error {
	if command.AlbumID == uuid.Nil || command.MediaID == uuid.Nil {
		return domain.ErrInvalidInput
	}

	user, err := requireActiveUser(ctx, h.userRepo, command.UserID)
	if err != nil {
		return err
	}

	album, err := h.albumRepo.FindByID(ctx, command.AlbumID)
	if err != nil {
		return err
	}
	if album.OwnerID != user.ID && !user.IsAdmin() {
		return domain.ErrForbidden
	}

	return h.albumRepo.RemoveMedia(ctx, album.ID, command.MediaID)
}
