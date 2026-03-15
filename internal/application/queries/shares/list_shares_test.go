package shares

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
	album *domain.Album
}

func (r *fakeAlbumRepo) Create(context.Context, *domain.Album) error {
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

func (r *fakeAlbumRepo) Update(context.Context, *domain.Album) error {
	return nil
}

func (r *fakeAlbumRepo) Delete(context.Context, uuid.UUID) error {
	return nil
}

func (r *fakeAlbumRepo) HasMedia(context.Context, uuid.UUID, uuid.UUID) (bool, error) {
	return false, nil
}

func (r *fakeAlbumRepo) AddMedia(context.Context, uuid.UUID, uuid.UUID, uuid.UUID) (bool, error) {
	return false, nil
}

func (r *fakeAlbumRepo) RemoveMedia(context.Context, uuid.UUID, uuid.UUID) error {
	return nil
}

type fakeShareRepo struct {
	shares []*domain.Share
}

func (r *fakeShareRepo) Create(context.Context, *domain.Share) error {
	return nil
}

func (r *fakeShareRepo) FindByID(context.Context, uuid.UUID) (*domain.Share, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeShareRepo) ListActiveByAlbum(context.Context, uuid.UUID) ([]*domain.Share, error) {
	return r.shares, nil
}

func (r *fakeShareRepo) UserCanContribute(context.Context, uuid.UUID, uuid.UUID) (bool, error) {
	return false, nil
}

func (r *fakeShareRepo) Delete(context.Context, uuid.UUID) error {
	return nil
}

func TestListSharesHandlerExecuteReturnsAlbumSharesForOwner(t *testing.T) {
	t.Parallel()

	owner := &domain.User{ID: uuid.New(), Active: true}
	album := &domain.Album{ID: uuid.New(), OwnerID: owner.ID}
	shares := []*domain.Share{{ID: uuid.New(), AlbumID: album.ID}}

	handler := NewListSharesHandler(
		&fakeUserRepo{user: owner},
		&fakeAlbumRepo{album: album},
		&fakeShareRepo{shares: shares},
	)

	result, err := handler.Execute(context.Background(), ListSharesQuery{
		UserID:  owner.ID,
		AlbumID: album.ID,
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if len(result) != 1 || result[0].ID != shares[0].ID {
		t.Fatalf("Execute() returned unexpected shares: %#v", result)
	}
}

func TestListSharesHandlerExecuteRejectsNonOwner(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	album := &domain.Album{ID: uuid.New(), OwnerID: uuid.New()}

	handler := NewListSharesHandler(
		&fakeUserRepo{user: user},
		&fakeAlbumRepo{album: album},
		&fakeShareRepo{},
	)

	if _, err := handler.Execute(context.Background(), ListSharesQuery{
		UserID:  user.ID,
		AlbumID: album.ID,
	}); err != domain.ErrForbidden {
		t.Fatalf("Execute() error = %v, want %v", err, domain.ErrForbidden)
	}
}
