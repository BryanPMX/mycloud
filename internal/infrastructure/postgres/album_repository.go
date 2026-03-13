package postgres

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/yourorg/mycloud/internal/domain"
)

type AlbumRepository struct {
	db *pgxpool.Pool
}

func NewAlbumRepository(db *pgxpool.Pool) *AlbumRepository {
	return &AlbumRepository{db: db}
}

func (r *AlbumRepository) Create(ctx context.Context, album *domain.Album) error {
	const query = `
		INSERT INTO albums (id, owner_id, name, description, cover_media_id, media_count, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
	`

	_, err := r.db.Exec(ctx, query,
		album.ID,
		album.OwnerID,
		album.Name,
		album.Description,
		album.CoverMediaID,
		album.MediaCount,
		album.CreatedAt,
		album.UpdatedAt,
	)
	return err
}

func (r *AlbumRepository) FindByID(ctx context.Context, id uuid.UUID) (*domain.Album, error) {
	const query = `
		SELECT id, owner_id, name, description, cover_media_id, media_count, created_at, updated_at
		FROM albums
		WHERE id = $1
	`

	row := albumRow{}
	if err := r.db.QueryRow(ctx, query, id).Scan(
		&row.ID,
		&row.OwnerID,
		&row.Name,
		&row.Description,
		&row.CoverMediaID,
		&row.MediaCount,
		&row.CreatedAt,
		&row.UpdatedAt,
	); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, domain.ErrNotFound
		}

		return nil, err
	}

	return row.toDomain(), nil
}

func (r *AlbumRepository) ListOwnedByUser(ctx context.Context, userID uuid.UUID) ([]*domain.Album, error) {
	const query = `
		SELECT id, owner_id, name, description, cover_media_id, media_count, created_at, updated_at
		FROM albums
		WHERE owner_id = $1
		ORDER BY created_at DESC, id DESC
	`

	return r.listAlbums(ctx, query, userID)
}

func (r *AlbumRepository) ListSharedWithUser(ctx context.Context, userID uuid.UUID) ([]*domain.Album, error) {
	const query = `
		SELECT a.id, a.owner_id, a.name, a.description, a.cover_media_id, a.media_count, a.created_at, a.updated_at
		FROM albums a
		WHERE a.owner_id <> $1
		  AND EXISTS (
		    SELECT 1
		    FROM shares s
		    WHERE s.album_id = a.id
		      AND s.shared_with IN ($1, $2)
		      AND (s.expires_at IS NULL OR s.expires_at > now())
		  )
		ORDER BY a.created_at DESC, a.id DESC
	`

	return r.listAlbums(ctx, query, userID, uuid.Nil)
}

func (r *AlbumRepository) AddMedia(ctx context.Context, albumID, mediaID, addedBy uuid.UUID) (bool, error) {
	const query = `
		INSERT INTO album_media (album_id, media_id, added_by)
		VALUES ($1, $2, $3)
		ON CONFLICT (album_id, media_id) DO NOTHING
	`

	tag, err := r.db.Exec(ctx, query, albumID, mediaID, addedBy)
	if err != nil {
		return false, err
	}

	return tag.RowsAffected() == 1, nil
}

func (r *AlbumRepository) RemoveMedia(ctx context.Context, albumID, mediaID uuid.UUID) error {
	const query = `
		DELETE FROM album_media
		WHERE album_id = $1
		  AND media_id = $2
	`

	tag, err := r.db.Exec(ctx, query, albumID, mediaID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}

	return nil
}

func (r *AlbumRepository) listAlbums(ctx context.Context, query string, args ...any) ([]*domain.Album, error) {
	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	albums := make([]*domain.Album, 0)
	for rows.Next() {
		row := albumRow{}
		if err := rows.Scan(
			&row.ID,
			&row.OwnerID,
			&row.Name,
			&row.Description,
			&row.CoverMediaID,
			&row.MediaCount,
			&row.CreatedAt,
			&row.UpdatedAt,
		); err != nil {
			return nil, err
		}

		albums = append(albums, row.toDomain())
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return albums, nil
}

type albumRow struct {
	ID           uuid.UUID
	OwnerID      uuid.UUID
	Name         string
	Description  string
	CoverMediaID *uuid.UUID
	MediaCount   int
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

func (r albumRow) toDomain() *domain.Album {
	return &domain.Album{
		ID:           r.ID,
		OwnerID:      r.OwnerID,
		Name:         r.Name,
		Description:  r.Description,
		CoverMediaID: r.CoverMediaID,
		MediaCount:   r.MediaCount,
		CreatedAt:    r.CreatedAt,
		UpdatedAt:    r.UpdatedAt,
	}
}
