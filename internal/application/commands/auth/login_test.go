package auth

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
	pkgauth "github.com/yourorg/mycloud/pkg/auth"
)

type fakeUserRepo struct {
	user             *domain.User
	updatedLastLogin bool
}

func (r *fakeUserRepo) FindByID(_ context.Context, id uuid.UUID) (*domain.User, error) {
	if r.user == nil || r.user.ID != id {
		return nil, domain.ErrNotFound
	}
	return r.user, nil
}

func (r *fakeUserRepo) FindByEmail(_ context.Context, email string) (*domain.User, error) {
	if r.user == nil || r.user.Email != email {
		return nil, domain.ErrNotFound
	}
	return r.user, nil
}

func (r *fakeUserRepo) UpdateLastLogin(_ context.Context, _ uuid.UUID, _ time.Time) error {
	r.updatedLastLogin = true
	return nil
}

type fakeSessionStore struct {
	userID uuid.UUID
	jti    string
}

func (s *fakeSessionStore) StoreRefreshToken(_ context.Context, userID uuid.UUID, jti string, _ time.Duration) error {
	s.userID = userID
	s.jti = jti
	return nil
}

func (s *fakeSessionStore) ValidateRefreshToken(context.Context, uuid.UUID, string) (bool, error) {
	return true, nil
}

func (s *fakeSessionStore) RevokeRefreshToken(context.Context, uuid.UUID, string) error {
	return nil
}

func (s *fakeSessionStore) RevokeAllForUser(context.Context, uuid.UUID) error {
	return nil
}

func TestLoginHandlerExecute(t *testing.T) {
	t.Parallel()

	passwordHash, err := pkgauth.HashPassword("super-secret-password")
	if err != nil {
		t.Fatalf("HashPassword() error = %v", err)
	}

	user := &domain.User{
		ID:           uuid.New(),
		Email:        "user@example.com",
		DisplayName:  "User",
		Role:         domain.RoleMember,
		PasswordHash: passwordHash,
		Active:       true,
	}
	userRepo := &fakeUserRepo{user: user}
	sessionStore := &fakeSessionStore{}

	tokenService, err := pkgauth.NewJWTService("12345678901234567890123456789012", "mycloud", 15*time.Minute, 24*time.Hour)
	if err != nil {
		t.Fatalf("NewJWTService() error = %v", err)
	}

	handler := NewLoginHandler(userRepo, sessionStore, tokenService, 15*time.Minute, 24*time.Hour)
	result, err := handler.Execute(context.Background(), LoginCommand{
		Email:    "user@example.com",
		Password: "super-secret-password",
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if result.AccessToken == "" || result.RefreshToken == "" {
		t.Fatal("Execute() returned empty tokens")
	}
	if sessionStore.userID != user.ID || sessionStore.jti == "" {
		t.Fatal("Execute() did not persist refresh session")
	}
	if !userRepo.updatedLastLogin {
		t.Fatal("Execute() did not update last login")
	}
}
