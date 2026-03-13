package postgres

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgconn"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/yourorg/mycloud/internal/domain"
)

type ShareRepository struct {
	db *pgxpool.Pool
}

func NewShareRepository(db *pgxpool.Pool) *ShareRepository {
	return &ShareRepository{db: db}
}

func (r *ShareRepository) Create(ctx context.Context, share *domain.Share) error {
	const query = `
		INSERT INTO shares (id, album_id, shared_by, shared_with, permission, expires_at, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`

	_, err := r.db.Exec(ctx, query,
		share.ID,
		share.AlbumID,
		share.SharedBy,
		share.SharedWith,
		share.Permission,
		share.ExpiresAt,
		share.CreatedAt,
	)
	if err == nil {
		return nil
	}

	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		return domain.ErrConflict
	}

	return err
}

func (r *ShareRepository) FindByID(ctx context.Context, id uuid.UUID) (*domain.Share, error) {
	const query = `
		SELECT s.id, s.album_id, s.shared_by, s.shared_with, s.permission, s.expires_at, s.created_at,
		       u.display_name, u.avatar_key
		FROM shares s
		LEFT JOIN users u ON u.id = s.shared_with
		WHERE s.id = $1
	`

	row := shareRow{}
	if err := r.db.QueryRow(ctx, query, id).Scan(
		&row.ID,
		&row.AlbumID,
		&row.SharedBy,
		&row.SharedWith,
		&row.Permission,
		&row.ExpiresAt,
		&row.CreatedAt,
		&row.RecipientDisplayName,
		&row.RecipientAvatarKey,
	); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, domain.ErrNotFound
		}

		return nil, err
	}

	return row.toDomain(), nil
}

func (r *ShareRepository) ListActiveByAlbum(ctx context.Context, albumID uuid.UUID) ([]*domain.Share, error) {
	const query = `
		SELECT s.id, s.album_id, s.shared_by, s.shared_with, s.permission, s.expires_at, s.created_at,
		       u.display_name, u.avatar_key
		FROM shares s
		LEFT JOIN users u ON u.id = s.shared_with
		WHERE s.album_id = $1
		  AND (s.expires_at IS NULL OR s.expires_at > now())
		ORDER BY s.created_at DESC, s.id DESC
	`

	rows, err := r.db.Query(ctx, query, albumID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	shares := make([]*domain.Share, 0)
	for rows.Next() {
		row := shareRow{}
		if err := rows.Scan(
			&row.ID,
			&row.AlbumID,
			&row.SharedBy,
			&row.SharedWith,
			&row.Permission,
			&row.ExpiresAt,
			&row.CreatedAt,
			&row.RecipientDisplayName,
			&row.RecipientAvatarKey,
		); err != nil {
			return nil, err
		}

		shares = append(shares, row.toDomain())
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return shares, nil
}

func (r *ShareRepository) Delete(ctx context.Context, id uuid.UUID) error {
	const query = `
		DELETE FROM shares
		WHERE id = $1
	`

	tag, err := r.db.Exec(ctx, query, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}

	return nil
}

type shareRow struct {
	ID                   uuid.UUID
	AlbumID              uuid.UUID
	SharedBy             uuid.UUID
	SharedWith           uuid.UUID
	Permission           string
	ExpiresAt            *time.Time
	CreatedAt            time.Time
	RecipientDisplayName *string
	RecipientAvatarKey   *string
}

func (r shareRow) toDomain() *domain.Share {
	var recipient *domain.ShareRecipient
	switch {
	case r.SharedWith == uuid.Nil:
		recipient = &domain.ShareRecipient{
			ID:          uuid.Nil,
			DisplayName: "Entire family",
		}
	case r.RecipientDisplayName != nil:
		avatarKey := ""
		if r.RecipientAvatarKey != nil {
			avatarKey = *r.RecipientAvatarKey
		}
		recipient = &domain.ShareRecipient{
			ID:          r.SharedWith,
			DisplayName: *r.RecipientDisplayName,
			AvatarKey:   avatarKey,
		}
	}

	return &domain.Share{
		ID:         r.ID,
		AlbumID:    r.AlbumID,
		SharedBy:   r.SharedBy,
		SharedWith: r.SharedWith,
		Recipient:  recipient,
		Permission: domain.Permission(r.Permission),
		ExpiresAt:  r.ExpiresAt,
		CreatedAt:  r.CreatedAt,
	}
}
