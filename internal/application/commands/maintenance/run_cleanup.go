package maintenance

import (
	"context"
	"errors"
	"time"

	"github.com/yourorg/mycloud/internal/domain"
)

type RunCleanupResult struct {
	PurgedMediaCount  int
	DeletedShareCount int
}

type RunCleanupHandler struct {
	mediaRepo domain.MediaMaintenanceRepository
	shareRepo domain.ShareMaintenanceRepository
	cleaner   domain.MediaAssetCleaner
	now       func() time.Time
}

func NewRunCleanupHandler(
	mediaRepo domain.MediaMaintenanceRepository,
	shareRepo domain.ShareMaintenanceRepository,
	cleaner domain.MediaAssetCleaner,
) *RunCleanupHandler {
	return &RunCleanupHandler{
		mediaRepo: mediaRepo,
		shareRepo: shareRepo,
		cleaner:   cleaner,
		now:       time.Now,
	}
}

func (h *RunCleanupHandler) Execute(ctx context.Context) (*RunCleanupResult, error) {
	if h.mediaRepo == nil || h.shareRepo == nil {
		return nil, domain.ErrInvalidInput
	}

	now := h.now().UTC()
	media, err := h.mediaRepo.DeleteExpiredTrash(ctx, now.Add(-domain.TrashRetentionWindow))
	if err != nil {
		return nil, err
	}

	deletedShares, err := h.shareRepo.DeleteExpired(ctx, now)
	if err != nil {
		return nil, err
	}

	var cleanupErr error
	if h.cleaner != nil {
		for _, item := range media {
			if err := h.cleaner.DeleteMediaAssets(ctx, item); err != nil {
				cleanupErr = errors.Join(cleanupErr, err)
			}
		}
	}
	if cleanupErr != nil {
		return nil, cleanupErr
	}

	return &RunCleanupResult{
		PurgedMediaCount:  len(media),
		DeletedShareCount: deletedShares,
	}, nil
}
