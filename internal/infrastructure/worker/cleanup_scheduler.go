package worker

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type CleanupScheduler struct {
	jobRepo  domain.JobRepository
	jobQueue domain.JobQueue
	interval time.Duration
	now      func() time.Time
}

func NewCleanupScheduler(jobRepo domain.JobRepository, jobQueue domain.JobQueue, interval time.Duration) *CleanupScheduler {
	if interval <= 0 {
		interval = time.Hour
	}

	return &CleanupScheduler{
		jobRepo:  jobRepo,
		jobQueue: jobQueue,
		interval: interval,
		now:      time.Now,
	}
}

func (s *CleanupScheduler) Run(ctx context.Context) {
	if s == nil || s.jobRepo == nil || s.jobQueue == nil {
		<-ctx.Done()
		return
	}

	s.enqueueIfNeeded(ctx)

	ticker := time.NewTicker(s.interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.enqueueIfNeeded(ctx)
		}
	}
}

func (s *CleanupScheduler) enqueueIfNeeded(ctx context.Context) {
	latest, err := s.jobRepo.FindLatestByType(ctx, domain.JobTypeCleanup)
	switch {
	case err == nil:
		if latest.Status == domain.JobStatusQueued || latest.Status == domain.JobStatusRunning {
			return
		}
	case !errors.Is(err, domain.ErrNotFound):
		return
	}

	now := s.now().UTC()
	job := &domain.Job{
		ID:        uuid.New(),
		Type:      domain.JobTypeCleanup,
		Status:    domain.JobStatusQueued,
		Payload:   map[string]any{"scheduled_at": now.Format(time.RFC3339)},
		CreatedAt: now,
	}
	if err := s.jobRepo.Create(ctx, job); err != nil {
		return
	}
	_ = s.jobQueue.Enqueue(ctx, job)
}
