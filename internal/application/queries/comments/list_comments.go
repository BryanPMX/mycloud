package comments

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type ListCommentsQuery struct {
	UserID  uuid.UUID
	MediaID uuid.UUID
}

type ListCommentsHandler struct {
	userRepo    domain.UserRepository
	mediaRepo   domain.MediaRepository
	commentRepo domain.CommentRepository
}

func NewListCommentsHandler(
	userRepo domain.UserRepository,
	mediaRepo domain.MediaRepository,
	commentRepo domain.CommentRepository,
) *ListCommentsHandler {
	return &ListCommentsHandler{
		userRepo:    userRepo,
		mediaRepo:   mediaRepo,
		commentRepo: commentRepo,
	}
}

func (h *ListCommentsHandler) Execute(ctx context.Context, query ListCommentsQuery) ([]*domain.Comment, error) {
	if query.MediaID == uuid.Nil {
		return nil, domain.ErrInvalidInput
	}

	user, err := h.userRepo.FindByID(ctx, query.UserID)
	if err != nil {
		return nil, err
	}
	if !user.Active {
		return nil, domain.ErrUnauthorized
	}

	if _, err := h.mediaRepo.FindByIDForUser(ctx, query.MediaID, query.UserID); err != nil {
		return nil, err
	}

	return h.commentRepo.ListByMedia(ctx, query.MediaID)
}
