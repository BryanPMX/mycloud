package auth

import (
	"context"
	"net/netip"
	"strings"
	"time"

	"github.com/yourorg/mycloud/internal/domain"
	pkgauth "github.com/yourorg/mycloud/pkg/auth"
)

type AcceptInviteCommand struct {
	Token       string
	DisplayName string
	Password    string
	IPAddress   *netip.Addr
}

type AcceptInviteResult struct {
	AccessToken  string
	RefreshToken string
	ExpiresIn    int
	User         *domain.User
}

type AcceptInviteHandler struct {
	adminRepo    domain.AdminRepository
	sessionStore domain.SessionStore
	tokenService pkgauth.Service
	accessTTL    time.Duration
	refreshTTL   time.Duration
}

func NewAcceptInviteHandler(
	adminRepo domain.AdminRepository,
	sessionStore domain.SessionStore,
	tokenService pkgauth.Service,
	accessTTL time.Duration,
	refreshTTL time.Duration,
) *AcceptInviteHandler {
	return &AcceptInviteHandler{
		adminRepo:    adminRepo,
		sessionStore: sessionStore,
		tokenService: tokenService,
		accessTTL:    accessTTL,
		refreshTTL:   refreshTTL,
	}
}

func (h *AcceptInviteHandler) Execute(ctx context.Context, command AcceptInviteCommand) (*AcceptInviteResult, error) {
	token := strings.TrimSpace(command.Token)
	displayName := strings.TrimSpace(command.DisplayName)
	if token == "" || displayName == "" {
		return nil, domain.ErrInvalidInput
	}

	tokenHash := pkgauth.HashInviteToken(token)
	user, err := h.adminRepo.FindInviteByTokenHash(ctx, tokenHash)
	if err != nil {
		if err == domain.ErrNotFound {
			return nil, domain.ErrInvalidToken
		}
		return nil, err
	}
	if user.Active || user.InviteExpiry == nil || !user.InviteExpiry.After(time.Now().UTC()) {
		return nil, domain.ErrInvalidToken
	}
	if !pkgauth.CompareInviteTokenHashes(user.InviteToken, tokenHash) {
		return nil, domain.ErrInvalidToken
	}

	passwordHash, err := pkgauth.HashPassword(command.Password)
	if err != nil {
		return nil, domain.ErrInvalidInput
	}

	now := time.Now().UTC()
	actorID := user.ID
	acceptedUser, err := h.adminRepo.AcceptInvite(ctx, domain.AcceptInviteParams{
		UserID:          user.ID,
		InviteTokenHash: tokenHash,
		DisplayName:     displayName,
		PasswordHash:    passwordHash,
		AcceptedAt:      now,
	}, &domain.AuditLog{
		ActorID:   &actorID,
		Action:    domain.AuditActionAuthInviteAccepted,
		TargetID:  &user.ID,
		Meta:      map[string]any{"email": user.Email},
		IPAddress: command.IPAddress,
		CreatedAt: now,
	})
	if err != nil {
		return nil, err
	}

	accessToken, err := h.tokenService.GenerateAccessToken(acceptedUser.ID, string(acceptedUser.Role))
	if err != nil {
		return nil, err
	}
	refreshToken, err := h.tokenService.GenerateRefreshToken(acceptedUser.ID)
	if err != nil {
		return nil, err
	}
	refreshDetails, err := h.tokenService.ValidateRefreshToken(refreshToken)
	if err != nil {
		return nil, err
	}
	if err := h.sessionStore.StoreRefreshToken(ctx, acceptedUser.ID, refreshDetails.ID, h.refreshTTL); err != nil {
		return nil, err
	}

	return &AcceptInviteResult{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    int(h.accessTTL.Seconds()),
		User:         acceptedUser,
	}, nil
}
