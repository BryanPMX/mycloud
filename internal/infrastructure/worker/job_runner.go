package worker

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type JobRunner struct {
	queue       domain.JobQueue
	jobRepo     domain.JobRepository
	mediaRepo   domain.MediaRepository
	storage     domain.StorageService
	scanner     domain.VirusScanner
	keyBuilder  domain.MediaKeyBuilder
	pollTimeout time.Duration
}

func NewJobRunner(
	queue domain.JobQueue,
	jobRepo domain.JobRepository,
	mediaRepo domain.MediaRepository,
	storage domain.StorageService,
	scanner domain.VirusScanner,
	keyBuilder domain.MediaKeyBuilder,
	pollTimeout time.Duration,
) *JobRunner {
	if pollTimeout <= 0 {
		pollTimeout = 5 * time.Second
	}

	return &JobRunner{
		queue:       queue,
		jobRepo:     jobRepo,
		mediaRepo:   mediaRepo,
		storage:     storage,
		scanner:     scanner,
		keyBuilder:  keyBuilder,
		pollTimeout: pollTimeout,
	}
}

func (r *JobRunner) Run(ctx context.Context) {
	for {
		if ctx.Err() != nil {
			return
		}

		job, err := r.queue.Dequeue(ctx, r.pollTimeout)
		if err != nil {
			if errors.Is(err, context.Canceled) {
				return
			}
			continue
		}
		if job == nil {
			continue
		}

		r.process(ctx, job)
	}
}

func (r *JobRunner) process(ctx context.Context, queued *domain.Job) {
	job, err := r.jobRepo.FindByID(ctx, queued.ID)
	if err != nil {
		return
	}
	if job.Status != domain.JobStatusQueued {
		return
	}

	now := time.Now().UTC()
	if err := r.jobRepo.MarkRunning(ctx, job.ID, now); err != nil {
		return
	}

	if job.Type != domain.JobTypeProcessMedia {
		r.failJob(ctx, job.ID, job.MediaID, fmt.Errorf("unsupported job type %q", job.Type))
		return
	}
	if job.MediaID == nil || *job.MediaID == uuid.Nil {
		r.failJob(ctx, job.ID, nil, errors.New("missing media id"))
		return
	}

	media, err := r.mediaRepo.FindByID(ctx, *job.MediaID)
	if err != nil {
		r.failJob(ctx, job.ID, job.MediaID, err)
		return
	}
	if media.Status == domain.MediaStatusReady {
		_ = r.jobRepo.MarkDone(ctx, job.ID, time.Now().UTC())
		return
	}
	if err := r.mediaRepo.UpdateStatus(ctx, media.ID, domain.MediaStatusProcessing); err != nil {
		r.failJob(ctx, job.ID, job.MediaID, err)
		return
	}

	obj, err := r.storage.OpenUpload(ctx, media.OriginalKey)
	if err != nil {
		r.failJob(ctx, job.ID, job.MediaID, err)
		return
	}

	clean, threat, scanErr := r.scanner.ScanReader(ctx, obj)
	_ = obj.Close()
	if scanErr != nil {
		r.failJob(ctx, job.ID, job.MediaID, scanErr)
		return
	}
	if !clean {
		_ = r.storage.DeleteUpload(ctx, media.OriginalKey)
		r.failJob(ctx, job.ID, job.MediaID, fmt.Errorf("virus detected: %s", strings.TrimSpace(threat)))
		return
	}

	if err := r.storage.PromoteUpload(ctx, media.OriginalKey); err != nil {
		r.failJob(ctx, job.ID, job.MediaID, err)
		return
	}
	_ = r.storage.DeleteUpload(ctx, media.OriginalKey)

	result := domain.MediaProcessingResult{
		ThumbKeys: r.keyBuilder.BuildThumbKeys(media.ID, media.MimeType),
		Metadata:  buildProcessingMetadata(media, job.ID, now),
	}
	if err := r.mediaRepo.ApplyProcessingResult(ctx, media.ID, result); err != nil {
		r.failJob(ctx, job.ID, job.MediaID, err)
		return
	}

	_ = r.jobRepo.MarkDone(ctx, job.ID, time.Now().UTC())
}

func (r *JobRunner) failJob(ctx context.Context, jobID uuid.UUID, mediaID *uuid.UUID, err error) {
	if mediaID != nil && *mediaID != uuid.Nil {
		_ = r.mediaRepo.UpdateStatus(ctx, *mediaID, domain.MediaStatusFailed)
	}
	_ = r.jobRepo.MarkFailed(ctx, jobID, err.Error(), time.Now().UTC())
}

func buildProcessingMetadata(media *domain.Media, jobID uuid.UUID, processedAt time.Time) map[string]any {
	metadata := cloneMetadata(media.Metadata)
	metadata["processing"] = map[string]any{
		"job_id":       jobID.String(),
		"processed_at": processedAt,
		"scan_status":  "clean",
	}
	return metadata
}

func cloneMetadata(value map[string]any) map[string]any {
	if len(value) == 0 {
		return map[string]any{}
	}

	cloned := make(map[string]any, len(value))
	for key, item := range value {
		cloned[key] = item
	}
	return cloned
}
