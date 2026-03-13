package auth

import (
	"context"

	"github.com/yourorg/mycloud/internal/domain"
	pkgauth "github.com/yourorg/mycloud/pkg/auth"
)

type LogoutCommand struct {
	RefreshToken string
}

type LogoutHandler struct {
	sessionStore domain.SessionStore
	tokenService pkgauth.Service
}

func NewLogoutHandler(sessionStore domain.SessionStore, tokenService pkgauth.Service) *LogoutHandler {
	return &LogoutHandler{
		sessionStore: sessionStore,
		tokenService: tokenService,
	}
}

func (h *LogoutHandler) Execute(ctx context.Context, command LogoutCommand) error {
	if command.RefreshToken == "" {
		return nil
	}

	claims, err := h.tokenService.ValidateRefreshToken(command.RefreshToken)
	if err != nil {
		return nil
	}

	return h.sessionStore.RevokeRefreshToken(ctx, claims.UserID, claims.ID)
}
