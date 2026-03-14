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
	user, err := h.userRepo.FindByID(ctx, query.UserID)
	if err != nil {
		return domain.MediaPage{}, err
	}
	if !user.Active {
		return domain.MediaPage{}, domain.ErrUnauthorized
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

	favoriteIDs, err := h.favoriteRepo.ListMediaIDsByUser(ctx, query.UserID, collectMediaIDs(page.Items))
	if err != nil {
		return domain.MediaPage{}, err
	}

	favorites := make(map[uuid.UUID]struct{}, len(favoriteIDs))
	for _, favoriteID := range favoriteIDs {
		favorites[favoriteID] = struct{}{}
	}
	for _, item := range page.Items {
		_, item.IsFavorite = favorites[item.ID]
	}

	return page, nil
}

func collectMediaIDs(items []*domain.Media) []uuid.UUID {
	ids := make([]uuid.UUID, 0, len(items))
	for _, item := range items {
		ids = append(ids, item.ID)
	}

	return ids
}
