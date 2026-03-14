package media

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type fakeTrashUserRepo struct {
	user *domain.User
}

func (r *fakeTrashUserRepo) FindByID(_ context.Context, id uuid.UUID) (*domain.User, error) {
	if r.user == nil || r.user.ID != id {
		return nil, domain.ErrNotFound
	}

	return r.user, nil
}

func (r *fakeTrashUserRepo) FindByEmail(context.Context, string) (*domain.User, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeTrashUserRepo) UpdateLastLogin(context.Context, uuid.UUID, time.Time) error {
	return nil
}

type fakeTrashRepo struct {
	media       *domain.Media
	deletedAt   *time.Time
	restoredID  uuid.UUID
	hardDeleted uuid.UUID
	deletedAll  []*domain.Media
}

func (r *fakeTrashRepo) FindByIDIncludingDeleted(context.Context, uuid.UUID) (*domain.Media, error) {
	if r.media == nil {
		return nil, domain.ErrNotFound
	}

	return r.media, nil
}

func (r *fakeTrashRepo) FindOwnedByUserIncludingDeleted(context.Context, uuid.UUID, uuid.UUID) (*domain.Media, error) {
	if r.media == nil {
		return nil, domain.ErrNotFound
	}

	return r.media, nil
}

func (r *fakeTrashRepo) ListTrashedOwnedByUser(context.Context, uuid.UUID, domain.ListTrashOptions) (domain.MediaPage, error) {
	return domain.MediaPage{}, nil
}

func (r *fakeTrashRepo) SoftDelete(_ context.Context, _ uuid.UUID, deletedAt time.Time) error {
	copied := deletedAt
	r.deletedAt = &copied
	return nil
}

func (r *fakeTrashRepo) Restore(_ context.Context, id uuid.UUID) error {
	r.restoredID = id
	return nil
}

func (r *fakeTrashRepo) HardDelete(_ context.Context, id uuid.UUID) error {
	r.hardDeleted = id
	return nil
}

func (r *fakeTrashRepo) HardDeleteAllTrashedOwnedByUser(context.Context, uuid.UUID) ([]*domain.Media, error) {
	return append([]*domain.Media(nil), r.deletedAll...), nil
}

type fakeAssetCleaner struct {
	deleted []*domain.Media
}

func (c *fakeAssetCleaner) DeleteMediaAssets(_ context.Context, media *domain.Media) error {
	c.deleted = append(c.deleted, media)
	return nil
}

func TestAbortUploadHandlerExecuteDeletesSession(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	session := &domain.UploadSession{
		MediaID:   uuid.New(),
		OwnerID:   user.ID,
		ObjectKey: "owner/2026/03/media.mp4",
		UploadID:  "upload-123",
	}
	storage := &fakeStorageService{}
	uploadStore := &fakeUploadStore{session: session}
	handler := NewAbortUploadHandler(&fakeTrashUserRepo{user: user}, storage, uploadStore)

	if err := handler.Execute(context.Background(), AbortUploadCommand{
		UserID:  user.ID,
		MediaID: session.MediaID,
	}); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if !storage.abortCalled {
		t.Fatal("Execute() did not abort the multipart upload")
	}
	if uploadStore.deletedID != session.MediaID {
		t.Fatal("Execute() did not delete the upload session")
	}
}

func TestDeleteMediaHandlerExecuteSoftDeletesOwnedMedia(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	repo := &fakeTrashRepo{media: &domain.Media{ID: uuid.New(), OwnerID: user.ID}}
	handler := NewDeleteMediaHandler(&fakeTrashUserRepo{user: user}, repo)

	if err := handler.Execute(context.Background(), DeleteMediaCommand{
		UserID:  user.ID,
		MediaID: repo.media.ID,
	}); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if repo.deletedAt == nil {
		t.Fatal("Execute() did not soft-delete the media")
	}
}

func TestRestoreMediaHandlerExecuteRestoresDeletedMedia(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	deletedAt := time.Now().UTC()
	repo := &fakeTrashRepo{
		media: &domain.Media{ID: uuid.New(), OwnerID: user.ID, DeletedAt: &deletedAt},
	}
	handler := NewRestoreMediaHandler(&fakeTrashUserRepo{user: user}, repo)

	if err := handler.Execute(context.Background(), RestoreMediaCommand{
		UserID:  user.ID,
		MediaID: repo.media.ID,
	}); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if repo.restoredID != repo.media.ID {
		t.Fatal("Execute() did not restore the media")
	}
}

func TestPermanentDeleteMediaHandlerExecuteDeletesAssets(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	deletedAt := time.Now().UTC()
	repo := &fakeTrashRepo{
		media: &domain.Media{ID: uuid.New(), OwnerID: user.ID, DeletedAt: &deletedAt},
	}
	cleaner := &fakeAssetCleaner{}
	handler := NewPermanentDeleteMediaHandler(&fakeTrashUserRepo{user: user}, repo, cleaner)

	if err := handler.Execute(context.Background(), PermanentDeleteMediaCommand{
		UserID:  user.ID,
		MediaID: repo.media.ID,
	}); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if repo.hardDeleted != repo.media.ID {
		t.Fatal("Execute() did not hard-delete the media row")
	}
	if len(cleaner.deleted) != 1 || cleaner.deleted[0].ID != repo.media.ID {
		t.Fatal("Execute() did not clean up media assets")
	}
}

func TestEmptyTrashHandlerExecuteCleansAllDeletedAssets(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	repo := &fakeTrashRepo{
		deletedAll: []*domain.Media{{ID: uuid.New()}, {ID: uuid.New()}},
	}
	cleaner := &fakeAssetCleaner{}
	handler := NewEmptyTrashHandler(&fakeTrashUserRepo{user: user}, repo, cleaner)

	if err := handler.Execute(context.Background(), EmptyTrashCommand{UserID: user.ID}); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if len(cleaner.deleted) != 2 {
		t.Fatalf("Execute() deleted %d assets, want 2", len(cleaner.deleted))
	}
}
