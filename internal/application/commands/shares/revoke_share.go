package shares

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type RevokeShareCommand struct {
	UserID  uuid.UUID
	AlbumID uuid.UUID
	ShareID uuid.UUID
}

type RevokeShareHandler struct {
	userRepo  domain.UserRepository
	albumRepo domain.AlbumRepository
	shareRepo domain.ShareRepository
}

func NewRevokeShareHandler(
	userRepo domain.UserRepository,
	albumRepo domain.AlbumRepository,
	shareRepo domain.ShareRepository,
) *RevokeShareHandler {
	return &RevokeShareHandler{
		userRepo:  userRepo,
		albumRepo: albumRepo,
		shareRepo: shareRepo,
	}
}

func (h *RevokeShareHandler) Execute(ctx context.Context, command RevokeShareCommand) error {
	if command.AlbumID == uuid.Nil || command.ShareID == uuid.Nil {
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

	share, err := h.shareRepo.FindByID(ctx, command.ShareID)
	if err != nil {
		return err
	}
	if share.AlbumID != album.ID {
		return domain.ErrNotFound
	}

	return h.shareRepo.Delete(ctx, share.ID)
}
