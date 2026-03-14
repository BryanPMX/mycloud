package auth

import (
	"context"
	"strings"
	"time"

	"github.com/yourorg/mycloud/internal/domain"
	pkgauth "github.com/yourorg/mycloud/pkg/auth"
)

const dummyPasswordHash = "$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy"

type LoginCommand struct {
	Email    string
	Password string
}

type LoginResult struct {
	AccessToken  string
	RefreshToken string
	ExpiresIn    int
	User         *domain.User
}

type LoginHandler struct {
	userRepo     domain.UserRepository
	sessionStore domain.SessionStore
	tokenService pkgauth.Service
	accessTTL    time.Duration
	refreshTTL   time.Duration
}

func NewLoginHandler(
	userRepo domain.UserRepository,
	sessionStore domain.SessionStore,
	tokenService pkgauth.Service,
	accessTTL time.Duration,
	refreshTTL time.Duration,
) *LoginHandler {
	return &LoginHandler{
		userRepo:     userRepo,
		sessionStore: sessionStore,
		tokenService: tokenService,
		accessTTL:    accessTTL,
		refreshTTL:   refreshTTL,
	}
}

func (h *LoginHandler) Execute(ctx context.Context, command LoginCommand) (*LoginResult, error) {
	user, err := h.userRepo.FindByEmail(ctx, strings.TrimSpace(command.Email))
	if err != nil {
		if err == domain.ErrNotFound {
			burnPasswordCheck(command.Password)
			return nil, domain.ErrInvalidCredentials
		}
		return nil, err
	}

	if !pkgauth.CheckPassword(user.PasswordHash, command.Password) || !user.Active {
		return nil, domain.ErrInvalidCredentials
	}

	accessToken, err := h.tokenService.GenerateAccessToken(user.ID, string(user.Role))
	if err != nil {
		return nil, err
	}
	refreshToken, err := h.tokenService.GenerateRefreshToken(user.ID)
	if err != nil {
		return nil, err
	}

	refreshDetails, err := h.tokenService.ValidateRefreshToken(refreshToken)
	if err != nil {
		return nil, err
	}
	if err := h.sessionStore.StoreRefreshToken(ctx, user.ID, refreshDetails.ID, h.refreshTTL); err != nil {
		return nil, err
	}

	now := time.Now().UTC()
	user.LastLoginAt = &now
	_ = h.userRepo.UpdateLastLogin(ctx, user.ID, now)

	return &LoginResult{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    int(h.accessTTL.Seconds()),
		User:         user,
	}, nil
}

func burnPasswordCheck(password string) {
	_ = pkgauth.CheckPassword(dummyPasswordHash, password)
}
