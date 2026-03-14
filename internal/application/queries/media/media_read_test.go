package media

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type fakeReadUserRepo struct {
	user *domain.User
}

func (r *fakeReadUserRepo) FindByID(_ context.Context, id uuid.UUID) (*domain.User, error) {
	if r.user == nil || r.user.ID != id {
		return nil, domain.ErrNotFound
	}

	return r.user, nil
}

func (r *fakeReadUserRepo) FindByEmail(context.Context, string) (*domain.User, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeReadUserRepo) UpdateLastLogin(context.Context, uuid.UUID, time.Time) error {
	return nil
}

type fakeMediaReadRepo struct {
	media      *domain.Media
	page       domain.MediaPage
	searchOpts domain.SearchMediaOptions
}

func (r *fakeMediaReadRepo) FindByIDForUser(context.Context, uuid.UUID, uuid.UUID) (*domain.Media, error) {
	if r.media == nil {
		return nil, domain.ErrNotFound
	}

	return r.media, nil
}

func (r *fakeMediaReadRepo) SearchVisibleToUser(_ context.Context, _ uuid.UUID, opts domain.SearchMediaOptions) (domain.MediaPage, error) {
	r.searchOpts = opts
	return r.page, nil
}

type fakeMediaTrashRepo struct {
	page domain.MediaPage
}

func (r *fakeMediaTrashRepo) FindByIDIncludingDeleted(context.Context, uuid.UUID) (*domain.Media, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeMediaTrashRepo) FindOwnedByUserIncludingDeleted(context.Context, uuid.UUID, uuid.UUID) (*domain.Media, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeMediaTrashRepo) ListTrashedOwnedByUser(context.Context, uuid.UUID, domain.ListTrashOptions) (domain.MediaPage, error) {
	return r.page, nil
}

func (r *fakeMediaTrashRepo) SoftDelete(context.Context, uuid.UUID, time.Time) error {
	return nil
}

func (r *fakeMediaTrashRepo) Restore(context.Context, uuid.UUID) error {
	return nil
}

func (r *fakeMediaTrashRepo) HardDelete(context.Context, uuid.UUID) error {
	return nil
}

func (r *fakeMediaTrashRepo) HardDeleteAllTrashedOwnedByUser(context.Context, uuid.UUID) ([]*domain.Media, error) {
	return nil, nil
}

type fakeReadFavoriteRepo struct {
	favoriteIDs []uuid.UUID
}

func (r *fakeReadFavoriteRepo) Create(context.Context, *domain.Favorite) error {
	return nil
}

func (r *fakeReadFavoriteRepo) Delete(context.Context, uuid.UUID, uuid.UUID) error {
	return nil
}

func (r *fakeReadFavoriteRepo) ListMediaIDsByUser(context.Context, uuid.UUID, []uuid.UUID) ([]uuid.UUID, error) {
	return append([]uuid.UUID(nil), r.favoriteIDs...), nil
}

type fakeAssetReader struct {
	originalURL    string
	thumbURL       string
	originalExists bool
	thumbExists    bool
}

func (r *fakeAssetReader) PresignOriginalDownload(context.Context, string, time.Duration) (string, error) {
	return r.originalURL, nil
}

func (r *fakeAssetReader) PresignThumbnail(context.Context, string, time.Duration) (string, error) {
	return r.thumbURL, nil
}

func (r *fakeAssetReader) OriginalExists(context.Context, string) (bool, error) {
	return r.originalExists, nil
}

func (r *fakeAssetReader) ThumbnailExists(context.Context, string) (bool, error) {
	return r.thumbExists, nil
}

