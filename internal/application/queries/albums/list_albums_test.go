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
	owned  []*domain.Album
	shared []*domain.Album
}

func (r *fakeAlbumRepo) Create(context.Context, *domain.Album) error {
	return nil
}

func (r *fakeAlbumRepo) FindByID(context.Context, uuid.UUID) (*domain.Album, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeAlbumRepo) ListOwnedByUser(context.Context, uuid.UUID) ([]*domain.Album, error) {
	return r.owned, nil
}

func (r *fakeAlbumRepo) ListSharedWithUser(context.Context, uuid.UUID) ([]*domain.Album, error) {
	return r.shared, nil
}

func (r *fakeAlbumRepo) AddMedia(context.Context, uuid.UUID, uuid.UUID, uuid.UUID) (bool, error) {
	return false, nil
}

func (r *fakeAlbumRepo) RemoveMedia(context.Context, uuid.UUID, uuid.UUID) error {
	return nil
}

func TestListAlbumsHandlerExecuteReturnsOwnedAndSharedGroups(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	owned := []*domain.Album{{ID: uuid.New(), OwnerID: user.ID, Name: "Owned"}}
	shared := []*domain.Album{{ID: uuid.New(), OwnerID: uuid.New(), Name: "Shared"}}

	handler := NewListAlbumsHandler(&fakeUserRepo{user: user}, &fakeAlbumRepo{
		owned:  owned,
		shared: shared,
	})

	result, err := handler.Execute(context.Background(), ListAlbumsQuery{UserID: user.ID})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if len(result.Owned) != 1 || result.Owned[0].Name != "Owned" {
		t.Fatalf("Execute() returned unexpected owned albums: %#v", result.Owned)
	}
	if len(result.SharedWithMe) != 1 || result.SharedWithMe[0].Name != "Shared" {
		t.Fatalf("Execute() returned unexpected shared albums: %#v", result.SharedWithMe)
	}
}
