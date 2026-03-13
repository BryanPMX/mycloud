package shares

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type fakeUserRepo struct {
	users map[uuid.UUID]*domain.User
}

func (r *fakeUserRepo) FindByID(_ context.Context, id uuid.UUID) (*domain.User, error) {
	user, ok := r.users[id]
	if !ok {
		return nil, domain.ErrNotFound
	}

	return user, nil
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
	existing  *domain.Share
	created   *domain.Share
	deletedID uuid.UUID
}

func (r *fakeShareRepo) Create(_ context.Context, share *domain.Share) error {
	copied := *share
	r.created = &copied
	r.existing = &copied
	return nil
}

func (r *fakeShareRepo) FindByID(context.Context, uuid.UUID) (*domain.Share, error) {
	if r.existing == nil {
		return nil, domain.ErrNotFound
	}

	return r.existing, nil
}

func (r *fakeShareRepo) ListActiveByAlbum(context.Context, uuid.UUID) ([]*domain.Share, error) {
	return nil, nil
}

func (r *fakeShareRepo) Delete(_ context.Context, id uuid.UUID) error {
	r.deletedID = id
	return nil
}

func TestCreateShareHandlerExecuteCreatesFamilyWideShare(t *testing.T) {
	t.Parallel()

	owner := &domain.User{ID: uuid.New(), Active: true, Role: domain.RoleMember}
	album := &domain.Album{ID: uuid.New(), OwnerID: owner.ID}
	shareRepo := &fakeShareRepo{}

	handler := NewCreateShareHandler(
		&fakeUserRepo{users: map[uuid.UUID]*domain.User{owner.ID: owner}},
		&fakeAlbumRepo{album: album},
		shareRepo,
	)

	share, err := handler.Execute(context.Background(), CreateShareCommand{
		UserID:  owner.ID,
		AlbumID: album.ID,
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if share.Permission != domain.PermissionView {
		t.Fatalf("Execute() permission = %q, want view", share.Permission)
	}
	if share.SharedWith != uuid.Nil || share.Recipient == nil || share.Recipient.DisplayName != "Entire family" {
		t.Fatalf("Execute() returned unexpected family-wide share: %#v", share)
	}
}

func TestCreateShareHandlerExecuteRejectsSharingToOwner(t *testing.T) {
	t.Parallel()

	owner := &domain.User{ID: uuid.New(), Active: true}
	album := &domain.Album{ID: uuid.New(), OwnerID: owner.ID}

	handler := NewCreateShareHandler(
		&fakeUserRepo{users: map[uuid.UUID]*domain.User{owner.ID: owner}},
		&fakeAlbumRepo{album: album},
		&fakeShareRepo{},
	)

	if _, err := handler.Execute(context.Background(), CreateShareCommand{
		UserID:     owner.ID,
		AlbumID:    album.ID,
		SharedWith: &owner.ID,
	}); err != domain.ErrInvalidInput {
		t.Fatalf("Execute() error = %v, want %v", err, domain.ErrInvalidInput)
	}
}

func TestRevokeShareHandlerExecuteDeletesShareOwnedByAlbum(t *testing.T) {
	t.Parallel()

	owner := &domain.User{ID: uuid.New(), Active: true}
	album := &domain.Album{ID: uuid.New(), OwnerID: owner.ID}
	share := &domain.Share{ID: uuid.New(), AlbumID: album.ID}
	shareRepo := &fakeShareRepo{existing: share}

	handler := NewRevokeShareHandler(
		&fakeUserRepo{users: map[uuid.UUID]*domain.User{owner.ID: owner}},
		&fakeAlbumRepo{album: album},
		shareRepo,
	)

	if err := handler.Execute(context.Background(), RevokeShareCommand{
		UserID:  owner.ID,
		AlbumID: album.ID,
		ShareID: share.ID,
	}); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if shareRepo.deletedID != share.ID {
		t.Fatal("Execute() did not revoke the target share")
	}
}
