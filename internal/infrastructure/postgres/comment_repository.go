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

type CommentRepository struct {
	db *pgxpool.Pool
}

func NewCommentRepository(db *pgxpool.Pool) *CommentRepository {
	return &CommentRepository{db: db}
}

func (r *CommentRepository) Create(ctx context.Context, comment *domain.Comment) error {
	const query = `
		INSERT INTO comments (id, media_id, user_id, body, created_at, deleted_at)
		VALUES ($1, $2, $3, $4, $5, $6)
	`

	_, err := r.db.Exec(ctx, query,
		comment.ID,
		comment.MediaID,
		comment.UserID,
		comment.Body,
		comment.CreatedAt,
		comment.DeletedAt,
	)
	return err
}

func (r *CommentRepository) FindByID(ctx context.Context, id uuid.UUID) (*domain.Comment, error) {
	const query = `
		SELECT c.id, c.media_id, c.user_id, c.body, c.created_at, c.deleted_at,
		       u.display_name, u.avatar_key
		FROM comments c
		JOIN users u ON u.id = c.user_id
		WHERE c.id = $1
		  AND c.deleted_at IS NULL
	`

	row := commentRow{}
	if err := r.db.QueryRow(ctx, query, id).Scan(
		&row.ID,
		&row.MediaID,
		&row.UserID,
		&row.Body,
		&row.CreatedAt,
		&row.DeletedAt,
		&row.AuthorDisplayName,
		&row.AuthorAvatarKey,
	); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, domain.ErrNotFound
		}

		return nil, err
	}

	return row.toDomain(), nil
}

func (r *CommentRepository) ListByMedia(ctx context.Context, mediaID uuid.UUID) ([]*domain.Comment, error) {
	const query = `
		SELECT c.id, c.media_id, c.user_id, c.body, c.created_at, c.deleted_at,
		       u.display_name, u.avatar_key
		FROM comments c
		JOIN users u ON u.id = c.user_id
		WHERE c.media_id = $1
		  AND c.deleted_at IS NULL
		ORDER BY c.created_at ASC, c.id ASC
	`

	rows, err := r.db.Query(ctx, query, mediaID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	comments := make([]*domain.Comment, 0)
	for rows.Next() {
		row := commentRow{}
		if err := rows.Scan(
			&row.ID,
			&row.MediaID,
			&row.UserID,
			&row.Body,
			&row.CreatedAt,
			&row.DeletedAt,
			&row.AuthorDisplayName,
			&row.AuthorAvatarKey,
		); err != nil {
			return nil, err
		}

		comments = append(comments, row.toDomain())
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return comments, nil
}

func (r *CommentRepository) SoftDelete(ctx context.Context, id uuid.UUID, deletedAt time.Time) error {
	const query = `
		UPDATE comments
		SET deleted_at = $2
		WHERE id = $1
		  AND deleted_at IS NULL
	`

	tag, err := r.db.Exec(ctx, query, id, deletedAt)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}

	return nil
}

type commentRow struct {
	ID                uuid.UUID
	MediaID           uuid.UUID
	UserID            uuid.UUID
	Body              string
	CreatedAt         time.Time
	DeletedAt         *time.Time
	AuthorDisplayName string
	AuthorAvatarKey   *string
}

func (r commentRow) toDomain() *domain.Comment {
	avatarKey := ""
	if r.AuthorAvatarKey != nil {
		avatarKey = *r.AuthorAvatarKey
	}

	return &domain.Comment{
		ID:      r.ID,
		MediaID: r.MediaID,
		UserID:  r.UserID,
		Author: domain.CommentAuthor{
			ID:          r.UserID,
			DisplayName: r.AuthorDisplayName,
			AvatarKey:   avatarKey,
		},
		Body:      r.Body,
		CreatedAt: r.CreatedAt,
		DeletedAt: r.DeletedAt,
	}
}
