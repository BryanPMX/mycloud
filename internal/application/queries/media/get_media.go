package media

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type GetMediaQuery struct {
	UserID  uuid.UUID
	MediaID uuid.UUID
}

type GetMediaResult struct {
	Media *domain.Media
}

type GetMediaHandler struct {
	userRepo     domain.UserRepository
	mediaRepo    domain.MediaReadRepository
	favoriteRepo domain.FavoriteRepository
}

func NewGetMediaHandler(
	userRepo domain.UserRepository,
	mediaRepo domain.MediaReadRepository,
	favoriteRepo domain.FavoriteRepository,
) *GetMediaHandler {
	return &GetMediaHandler{
		userRepo:     userRepo,
		mediaRepo:    mediaRepo,
		favoriteRepo: favoriteRepo,
	}
}

func (h *GetMediaHandler) Execute(ctx context.Context, query GetMediaQuery) (*GetMediaResult, error) {
	if query.MediaID == uuid.Nil {
		return nil, domain.ErrInvalidInput
	}

	if _, err := requireActiveUser(ctx, h.userRepo, query.UserID); err != nil {
		return nil, err
	}

	media, err := h.mediaRepo.FindByIDForUser(ctx, query.MediaID, query.UserID)
	if err != nil {
		return nil, err
	}

	if err := markFavorites(ctx, h.favoriteRepo, query.UserID, []*domain.Media{media}); err != nil {
		return nil, err
	}

	return &GetMediaResult{Media: media}, nil
}
