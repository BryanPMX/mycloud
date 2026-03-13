package shares

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type ListSharesQuery struct {
	UserID  uuid.UUID
	AlbumID uuid.UUID
}

type ListSharesHandler struct {
	userRepo  domain.UserRepository
	albumRepo domain.AlbumRepository
	shareRepo domain.ShareRepository
}

func NewListSharesHandler(
	userRepo domain.UserRepository,
	albumRepo domain.AlbumRepository,
	shareRepo domain.ShareRepository,
) *ListSharesHandler {
	return &ListSharesHandler{
		userRepo:  userRepo,
		albumRepo: albumRepo,
		shareRepo: shareRepo,
	}
}

func (h *ListSharesHandler) Execute(ctx context.Context, query ListSharesQuery) ([]*domain.Share, error) {
	if query.AlbumID == uuid.Nil {
		return nil, domain.ErrInvalidInput
	}

	user, err := h.userRepo.FindByID(ctx, query.UserID)
	if err != nil {
		return nil, err
	}
	if !user.Active {
		return nil, domain.ErrUnauthorized
	}

	album, err := h.albumRepo.FindByID(ctx, query.AlbumID)
	if err != nil {
		return nil, err
	}
	if album.OwnerID != user.ID && !user.IsAdmin() {
		return nil, domain.ErrForbidden
	}

	return h.shareRepo.ListActiveByAlbum(ctx, album.ID)
}