func TestGetMediaHandlerExecuteMarksFavorite(t *testing.T) {
	t.Parallel()

	userID := uuid.New()
	mediaID := uuid.New()
	handler := NewGetMediaHandler(
		&fakeReadUserRepo{user: &domain.User{ID: userID, Active: true}},
		&fakeMediaReadRepo{media: &domain.Media{ID: mediaID, OwnerID: userID, Filename: "photo.jpg"}},
		&fakeReadFavoriteRepo{favoriteIDs: []uuid.UUID{mediaID}},
	)

	result, err := handler.Execute(context.Background(), GetMediaQuery{
		UserID:  userID,
		MediaID: mediaID,
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if !result.Media.IsFavorite {
		t.Fatal("Execute() did not mark the media as favorite")
	}
}

func TestSearchMediaHandlerExecuteUsesTrimmedQuery(t *testing.T) {
	t.Parallel()

	userID := uuid.New()
	repo := &fakeMediaReadRepo{
		page: domain.MediaPage{
			Items: []*domain.Media{{ID: uuid.New()}, {ID: uuid.New()}},
		},
	}
	handler := NewSearchMediaHandler(
		&fakeReadUserRepo{user: &domain.User{ID: userID, Active: true}},
		repo,
		&fakeReadFavoriteRepo{},
	)

	_, err := handler.Execute(context.Background(), SearchMediaQuery{
		UserID: userID,
		Query:  "  vacation  ",
		Limit:  25,
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if repo.searchOpts.Query != "vacation" {
		t.Fatalf("Execute() query = %q, want %q", repo.searchOpts.Query, "vacation")
	}
}

func TestGetMediaDownloadURLHandlerExecuteRequiresReadyMedia(t *testing.T) {
	t.Parallel()

	userID := uuid.New()
	handler := NewGetMediaDownloadURLHandler(
		&fakeReadUserRepo{user: &domain.User{ID: userID, Active: true}},
		&fakeMediaReadRepo{media: &domain.Media{ID: uuid.New(), Status: domain.MediaStatusPending}},
		&fakeAssetReader{originalExists: true, originalURL: "https://example.com/original"},
	)

	_, err := handler.Execute(context.Background(), GetMediaDownloadURLQuery{
		UserID:  userID,
		MediaID: uuid.New(),
	})
	if err != domain.ErrConflict {
		t.Fatalf("Execute() error = %v, want %v", err, domain.ErrConflict)
	}
}

func TestGetMediaThumbURLHandlerExecuteRequiresExistingThumb(t *testing.T) {
	t.Parallel()

	userID := uuid.New()
	handler := NewGetMediaThumbURLHandler(
		&fakeReadUserRepo{user: &domain.User{ID: userID, Active: true}},
		&fakeMediaReadRepo{media: &domain.Media{
			ID:     uuid.New(),
			Status: domain.MediaStatusReady,
			ThumbKeys: domain.ThumbKeys{
				Medium: "thumb.webp",
			},
		}},
		&fakeAssetReader{thumbExists: false},
	)

	_, err := handler.Execute(context.Background(), GetMediaThumbURLQuery{
		UserID:  userID,
		MediaID: uuid.New(),
	})
	if err != domain.ErrNotFound {
		t.Fatalf("Execute() error = %v, want %v", err, domain.ErrNotFound)
	}
}

func TestListTrashHandlerExecuteMarksFavorites(t *testing.T) {
	t.Parallel()

	userID := uuid.New()
	mediaID := uuid.New()
	trashRepo := &fakeMediaTrashRepo{
		page: domain.MediaPage{
			Items: []*domain.Media{{ID: mediaID, DeletedAt: timePtr(time.Now().UTC())}},
		},
	}
	handler := NewListTrashHandler(
		&fakeReadUserRepo{user: &domain.User{ID: userID, Active: true}},
		trashRepo,
		&fakeReadFavoriteRepo{favoriteIDs: []uuid.UUID{mediaID}},
	)

	page, err := handler.Execute(context.Background(), ListTrashQuery{UserID: userID})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if len(page.Items) != 1 || !page.Items[0].IsFavorite {
		t.Fatal("Execute() did not preserve favorite state in trash results")
	}
}

func timePtr(value time.Time) *time.Time {
	return &value
}
