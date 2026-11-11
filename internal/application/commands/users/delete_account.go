package users

import (
	"context"
	"github.com/google/uuid"
	"github.com/yourorg/mycloud/internal/domain"
	pkgauth "github.com/yourorg/mycloud/pkg/auth"
)

type AccountDeletionRepository interface {
	DeleteAccount(context.Context, uuid.UUID, string) error
}
type DeleteAccountHandler struct {
	users    domain.UserRepository
	accounts AccountDeletionRepository
	sessions domain.SessionStore
}

func NewDeleteAccountHandler(users domain.UserRepository, accounts AccountDeletionRepository, sessions domain.SessionStore) *DeleteAccountHandler {
	return &DeleteAccountHandler{users: users, accounts: accounts, sessions: sessions}
}
func (h *DeleteAccountHandler) Execute(ctx context.Context, id uuid.UUID, password string) error {
	user, err := h.users.FindByID(ctx, id)
	if err != nil {
		return err
	}
	if !user.Active || !pkgauth.CheckPassword(user.PasswordHash, password) {
		return domain.ErrInvalidCredentials
	}
	if err = h.accounts.DeleteAccount(ctx, id, user.PasswordHash); err != nil {
		return err
	}
	// Database active=false immediately rejects access and refresh even if Redis is down.
	_ = h.sessions.RevokeAllForUser(ctx, id)
	return nil
}
