package media

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type ListMediaQuery struct {
	UserID        uuid.UUID
	Cursor        string
	Limit         int
	FavoritesOnly bool
}

type ListMediaHandler struct {
	userRepo     domain.UserRepository
	mediaRepo    domain.MediaRepository
	favoriteRepo domain.FavoriteRepository
}

func NewListMediaHandler(
	userRepo domain.UserRepository,
	mediaRepo domain.MediaRepository,
	favoriteRepo domain.FavoriteRepository,
) *ListMediaHandler {
	return &ListMediaHandler{
		userRepo:     userRepo,
		mediaRepo:    mediaRepo,
		favoriteRepo: favoriteRepo,
	}
}

func (h *ListMediaHandler) Execute(ctx context.Context, query ListMediaQuery) (domain.MediaPage, error) {
	if _, err := requireActiveUser(ctx, h.userRepo, query.UserID); err != nil {
		return domain.MediaPage{}, err
	}

	page, err := h.mediaRepo.ListVisibleToUser(ctx, query.UserID, domain.ListMediaOptions{
		Cursor:        query.Cursor,
		Limit:         query.Limit,
		FavoritesOnly: query.FavoritesOnly,
	})
	if err != nil {
		return domain.MediaPage{}, err
	}

	if query.FavoritesOnly {
		for _, item := range page.Items {
			item.IsFavorite = true
		}
		return page, nil
	}

	if err := markFavorites(ctx, h.favoriteRepo, query.UserID, page.Items); err != nil {
		return domain.MediaPage{}, err
	}

	return page, nil
}
