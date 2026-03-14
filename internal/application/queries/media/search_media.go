package media

import (
	"context"
	"strings"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type SearchMediaQuery struct {
	UserID uuid.UUID
	Query  string
	Cursor string
	Limit  int
}

type SearchMediaHandler struct {
	userRepo     domain.UserRepository
	mediaRepo    domain.MediaReadRepository
	favoriteRepo domain.FavoriteRepository
}

func NewSearchMediaHandler(
	userRepo domain.UserRepository,
	mediaRepo domain.MediaReadRepository,
	favoriteRepo domain.FavoriteRepository,
) *SearchMediaHandler {
	return &SearchMediaHandler{
		userRepo:     userRepo,
		mediaRepo:    mediaRepo,
		favoriteRepo: favoriteRepo,
	}
}

func (h *SearchMediaHandler) Execute(ctx context.Context, query SearchMediaQuery) (domain.MediaPage, error) {
	searchQuery := strings.TrimSpace(query.Query)
	if searchQuery == "" {
		return domain.MediaPage{}, domain.ErrInvalidInput
	}

	if _, err := requireActiveUser(ctx, h.userRepo, query.UserID); err != nil {
		return domain.MediaPage{}, err
	}

	page, err := h.mediaRepo.SearchVisibleToUser(ctx, query.UserID, domain.SearchMediaOptions{
		Query:  searchQuery,
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
