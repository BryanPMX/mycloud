package admin

import (
	"context"
	"net/mail"
	"net/netip"
	"net/url"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
	pkgauth "github.com/yourorg/mycloud/pkg/auth"
)

const pendingInvitePasswordHash = "!invite_pending!"

type InviteUserCommand struct {
	AdminUserID uuid.UUID
	Email       string
	Role        string
	QuotaGB     int64
	IPAddress   *netip.Addr
}

type InviteUserResult struct {
	User      *domain.User
	InviteURL string
	ExpiresAt time.Time
}

type InviteUserHandler struct {
	userRepo    domain.UserRepository
	adminRepo   domain.AdminRepository
	emailSender domain.InviteEmailSender
	appName     string
	appBaseURL  string
}

func NewInviteUserHandler(
	userRepo domain.UserRepository,
	adminRepo domain.AdminRepository,
	emailSender domain.InviteEmailSender,
	appName string,
	appBaseURL string,
) *InviteUserHandler {
	return &InviteUserHandler{
		userRepo:    userRepo,
		adminRepo:   adminRepo,
		emailSender: emailSender,
		appName:     strings.TrimSpace(appName),
		appBaseURL:  strings.TrimRight(strings.TrimSpace(appBaseURL), "/"),
	}
}

func (h *InviteUserHandler) Execute(ctx context.Context, command InviteUserCommand) (*InviteUserResult, error) {
	adminUser, err := requireActiveAdmin(ctx, h.userRepo, command.AdminUserID)
	if err != nil {
		return nil, err
	}

	address, err := mail.ParseAddress(strings.TrimSpace(command.Email))
	if err != nil || address.Address == "" {
		return nil, domain.ErrInvalidInput
	}
	if command.QuotaGB <= 0 {
		return nil, domain.ErrInvalidInput
	}

	role, err := normalizeRole(command.Role)
	if err != nil {
		return nil, err
	}

	token, err := pkgauth.GenerateInviteToken()
	if err != nil {
		return nil, err
	}
	tokenHash := pkgauth.HashInviteToken(token)
	now := time.Now().UTC()
	expiresAt := now.Add(72 * time.Hour)

	invitedUser, err := h.adminRepo.CreateOrRefreshInvite(ctx, domain.InviteUserParams{
		Email:           strings.ToLower(strings.TrimSpace(address.Address)),
		DisplayName:     defaultDisplayName(address.Address),
		Role:            role,
		QuotaBytes:      quotaBytesFromGB(command.QuotaGB),
		PasswordHash:    pendingInvitePasswordHash,
		InviteTokenHash: tokenHash,
		InviteExpiresAt: expiresAt,
		CreatedAt:       now,
	}, &domain.AuditLog{
		ActorID:   &adminUser.ID,
		Action:    domain.AuditActionAdminInviteUser,
		TargetID:  nil,
		Meta:      map[string]any{"email": strings.ToLower(strings.TrimSpace(address.Address)), "role": string(role), "quota_bytes": quotaBytesFromGB(command.QuotaGB)},
		IPAddress: command.IPAddress,
		CreatedAt: now,
	})
	if err != nil {
		return nil, err
	}

	result := &InviteUserResult{
		User:      invitedUser,
		InviteURL: buildInviteURL(h.appBaseURL, token),
		ExpiresAt: expiresAt,
	}
	if h.emailSender != nil {
		if err := h.emailSender.SendInviteEmail(ctx, domain.InviteEmail{
			AppName:     h.appName,
			To:          invitedUser.Email,
			DisplayName: invitedUser.DisplayName,
			InviteURL:   result.InviteURL,
			ExpiresAt:   result.ExpiresAt,
		}); err != nil {
			return nil, err
		}
	}

	return result, nil
}

func normalizeRole(raw string) (domain.UserRole, error) {
	role := domain.UserRole(strings.TrimSpace(raw))
	if role == "" {
		role = domain.RoleMember
	}

	switch role {
	case domain.RoleMember, domain.RoleAdmin:
		return role, nil
	default:
		return "", domain.ErrInvalidInput
	}
}

func quotaBytesFromGB(gb int64) int64 {
	return gb * 1024 * 1024 * 1024
}

func defaultDisplayName(email string) string {
	local := strings.TrimSpace(strings.SplitN(email, "@", 2)[0])
	local = strings.NewReplacer(".", " ", "_", " ", "-", " ").Replace(local)
	fields := strings.Fields(local)
	if len(fields) == 0 {
		return email
	}

	for idx, field := range fields {
		fields[idx] = strings.ToUpper(field[:1]) + field[1:]
	}

	return strings.Join(fields, " ")
}

func buildInviteURL(baseURL, token string) string {
	if baseURL == "" {
		baseURL = "http://localhost:8080"
	}

	return baseURL + "/accept?token=" + url.QueryEscape(token)
}
