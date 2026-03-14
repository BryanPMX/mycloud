package media

import (
	"context"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type DeleteMediaCommand struct {
	UserID  uuid.UUID
	MediaID uuid.UUID
}

type DeleteMediaHandler struct {
	userRepo  domain.UserRepository
	mediaRepo domain.MediaTrashRepository
}

func NewDeleteMediaHandler(userRepo domain.UserRepository, mediaRepo domain.MediaTrashRepository) *DeleteMediaHandler {
	return &DeleteMediaHandler{
		userRepo:  userRepo,
		mediaRepo: mediaRepo,
	}
}

func (h *DeleteMediaHandler) Execute(ctx context.Context, command DeleteMediaCommand) error {
	if command.MediaID == uuid.Nil {
		return domain.ErrInvalidInput
	}

	user, err := requireActiveUser(ctx, h.userRepo, command.UserID)
	if err != nil {
		return err
	}

	media, err := loadOwnedOrAdminMedia(ctx, h.mediaRepo, user, command.MediaID)
	if err != nil {
		return err
	}
	if media.DeletedAt != nil {
		return nil
	}

	return h.mediaRepo.SoftDelete(ctx, media.ID, time.Now().UTC())
}
