package media

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type fakeMediaUserRepo struct {
	user *domain.User
}

func (r *fakeMediaUserRepo) FindByID(_ context.Context, id uuid.UUID) (*domain.User, error) {
	if r.user == nil || r.user.ID != id {
		return nil, domain.ErrNotFound
	}

	return r.user, nil
}

func (r *fakeMediaUserRepo) FindByEmail(context.Context, string) (*domain.User, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeMediaUserRepo) UpdateLastLogin(context.Context, uuid.UUID, time.Time) error {
	return nil
}

type fakeStorageService struct {
	uploadID      string
	initiatedKey  string
	initiatedMIME string
	partURL       string
	partNum       int
	partUploadID  string
	partKey       string
	completedKey  string
	completedID   string
	completed     []domain.CompletedPart
	abortCalled   bool
	uploadExists  bool

	initErr         error
	presignErr      error
	completeErr     error
	uploadExistsErr error
}

func (s *fakeStorageService) DeleteUpload(context.Context, string) error {
	return nil
}

type fakeUploadStore struct {
	session *domain.UploadSession

	savedSession *domain.UploadSession
	deletedID    uuid.UUID

	saveErr error
	getErr  error
}

func (s *fakeUploadStore) SaveUploadSession(_ context.Context, session domain.UploadSession, _ time.Duration) error {
	if s.saveErr != nil {
		return s.saveErr
	}

	copied := session
	s.savedSession = &copied
	s.session = &copied
	return nil
}

func (s *fakeUploadStore) GetUploadSession(context.Context, uuid.UUID) (*domain.UploadSession, error) {
	if s.getErr != nil {
		return nil, s.getErr
	}
	if s.session == nil {
		return nil, domain.ErrNotFound
	}

	return s.session, nil
}

func (s *fakeUploadStore) DeleteUploadSession(_ context.Context, mediaID uuid.UUID) error {
	s.deletedID = mediaID
	return nil
}

type fakeMediaRepo struct {
	existing  *domain.Media
	created   *domain.Media
	createErr error
}

func (r *fakeMediaRepo) Create(_ context.Context, media *domain.Media) error {
	if r.createErr != nil {
		return r.createErr
	}

	copied := *media
	r.created = &copied
	return nil
}

func (r *fakeMediaRepo) FindByIDForUser(context.Context, uuid.UUID, uuid.UUID) (*domain.Media, error) {
	if r.existing == nil {
		return nil, domain.ErrNotFound
	}

	return r.existing, nil
}

func (r *fakeMediaRepo) ListVisibleToUser(context.Context, uuid.UUID, domain.ListMediaOptions) (domain.MediaPage, error) {
	return domain.MediaPage{}, nil
}

type fakeKeyBuilder struct {
	key string
}

func (b fakeKeyBuilder) BuildMediaObjectKey(uuid.UUID, uuid.UUID, string, string, time.Time) string {
	return b.key
}

func (s *fakeStorageService) InitiateUpload(_ context.Context, key, mimeType string) (string, error) {
	s.initiatedKey = key
	s.initiatedMIME = mimeType
	if s.initErr != nil {
		return "", s.initErr
	}

	return s.uploadID, nil
}

func (s *fakeStorageService) PresignUploadPart(_ context.Context, key, uploadID string, partNum int, _ time.Duration) (string, error) {
	s.partKey = key
	s.partUploadID = uploadID
	s.partNum = partNum
	if s.presignErr != nil {
		return "", s.presignErr
	}

	return s.partURL, nil
}

func (s *fakeStorageService) CompleteUpload(_ context.Context, key, uploadID string, parts []domain.CompletedPart) error {
	s.completedKey = key
	s.completedID = uploadID
	s.completed = append([]domain.CompletedPart(nil), parts...)
	return s.completeErr
}

func (s *fakeStorageService) AbortUpload(_ context.Context, _, _ string) error {
	s.abortCalled = true
	return nil
}

func (s *fakeStorageService) UploadExists(context.Context, string) (bool, error) {
	return s.uploadExists, s.uploadExistsErr
}

