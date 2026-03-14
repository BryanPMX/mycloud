package admin

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type fakeAdminQueryUserRepo struct {
	user *domain.User
}

func (r *fakeAdminQueryUserRepo) FindByID(_ context.Context, id uuid.UUID) (*domain.User, error) {
	if r.user == nil || r.user.ID != id {
		return nil, domain.ErrNotFound
	}

	return r.user, nil
}

func (r *fakeAdminQueryUserRepo) FindByEmail(context.Context, string) (*domain.User, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeAdminQueryUserRepo) UpdateLastLogin(context.Context, uuid.UUID, time.Time) error {
	return nil
}

type fakeAdminQueryRepo struct {
	users []*domain.User
	stats *domain.SystemStats
}

func (r *fakeAdminQueryRepo) ListUsers(context.Context) ([]*domain.User, error) {
	return r.users, nil
}

func (r *fakeAdminQueryRepo) CreateOrRefreshInvite(context.Context, domain.InviteUserParams, *domain.AuditLog) (*domain.User, error) {
	return nil, nil
}

func (r *fakeAdminQueryRepo) FindInviteByTokenHash(context.Context, string) (*domain.User, error) {
	return nil, nil
}

func (r *fakeAdminQueryRepo) AcceptInvite(context.Context, domain.AcceptInviteParams, *domain.AuditLog) (*domain.User, error) {
	return nil, nil
}

func (r *fakeAdminQueryRepo) UpdateUser(context.Context, domain.AdminUpdateUserParams, *domain.AuditLog) (*domain.User, error) {
	return nil, nil
}

func (r *fakeAdminQueryRepo) GetSystemStats(context.Context) (*domain.SystemStats, error) {
	return r.stats, nil
}

func TestListUsersHandlerExecuteRequiresAdmin(t *testing.T) {
	t.Parallel()

	user := &domain.User{ID: uuid.New(), Active: true, Role: domain.RoleMember}
	handler := NewListUsersHandler(
		&fakeAdminQueryUserRepo{user: user},
		&fakeAdminQueryRepo{},
	)

	_, err := handler.Execute(context.Background(), ListUsersQuery{UserID: user.ID})
	if err != domain.ErrForbidden {
		t.Fatalf("Execute() error = %v, want %v", err, domain.ErrForbidden)
	}
}

func TestSystemStatsHandlerExecuteReturnsStatsForAdmin(t *testing.T) {
	t.Parallel()

	adminUser := &domain.User{ID: uuid.New(), Active: true, Role: domain.RoleAdmin}
	stats := &domain.SystemStats{
		Users: domain.SystemUserStats{Total: 3, Active: 2},
		Media: domain.SystemMediaStats{PendingJobs: 1},
	}
	handler := NewSystemStatsHandler(
		&fakeAdminQueryUserRepo{user: adminUser},
		&fakeAdminQueryRepo{stats: stats},
	)

	result, err := handler.Execute(context.Background(), SystemStatsQuery{UserID: adminUser.ID})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if result.Users.Total != 3 || result.Media.PendingJobs != 1 {
		t.Fatalf("Execute() returned unexpected stats: %#v", result)
	}
}
