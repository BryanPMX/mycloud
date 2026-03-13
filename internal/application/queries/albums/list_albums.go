package albums

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type ListAlbumsQuery struct {
	UserID uuid.UUID
}

type ListAlbumsResult struct {
	Owned        []*domain.Album
	SharedWithMe []*domain.Album
}

type ListAlbumsHandler struct {
	userRepo  domain.UserRepository
	albumRepo domain.AlbumRepository
}

func NewListAlbumsHandler(userRepo domain.UserRepository, albumRepo domain.AlbumRepository) *ListAlbumsHandler {
	return &ListAlbumsHandler{
		userRepo:  userRepo,
		albumRepo: albumRepo,
	}
}

func (h *ListAlbumsHandler) Execute(ctx context.Context, query ListAlbumsQuery) (ListAlbumsResult, error) {
	_, err := requireActiveUser(ctx, h.userRepo, query.UserID)
	if err != nil {
		return ListAlbumsResult{}, err
	}

	owned, err := h.albumRepo.ListOwnedByUser(ctx, query.UserID)
	if err != nil {
		return ListAlbumsResult{}, err
	}

	shared, err := h.albumRepo.ListSharedWithUser(ctx, query.UserID)
	if err != nil {
		return ListAlbumsResult{}, err
	}

	return ListAlbumsResult{
		Owned:        owned,
		SharedWithMe: shared,
	}, nil
}
