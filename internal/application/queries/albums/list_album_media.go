package albums

import (
	"context"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type ListAlbumMediaQuery struct {
	UserID  uuid.UUID
	AlbumID uuid.UUID
	Cursor  string
	Limit   int
}

type ListAlbumMediaHandler struct {
	userRepo  domain.UserRepository
	albumRepo domain.AlbumRepository
	mediaRepo domain.MediaRepository
}

func NewListAlbumMediaHandler(
	userRepo domain.UserRepository,
	albumRepo domain.AlbumRepository,
	mediaRepo domain.MediaRepository,
) *ListAlbumMediaHandler {
	return &ListAlbumMediaHandler{
		userRepo:  userRepo,
		albumRepo: albumRepo,
		mediaRepo: mediaRepo,
	}
}

func (h *ListAlbumMediaHandler) Execute(ctx context.Context, query ListAlbumMediaQuery) (domain.MediaPage, error) {
	if query.AlbumID == uuid.Nil {
		return domain.MediaPage{}, domain.ErrInvalidInput
	}

	if _, _, err := requireReadableAlbum(ctx, h.userRepo, h.albumRepo, query.UserID, query.AlbumID); err != nil {
		return domain.MediaPage{}, err
	}

	return h.mediaRepo.ListByAlbum(ctx, query.AlbumID, domain.ListMediaOptions{
		Cursor: query.Cursor,
		Limit:  query.Limit,
	})
}
