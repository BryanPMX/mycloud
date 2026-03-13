package media

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type CompleteUploadCommand struct {
	UserID   uuid.UUID
	MediaID  uuid.UUID
	UploadID string
	Parts    []domain.CompletedPart
}

type CompleteUploadResult struct {
	Media *domain.Media
}

type CompleteUploadHandler struct {
	userRepo    domain.UserRepository
	mediaRepo   domain.MediaRepository
	storage     domain.StorageService
	uploadStore domain.UploadSessionStore
}

func NewCompleteUploadHandler(
	userRepo domain.UserRepository,
	mediaRepo domain.MediaRepository,
	storage domain.StorageService,
	uploadStore domain.UploadSessionStore,
) *CompleteUploadHandler {
	return &CompleteUploadHandler{
		userRepo:    userRepo,
		mediaRepo:   mediaRepo,
		storage:     storage,
		uploadStore: uploadStore,
	}
}

func (h *CompleteUploadHandler) Execute(ctx context.Context, command CompleteUploadCommand) (*CompleteUploadResult, error) {
	if command.MediaID == uuid.Nil || command.UploadID == "" {
		return nil, domain.ErrInvalidInput
	}

	if _, err := requireActiveUser(ctx, h.userRepo, command.UserID); err != nil {
		return nil, err
	}

	parts, err := normalizeCompletedParts(command.Parts)
	if err != nil {
		return nil, err
	}

	session, err := h.uploadStore.GetUploadSession(ctx, command.MediaID)
	if err != nil {
		if !errors.Is(err, domain.ErrNotFound) {
			return nil, err
		}

		media, findErr := h.mediaRepo.FindByIDForUser(ctx, command.MediaID, command.UserID)
		if findErr != nil {
			return nil, findErr
		}

		return &CompleteUploadResult{Media: media}, nil
	}
	if session.OwnerID != command.UserID {
		return nil, domain.ErrForbidden
	}
	if session.UploadID != command.UploadID {
		return nil, domain.ErrInvalidInput
	}

	if err := h.storage.CompleteUpload(ctx, session.ObjectKey, session.UploadID, parts); err != nil {
		exists, existsErr := h.storage.UploadExists(ctx, session.ObjectKey)
		if existsErr != nil {
			return nil, existsErr
		}
		if !exists {
			return nil, err
		}
	}

	media := &domain.Media{
		ID:          session.MediaID,
		OwnerID:     session.OwnerID,
		Filename:    session.Filename,
		MimeType:    session.MimeType,
		SizeBytes:   session.SizeBytes,
		OriginalKey: session.ObjectKey,
		Status:      domain.MediaStatusPending,
		UploadedAt:  time.Now().UTC(),
		Metadata:    map[string]any{},
	}
	if err := h.mediaRepo.Create(ctx, media); err != nil {
		if !errors.Is(err, domain.ErrConflict) {
			return nil, err
		}

		existing, findErr := h.mediaRepo.FindByIDForUser(ctx, session.MediaID, command.UserID)
		if findErr != nil {
			return nil, findErr
		}

		media = existing
	}

	_ = h.uploadStore.DeleteUploadSession(ctx, session.MediaID)

	return &CompleteUploadResult{Media: media}, nil
}
