package comments

import (
	"context"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type DeleteCommentCommand struct {
	UserID    uuid.UUID
	MediaID   uuid.UUID
	CommentID uuid.UUID
}

type DeleteCommentHandler struct {
	userRepo    domain.UserRepository
	commentRepo domain.CommentRepository
}

func NewDeleteCommentHandler(
	userRepo domain.UserRepository,
	commentRepo domain.CommentRepository,
) *DeleteCommentHandler {
	return &DeleteCommentHandler{
		userRepo:    userRepo,
		commentRepo: commentRepo,
	}
}

func (h *DeleteCommentHandler) Execute(ctx context.Context, command DeleteCommentCommand) error {
	if command.MediaID == uuid.Nil || command.CommentID == uuid.Nil {
		return domain.ErrInvalidInput
	}

	user, err := requireActiveUser(ctx, h.userRepo, command.UserID)
	if err != nil {
		return err
	}

	comment, err := h.commentRepo.FindByID(ctx, command.CommentID)
	if err != nil {
		return err
	}
	if comment.MediaID != command.MediaID {
		return domain.ErrNotFound
	}
	if !user.IsAdmin() && comment.UserID != user.ID {
		return domain.ErrForbidden
	}

	return h.commentRepo.SoftDelete(ctx, comment.ID, time.Now().UTC())
}
