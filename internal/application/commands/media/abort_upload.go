package media

import (
	"context"
	"errors"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type AbortUploadCommand struct {
	UserID  uuid.UUID
	MediaID uuid.UUID
}

type AbortUploadHandler struct {
	userRepo    domain.UserRepository
	storage     domain.StorageService
	uploadStore domain.UploadSessionStore
}

func NewAbortUploadHandler(
	userRepo domain.UserRepository,
	storage domain.StorageService,
	uploadStore domain.UploadSessionStore,
) *AbortUploadHandler {
	return &AbortUploadHandler{
		userRepo:    userRepo,
		storage:     storage,
		uploadStore: uploadStore,
	}
}

func (h *AbortUploadHandler) Execute(ctx context.Context, command AbortUploadCommand) error {
	if command.MediaID == uuid.Nil {
		return domain.ErrInvalidInput
	}

	if _, err := requireActiveUser(ctx, h.userRepo, command.UserID); err != nil {
		return err
	}

	session, err := h.uploadStore.GetUploadSession(ctx, command.MediaID)
	if err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			return nil
		}
		return err
	}
	if session.OwnerID != command.UserID {
		return domain.ErrForbidden
	}

	if err := h.storage.AbortUpload(ctx, session.ObjectKey, session.UploadID); err != nil {
		return err
	}
	if err := h.storage.DeleteUpload(ctx, session.ObjectKey); err != nil {
		return err
	}

	return h.uploadStore.DeleteUploadSession(ctx, command.MediaID)
}
