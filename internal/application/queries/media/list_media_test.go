package media

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

type fakeMediaRepo struct {
	page       domain.MediaPage
	received   domain.ListMediaOptions
	receivedID uuid.UUID
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

func (r *fakeMediaRepo) ListVisibleToUser(_ context.Context, userID uuid.UUID, opts domain.ListMediaOptions) (domain.MediaPage, error) {
	r.receivedID = userID
	r.received = opts
	return r.page, nil
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

type fakeFavoriteRepo struct {
	mediaIDs        []uuid.UUID
	requestedUserID uuid.UUID
	requestedIDs    []uuid.UUID
	calls           int
}

func (r *fakeFavoriteRepo) Create(context.Context, *domain.Favorite) error {
	return nil
}

func (r *fakeFavoriteRepo) Delete(context.Context, uuid.UUID, uuid.UUID) error {
	return nil
}

func (r *fakeFavoriteRepo) ListMediaIDsByUser(_ context.Context, userID uuid.UUID, mediaIDs []uuid.UUID) ([]uuid.UUID, error) {
	r.calls++
	r.requestedUserID = userID
	r.requestedIDs = append([]uuid.UUID(nil), mediaIDs...)
	return r.mediaIDs, nil
}

func TestListMediaHandlerExecuteAnnotatesFavorites(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	firstMedia := &domain.Media{ID: uuid.New()}
	secondMedia := &domain.Media{ID: uuid.New()}
	mediaRepo := &fakeMediaRepo{
		page: domain.MediaPage{
			Items: []*domain.Media{firstMedia, secondMedia},
			Total: 2,
		},
	}
	favoriteRepo := &fakeFavoriteRepo{mediaIDs: []uuid.UUID{secondMedia.ID}}

	handler := NewListMediaHandler(&fakeUserRepo{user: user}, mediaRepo, favoriteRepo)
	page, err := handler.Execute(context.Background(), ListMediaQuery{
		UserID: user.ID,
		Limit:  25,
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if mediaRepo.receivedID != user.ID || mediaRepo.received.Limit != 25 {
		t.Fatalf("Execute() forwarded unexpected media query: %#v for %s", mediaRepo.received, mediaRepo.receivedID)
	}
	if favoriteRepo.requestedUserID != user.ID || len(favoriteRepo.requestedIDs) != 2 {
		t.Fatalf("Execute() requested unexpected favorite lookup: %#v", favoriteRepo)
	}
	if page.Items[0].IsFavorite {
		t.Fatal("Execute() marked non-favorited media as favorite")
	}
	if !page.Items[1].IsFavorite {
		t.Fatal("Execute() did not mark favorited media")
	}
}

func TestListMediaHandlerExecuteMarksFavoritesOnlyPage(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	mediaItem := &domain.Media{ID: uuid.New()}
	mediaRepo := &fakeMediaRepo{
		page: domain.MediaPage{
			Items: []*domain.Media{mediaItem},
			Total: 1,
		},
	}
	favoriteRepo := &fakeFavoriteRepo{}

	handler := NewListMediaHandler(&fakeUserRepo{user: user}, mediaRepo, favoriteRepo)
	page, err := handler.Execute(context.Background(), ListMediaQuery{
		UserID:        user.ID,
		FavoritesOnly: true,
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if !mediaRepo.received.FavoritesOnly {
		t.Fatal("Execute() did not forward FavoritesOnly to the media repository")
	}
	if favoriteRepo.calls != 0 {
		t.Fatalf("Execute() should not perform a second favorite lookup for favorites-only pages, got %d calls", favoriteRepo.calls)
	}
	if len(page.Items) != 1 || !page.Items[0].IsFavorite {
		t.Fatalf("Execute() returned unexpected favorites-only page: %#v", page)
	}
}
