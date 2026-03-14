package admin

import (
	"context"
	"net/url"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
	pkgauth "github.com/yourorg/mycloud/pkg/auth"
)

type fakeAdminUserRepo struct {
	user *domain.User
}

func (r *fakeAdminUserRepo) FindByID(_ context.Context, id uuid.UUID) (*domain.User, error) {
	if r.user == nil || r.user.ID != id {
		return nil, domain.ErrNotFound
	}

	return r.user, nil
}

func (r *fakeAdminUserRepo) FindByEmail(context.Context, string) (*domain.User, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeAdminUserRepo) UpdateLastLogin(context.Context, uuid.UUID, time.Time) error {
	return nil
}

type fakeAdminRepo struct {
	inviteParams domain.InviteUserParams
	inviteAudit  *domain.AuditLog
	invitedUser  *domain.User

	updateParams domain.AdminUpdateUserParams
	updateAudit  *domain.AuditLog
	updatedUser  *domain.User

	findInviteUser *domain.User
	acceptedUser   *domain.User
	acceptParams   domain.AcceptInviteParams
	acceptAudit    *domain.AuditLog
}

func (r *fakeAdminRepo) ListUsers(context.Context) ([]*domain.User, error) {
	return nil, nil
}

func (r *fakeAdminRepo) CreateOrRefreshInvite(_ context.Context, params domain.InviteUserParams, audit *domain.AuditLog) (*domain.User, error) {
	r.inviteParams = params
	r.inviteAudit = audit
	return r.invitedUser, nil
}

func (r *fakeAdminRepo) FindInviteByTokenHash(context.Context, string) (*domain.User, error) {
	if r.findInviteUser == nil {
		return nil, domain.ErrNotFound
	}

	return r.findInviteUser, nil
}

func (r *fakeAdminRepo) AcceptInvite(_ context.Context, params domain.AcceptInviteParams, audit *domain.AuditLog) (*domain.User, error) {
	r.acceptParams = params
	r.acceptAudit = audit
	return r.acceptedUser, nil
}

func (r *fakeAdminRepo) UpdateUser(_ context.Context, params domain.AdminUpdateUserParams, audit *domain.AuditLog) (*domain.User, error) {
	r.updateParams = params
	r.updateAudit = audit
	return r.updatedUser, nil
}

func (r *fakeAdminRepo) GetSystemStats(context.Context) (*domain.SystemStats, error) {
	return nil, nil
}

type fakeAdminSessionStore struct {
	revokedUserID uuid.UUID
}

func (s *fakeAdminSessionStore) StoreRefreshToken(context.Context, uuid.UUID, string, time.Duration) error {
	return nil
}

func (s *fakeAdminSessionStore) ValidateRefreshToken(context.Context, uuid.UUID, string) (bool, error) {
	return true, nil
}

func (s *fakeAdminSessionStore) RevokeRefreshToken(context.Context, uuid.UUID, string) error {
	return nil
}

func (s *fakeAdminSessionStore) RevokeAllForUser(_ context.Context, userID uuid.UUID) error {
	s.revokedUserID = userID
	return nil
}

func TestInviteUserHandlerExecuteCreatesInviteURLAndHashedToken(t *testing.T) {
	t.Parallel()

	adminUser := &domain.User{ID: uuid.New(), Active: true, Role: domain.RoleAdmin}
	invitedUser := &domain.User{ID: uuid.New(), Email: "new.member@example.com"}
	adminRepo := &fakeAdminRepo{invitedUser: invitedUser}

	handler := NewInviteUserHandler(
		&fakeAdminUserRepo{user: adminUser},
		adminRepo,
		"https://app.example.com",
	)

	result, err := handler.Execute(context.Background(), InviteUserCommand{
		AdminUserID: adminUser.ID,
		Email:       "New.Member@example.com",
		QuotaGB:     20,
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if result.User.ID != invitedUser.ID {
		t.Fatalf("Execute() returned user %s, want %s", result.User.ID, invitedUser.ID)
	}

	parsed, err := url.Parse(result.InviteURL)
	if err != nil {
		t.Fatalf("Parse(invite_url) error = %v", err)
	}
	token := parsed.Query().Get("token")
	if token == "" {
		t.Fatal("Execute() returned invite URL without token")
	}
	if got, want := adminRepo.inviteParams.InviteTokenHash, pkgauth.HashInviteToken(token); got != want {
		t.Fatalf("InviteTokenHash = %q, want hash of returned token", got)
	}
	if got, want := adminRepo.inviteParams.Email, "new.member@example.com"; got != want {
		t.Fatalf("Email = %q, want %q", got, want)
	}
	if got, want := adminRepo.inviteParams.Role, domain.RoleMember; got != want {
		t.Fatalf("Role = %q, want %q", got, want)
	}
	if got, want := adminRepo.inviteParams.QuotaBytes, int64(20*1024*1024*1024); got != want {
		t.Fatalf("QuotaBytes = %d, want %d", got, want)
	}
	if adminRepo.inviteAudit == nil || adminRepo.inviteAudit.Action != domain.AuditActionAdminInviteUser {
		t.Fatal("Execute() did not record invite audit metadata")
	}
}

func TestUpdateUserHandlerExecuteRevokesSessionsOnDeactivation(t *testing.T) {
	t.Parallel()

	adminUser := &domain.User{ID: uuid.New(), Active: true, Role: domain.RoleAdmin}
	targetUser := &domain.User{ID: uuid.New(), Active: false}
	adminRepo := &fakeAdminRepo{updatedUser: targetUser}
	sessionStore := &fakeAdminSessionStore{}
	active := false

	handler := NewUpdateUserHandler(
		&fakeAdminUserRepo{user: adminUser},
		adminRepo,
		sessionStore,
	)

	updatedUser, err := handler.Execute(context.Background(), UpdateUserCommand{
		AdminUserID:  adminUser.ID,
		TargetUserID: targetUser.ID,
		Active:       &active,
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if updatedUser.ID != targetUser.ID {
		t.Fatalf("Execute() returned user %s, want %s", updatedUser.ID, targetUser.ID)
	}
	if !adminRepo.updateParams.ClearInvite {
		t.Fatal("Execute() did not clear invite data on deactivation")
	}
	if sessionStore.revokedUserID != targetUser.ID {
		t.Fatalf("RevokeAllForUser() user = %s, want %s", sessionStore.revokedUserID, targetUser.ID)
	}
}

func TestUpdateUserHandlerExecuteRejectsSelfDeactivation(t *testing.T) {
	t.Parallel()

	adminUser := &domain.User{ID: uuid.New(), Active: true, Role: domain.RoleAdmin}
	active := false
	handler := NewUpdateUserHandler(
		&fakeAdminUserRepo{user: adminUser},
		&fakeAdminRepo{},
		&fakeAdminSessionStore{},
	)

	_, err := handler.Execute(context.Background(), UpdateUserCommand{
		AdminUserID:  adminUser.ID,
		TargetUserID: adminUser.ID,
		Active:       &active,
	})
	if err != domain.ErrForbidden {
		t.Fatalf("Execute() error = %v, want %v", err, domain.ErrForbidden)
	}
}
