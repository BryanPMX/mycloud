package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgconn"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/yourorg/mycloud/internal/domain"
	"github.com/yourorg/mycloud/pkg/pagination"
)

const mediaSelectColumns = `
	m.id, m.owner_id, m.filename, m.mime_type, m.size_bytes, m.width, m.height,
	m.duration_secs::float8, m.original_key, m.thumb_small_key, m.thumb_medium_key,
	m.thumb_large_key, m.thumb_poster_key, m.status, m.taken_at, m.uploaded_at,
	m.deleted_at, m.metadata
`

type MediaRepository struct {
	db *pgxpool.Pool
}

func NewMediaRepository(db *pgxpool.Pool) *MediaRepository {
	return &MediaRepository{db: db}
}

func (r *MediaRepository) Create(ctx context.Context, media *domain.Media) error {
	metadata, err := json.Marshal(media.Metadata)
	if err != nil {
		return err
	}

	const query = `
		INSERT INTO media (
			id, owner_id, filename, mime_type, size_bytes, width, height, duration_secs,
			original_key, thumb_small_key, thumb_medium_key, thumb_large_key, thumb_poster_key,
			status, taken_at, uploaded_at, deleted_at, metadata
		) VALUES (
			$1, $2, $3, $4, $5, NULLIF($6, 0), NULLIF($7, 0), NULLIF($8, 0),
			$9, NULLIF($10, ''), NULLIF($11, ''), NULLIF($12, ''), NULLIF($13, ''),
			$14, $15, $16, $17, $18
		)
	`

	_, err = r.db.Exec(ctx, query,
		media.ID,
		media.OwnerID,
		media.Filename,
		media.MimeType,
		media.SizeBytes,
		media.Width,
		media.Height,
		media.DurationSecs,
		media.OriginalKey,
		media.ThumbKeys.Small,
		media.ThumbKeys.Medium,
		media.ThumbKeys.Large,
		media.ThumbKeys.Poster,
		media.Status,
		media.TakenAt,
		media.UploadedAt,
		media.DeletedAt,
		metadata,
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

func (r *MediaRepository) FindByID(ctx context.Context, id uuid.UUID) (*domain.Media, error) {
	return r.findOne(ctx, `
		SELECT `+mediaSelectColumns+`
		FROM media m
		WHERE m.id = $1
		  AND m.deleted_at IS NULL
	`, id)
}

func (r *MediaRepository) FindByIDIncludingDeleted(ctx context.Context, id uuid.UUID) (*domain.Media, error) {
	return r.findOne(ctx, `
		SELECT `+mediaSelectColumns+`
		FROM media m
		WHERE m.id = $1
	`, id)
}

func (r *MediaRepository) FindOwnedByUserIncludingDeleted(ctx context.Context, id, userID uuid.UUID) (*domain.Media, error) {
	return r.findOne(ctx, `
		SELECT `+mediaSelectColumns+`
		FROM media m
		WHERE m.id = $1
		  AND m.owner_id = $2
	`, id, userID)
}

func (r *MediaRepository) FindByIDForUser(ctx context.Context, id, userID uuid.UUID) (*domain.Media, error) {
	return r.findOne(ctx, `
		SELECT `+mediaSelectColumns+`
		FROM media m
		WHERE m.id = $1
		  AND m.deleted_at IS NULL
		  AND (
		    m.owner_id = $2
		    OR EXISTS (
		      SELECT 1
		      FROM album_media am
		      JOIN shares s ON s.album_id = am.album_id
		      WHERE am.media_id = m.id
		        AND s.shared_with IN ($2, $3)
		        AND (s.expires_at IS NULL OR s.expires_at > now())
		    )
		  )
	`, id, userID, uuid.Nil)
}

func (r *MediaRepository) ListVisibleToUser(ctx context.Context, userID uuid.UUID, opts domain.ListMediaOptions) (domain.MediaPage, error) {
	limit, cursorTime, cursorID, err := decodePageCursor(opts.Cursor, opts.Limit)
	if err != nil {
		return domain.MediaPage{}, err
	}

	const countQuery = `
		SELECT count(*)
		FROM media m
		WHERE m.deleted_at IS NULL
		  AND (
		    m.owner_id = $1
		    OR EXISTS (
		      SELECT 1
		      FROM album_media am
		      JOIN shares s ON s.album_id = am.album_id
		      WHERE am.media_id = m.id
		        AND s.shared_with IN ($1, $2)
		        AND (s.expires_at IS NULL OR s.expires_at > now())
		    )
		  )
		  AND ($3::bool = false OR EXISTS (
		    SELECT 1
		    FROM favorites f
		    WHERE f.user_id = $1
		      AND f.media_id = m.id
		  ))
	`

	var total int
	if err := r.db.QueryRow(ctx, countQuery, userID, uuid.Nil, opts.FavoritesOnly).Scan(&total); err != nil {
		return domain.MediaPage{}, err
	}

	const listQuery = `
		SELECT ` + mediaSelectColumns + `
		FROM media m
		WHERE m.deleted_at IS NULL
		  AND (
		    m.owner_id = $1
		    OR EXISTS (
		      SELECT 1
		      FROM album_media am
		      JOIN shares s ON s.album_id = am.album_id
		      WHERE am.media_id = m.id
		        AND s.shared_with IN ($1, $2)
		        AND (s.expires_at IS NULL OR s.expires_at > now())
		    )
		  )
		  AND ($3::bool = false OR EXISTS (
		    SELECT 1
		    FROM favorites f
		    WHERE f.user_id = $1
		      AND f.media_id = m.id
		  ))
		  AND ($4::timestamptz IS NULL OR $5::uuid IS NULL OR (m.uploaded_at, m.id) < ($4, $5))
		ORDER BY m.uploaded_at DESC, m.id DESC
		LIMIT $6
	`

	rows, err := r.db.Query(ctx, listQuery, userID, uuid.Nil, opts.FavoritesOnly, cursorTime, cursorID, limit+1)
	if err != nil {
		return domain.MediaPage{}, err
	}

	return r.readMediaPage(rows, limit, func(item *domain.Media) (string, error) {
		return pagination.EncodeTimeUUID(item.UploadedAt, item.ID)
	}, total)
}

func (r *MediaRepository) SearchVisibleToUser(ctx context.Context, userID uuid.UUID, opts domain.SearchMediaOptions) (domain.MediaPage, error) {
	limit, cursorTime, cursorID, err := decodePageCursor(opts.Cursor, opts.Limit)
	if err != nil {
		return domain.MediaPage{}, err
	}

	searchQuery := strings.TrimSpace(opts.Query)
	if searchQuery == "" {
		return domain.MediaPage{}, domain.ErrInvalidInput
	}

	const countQuery = `
		SELECT count(*)
		FROM media m
		WHERE m.deleted_at IS NULL
		  AND (
		    m.owner_id = $1
		    OR EXISTS (
		      SELECT 1
		      FROM album_media am
		      JOIN shares s ON s.album_id = am.album_id
		      WHERE am.media_id = m.id
		        AND s.shared_with IN ($1, $2)
		        AND (s.expires_at IS NULL OR s.expires_at > now())
		    )
		  )
		  AND m.search_vector @@ plainto_tsquery('english', $3)
	`

	var total int
	if err := r.db.QueryRow(ctx, countQuery, userID, uuid.Nil, searchQuery).Scan(&total); err != nil {
		return domain.MediaPage{}, err
	}

	const listQuery = `
		SELECT ` + mediaSelectColumns + `
		FROM media m
		WHERE m.deleted_at IS NULL
		  AND (
		    m.owner_id = $1
		    OR EXISTS (
		      SELECT 1
		      FROM album_media am
		      JOIN shares s ON s.album_id = am.album_id
		      WHERE am.media_id = m.id
		        AND s.shared_with IN ($1, $2)
		        AND (s.expires_at IS NULL OR s.expires_at > now())
		    )
		  )
		  AND m.search_vector @@ plainto_tsquery('english', $3)
		  AND ($4::timestamptz IS NULL OR $5::uuid IS NULL OR (m.uploaded_at, m.id) < ($4, $5))
		ORDER BY m.uploaded_at DESC, m.id DESC
		LIMIT $6
	`

	rows, err := r.db.Query(ctx, listQuery, userID, uuid.Nil, searchQuery, cursorTime, cursorID, limit+1)
	if err != nil {
		return domain.MediaPage{}, err
	}

	return r.readMediaPage(rows, limit, func(item *domain.Media) (string, error) {
		return pagination.EncodeTimeUUID(item.UploadedAt, item.ID)
	}, total)
}

func (r *MediaRepository) ListTrashedOwnedByUser(ctx context.Context, userID uuid.UUID, opts domain.ListTrashOptions) (domain.MediaPage, error) {
	limit, cursorTime, cursorID, err := decodePageCursor(opts.Cursor, opts.Limit)
	if err != nil {
		return domain.MediaPage{}, err
	}

	const countQuery = `
		SELECT count(*)
		FROM media m
		WHERE m.owner_id = $1
		  AND m.deleted_at IS NOT NULL
	`

	var total int
	if err := r.db.QueryRow(ctx, countQuery, userID).Scan(&total); err != nil {
		return domain.MediaPage{}, err
	}

	const listQuery = `
		SELECT ` + mediaSelectColumns + `
		FROM media m
		WHERE m.owner_id = $1
		  AND m.deleted_at IS NOT NULL
		  AND ($2::timestamptz IS NULL OR $3::uuid IS NULL OR (m.deleted_at, m.id) < ($2, $3))
		ORDER BY m.deleted_at DESC, m.id DESC
		LIMIT $4
	`

	rows, err := r.db.Query(ctx, listQuery, userID, cursorTime, cursorID, limit+1)
	if err != nil {
		return domain.MediaPage{}, err
	}

	return r.readMediaPage(rows, limit, func(item *domain.Media) (string, error) {
		if item.DeletedAt == nil {
			return "", domain.ErrNotFound
		}
		return pagination.EncodeTimeUUID(item.DeletedAt.UTC(), item.ID)
	}, total)
}

func (r *MediaRepository) ListByAlbum(ctx context.Context, albumID uuid.UUID, opts domain.ListMediaOptions) (domain.MediaPage, error) {
	limit, cursorTime, cursorID, err := decodePageCursor(opts.Cursor, opts.Limit)
	if err != nil {
		return domain.MediaPage{}, err
	}

	const countQuery = `
		SELECT count(*)
		FROM media m
		JOIN album_media am ON am.media_id = m.id
		WHERE am.album_id = $1
		  AND m.deleted_at IS NULL
	`

	var total int
	if err := r.db.QueryRow(ctx, countQuery, albumID).Scan(&total); err != nil {
		return domain.MediaPage{}, err
	}

	const listQuery = `
		SELECT ` + mediaSelectColumns + `
		FROM media m
		JOIN album_media am ON am.media_id = m.id
		WHERE am.album_id = $1
		  AND m.deleted_at IS NULL
		  AND ($2::timestamptz IS NULL OR $3::uuid IS NULL OR (m.uploaded_at, m.id) < ($2, $3))
		ORDER BY m.uploaded_at DESC, m.id DESC
		LIMIT $4
	`

	rows, err := r.db.Query(ctx, listQuery, albumID, cursorTime, cursorID, limit+1)
	if err != nil {
		return domain.MediaPage{}, err
	}

	return r.readMediaPage(rows, limit, func(item *domain.Media) (string, error) {
		return pagination.EncodeTimeUUID(item.UploadedAt, item.ID)
	}, total)
}

func (r *MediaRepository) SoftDelete(ctx context.Context, id uuid.UUID, deletedAt time.Time) error {
	const query = `
		UPDATE media
		SET deleted_at = $2
		WHERE id = $1
		  AND deleted_at IS NULL
	`

	tag, err := r.db.Exec(ctx, query, id, deletedAt.UTC())
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}

	return nil
}

func (r *MediaRepository) Restore(ctx context.Context, id uuid.UUID) error {
	const query = `
		UPDATE media
		SET deleted_at = NULL
		WHERE id = $1
		  AND deleted_at IS NOT NULL
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

func (r *MediaRepository) HardDelete(ctx context.Context, id uuid.UUID) error {
	const query = `
		DELETE FROM media
		WHERE id = $1
		  AND deleted_at IS NOT NULL
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

func (r *MediaRepository) HardDeleteAllTrashedOwnedByUser(ctx context.Context, ownerID uuid.UUID) ([]*domain.Media, error) {
	rows, err := r.db.Query(ctx, `
		DELETE FROM media AS m
		WHERE owner_id = $1
		  AND deleted_at IS NOT NULL
		RETURNING `+mediaSelectColumns, ownerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	return scanMediaRows(rows)
}

func (r *MediaRepository) UpdateStatus(ctx context.Context, id uuid.UUID, status domain.MediaStatus) error {
	const query = `
		UPDATE media
		SET status = $2
		WHERE id = $1
		  AND deleted_at IS NULL
	`

	tag, err := r.db.Exec(ctx, query, id, status)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}

	return nil
}

func (r *MediaRepository) ApplyProcessingResult(ctx context.Context, id uuid.UUID, result domain.MediaProcessingResult) error {
	metadata, err := json.Marshal(result.Metadata)
	if err != nil {
		return err
	}

	const query = `
		UPDATE media
		SET status = $2,
		    width = CASE WHEN $3 > 0 THEN $3 ELSE width END,
		    height = CASE WHEN $4 > 0 THEN $4 ELSE height END,
		    duration_secs = CASE WHEN $5 > 0 THEN $5 ELSE duration_secs END,
		    thumb_small_key = NULLIF($6, ''),
		    thumb_medium_key = NULLIF($7, ''),
		    thumb_large_key = NULLIF($8, ''),
		    thumb_poster_key = NULLIF($9, ''),
		    metadata = $10,
		    taken_at = COALESCE($11, taken_at)
		WHERE id = $1
		  AND deleted_at IS NULL
	`

	tag, err := r.db.Exec(ctx, query,
		id,
		domain.MediaStatusReady,
		result.Width,
		result.Height,
		result.DurationSecs,
		result.ThumbKeys.Small,
		result.ThumbKeys.Medium,
		result.ThumbKeys.Large,
		result.ThumbKeys.Poster,
		metadata,
		result.TakenAt,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}

	return nil
}

func (r *MediaRepository) DeleteExpiredTrash(ctx context.Context, before time.Time) ([]*domain.Media, error) {
	const query = `
		DELETE FROM media
		WHERE deleted_at IS NOT NULL
		  AND deleted_at <= $1
		RETURNING id, owner_id, filename, mime_type, size_bytes, width, height,
		          duration_secs::float8, original_key, thumb_small_key, thumb_medium_key,
		          thumb_large_key, thumb_poster_key, status, taken_at, uploaded_at,
		          deleted_at, metadata
	`
	rows, err := r.db.Query(ctx, query, before)
	if err != nil {
		return nil, err
	}

	return scanMediaRows(rows)
}

type mediaRow struct {
	ID             uuid.UUID
	OwnerID        uuid.UUID
	Filename       string
	MimeType       string
	SizeBytes      int64
	Width          *int
	Height         *int
	DurationSecs   *float64
	OriginalKey    string
	ThumbSmallKey  *string
	ThumbMediumKey *string
	ThumbLargeKey  *string
	ThumbPosterKey *string
	Status         string
	TakenAt        *time.Time
	UploadedAt     time.Time
	DeletedAt      *time.Time
	Metadata       []byte
}

func (r mediaRow) toDomain() (*domain.Media, error) {
	var metadata map[string]any
	if len(r.Metadata) > 0 {
		if err := json.Unmarshal(r.Metadata, &metadata); err != nil {
			return nil, err
		}
	}
	if metadata == nil {
		metadata = map[string]any{}
	}

	return &domain.Media{
		ID:           r.ID,
		OwnerID:      r.OwnerID,
		Filename:     r.Filename,
		MimeType:     r.MimeType,
		SizeBytes:    r.SizeBytes,
		Width:        derefInt(r.Width),
		Height:       derefInt(r.Height),
		DurationSecs: derefFloat64(r.DurationSecs),
		OriginalKey:  r.OriginalKey,
		ThumbKeys: domain.ThumbKeys{
			Small:  derefString(r.ThumbSmallKey),
			Medium: derefString(r.ThumbMediumKey),
			Large:  derefString(r.ThumbLargeKey),
			Poster: derefString(r.ThumbPosterKey),
		},
		Status:     domain.MediaStatus(r.Status),
		TakenAt:    r.TakenAt,
		UploadedAt: r.UploadedAt,
		DeletedAt:  r.DeletedAt,
		Metadata:   metadata,
	}, nil
}

func (r *MediaRepository) findOne(ctx context.Context, query string, args ...any) (*domain.Media, error) {
	row := mediaRow{}
	if err := r.db.QueryRow(ctx, query, args...).Scan(
		&row.ID,
		&row.OwnerID,
		&row.Filename,
		&row.MimeType,
		&row.SizeBytes,
		&row.Width,
		&row.Height,
		&row.DurationSecs,
		&row.OriginalKey,
		&row.ThumbSmallKey,
		&row.ThumbMediumKey,
		&row.ThumbLargeKey,
		&row.ThumbPosterKey,
		&row.Status,
		&row.TakenAt,
		&row.UploadedAt,
		&row.DeletedAt,
		&row.Metadata,
	); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, domain.ErrNotFound
		}

		return nil, err
	}

	return row.toDomain()
}

