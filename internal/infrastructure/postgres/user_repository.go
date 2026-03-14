package postgres

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/yourorg/mycloud/internal/domain"
)

type UserRepository struct {
	db *pgxpool.Pool
}

func NewUserRepository(db *pgxpool.Pool) *UserRepository {
	return &UserRepository{db: db}
}

type userRow struct {
	ID           uuid.UUID
	Email        string
	DisplayName  string
	AvatarKey    *string
	Role         string
	PasswordHash string
	StorageUsed  int64
	QuotaBytes   int64
	Active       bool
	InviteToken  *string
	InviteExpiry *time.Time
	CreatedAt    time.Time
	UpdatedAt    time.Time
	LastLoginAt  *time.Time
}

func (r *UserRepository) FindByID(ctx context.Context, id uuid.UUID) (*domain.User, error) {
	const query = `
		SELECT id, email, display_name, avatar_key, role, password_hash, storage_used,
		       quota_bytes, active, invite_token, invite_token_expires_at, created_at, updated_at, last_login_at
		FROM users
		WHERE id = $1
	`

	return scanUser(r.db.QueryRow(ctx, query, id))
}

func (r *UserRepository) FindByEmail(ctx context.Context, email string) (*domain.User, error) {
	const query = `
		SELECT id, email, display_name, avatar_key, role, password_hash, storage_used,
		       quota_bytes, active, invite_token, invite_token_expires_at, created_at, updated_at, last_login_at
		FROM users
		WHERE lower(email) = lower($1)
	`

	return scanUser(r.db.QueryRow(ctx, query, strings.TrimSpace(email)))
}

func (r *UserRepository) UpdateLastLogin(ctx context.Context, id uuid.UUID, lastLoginAt time.Time) error {
	const query = `
		UPDATE users
		SET last_login_at = $2, updated_at = now()
		WHERE id = $1
	`

	tag, err := r.db.Exec(ctx, query, id, lastLoginAt.UTC())
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}

	return nil
}

func (r userRow) toDomain() *domain.User {
	avatarKey := ""
	if r.AvatarKey != nil {
		avatarKey = *r.AvatarKey
	}
	inviteToken := ""
	if r.InviteToken != nil {
		inviteToken = *r.InviteToken
	}

	return &domain.User{
		ID:           r.ID,
		Email:        r.Email,
		DisplayName:  r.DisplayName,
		AvatarKey:    avatarKey,
		Role:         domain.UserRole(r.Role),
		PasswordHash: r.PasswordHash,
		StorageUsed:  r.StorageUsed,
		QuotaBytes:   r.QuotaBytes,
		Active:       r.Active,
		InviteToken:  inviteToken,
		InviteExpiry: r.InviteExpiry,
		CreatedAt:    r.CreatedAt,
		UpdatedAt:    r.UpdatedAt,
		LastLoginAt:  r.LastLoginAt,
	}
}

func scanUser(row pgx.Row) (*domain.User, error) {
	record := userRow{}
	if err := row.Scan(
		&record.ID,
		&record.Email,
		&record.DisplayName,
		&record.AvatarKey,
		&record.Role,
		&record.PasswordHash,
		&record.StorageUsed,
		&record.QuotaBytes,
		&record.Active,
		&record.InviteToken,
		&record.InviteExpiry,
		&record.CreatedAt,
		&record.UpdatedAt,
		&record.LastLoginAt,
	); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, domain.ErrNotFound
		}

		return nil, err
	}

	return record.toDomain(), nil
}
