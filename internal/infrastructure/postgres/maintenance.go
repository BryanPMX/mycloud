package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"time"

	"github.com/google/uuid"
	"github.com/yourorg/mycloud/internal/domain"
)

// RecoverJobs treats PostgreSQL as the durable outbox. Re-dispatch is harmless:
// MarkRunning atomically claims queued work, and processing is idempotent.
func (r *JobRepository) RecoverJobs(ctx context.Context) ([]*domain.Job, error) {
	_, err := r.db.Exec(ctx, `UPDATE jobs SET status='failed', completed_at=now(), error='worker lease expired'
 WHERE status='running' AND started_at<now()-interval '12 minutes' AND attempts>=3`)
	if err != nil {
		return nil, err
	}
	_, err = r.db.Exec(ctx, `UPDATE jobs SET status='queued', started_at=NULL, completed_at=NULL
 WHERE attempts<3 AND NOT EXISTS (SELECT 1 FROM jobs active WHERE active.media_id=jobs.media_id AND active.type=jobs.type AND active.id<>jobs.id AND active.status IN ('queued','running')) AND ((status='running' AND started_at<now()-interval '12 minutes')
 OR (status='failed' AND completed_at<now()-interval '1 minute'))`)
	if err != nil {
		return nil, err
	}
	// Repair the crash window between a media INSERT and its job INSERT.
	_, err = r.db.Exec(ctx, `INSERT INTO jobs(media_id,type,status)
 SELECT m.id,'process_media','queued' FROM media m WHERE m.status='pending' AND m.deleted_at IS NULL
 AND NOT EXISTS(SELECT 1 FROM jobs j WHERE j.media_id=m.id AND j.type='process_media') ON CONFLICT DO NOTHING`)
	if err != nil {
		return nil, err
	}
	rows, err := r.db.Query(ctx, `SELECT id FROM jobs WHERE status='queued' ORDER BY created_at LIMIT 100`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var jobs []*domain.Job
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		jobs = append(jobs, &domain.Job{ID: id})
	}
	return jobs, rows.Err()
}

func (r *MediaRepository) DrainDeletions(ctx context.Context, cleaner domain.MediaAssetCleaner) error {
	// A transaction-scoped lock prevents restoration of metadata from being mistaken
	// for completion. All deletes are idempotent and retained until acknowledged.
	rows, err := r.db.Query(ctx, `SELECT media_id,owner_id,charged_bytes,original_key,
 COALESCE(thumb_small_key,''),COALESCE(thumb_medium_key,''),COALESCE(thumb_large_key,''),COALESCE(thumb_poster_key,''),mime_type
 FROM media_deletions WHERE not_before<=now() ORDER BY created_at LIMIT 100`)
	if err != nil {
		return err
	}
	type pending struct {
		media   domain.Media
		charged int64
	}
	var batch []pending
	for rows.Next() {
		var p pending
		if err := rows.Scan(&p.media.ID, &p.media.OwnerID, &p.charged, &p.media.OriginalKey, &p.media.ThumbKeys.Small, &p.media.ThumbKeys.Medium, &p.media.ThumbKeys.Large, &p.media.ThumbKeys.Poster, &p.media.MimeType); err != nil {
			rows.Close()
			return err
		}
		batch = append(batch, p)
	}
	scanErr := rows.Err()
	rows.Close()
	if scanErr != nil {
		return scanErr
	}
	var joined error
	for _, p := range batch {
		if err := cleaner.DeleteMediaAssets(ctx, &p.media); err != nil {
			joined = errors.Join(joined, err)
			continue
		}
		// Both the acknowledgement and accounting adjustment commit together. Multiple
		// sweepers can delete objects, but only one receives the RETURNING quota charge.
		_, err := r.db.Exec(ctx, `WITH acknowledged AS (DELETE FROM media_deletions WHERE media_id=$1 RETURNING owner_id,charged_bytes)
  UPDATE users u SET storage_used=GREATEST(0,u.storage_used-a.charged_bytes) FROM acknowledged a WHERE u.id=a.owner_id`, p.media.ID)
		joined = errors.Join(joined, err)
	}
	return joined
}

func (s *UploadSessionStore) CleanupExpired(ctx context.Context, storage domain.StorageService) error {
	rows, err := s.db.Query(ctx, `SELECT media_id,session,EXISTS(SELECT 1 FROM media m WHERE m.id=s.media_id) FROM upload_sessions s WHERE expires_at<now() LIMIT 100`)
	if err != nil {
		return err
	}
	type expired struct {
		id        uuid.UUID
		session   domain.UploadSession
		completed bool
	}
	var batch []expired
	for rows.Next() {
		var e expired
		var payload []byte
		if err := rows.Scan(&e.id, &payload, &e.completed); err != nil {
			rows.Close()
			return err
		}
		if err := json.Unmarshal(payload, &e.session); err != nil {
			rows.Close()
			return err
		}
		batch = append(batch, e)
	}
	scanErr := rows.Err()
	rows.Close()
	if scanErr != nil {
		return scanErr
	}
	var joined error
	for _, e := range batch {
		if !e.completed {
			if err := storage.AbortUpload(ctx, e.session.ObjectKey, e.session.UploadID); err != nil {
				joined = errors.Join(joined, err)
				continue
			}
			if err := storage.DeleteUpload(ctx, e.session.ObjectKey); err != nil {
				joined = errors.Join(joined, err)
				continue
			}
		}
		joined = errors.Join(joined, s.DeleteUploadSession(ctx, e.id))
	}
	return joined
}

func RunMaintenance(ctx context.Context, jobs *JobRepository, media *MediaRepository, uploads *UploadSessionStore, storage interface {
	domain.StorageService
	domain.MediaAssetCleaner
}, queue domain.JobQueue) {
	tick := time.NewTicker(30 * time.Second)
	defer tick.Stop()
	for {
		cycle, cancel := context.WithTimeout(ctx, 20*time.Second)
		pending, err := jobs.RecoverJobs(cycle)
		if err == nil {
			for _, job := range pending {
				if err = queue.Enqueue(cycle, job); err != nil {
					break
				}
			}
		}
		if err != nil {
			slog.Warn("maintenance_failed", "stage", "dispatch")
		}
		if err := media.DrainDeletions(cycle, storage); err != nil {
			slog.Warn("maintenance_failed", "stage", "object_deletion")
		}
		if avatars, ok := storage.(domain.AvatarStorage); ok {
			_ = media.DrainAvatarDeletions(cycle, avatars)
		}
		if err := uploads.CleanupExpired(cycle, storage); err != nil {
			slog.Warn("maintenance_failed", "stage", "expired_upload")
		}
		cancel()
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
		}
	}
}
