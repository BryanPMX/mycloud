package auth

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
	pkgauth "github.com/yourorg/mycloud/pkg/auth"
)

type fakeInviteAdminRepo struct {
	findInviteUser *domain.User
	acceptedUser   *domain.User
	acceptParams   domain.AcceptInviteParams
}

func (r *fakeInviteAdminRepo) ListUsers(context.Context) ([]*domain.User, error) {
	return nil, nil
}

func (r *fakeInviteAdminRepo) CreateOrRefreshInvite(context.Context, domain.InviteUserParams, *domain.AuditLog) (*domain.User, error) {
	return nil, nil
}

func (r *fakeInviteAdminRepo) FindInviteByTokenHash(context.Context, string) (*domain.User, error) {
	if r.findInviteUser == nil {
		return nil, domain.ErrNotFound
	}

	return r.findInviteUser, nil
}

func (r *fakeInviteAdminRepo) AcceptInvite(_ context.Context, params domain.AcceptInviteParams, _ *domain.AuditLog) (*domain.User, error) {
	r.acceptParams = params
	return r.acceptedUser, nil
}

func (r *fakeInviteAdminRepo) UpdateUser(context.Context, domain.AdminUpdateUserParams, *domain.AuditLog) (*domain.User, error) {
	return nil, nil
}

func (r *fakeInviteAdminRepo) GetSystemStats(context.Context) (*domain.SystemStats, error) {
	return nil, nil
}

type fakeInviteSessionStore struct {
	userID uuid.UUID
	jti    string
}

func (s *fakeInviteSessionStore) StoreRefreshToken(_ context.Context, userID uuid.UUID, jti string, _ time.Duration) error {
	s.userID = userID
	s.jti = jti
	return nil
}

func (s *fakeInviteSessionStore) ValidateRefreshToken(context.Context, uuid.UUID, string) (bool, error) {
	return true, nil
}

func (s *fakeInviteSessionStore) RevokeRefreshToken(context.Context, uuid.UUID, string) error {
	return nil
}

func (s *fakeInviteSessionStore) RevokeAllForUser(context.Context, uuid.UUID) error {
	return nil
}

func TestAcceptInviteHandlerExecuteActivatesInviteAndCreatesSession(t *testing.T) {
	t.Parallel()

	token := "invite-token"
	tokenHash := pkgauth.HashInviteToken(token)
	userID := uuid.New()
	adminRepo := &fakeInviteAdminRepo{
		findInviteUser: &domain.User{
			ID:           userID,
			Email:        "invited@example.com",
			Role:         domain.RoleMember,
			InviteToken:  tokenHash,
			InviteExpiry: timePtr(time.Now().UTC().Add(time.Hour)),
		},
		acceptedUser: &domain.User{
			ID:          userID,
			Email:       "invited@example.com",
			Role:        domain.RoleMember,
			Active:      true,
			DisplayName: "Invited User",
		},
	}
	sessionStore := &fakeInviteSessionStore{}
	tokenService, err := pkgauth.NewJWTService("12345678901234567890123456789012", "mycloud", 15*time.Minute, 24*time.Hour)
	if err != nil {
		t.Fatalf("NewJWTService() error = %v", err)
	}

	handler := NewAcceptInviteHandler(adminRepo, sessionStore, tokenService, 15*time.Minute, 24*time.Hour)
	result, err := handler.Execute(context.Background(), AcceptInviteCommand{
		Token:       token,
		DisplayName: "Invited User",
		Password:    "super-secret-password",
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if result.AccessToken == "" || result.RefreshToken == "" {
		t.Fatal("Execute() returned empty tokens")
	}
	if sessionStore.userID != userID || sessionStore.jti == "" {
		t.Fatal("Execute() did not persist a refresh session")
	}
	if adminRepo.acceptParams.InviteTokenHash != tokenHash {
		t.Fatalf("InviteTokenHash = %q, want %q", adminRepo.acceptParams.InviteTokenHash, tokenHash)
	}
}

func TestAcceptInviteHandlerExecuteRejectsExpiredInvite(t *testing.T) {
	t.Parallel()

	tokenHash := pkgauth.HashInviteToken("expired-token")
	handler := NewAcceptInviteHandler(
		&fakeInviteAdminRepo{
			findInviteUser: &domain.User{
				ID:           uuid.New(),
				InviteToken:  tokenHash,
				InviteExpiry: timePtr(time.Now().UTC().Add(-time.Minute)),
			},
		},
		&fakeInviteSessionStore{},
		mustJWTService(t),
		15*time.Minute,
		24*time.Hour,
	)

	_, err := handler.Execute(context.Background(), AcceptInviteCommand{
		Token:       "expired-token",
		DisplayName: "Expired User",
		Password:    "super-secret-password",
	})
	if err != domain.ErrInvalidToken {
		t.Fatalf("Execute() error = %v, want %v", err, domain.ErrInvalidToken)
	}
}

func mustJWTService(t *testing.T) pkgauth.Service {
	t.Helper()

	service, err := pkgauth.NewJWTService("12345678901234567890123456789012", "mycloud", 15*time.Minute, 24*time.Hour)
	if err != nil {
		t.Fatalf("NewJWTService() error = %v", err)
	}

	return service
}

func timePtr(value time.Time) *time.Time {
	return &value
}
