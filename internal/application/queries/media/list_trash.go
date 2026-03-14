package media

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type ListTrashQuery struct {
	UserID uuid.UUID
	Cursor string
	Limit  int
}

type ListTrashHandler struct {
	userRepo     domain.UserRepository
	mediaRepo    domain.MediaTrashRepository
	favoriteRepo domain.FavoriteRepository
}

func NewListTrashHandler(
	userRepo domain.UserRepository,
	mediaRepo domain.MediaTrashRepository,
	favoriteRepo domain.FavoriteRepository,
) *ListTrashHandler {
	return &ListTrashHandler{
		userRepo:     userRepo,
		mediaRepo:    mediaRepo,
		favoriteRepo: favoriteRepo,
	}
}

func (h *ListTrashHandler) Execute(ctx context.Context, query ListTrashQuery) (domain.MediaPage, error) {
	if _, err := requireActiveUser(ctx, h.userRepo, query.UserID); err != nil {
		return domain.MediaPage{}, err
	}

	page, err := h.mediaRepo.ListTrashedOwnedByUser(ctx, query.UserID, domain.ListTrashOptions{
		Cursor: query.Cursor,
		Limit:  query.Limit,
	})
	if err != nil {
		return domain.MediaPage{}, err
	}

	if err := markFavorites(ctx, h.favoriteRepo, query.UserID, page.Items); err != nil {
		return domain.MediaPage{}, err
	}

	return page, nil
}
