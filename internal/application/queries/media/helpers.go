package media

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

func requireActiveUser(ctx context.Context, userRepo domain.UserRepository, userID uuid.UUID) (*domain.User, error) {
	user, err := userRepo.FindByID(ctx, userID)
	if err != nil {
		return nil, err
	}
	if !user.Active {
		return nil, domain.ErrUnauthorized
	}

	return user, nil
}

func markFavorites(ctx context.Context, favoriteRepo domain.FavoriteRepository, userID uuid.UUID, items []*domain.Media) error {
	if len(items) == 0 {
		return nil
	}

	favoriteIDs, err := favoriteRepo.ListMediaIDsByUser(ctx, userID, collectMediaIDs(items))
	if err != nil {
		return err
	}

	favorites := make(map[uuid.UUID]struct{}, len(favoriteIDs))
	for _, favoriteID := range favoriteIDs {
		favorites[favoriteID] = struct{}{}
	}
	for _, item := range items {
		_, item.IsFavorite = favorites[item.ID]
	}

	return nil
}

func collectMediaIDs(items []*domain.Media) []uuid.UUID {
	ids := make([]uuid.UUID, 0, len(items))
	for _, item := range items {
		ids = append(ids, item.ID)
	}

	return ids
}
