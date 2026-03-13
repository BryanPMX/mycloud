package media

import (
	"context"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type PresignUploadPartCommand struct {
	UserID     uuid.UUID
	MediaID    uuid.UUID
	UploadID   string
	PartNumber int
}

type PresignUploadPartResult struct {
	URL       string
	ExpiresAt time.Time
}

type PresignUploadPartHandler struct {
	userRepo    domain.UserRepository
	storage     domain.StorageService
	uploadStore domain.UploadSessionStore
	partURLTTL  time.Duration
}

func NewPresignUploadPartHandler(
	userRepo domain.UserRepository,
	storage domain.StorageService,
	uploadStore domain.UploadSessionStore,
	partURLTTL time.Duration,
) *PresignUploadPartHandler {
	return &PresignUploadPartHandler{
		userRepo:    userRepo,
		storage:     storage,
		uploadStore: uploadStore,
		partURLTTL:  partURLTTL,
	}
}

func (h *PresignUploadPartHandler) Execute(ctx context.Context, command PresignUploadPartCommand) (*PresignUploadPartResult, error) {
	if command.MediaID == uuid.Nil || command.PartNumber <= 0 || command.UploadID == "" {
		return nil, domain.ErrInvalidInput
	}

	if _, err := requireActiveUser(ctx, h.userRepo, command.UserID); err != nil {
		return nil, err
	}

	session, err := h.uploadStore.GetUploadSession(ctx, command.MediaID)
	if err != nil {
		return nil, err
	}
	if session.OwnerID != command.UserID {
		return nil, domain.ErrForbidden
	}
	if session.UploadID != command.UploadID {
		return nil, domain.ErrInvalidInput
	}

	url, err := h.storage.PresignUploadPart(ctx, session.ObjectKey, session.UploadID, command.PartNumber, h.partURLTTL)
	if err != nil {
		return nil, err
	}

	return &PresignUploadPartResult{
		URL:       url,
		ExpiresAt: time.Now().UTC().Add(h.partURLTTL),
	}, nil
}
