package media

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type ListMediaQuery struct {
	UserID uuid.UUID
	Cursor string
	Limit  int
}

type ListMediaHandler struct {
	userRepo  domain.UserRepository
	mediaRepo domain.MediaRepository
}

func NewListMediaHandler(userRepo domain.UserRepository, mediaRepo domain.MediaRepository) *ListMediaHandler {
	return &ListMediaHandler{
		userRepo:  userRepo,
		mediaRepo: mediaRepo,
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

	return h.mediaRepo.ListVisibleToUser(ctx, query.UserID, domain.ListMediaOptions{
		Cursor: query.Cursor,
		Limit:  query.Limit,
	})
}
