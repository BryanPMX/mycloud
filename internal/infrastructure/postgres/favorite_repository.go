package postgres

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/yourorg/mycloud/internal/domain"
)

type FavoriteRepository struct {
	db *pgxpool.Pool
}

func NewFavoriteRepository(db *pgxpool.Pool) *FavoriteRepository {
	return &FavoriteRepository{db: db}
}

func (r *FavoriteRepository) Create(ctx context.Context, favorite *domain.Favorite) error {
	const query = `
		INSERT INTO favorites (user_id, media_id, created_at)
		VALUES ($1, $2, $3)
		ON CONFLICT (user_id, media_id) DO NOTHING
	`

	_, err := r.db.Exec(ctx, query, favorite.UserID, favorite.MediaID, favorite.CreatedAt)
	return err
}

func (r *FavoriteRepository) Delete(ctx context.Context, userID, mediaID uuid.UUID) error {
	const query = `
		DELETE FROM favorites
		WHERE user_id = $1
		  AND media_id = $2
	`

	_, err := r.db.Exec(ctx, query, userID, mediaID)
	return err
}

func (r *FavoriteRepository) ListMediaIDsByUser(ctx context.Context, userID uuid.UUID, mediaIDs []uuid.UUID) ([]uuid.UUID, error) {
	if len(mediaIDs) == 0 {
		return nil, nil
	}

	const query = `
		SELECT media_id
		FROM favorites
		WHERE user_id = $1
		  AND media_id = ANY($2::uuid[])
	`

	rows, err := r.db.Query(ctx, query, userID, mediaIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	favoriteIDs := make([]uuid.UUID, 0, len(mediaIDs))
	for rows.Next() {
		var mediaID uuid.UUID
		if err := rows.Scan(&mediaID); err != nil {
			return nil, err
		}
		favoriteIDs = append(favoriteIDs, mediaID)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return favoriteIDs, nil
}
