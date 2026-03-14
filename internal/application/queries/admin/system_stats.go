package admin

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type SystemStatsQuery struct {
	UserID uuid.UUID
}

type SystemStatsHandler struct {
	userRepo  domain.UserRepository
	adminRepo domain.AdminRepository
}

func NewSystemStatsHandler(userRepo domain.UserRepository, adminRepo domain.AdminRepository) *SystemStatsHandler {
	return &SystemStatsHandler{
		userRepo:  userRepo,
		adminRepo: adminRepo,
	}
}

func (h *SystemStatsHandler) Execute(ctx context.Context, query SystemStatsQuery) (*domain.SystemStats, error) {
	if _, err := requireActiveAdmin(ctx, h.userRepo, query.UserID); err != nil {
		return nil, err
	}

	return h.adminRepo.GetSystemStats(ctx)
}
