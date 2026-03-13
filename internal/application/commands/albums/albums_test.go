package albums

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type fakeUserRepo struct {
	user *domain.User
}

func (r *fakeUserRepo) FindByID(context.Context, uuid.UUID) (*domain.User, error) {
	if r.user == nil {
		return nil, domain.ErrNotFound
	}

	return r.user, nil
}

func (r *fakeUserRepo) FindByEmail(context.Context, string) (*domain.User, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeUserRepo) UpdateLastLogin(context.Context, uuid.UUID, time.Time) error {
	return nil
}

type fakeAlbumRepo struct {
	album         *domain.Album
	created       *domain.Album
	addedResults  map[uuid.UUID]bool
	addedMediaIDs []uuid.UUID
	removedMedia  uuid.UUID
}

func (r *fakeAlbumRepo) Create(_ context.Context, album *domain.Album) error {
	copied := *album
	r.created = &copied
	r.album = &copied
	return nil
}

func (r *fakeAlbumRepo) FindByID(context.Context, uuid.UUID) (*domain.Album, error) {
	if r.album == nil {
		return nil, domain.ErrNotFound
	}

	return r.album, nil
}

func (r *fakeAlbumRepo) ListOwnedByUser(context.Context, uuid.UUID) ([]*domain.Album, error) {
	return nil, nil
}

func (r *fakeAlbumRepo) ListSharedWithUser(context.Context, uuid.UUID) ([]*domain.Album, error) {
	return nil, nil
}

func (r *fakeAlbumRepo) AddMedia(_ context.Context, _ uuid.UUID, mediaID, _ uuid.UUID) (bool, error) {
	r.addedMediaIDs = append(r.addedMediaIDs, mediaID)
	return r.addedResults[mediaID], nil
}

func (r *fakeAlbumRepo) RemoveMedia(context.Context, uuid.UUID, uuid.UUID) error {
	return nil
}

type fakeMediaRepo struct {
	media map[uuid.UUID]*domain.Media
}

func (r *fakeMediaRepo) Create(context.Context, *domain.Media) error {
	return nil
}

func (r *fakeMediaRepo) FindByID(_ context.Context, id uuid.UUID) (*domain.Media, error) {
	media, ok := r.media[id]
	if !ok {
		return nil, domain.ErrNotFound
	}

	return media, nil
}

func (r *fakeMediaRepo) FindByIDForUser(context.Context, uuid.UUID, uuid.UUID) (*domain.Media, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeMediaRepo) ListVisibleToUser(context.Context, uuid.UUID, domain.ListMediaOptions) (domain.MediaPage, error) {
	return domain.MediaPage{}, nil
}

func (r *fakeMediaRepo) UpdateStatus(context.Context, uuid.UUID, domain.MediaStatus) error {
	return nil
}

func (r *fakeMediaRepo) ApplyProcessingResult(context.Context, uuid.UUID, domain.MediaProcessingResult) error {
	return nil
}

func TestCreateAlbumHandlerExecuteCreatesTrimmedAlbum(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	albumRepo := &fakeAlbumRepo{}
	handler := NewCreateAlbumHandler(&fakeUserRepo{user: user}, albumRepo)

	album, err := handler.Execute(context.Background(), CreateAlbumCommand{
		UserID:      user.ID,
		Name:        "  Summer 2026  ",
		Description: "  Cabin trip  ",
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if album.Name != "Summer 2026" || album.Description != "Cabin trip" {
		t.Fatalf("Execute() returned unexpected album: %#v", album)
	}
	if albumRepo.created == nil || albumRepo.created.OwnerID != user.ID {
		t.Fatal("Execute() did not persist the album with the acting owner")
	}
}

func TestAddMediaHandlerExecuteCountsAddedAndExisting(t *testing.T) {
	t.Parallel()

	ownerID := uuid.New()
	albumID := uuid.New()
	firstMediaID := uuid.New()
	secondMediaID := uuid.New()

	handler := NewAddMediaHandler(
		&fakeUserRepo{user: &domain.User{ID: ownerID, Active: true}},
		&fakeAlbumRepo{
			album: &domain.Album{ID: albumID, OwnerID: ownerID},
			addedResults: map[uuid.UUID]bool{
				firstMediaID:  true,
				secondMediaID: false,
			},
		},
		&fakeMediaRepo{
			media: map[uuid.UUID]*domain.Media{
				firstMediaID:  {ID: firstMediaID, OwnerID: ownerID},
				secondMediaID: {ID: secondMediaID, OwnerID: ownerID},
			},
		},
	)

	result, err := handler.Execute(context.Background(), AddMediaCommand{
		UserID:   ownerID,
		AlbumID:  albumID,
		MediaIDs: []uuid.UUID{firstMediaID, secondMediaID, firstMediaID},
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if result.Added != 1 || result.AlreadyInAlbum != 1 {
		t.Fatalf("Execute() = %#v, want 1 added and 1 already_in_album", result)
	}
}

func TestRemoveMediaHandlerExecuteRejectsNonOwner(t *testing.T) {
	t.Parallel()

	handler := NewRemoveMediaHandler(
		&fakeUserRepo{user: &domain.User{ID: uuid.New(), Active: true, Role: domain.RoleMember}},
		&fakeAlbumRepo{album: &domain.Album{ID: uuid.New(), OwnerID: uuid.New()}},
	)

	err := handler.Execute(context.Background(), RemoveMediaCommand{
		UserID:  handler.userRepo.(*fakeUserRepo).user.ID,
		AlbumID: handler.albumRepo.(*fakeAlbumRepo).album.ID,
		MediaID: uuid.New(),
	})
	if err != domain.ErrForbidden {
		t.Fatalf("Execute() error = %v, want %v", err, domain.ErrForbidden)
	}
}
