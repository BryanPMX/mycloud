package auth

import (
	"context"
	"time"

	"github.com/yourorg/mycloud/internal/domain"
	pkgauth "github.com/yourorg/mycloud/pkg/auth"
)

type RefreshCommand struct {
	RefreshToken string
}

type RefreshResult struct {
	AccessToken  string
	RefreshToken string
	ExpiresIn    int
	User         *domain.User
}

type RefreshHandler struct {
	userRepo     domain.UserRepository
	sessionStore domain.SessionStore
	tokenService pkgauth.Service
	accessTTL    time.Duration
	refreshTTL   time.Duration
}

func NewRefreshHandler(
	userRepo domain.UserRepository,
	sessionStore domain.SessionStore,
	tokenService pkgauth.Service,
	accessTTL time.Duration,
	refreshTTL time.Duration,
) *RefreshHandler {
	return &RefreshHandler{
		userRepo:     userRepo,
		sessionStore: sessionStore,
		tokenService: tokenService,
		accessTTL:    accessTTL,
		refreshTTL:   refreshTTL,
	}
}

func (h *RefreshHandler) Execute(ctx context.Context, command RefreshCommand) (*RefreshResult, error) {
	if command.RefreshToken == "" {
		return nil, domain.ErrMissingToken
	}

	claims, err := h.tokenService.ValidateRefreshToken(command.RefreshToken)
	if err != nil {
		return nil, domain.ErrInvalidToken
	}

	valid, err := h.sessionStore.ValidateRefreshToken(ctx, claims.UserID, claims.ID)
	if err != nil {
		return nil, err
	}
	if !valid {
		return nil, domain.ErrInactiveSession
	}

	user, err := h.userRepo.FindByID(ctx, claims.UserID)
	if err != nil {
		return nil, err
	}
	if !user.Active {
		return nil, domain.ErrUnauthorized
	}

	if err := h.sessionStore.RevokeRefreshToken(ctx, claims.UserID, claims.ID); err != nil {
		return nil, err
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

	return &RefreshResult{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    int(h.accessTTL.Seconds()),
		User:         user,
	}, nil
}
