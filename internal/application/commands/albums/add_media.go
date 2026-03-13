package albums

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type AddMediaCommand struct {
	UserID   uuid.UUID
	AlbumID  uuid.UUID
	MediaIDs []uuid.UUID
}

type AddMediaResult struct {
	Added          int
	AlreadyInAlbum int
}

type AddMediaHandler struct {
	userRepo  domain.UserRepository
	albumRepo domain.AlbumRepository
	mediaRepo domain.MediaRepository
}

func NewAddMediaHandler(
	userRepo domain.UserRepository,
	albumRepo domain.AlbumRepository,
	mediaRepo domain.MediaRepository,
) *AddMediaHandler {
	return &AddMediaHandler{
		userRepo:  userRepo,
		albumRepo: albumRepo,
		mediaRepo: mediaRepo,
	}
}

func (h *AddMediaHandler) Execute(ctx context.Context, command AddMediaCommand) (AddMediaResult, error) {
	if command.AlbumID == uuid.Nil || len(command.MediaIDs) == 0 {
		return AddMediaResult{}, domain.ErrInvalidInput
	}

	user, album, err := requireManageableAlbum(ctx, h.userRepo, h.albumRepo, command.UserID, command.AlbumID)
	if err != nil {
		return AddMediaResult{}, err
	}

	seen := make(map[uuid.UUID]struct{}, len(command.MediaIDs))
	result := AddMediaResult{}
	for _, mediaID := range command.MediaIDs {
		if mediaID == uuid.Nil {
			return AddMediaResult{}, domain.ErrInvalidInput
		}
		if _, ok := seen[mediaID]; ok {
			continue
		}
		seen[mediaID] = struct{}{}

		media, err := h.mediaRepo.FindByID(ctx, mediaID)
		if err != nil {
			return AddMediaResult{}, err
		}
		if media.OwnerID != album.OwnerID {
			return AddMediaResult{}, domain.ErrForbidden
		}

		added, err := h.albumRepo.AddMedia(ctx, album.ID, mediaID, user.ID)
		if err != nil {
			return AddMediaResult{}, err
		}
		if added {
			result.Added++
		} else {
			result.AlreadyInAlbum++
		}
	}

	return result, nil
}
