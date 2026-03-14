package users

import (
	"context"
	"errors"
	"io"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type fakeUserProfileRepo struct {
	user *domain.User

	updatedDisplayName string
	updatedAvatarKey   string

	updateProfileErr error
	updateAvatarErr  error
}

func (r *fakeUserProfileRepo) FindByID(_ context.Context, id uuid.UUID) (*domain.User, error) {
	if r.user == nil || r.user.ID != id {
		return nil, domain.ErrNotFound
	}

	return r.user, nil
}

func (r *fakeUserProfileRepo) UpdateProfile(_ context.Context, _ uuid.UUID, displayName string) (*domain.User, error) {
	if r.updateProfileErr != nil {
		return nil, r.updateProfileErr
	}

	r.updatedDisplayName = displayName
	updated := *r.user
	updated.DisplayName = displayName
	updated.UpdatedAt = time.Now().UTC()
	return &updated, nil
}

func (r *fakeUserProfileRepo) UpdateAvatarKey(_ context.Context, _ uuid.UUID, avatarKey string) (*domain.User, error) {
	if r.updateAvatarErr != nil {
		return nil, r.updateAvatarErr
	}

	r.updatedAvatarKey = avatarKey
	updated := *r.user
	updated.AvatarKey = avatarKey
	updated.UpdatedAt = time.Now().UTC()
	return &updated, nil
}

type fakeAvatarStorage struct {
	uploadedKey  string
	uploadedMIME string
	uploadedData []byte
	deletedKeys  []string
	uploadErr    error
}

func (s *fakeAvatarStorage) UploadAvatar(_ context.Context, key, mimeType string, body io.Reader, _ int64) error {
	if s.uploadErr != nil {
		return s.uploadErr
	}

	data, err := io.ReadAll(body)
	if err != nil {
		return err
	}
	s.uploadedKey = key
	s.uploadedMIME = mimeType
	s.uploadedData = append([]byte(nil), data...)
	return nil
}

func (s *fakeAvatarStorage) DeleteAvatar(_ context.Context, key string) error {
	s.deletedKeys = append(s.deletedKeys, key)
	return nil
}

type fakeAvatarKeyBuilder struct {
	key string
}

func (b fakeAvatarKeyBuilder) BuildAvatarObjectKey(uuid.UUID, string, time.Time) string {
	return b.key
}

func TestUpdateProfileHandlerExecuteTrimsDisplayName(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true, DisplayName: "Dad"}
	repo := &fakeUserProfileRepo{user: user}
	handler := NewUpdateProfileHandler(repo)

	updated, err := handler.Execute(context.Background(), UpdateProfileCommand{
		UserID:      user.ID,
		DisplayName: "  Papa  ",
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got, want := repo.updatedDisplayName, "Papa"; got != want {
		t.Fatalf("UpdateProfile() display_name = %q, want %q", got, want)
	}
	if got, want := updated.DisplayName, "Papa"; got != want {
		t.Fatalf("Execute() display_name = %q, want %q", got, want)
	}
}

func TestUpdateAvatarHandlerExecuteUploadsAndDeletesPreviousAvatar(t *testing.T) {
	t.Parallel()

	user := &domain.User{
		ID:        uuid.New(),
		Active:    true,
		AvatarKey: "users/existing/avatar-old.png",
	}
	repo := &fakeUserProfileRepo{user: user}
	storage := &fakeAvatarStorage{}
	handler := NewUpdateAvatarHandler(
		repo,
		storage,
		fakeAvatarKeyBuilder{key: "users/new/avatar-20260314T160509.png"},
	)

	updated, err := handler.Execute(context.Background(), UpdateAvatarCommand{
		UserID:   user.ID,
		MimeType: "image/png",
		Content:  []byte("avatar-binary"),
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got, want := storage.uploadedKey, "users/new/avatar-20260314T160509.png"; got != want {
		t.Fatalf("UploadAvatar() key = %q, want %q", got, want)
	}
	if got, want := string(storage.uploadedData), "avatar-binary"; got != want {
		t.Fatalf("UploadAvatar() payload = %q, want %q", got, want)
	}
	if got, want := repo.updatedAvatarKey, "users/new/avatar-20260314T160509.png"; got != want {
		t.Fatalf("UpdateAvatarKey() key = %q, want %q", got, want)
	}
	if len(storage.deletedKeys) != 1 || storage.deletedKeys[0] != "users/existing/avatar-old.png" {
		t.Fatalf("DeleteAvatar() keys = %v, want previous avatar key cleanup", storage.deletedKeys)
	}
	if got, want := updated.AvatarKey, "users/new/avatar-20260314T160509.png"; got != want {
		t.Fatalf("Execute() avatar_key = %q, want %q", got, want)
	}
}

func TestUpdateAvatarHandlerExecuteDeletesNewUploadWhenDatabaseWriteFails(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true}
	repo := &fakeUserProfileRepo{
		user:            user,
		updateAvatarErr: errors.New("db write failed"),
	}
	storage := &fakeAvatarStorage{}
	handler := NewUpdateAvatarHandler(
		repo,
		storage,
		fakeAvatarKeyBuilder{key: "users/new/avatar.png"},
	)

	_, err := handler.Execute(context.Background(), UpdateAvatarCommand{
		UserID:   user.ID,
		MimeType: "image/png",
		Content:  []byte("avatar-binary"),
	})
	if err == nil {
		t.Fatal("Execute() error = nil, want database failure")
	}
	if len(storage.deletedKeys) != 1 || storage.deletedKeys[0] != "users/new/avatar.png" {
		t.Fatalf("DeleteAvatar() keys = %v, want rollback cleanup of new object", storage.deletedKeys)
	}
}
