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
	album           *domain.Album
	created         *domain.Album
	updated         *domain.Album
	addedResults    map[uuid.UUID]bool
	hasMediaResults map[uuid.UUID]bool
	addedMediaIDs   []uuid.UUID
	removedMedia    uuid.UUID
	deletedAlbumID  uuid.UUID
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

func (r *fakeAlbumRepo) FindByIDVisibleToUser(context.Context, uuid.UUID, uuid.UUID) (*domain.Album, error) {
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

func (r *fakeAlbumRepo) Update(_ context.Context, album *domain.Album) error {
	copied := *album
	r.updated = &copied
	r.album = &copied
	return nil
}

func (r *fakeAlbumRepo) Delete(_ context.Context, id uuid.UUID) error {
	r.deletedAlbumID = id
	if r.album != nil && r.album.ID == id {
		r.album = nil
	}
	return nil
}

func (r *fakeAlbumRepo) HasMedia(_ context.Context, _ uuid.UUID, mediaID uuid.UUID) (bool, error) {
	if r.hasMediaResults == nil {
		return false, nil
	}

	return r.hasMediaResults[mediaID], nil
}

func (r *fakeAlbumRepo) AddMedia(_ context.Context, _ uuid.UUID, mediaID, _ uuid.UUID) (bool, error) {
	r.addedMediaIDs = append(r.addedMediaIDs, mediaID)
	return r.addedResults[mediaID], nil
}

func (r *fakeAlbumRepo) RemoveMedia(_ context.Context, _ uuid.UUID, mediaID uuid.UUID) error {
	r.removedMedia = mediaID
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

func (r *fakeMediaRepo) ListByAlbum(context.Context, uuid.UUID, domain.ListMediaOptions) (domain.MediaPage, error) {
	return domain.MediaPage{}, nil
}

func (r *fakeMediaRepo) UpdateStatus(context.Context, uuid.UUID, domain.MediaStatus) error {
	return nil
}

func (r *fakeMediaRepo) ApplyProcessingResult(context.Context, uuid.UUID, domain.MediaProcessingResult) error {
	return nil
}

type fakeShareRepo struct {
	canContribute bool
}

func (r *fakeShareRepo) Create(context.Context, *domain.Share) error {
	return nil
}

func (r *fakeShareRepo) FindByID(context.Context, uuid.UUID) (*domain.Share, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeShareRepo) ListActiveByAlbum(context.Context, uuid.UUID) ([]*domain.Share, error) {
	return nil, nil
}

func (r *fakeShareRepo) UserCanContribute(context.Context, uuid.UUID, uuid.UUID) (bool, error) {
	return r.canContribute, nil
}

func (r *fakeShareRepo) Delete(context.Context, uuid.UUID) error {
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
		&fakeShareRepo{},
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

func TestAddMediaHandlerExecuteAllowsContributorToAddOnlyOwnMedia(t *testing.T) {
	t.Parallel()

	ownerID := uuid.New()
	contributorID := uuid.New()
	albumID := uuid.New()
	ownMediaID := uuid.New()
	otherMediaID := uuid.New()

	handler := NewAddMediaHandler(
		&fakeUserRepo{user: &domain.User{ID: contributorID, Active: true}},
		&fakeAlbumRepo{
			album:        &domain.Album{ID: albumID, OwnerID: ownerID},
			addedResults: map[uuid.UUID]bool{ownMediaID: true},
		},
		&fakeMediaRepo{
			media: map[uuid.UUID]*domain.Media{
				ownMediaID:   {ID: ownMediaID, OwnerID: contributorID},
				otherMediaID: {ID: otherMediaID, OwnerID: ownerID},
			},
		},
		&fakeShareRepo{canContribute: true},
	)

	result, err := handler.Execute(context.Background(), AddMediaCommand{
		UserID:   contributorID,
		AlbumID:  albumID,
		MediaIDs: []uuid.UUID{ownMediaID},
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if result.Added != 1 || result.AlreadyInAlbum != 0 {
		t.Fatalf("Execute() = %#v, want 1 added and 0 already_in_album", result)
	}

	_, err = handler.Execute(context.Background(), AddMediaCommand{
		UserID:   contributorID,
		AlbumID:  albumID,
		MediaIDs: []uuid.UUID{otherMediaID},
	})
	if err != domain.ErrForbidden {
		t.Fatalf("Execute() error = %v, want %v when contributor adds someone else's media", err, domain.ErrForbidden)
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

func TestUpdateAlbumHandlerExecuteTrimsFieldsAndSetsCover(t *testing.T) {
	t.Parallel()

	ownerID := uuid.New()
	albumID := uuid.New()
	coverMediaID := uuid.New()
	albumRepo := &fakeAlbumRepo{
		album: &domain.Album{
			ID:          albumID,
			OwnerID:     ownerID,
			Name:        "Original",
			Description: "Original description",
		},
		hasMediaResults: map[uuid.UUID]bool{
			coverMediaID: true,
		},
	}

	handler := NewUpdateAlbumHandler(&fakeUserRepo{user: &domain.User{ID: ownerID, Active: true}}, albumRepo)
	name := "  Summer 2026  "
	description := "  Updated description  "

	album, err := handler.Execute(context.Background(), UpdateAlbumCommand{
		UserID:        ownerID,
		AlbumID:       albumID,
		Name:          &name,
		Description:   &description,
		CoverMediaID:  &coverMediaID,
		CoverMediaSet: true,
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if album.Name != "Summer 2026" || album.Description != "Updated description" {
		t.Fatalf("Execute() returned unexpected album fields: %#v", album)
	}
	if album.CoverMediaID == nil || *album.CoverMediaID != coverMediaID {
		t.Fatalf("Execute() cover_media_id = %#v, want %v", album.CoverMediaID, coverMediaID)
	}
	if albumRepo.updated == nil || albumRepo.updated.CoverMediaID == nil || *albumRepo.updated.CoverMediaID != coverMediaID {
		t.Fatal("Execute() did not persist the updated cover media")
	}
}

func TestUpdateAlbumHandlerExecuteRejectsCoverOutsideAlbum(t *testing.T) {
	t.Parallel()

	ownerID := uuid.New()
	albumID := uuid.New()
	coverMediaID := uuid.New()

	handler := NewUpdateAlbumHandler(
		&fakeUserRepo{user: &domain.User{ID: ownerID, Active: true}},
		&fakeAlbumRepo{
			album: &domain.Album{ID: albumID, OwnerID: ownerID},
		},
	)

	_, err := handler.Execute(context.Background(), UpdateAlbumCommand{
		UserID:        ownerID,
		AlbumID:       albumID,
		CoverMediaID:  &coverMediaID,
		CoverMediaSet: true,
	})
	if err != domain.ErrInvalidInput {
		t.Fatalf("Execute() error = %v, want %v", err, domain.ErrInvalidInput)
	}
}

func TestDeleteAlbumHandlerExecuteDeletesAlbum(t *testing.T) {
	t.Parallel()

	ownerID := uuid.New()
	album := &domain.Album{ID: uuid.New(), OwnerID: ownerID}
	albumRepo := &fakeAlbumRepo{album: album}
	handler := NewDeleteAlbumHandler(
		&fakeUserRepo{user: &domain.User{ID: ownerID, Active: true}},
		albumRepo,
	)

	if err := handler.Execute(context.Background(), DeleteAlbumCommand{
		UserID:  ownerID,
		AlbumID: album.ID,
	}); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if albumRepo.deletedAlbumID != album.ID {
		t.Fatalf("Execute() deleted album = %v, want %v", albumRepo.deletedAlbumID, album.ID)
	}
}
