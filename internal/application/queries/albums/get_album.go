package albums

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type GetAlbumQuery struct {
	UserID  uuid.UUID
	AlbumID uuid.UUID
}

type GetAlbumHandler struct {
	userRepo  domain.UserRepository
	albumRepo domain.AlbumRepository
}

func NewGetAlbumHandler(userRepo domain.UserRepository, albumRepo domain.AlbumRepository) *GetAlbumHandler {
	return &GetAlbumHandler{
		userRepo:  userRepo,
		albumRepo: albumRepo,
	}
}

func (h *GetAlbumHandler) Execute(ctx context.Context, query GetAlbumQuery) (*domain.Album, error) {
	if query.AlbumID == uuid.Nil {
		return nil, domain.ErrInvalidInput
	}

	_, album, err := requireReadableAlbum(ctx, h.userRepo, h.albumRepo, query.UserID, query.AlbumID)
	if err != nil {
		return nil, err
	}

	return album, nil
}
