package albums

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

func requireReadableAlbum(
	ctx context.Context,
	userRepo domain.UserRepository,
	albumRepo domain.AlbumRepository,
	userID, albumID uuid.UUID,
) (*domain.User, *domain.Album, error) {
	user, err := requireActiveUser(ctx, userRepo, userID)
	if err != nil {
		return nil, nil, err
	}

	if user.IsAdmin() {
		album, err := albumRepo.FindByID(ctx, albumID)
		if err != nil {
			return nil, nil, err
		}

		return user, album, nil
	}

	album, err := albumRepo.FindByIDVisibleToUser(ctx, albumID, userID)
	if err != nil {
		return nil, nil, err
	}

	return user, album, nil
}
