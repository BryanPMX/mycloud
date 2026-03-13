package albums

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type fakeMediaRepo struct {
	page domain.MediaPage
}

func (r *fakeMediaRepo) Create(context.Context, *domain.Media) error {
	return nil
}

func (r *fakeMediaRepo) FindByID(context.Context, uuid.UUID) (*domain.Media, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeMediaRepo) FindByIDForUser(context.Context, uuid.UUID, uuid.UUID) (*domain.Media, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeMediaRepo) ListVisibleToUser(context.Context, uuid.UUID, domain.ListMediaOptions) (domain.MediaPage, error) {
	return domain.MediaPage{}, nil
}

func (r *fakeMediaRepo) ListByAlbum(context.Context, uuid.UUID, domain.ListMediaOptions) (domain.MediaPage, error) {
	return r.page, nil
}

func (r *fakeMediaRepo) UpdateStatus(context.Context, uuid.UUID, domain.MediaStatus) error {
	return nil
}

func (r *fakeMediaRepo) ApplyProcessingResult(context.Context, uuid.UUID, domain.MediaProcessingResult) error {
	return nil
}

func TestGetAlbumHandlerExecuteReturnsSharedAlbum(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	sharedAlbum := &domain.Album{ID: uuid.New(), OwnerID: uuid.New(), Name: "Shared trip"}

	handler := NewGetAlbumHandler(&fakeUserRepo{user: user}, &fakeAlbumRepo{
		visibleAlbum: sharedAlbum,
	})

	album, err := handler.Execute(context.Background(), GetAlbumQuery{
		UserID:  user.ID,
		AlbumID: sharedAlbum.ID,
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if album.ID != sharedAlbum.ID {
		t.Fatalf("Execute() album = %#v, want %#v", album, sharedAlbum)
	}
}

func TestListAlbumMediaHandlerExecuteReturnsPageForReadableAlbum(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	album := &domain.Album{ID: uuid.New(), OwnerID: uuid.New()}
	media := &domain.Media{
		ID:         uuid.New(),
		OwnerID:    album.OwnerID,
		Filename:   "IMG_0001.JPG",
		Status:     domain.MediaStatusReady,
		UploadedAt: time.Now().UTC(),
	}
	expectedPage := domain.MediaPage{
		Items:      []*domain.Media{media},
		NextCursor: "cursor-1",
		Total:      1,
	}

	handler := NewListAlbumMediaHandler(
		&fakeUserRepo{user: user},
		&fakeAlbumRepo{visibleAlbum: album},
		&fakeMediaRepo{page: expectedPage},
	)

	page, err := handler.Execute(context.Background(), ListAlbumMediaQuery{
		UserID:  user.ID,
		AlbumID: album.ID,
		Limit:   25,
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if len(page.Items) != 1 || page.Items[0].ID != media.ID || page.NextCursor != expectedPage.NextCursor || page.Total != expectedPage.Total {
		t.Fatalf("Execute() returned unexpected page: %#v", page)
	}
}

func TestListAlbumMediaHandlerExecuteRequiresReadableAlbum(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	albumID := uuid.New()

	handler := NewListAlbumMediaHandler(
		&fakeUserRepo{user: user},
		&fakeAlbumRepo{},
		&fakeMediaRepo{},
	)

	_, err := handler.Execute(context.Background(), ListAlbumMediaQuery{
		UserID:  user.ID,
		AlbumID: albumID,
	})
	if err != domain.ErrNotFound {
		t.Fatalf("Execute() error = %v, want %v", err, domain.ErrNotFound)
	}
}
