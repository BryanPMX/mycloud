package admin

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type ListUsersQuery struct {
	UserID uuid.UUID
}

type ListUsersHandler struct {
	userRepo  domain.UserRepository
	adminRepo domain.AdminRepository
}

func NewListUsersHandler(userRepo domain.UserRepository, adminRepo domain.AdminRepository) *ListUsersHandler {
	return &ListUsersHandler{
		userRepo:  userRepo,
		adminRepo: adminRepo,
	}
}

func (h *ListUsersHandler) Execute(ctx context.Context, query ListUsersQuery) ([]*domain.User, error) {
	if _, err := requireActiveAdmin(ctx, h.userRepo, query.UserID); err != nil {
		return nil, err
	}

	return h.adminRepo.ListUsers(ctx)
}
