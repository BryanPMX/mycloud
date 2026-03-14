package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/yourorg/mycloud/internal/domain"
)

type JobRepository struct {
	db *pgxpool.Pool
}

func NewJobRepository(db *pgxpool.Pool) *JobRepository {
	return &JobRepository{db: db}
}

func (r *JobRepository) Create(ctx context.Context, job *domain.Job) error {
	payload, err := json.Marshal(job.Payload)
	if err != nil {
		return err
	}

	const query = `
		INSERT INTO jobs (
			id, media_id, type, status, payload, error, attempts, created_at, started_at, completed_at
		) VALUES (
			$1, $2, $3, $4, $5, NULLIF($6, ''), $7, $8, $9, $10
		)
	`

	_, err = r.db.Exec(ctx, query,
		job.ID,
		job.MediaID,
		job.Type,
		job.Status,
		payload,
		job.Error,
		job.Attempts,
		job.CreatedAt,
		job.StartedAt,
		job.CompletedAt,
	)
	return err
}

func (r *JobRepository) FindByID(ctx context.Context, id uuid.UUID) (*domain.Job, error) {
	const query = `
		SELECT id, media_id, type, status, payload, error, attempts, created_at, started_at, completed_at
		FROM jobs
		WHERE id = $1
	`

	row := jobRow{}
	if err := r.db.QueryRow(ctx, query, id).Scan(
		&row.ID,
		&row.MediaID,
		&row.Type,
		&row.Status,
		&row.Payload,
		&row.Error,
		&row.Attempts,
		&row.CreatedAt,
		&row.StartedAt,
		&row.CompletedAt,
	); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, domain.ErrNotFound
		}

		return nil, err
	}

	return row.toDomain()
}

func (r *JobRepository) FindLatestByMediaAndType(ctx context.Context, mediaID uuid.UUID, jobType domain.JobType) (*domain.Job, error) {
	const query = `
		SELECT id, media_id, type, status, payload, error, attempts, created_at, started_at, completed_at
		FROM jobs
		WHERE media_id = $1
		  AND type = $2
		ORDER BY created_at DESC, id DESC
		LIMIT 1
	`

	row := jobRow{}
	if err := r.db.QueryRow(ctx, query, mediaID, jobType).Scan(
		&row.ID,
		&row.MediaID,
		&row.Type,
		&row.Status,
		&row.Payload,
		&row.Error,
		&row.Attempts,
		&row.CreatedAt,
		&row.StartedAt,
		&row.CompletedAt,
	); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, domain.ErrNotFound
		}

		return nil, err
	}

	return row.toDomain()
}

func (r *JobRepository) FindLatestByType(ctx context.Context, jobType domain.JobType) (*domain.Job, error) {
	const query = `
		SELECT id, media_id, type, status, payload, error, attempts, created_at, started_at, completed_at
		FROM jobs
		WHERE type = $1
		ORDER BY created_at DESC, id DESC
		LIMIT 1
	`

	row := jobRow{}
	if err := r.db.QueryRow(ctx, query, jobType).Scan(
		&row.ID,
		&row.MediaID,
		&row.Type,
		&row.Status,
		&row.Payload,
		&row.Error,
		&row.Attempts,
		&row.CreatedAt,
		&row.StartedAt,
		&row.CompletedAt,
	); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, domain.ErrNotFound
		}

		return nil, err
	}

	return row.toDomain()
}

func (r *JobRepository) MarkRunning(ctx context.Context, id uuid.UUID, startedAt time.Time) error {
	const query = `
		UPDATE jobs
		SET status = $2,
		    attempts = attempts + 1,
		    started_at = $3,
		    completed_at = NULL,
		    error = NULL
		WHERE id = $1
	`

	tag, err := r.db.Exec(ctx, query, id, domain.JobStatusRunning, startedAt)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}

	return nil
}

func (r *JobRepository) MarkDone(ctx context.Context, id uuid.UUID, completedAt time.Time) error {
	const query = `
		UPDATE jobs
		SET status = $2,
		    completed_at = $3,
		    error = NULL
		WHERE id = $1
	`

	tag, err := r.db.Exec(ctx, query, id, domain.JobStatusDone, completedAt)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}

	return nil
}

func (r *JobRepository) MarkFailed(ctx context.Context, id uuid.UUID, message string, completedAt time.Time) error {
	const query = `
		UPDATE jobs
		SET status = $2,
		    error = $3,
		    completed_at = $4
		WHERE id = $1
	`

	tag, err := r.db.Exec(ctx, query, id, domain.JobStatusFailed, message, completedAt)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}

	return nil
}

type jobRow struct {
	ID          uuid.UUID
	MediaID     *uuid.UUID
	Type        string
	Status      string
	Payload     []byte
	Error       *string
	Attempts    int
	CreatedAt   time.Time
	StartedAt   *time.Time
	CompletedAt *time.Time
}

func (r jobRow) toDomain() (*domain.Job, error) {
	payload := map[string]any{}
	if len(r.Payload) > 0 {
		if err := json.Unmarshal(r.Payload, &payload); err != nil {
			return nil, err
		}
	}

	job := &domain.Job{
		ID:          r.ID,
		MediaID:     r.MediaID,
		Type:        domain.JobType(r.Type),
		Status:      domain.JobStatus(r.Status),
		Payload:     payload,
		Attempts:    r.Attempts,
		CreatedAt:   r.CreatedAt,
		StartedAt:   r.StartedAt,
		CompletedAt: r.CompletedAt,
	}
	if r.Error != nil {
		job.Error = *r.Error
	}

	return job, nil
}
