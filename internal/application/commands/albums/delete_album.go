package albums

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type DeleteAlbumCommand struct {
	UserID  uuid.UUID
	AlbumID uuid.UUID
}

type DeleteAlbumHandler struct {
	userRepo  domain.UserRepository
	albumRepo domain.AlbumRepository
}

func NewDeleteAlbumHandler(userRepo domain.UserRepository, albumRepo domain.AlbumRepository) *DeleteAlbumHandler {
	return &DeleteAlbumHandler{
		userRepo:  userRepo,
		albumRepo: albumRepo,
	}
}

func (h *DeleteAlbumHandler) Execute(ctx context.Context, command DeleteAlbumCommand) error {
	if command.AlbumID == uuid.Nil {
		return domain.ErrInvalidInput
	}

	_, album, err := requireManageableAlbum(ctx, h.userRepo, h.albumRepo, command.UserID, command.AlbumID)
	if err != nil {
		return err
	}

	return h.albumRepo.Delete(ctx, album.ID)
}
