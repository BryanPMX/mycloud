package comments

import (
	"context"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

const maxCommentLength = 2000

type AddCommentCommand struct {
	UserID  uuid.UUID
	MediaID uuid.UUID
	Body    string
}

type AddCommentHandler struct {
	userRepo    domain.UserRepository
	mediaRepo   domain.MediaRepository
	commentRepo domain.CommentRepository
}

func NewAddCommentHandler(
	userRepo domain.UserRepository,
	mediaRepo domain.MediaRepository,
	commentRepo domain.CommentRepository,
) *AddCommentHandler {
	return &AddCommentHandler{
		userRepo:    userRepo,
		mediaRepo:   mediaRepo,
		commentRepo: commentRepo,
	}
}

func (h *AddCommentHandler) Execute(ctx context.Context, command AddCommentCommand) (*domain.Comment, error) {
	if command.MediaID == uuid.Nil {
		return nil, domain.ErrInvalidInput
	}

	body := strings.TrimSpace(command.Body)
	if body == "" || utf8.RuneCountInString(body) > maxCommentLength {
		return nil, domain.ErrInvalidInput
	}

	user, err := requireActiveUser(ctx, h.userRepo, command.UserID)
	if err != nil {
		return nil, err
	}
	if _, err := h.mediaRepo.FindByIDForUser(ctx, command.MediaID, user.ID); err != nil {
		return nil, err
	}

	comment := &domain.Comment{
		ID:      uuid.New(),
		MediaID: command.MediaID,
		UserID:  user.ID,
		Author: domain.CommentAuthor{
			ID:          user.ID,
			DisplayName: user.DisplayName,
			AvatarKey:   user.AvatarKey,
		},
		Body:      body,
		CreatedAt: time.Now().UTC(),
	}
	if err := h.commentRepo.Create(ctx, comment); err != nil {
		return nil, err
	}

	return comment, nil
}
