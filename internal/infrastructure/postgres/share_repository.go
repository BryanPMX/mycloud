package postgres

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
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
 INSERT INTO shares(id,album_id,shared_by,shared_with,permission,expires_at,created_at,family_id)
 SELECT $1,$2,$3,$4,$5,$6,$7,CASE WHEN $4::uuid='00000000-0000-0000-0000-000000000000'::uuid
 THEN COALESCE($8::uuid,(SELECT f.id FROM families f JOIN family_memberships m ON m.family_id=f.id WHERE f.legacy AND m.user_id=$3)) ELSE NULL END
 WHERE ($4::uuid<>'00000000-0000-0000-0000-000000000000'::uuid AND users_share_family($3,$4)) OR
 ($4::uuid='00000000-0000-0000-0000-000000000000'::uuid AND EXISTS(SELECT 1 FROM family_memberships m JOIN families f ON f.id=m.family_id
 WHERE m.user_id=$3 AND m.family_id=COALESCE($8::uuid,(SELECT id FROM families WHERE legacy))))
 `
	tag, err := r.db.Exec(ctx, query,
		share.ID,
		share.AlbumID,
		share.SharedBy,
		share.SharedWith,
		share.Permission,
		share.ExpiresAt,
		share.CreatedAt, share.FamilyID,
	)
	if err == nil {
		if tag.RowsAffected() == 0 {
			return domain.ErrForbidden
		}
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
		       u.display_name, u.avatar_key, s.family_id, f.name
		FROM shares s
		LEFT JOIN users u ON u.id = s.shared_with
 LEFT JOIN families f ON f.id=s.family_id
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
		&row.RecipientAvatarKey, &row.FamilyID, &row.FamilyName,
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
		       u.display_name, u.avatar_key, s.family_id, f.name
		FROM shares s
		LEFT JOIN users u ON u.id = s.shared_with
 LEFT JOIN families f ON f.id=s.family_id
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
			&row.RecipientAvatarKey, &row.FamilyID, &row.FamilyName,
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

func (r *ShareRepository) UserCanContribute(ctx context.Context, albumID, userID uuid.UUID) (bool, error) {
	const query = `
		SELECT EXISTS (
			SELECT 1
			FROM shares s JOIN albums a ON a.id=s.album_id
			WHERE album_id = $1
			  AND (shared_with = $2 OR (shared_with = $3 AND users_share_family($2,a.owner_id)))
			  AND permission = $4
			  AND (expires_at IS NULL OR expires_at > now())
		)
	`

	var allowed bool
	if err := r.db.QueryRow(ctx, query, albumID, userID, uuid.Nil, domain.PermissionContribute).Scan(&allowed); err != nil {
		return false, err
	}

	return allowed, nil
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

func (r *ShareRepository) DeleteExpired(ctx context.Context, before time.Time) (int, error) {
	const query = `
		DELETE FROM shares
		WHERE expires_at IS NOT NULL
		  AND expires_at <= $1
	`

	tag, err := r.db.Exec(ctx, query, before)
	if err != nil {
		return 0, err
	}

	return int(tag.RowsAffected()), nil
}

type shareRow struct {
	FamilyID             *uuid.UUID
	FamilyName           *string
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

	if recipient != nil && r.SharedWith == uuid.Nil && r.FamilyName != nil {
		recipient.DisplayName = "Everyone in " + *r.FamilyName
	}
	return &domain.Share{
		FamilyID:   r.FamilyID,
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
