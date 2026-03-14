package admin

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

func requireActiveAdmin(ctx context.Context, userRepo domain.UserRepository, userID uuid.UUID) (*domain.User, error) {
	user, err := userRepo.FindByID(ctx, userID)
	if err != nil {
		return nil, err
	}
	if !user.Active {
		return nil, domain.ErrUnauthorized
	}
	if !user.IsAdmin() {
		return nil, domain.ErrForbidden
	}

	return user, nil
}
