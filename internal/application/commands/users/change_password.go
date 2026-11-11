package users

import (
	"context"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/yourorg/mycloud/internal/domain"
	pkgauth "github.com/yourorg/mycloud/pkg/auth"
)

type PasswordRepository interface {
	ChangePassword(context.Context, uuid.UUID, string, string) error
}

type ChangePasswordHandler struct {
	users     domain.UserRepository
	passwords PasswordRepository
	sessions  domain.SessionStore
}

func NewChangePasswordHandler(users domain.UserRepository, passwords PasswordRepository, sessions domain.SessionStore) *ChangePasswordHandler {
	return &ChangePasswordHandler{users: users, passwords: passwords, sessions: sessions}
}

func (h *ChangePasswordHandler) Execute(ctx context.Context, id uuid.UUID, current, next string) error {
	if id == uuid.Nil || utf8.RuneCountInString(next) < 12 || len(next) > 72 || len(current) > 1024 || current == next {
		return domain.ErrInvalidInput
	}
	user, err := h.users.FindByID(ctx, id)
	if err != nil {
		return err
	}
	if !user.Active || !pkgauth.CheckPassword(user.PasswordHash, current) {
		return domain.ErrInvalidCredentials
	}
	hash, err := pkgauth.HashPassword(next)
	if err != nil {
		return domain.ErrInvalidInput
	}
	if err = h.passwords.ChangePassword(ctx, id, user.PasswordHash, hash); err != nil {
		return err
	}
	// The database version immediately invalidates both access and refresh JWTs,
	// including when Redis is unavailable. Old refresh keys can safely expire.
	_ = h.sessions.RevokeAllForUser(ctx, id)
	return nil
}
