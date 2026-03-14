package admin

import (
	"context"
	"net/netip"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type UpdateUserCommand struct {
	AdminUserID  uuid.UUID
	TargetUserID uuid.UUID
	Role         *string
	QuotaBytes   *int64
	Active       *bool
	IPAddress    *netip.Addr
}

type UpdateUserHandler struct {
	userRepo     domain.UserRepository
	adminRepo    domain.AdminRepository
	sessionStore domain.SessionStore
}

func NewUpdateUserHandler(
	userRepo domain.UserRepository,
	adminRepo domain.AdminRepository,
	sessionStore domain.SessionStore,
) *UpdateUserHandler {
	return &UpdateUserHandler{
		userRepo:     userRepo,
		adminRepo:    adminRepo,
		sessionStore: sessionStore,
	}
}

func (h *UpdateUserHandler) Execute(ctx context.Context, command UpdateUserCommand) (*domain.User, error) {
	if command.TargetUserID == uuid.Nil {
		return nil, domain.ErrInvalidInput
	}
	if command.Role == nil && command.QuotaBytes == nil && command.Active == nil {
		return nil, domain.ErrInvalidInput
	}

	adminUser, err := requireActiveAdmin(ctx, h.userRepo, command.AdminUserID)
	if err != nil {
		return nil, err
	}

	role, roleChanged, err := parseRequestedRole(command.Role)
	if err != nil {
		return nil, err
	}
	if command.QuotaBytes != nil && *command.QuotaBytes <= 0 {
		return nil, domain.ErrInvalidInput
	}
	if command.TargetUserID == adminUser.ID {
		if roleChanged && role != adminUser.Role {
			return nil, domain.ErrForbidden
		}
		if command.Active != nil && !*command.Active {
			return nil, domain.ErrForbidden
		}
	}

	clearInvite := command.Active != nil && !*command.Active
	params := domain.AdminUpdateUserParams{
		UserID:      command.TargetUserID,
		QuotaBytes:  command.QuotaBytes,
		Active:      command.Active,
		ClearInvite: clearInvite,
	}
	if roleChanged {
		roleCopy := role
		params.Role = &roleCopy
	}

	action := domain.AuditActionAdminUpdateUser
	if clearInvite {
		action = domain.AuditActionAdminDeactivate
	}

	updatedUser, err := h.adminRepo.UpdateUser(ctx, params, &domain.AuditLog{
		ActorID:   &adminUser.ID,
		Action:    action,
		TargetID:  &command.TargetUserID,
		Meta:      buildUpdateAuditMeta(command),
		IPAddress: command.IPAddress,
		CreatedAt: time.Now().UTC(),
	})
	if err != nil {
		return nil, err
	}

	if clearInvite || roleChanged {
		if err := h.sessionStore.RevokeAllForUser(ctx, updatedUser.ID); err != nil {
			return nil, err
		}
	}

	return updatedUser, nil
}

func parseRequestedRole(role *string) (domain.UserRole, bool, error) {
	if role == nil {
		return "", false, nil
	}

	switch normalized := domain.UserRole(strings.TrimSpace(*role)); normalized {
	case domain.RoleMember, domain.RoleAdmin:
		return normalized, true, nil
	default:
		return "", false, domain.ErrInvalidInput
	}
}

func buildUpdateAuditMeta(command UpdateUserCommand) map[string]any {
	meta := map[string]any{}
	if command.Role != nil {
		meta["role"] = strings.TrimSpace(*command.Role)
	}
	if command.QuotaBytes != nil {
		meta["quota_bytes"] = *command.QuotaBytes
	}
	if command.Active != nil {
		meta["active"] = *command.Active
	}

	return meta
}
