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

	user, err := h.userRepo.FindByID(ctx, claims.UserID)
	if err != nil {
		return nil, err
	}
	if !user.Active {
		return nil, domain.ErrUnauthorized
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
	rotated, err := h.sessionStore.RotateRefreshToken(ctx, user.ID, claims.ID, refreshDetails.ID, h.refreshTTL)
	if err != nil {
		return nil, err
	}
	if !rotated {
		return nil, domain.ErrInactiveSession
	}

	return &RefreshResult{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    int(h.accessTTL.Seconds()),
		User:         user,
	}, nil
}
