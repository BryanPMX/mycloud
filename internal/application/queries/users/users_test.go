package users

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type fakeUserDirectoryRepo struct {
	users map[uuid.UUID]*domain.User
	list  []*domain.User
}

func (r *fakeUserDirectoryRepo) FindByID(_ context.Context, id uuid.UUID) (*domain.User, error) {
	user, ok := r.users[id]
	if !ok {
		return nil, domain.ErrNotFound
	}

	return user, nil
}

func (r *fakeUserDirectoryRepo) FindByEmail(context.Context, string) (*domain.User, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeUserDirectoryRepo) UpdateLastLogin(context.Context, uuid.UUID, time.Time) error {
	return nil
}

func (r *fakeUserDirectoryRepo) ListActiveUsers(context.Context) ([]*domain.User, error) {
	return r.list, nil
}

type fakeAvatarAssetReader struct {
	exists map[string]bool
	urls   map[string]string
}

func (r *fakeAvatarAssetReader) PresignAvatar(_ context.Context, key string, _ time.Duration) (string, error) {
	if url, ok := r.urls[key]; ok {
		return url, nil
	}

	return "https://signed.example/" + key, nil
}

func (r *fakeAvatarAssetReader) AvatarExists(_ context.Context, key string) (bool, error) {
	if r.exists == nil {
		return true, nil
	}

	return r.exists[key], nil
}

func TestGetAvatarURLHandlerExecuteReturnsSignedURL(t *testing.T) {
	t.Parallel()

	requestUserID := uuid.New()
	targetUserID := uuid.New()
	key := "users/target/avatar.png"
	handler := NewGetAvatarURLHandler(
		&fakeUserDirectoryRepo{
			users: map[uuid.UUID]*domain.User{
				requestUserID: {ID: requestUserID, Active: true},
				targetUserID:  {ID: targetUserID, Active: true, AvatarKey: key},
			},
		},
		&fakeAvatarAssetReader{
			exists: map[string]bool{key: true},
			urls:   map[string]string{key: "https://signed.example/avatar"},
		},
	)

	result, err := handler.Execute(context.Background(), GetAvatarURLQuery{
		RequestUserID: requestUserID,
		TargetUserID:  targetUserID,
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if result.URL != "https://signed.example/avatar" {
		t.Fatalf("Execute() URL = %q, want signed avatar URL", result.URL)
	}
	if time.Until(result.ExpiresAt) <= 0 {
		t.Fatal("Execute() ExpiresAt was not set in the future")
	}
}

func TestGetAvatarURLHandlerExecuteRejectsMissingAvatar(t *testing.T) {
	t.Parallel()

	requestUserID := uuid.New()
	targetUserID := uuid.New()
	handler := NewGetAvatarURLHandler(
		&fakeUserDirectoryRepo{
			users: map[uuid.UUID]*domain.User{
				requestUserID: {ID: requestUserID, Active: true},
				targetUserID:  {ID: targetUserID, Active: true},
			},
		},
		&fakeAvatarAssetReader{},
	)

	_, err := handler.Execute(context.Background(), GetAvatarURLQuery{
		RequestUserID: requestUserID,
		TargetUserID:  targetUserID,
	})
	if err != domain.ErrNotFound {
		t.Fatalf("Execute() error = %v, want %v", err, domain.ErrNotFound)
	}
}

func TestListDirectoryHandlerExecuteReturnsSignedAvatarURLs(t *testing.T) {
	t.Parallel()

	requestUserID := uuid.New()
	secondUserID := uuid.New()
	key := "users/second/avatar.png"
	handler := NewListDirectoryHandler(
		&fakeUserDirectoryRepo{
			users: map[uuid.UUID]*domain.User{
				requestUserID: {ID: requestUserID, Active: true},
			},
			list: []*domain.User{
				{ID: requestUserID, Active: true, DisplayName: "Requester"},
				{ID: secondUserID, Active: true, DisplayName: "Second User", AvatarKey: key},
			},
		},
		&fakeAvatarAssetReader{
			exists: map[string]bool{key: true},
			urls:   map[string]string{key: "https://signed.example/second"},
		},
	)

	result, err := handler.Execute(context.Background(), ListDirectoryQuery{UserID: requestUserID})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got, want := len(result), 2; got != want {
		t.Fatalf("Execute() len = %d, want %d", got, want)
	}
	if result[0].AvatarURL != nil {
		t.Fatalf("Execute() requester avatar_url = %#v, want nil", result[0].AvatarURL)
	}
	if result[1].AvatarURL == nil || *result[1].AvatarURL != "https://signed.example/second" {
		t.Fatalf("Execute() second avatar_url = %#v, want signed URL", result[1].AvatarURL)
	}
}
