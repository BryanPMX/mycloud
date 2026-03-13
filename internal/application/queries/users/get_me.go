package users

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type GetMeQuery struct {
	UserID uuid.UUID
}

type GetMeHandler struct {
	userRepo domain.UserRepository
}

func NewGetMeHandler(userRepo domain.UserRepository) *GetMeHandler {
	return &GetMeHandler{userRepo: userRepo}
}

func (h *GetMeHandler) Execute(ctx context.Context, query GetMeQuery) (*domain.User, error) {
	user, err := h.userRepo.FindByID(ctx, query.UserID)
	if err != nil {
		return nil, err
	}
	if !user.Active {
		return nil, domain.ErrUnauthorized
	}

	return user, nil
}