func TestInitUploadHandlerExecute(t *testing.T) {
	t.Parallel()

	user := &domain.User{
		ID:          uuid.New(),
		Active:      true,
		StorageUsed: 10,
		QuotaBytes:  10_000,
	}
	userRepo := &fakeMediaUserRepo{user: user}
	storage := &fakeStorageService{uploadID: "upload-123"}
	uploadStore := &fakeUploadStore{}

	handler := NewInitUploadHandler(
		userRepo,
		storage,
		uploadStore,
		fakeKeyBuilder{key: "owner/2026/03/media.mp4"},
		DefaultPartSizeBytes,
		15*time.Minute,
		48*time.Hour,
	)

	result, err := handler.Execute(context.Background(), InitUploadCommand{
		UserID:    user.ID,
		Filename:  "clip.mp4",
		MimeType:  "video/mp4",
		SizeBytes: 1234,
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if result.UploadID != "upload-123" {
		t.Fatalf("Execute() uploadID = %q, want upload-123", result.UploadID)
	}
	if result.Key != "owner/2026/03/media.mp4" {
		t.Fatalf("Execute() key = %q", result.Key)
	}
	if uploadStore.savedSession == nil || uploadStore.savedSession.MediaID != result.MediaID {
		t.Fatal("Execute() did not persist upload session")
	}
	if storage.initiatedKey != "owner/2026/03/media.mp4" || storage.initiatedMIME != "video/mp4" {
		t.Fatal("Execute() did not initiate multipart upload with the expected object metadata")
	}
}

func TestPresignUploadPartHandlerExecute(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	session := &domain.UploadSession{
		MediaID:   uuid.New(),
		OwnerID:   user.ID,
		ObjectKey: "owner/2026/03/media.mp4",
		UploadID:  "upload-123",
	}
	userRepo := &fakeMediaUserRepo{user: user}
	storage := &fakeStorageService{partURL: "https://example.com/upload"}
	uploadStore := &fakeUploadStore{session: session}

	handler := NewPresignUploadPartHandler(userRepo, storage, uploadStore, 15*time.Minute)
	result, err := handler.Execute(context.Background(), PresignUploadPartCommand{
		UserID:     user.ID,
		MediaID:    session.MediaID,
		UploadID:   session.UploadID,
		PartNumber: 2,
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if result.URL != "https://example.com/upload" {
		t.Fatalf("Execute() url = %q", result.URL)
	}
	if storage.partNum != 2 || storage.partKey != session.ObjectKey || storage.partUploadID != session.UploadID {
		t.Fatal("Execute() did not request a presigned URL for the expected part")
	}
}

func TestCompleteUploadHandlerExecuteCreatesPendingMedia(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	session := &domain.UploadSession{
		MediaID:   uuid.New(),
		OwnerID:   user.ID,
		Filename:  "clip.mp4",
		MimeType:  "video/mp4",
		SizeBytes: 2048,
		ObjectKey: "owner/2026/03/media.mp4",
		UploadID:  "upload-123",
	}
	userRepo := &fakeMediaUserRepo{user: user}
	storage := &fakeStorageService{}
	uploadStore := &fakeUploadStore{session: session}
	mediaRepo := &fakeMediaRepo{}

	handler := NewCompleteUploadHandler(userRepo, mediaRepo, storage, uploadStore)
	result, err := handler.Execute(context.Background(), CompleteUploadCommand{
		UserID:   user.ID,
		MediaID:  session.MediaID,
		UploadID: session.UploadID,
		Parts: []domain.CompletedPart{
			{PartNumber: 2, ETag: "\"b\""},
			{PartNumber: 1, ETag: "\"a\""},
		},
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if result.Media.Status != domain.MediaStatusPending {
		t.Fatalf("Execute() status = %q, want pending", result.Media.Status)
	}
	if mediaRepo.created == nil || mediaRepo.created.OriginalKey != session.ObjectKey {
		t.Fatal("Execute() did not persist the completed upload as media")
	}
	if len(storage.completed) != 2 || storage.completed[0].PartNumber != 1 || storage.completed[1].PartNumber != 2 {
		t.Fatal("Execute() did not normalize multipart completion parts")
	}
	if uploadStore.deletedID != session.MediaID {
		t.Fatal("Execute() did not delete the upload session after completion")
	}
}

func TestCompleteUploadHandlerExecuteReturnsExistingMediaWhenSessionIsGone(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	existing := &domain.Media{
		ID:        uuid.New(),
		OwnerID:   user.ID,
		Filename:  "clip.mp4",
		Status:    domain.MediaStatusPending,
		SizeBytes: 2048,
	}
	userRepo := &fakeMediaUserRepo{user: user}
	uploadStore := &fakeUploadStore{getErr: domain.ErrNotFound}
	mediaRepo := &fakeMediaRepo{existing: existing}

	handler := NewCompleteUploadHandler(userRepo, mediaRepo, &fakeStorageService{}, uploadStore)
	result, err := handler.Execute(context.Background(), CompleteUploadCommand{
		UserID:   user.ID,
		MediaID:  existing.ID,
		UploadID: "upload-123",
		Parts: []domain.CompletedPart{
			{PartNumber: 1, ETag: "\"a\""},
		},
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if result.Media != existing {
		t.Fatal("Execute() did not return the existing media row")
	}
}
