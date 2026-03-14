package media

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type RestoreMediaCommand struct {
	UserID  uuid.UUID
	MediaID uuid.UUID
}

type RestoreMediaHandler struct {
	userRepo  domain.UserRepository
	mediaRepo domain.MediaTrashRepository
}

func NewRestoreMediaHandler(userRepo domain.UserRepository, mediaRepo domain.MediaTrashRepository) *RestoreMediaHandler {
	return &RestoreMediaHandler{
		userRepo:  userRepo,
		mediaRepo: mediaRepo,
	}
}

func (h *RestoreMediaHandler) Execute(ctx context.Context, command RestoreMediaCommand) error {
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
	if media.DeletedAt == nil {
		return nil
	}

	return h.mediaRepo.Restore(ctx, media.ID)
}