func (r *MediaRepository) readMediaPage(
	rows pgx.Rows,
	limit int,
	nextCursor func(*domain.Media) (string, error),
	total int,
) (domain.MediaPage, error) {
	defer rows.Close()

	items, err := scanMediaRows(rows)
	if err != nil {
		return domain.MediaPage{}, err
	}

	cursor := ""
	if len(items) > limit {
		cursor, err = nextCursor(items[limit-1])
		if err != nil {
			return domain.MediaPage{}, err
		}
		items = items[:limit]
	}

	return domain.MediaPage{
		Items:      items,
		NextCursor: cursor,
		Total:      total,
	}, nil
}

func scanMediaRows(rows pgx.Rows) ([]*domain.Media, error) {
	items := make([]*domain.Media, 0)
	for rows.Next() {
		row := mediaRow{}
		if err := rows.Scan(
			&row.ID,
			&row.OwnerID,
			&row.Filename,
			&row.MimeType,
			&row.SizeBytes,
			&row.Width,
			&row.Height,
			&row.DurationSecs,
			&row.OriginalKey,
			&row.ThumbSmallKey,
			&row.ThumbMediumKey,
			&row.ThumbLargeKey,
			&row.ThumbPosterKey,
			&row.Status,
			&row.TakenAt,
			&row.UploadedAt,
			&row.DeletedAt,
			&row.Metadata,
		); err != nil {
			return nil, err
		}

		item, err := row.toDomain()
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return items, nil
}

func decodePageCursor(cursor string, limit int) (int, any, any, error) {
	if limit <= 0 {
		limit = 50
	}
	if limit > 100 {
		limit = 100
	}
	if cursor == "" {
		return limit, nil, nil, nil
	}

	cursorTime, cursorID, err := pagination.DecodeTimeUUID(cursor)
	if err != nil {
		return 0, nil, nil, domain.ErrInvalidInput
	}

	return limit, cursorTime, cursorID, nil
}

func derefInt(value *int) int {
	if value == nil {
		return 0
	}
	return *value
}

func derefFloat64(value *float64) float64 {
	if value == nil {
		return 0
	}
	return *value
}

func derefString(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}
