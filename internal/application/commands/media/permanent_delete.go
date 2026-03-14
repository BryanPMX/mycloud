package media

import (
	"context"
	"errors"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type PermanentDeleteMediaCommand struct {
	UserID  uuid.UUID
	MediaID uuid.UUID
}

type PermanentDeleteMediaHandler struct {
	userRepo  domain.UserRepository
	mediaRepo domain.MediaTrashRepository
	cleaner   domain.MediaAssetCleaner
}

func NewPermanentDeleteMediaHandler(
	userRepo domain.UserRepository,
	mediaRepo domain.MediaTrashRepository,
	cleaner domain.MediaAssetCleaner,
) *PermanentDeleteMediaHandler {
	return &PermanentDeleteMediaHandler{
		userRepo:  userRepo,
		mediaRepo: mediaRepo,
		cleaner:   cleaner,
	}
}

func (h *PermanentDeleteMediaHandler) Execute(ctx context.Context, command PermanentDeleteMediaCommand) error {
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
		return domain.ErrConflict
	}

	if err := h.mediaRepo.HardDelete(ctx, media.ID); err != nil {
		return err
	}
	if h.cleaner == nil {
		return nil
	}

	return h.cleaner.DeleteMediaAssets(ctx, media)
}

type EmptyTrashCommand struct {
	UserID uuid.UUID
}

type EmptyTrashHandler struct {
	userRepo  domain.UserRepository
	mediaRepo domain.MediaTrashRepository
	cleaner   domain.MediaAssetCleaner
}

func NewEmptyTrashHandler(
	userRepo domain.UserRepository,
	mediaRepo domain.MediaTrashRepository,
	cleaner domain.MediaAssetCleaner,
) *EmptyTrashHandler {
	return &EmptyTrashHandler{
		userRepo:  userRepo,
		mediaRepo: mediaRepo,
		cleaner:   cleaner,
	}
}

func (h *EmptyTrashHandler) Execute(ctx context.Context, command EmptyTrashCommand) error {
	if _, err := requireActiveUser(ctx, h.userRepo, command.UserID); err != nil {
		return err
	}

	deleted, err := h.mediaRepo.HardDeleteAllTrashedOwnedByUser(ctx, command.UserID)
	if err != nil {
		return err
	}
	if h.cleaner == nil {
		return nil
	}

	var cleanupErr error
	for _, media := range deleted {
		if err := h.cleaner.DeleteMediaAssets(ctx, media); err != nil {
			cleanupErr = errors.Join(cleanupErr, err)
		}
	}

	return cleanupErr
}
