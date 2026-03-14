package worker

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type fakeCleanupJobRepo struct {
	latest      *domain.Job
	latestErr   error
	createdJobs []*domain.Job
}

func (r *fakeCleanupJobRepo) Create(_ context.Context, job *domain.Job) error {
	r.createdJobs = append(r.createdJobs, job)
	return nil
}

func (r *fakeCleanupJobRepo) FindByID(context.Context, uuid.UUID) (*domain.Job, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeCleanupJobRepo) FindLatestByMediaAndType(context.Context, uuid.UUID, domain.JobType) (*domain.Job, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeCleanupJobRepo) FindLatestByType(context.Context, domain.JobType) (*domain.Job, error) {
	if r.latestErr != nil {
		return nil, r.latestErr
	}
	if r.latest == nil {
		return nil, domain.ErrNotFound
	}
	return r.latest, nil
}

func (r *fakeCleanupJobRepo) MarkRunning(context.Context, uuid.UUID, time.Time) error { return nil }
func (r *fakeCleanupJobRepo) MarkDone(context.Context, uuid.UUID, time.Time) error    { return nil }
func (r *fakeCleanupJobRepo) MarkFailed(context.Context, uuid.UUID, string, time.Time) error {
	return nil
}

type fakeCleanupJobQueue struct {
	enqueued []*domain.Job
}

func (q *fakeCleanupJobQueue) Enqueue(_ context.Context, job *domain.Job) error {
	q.enqueued = append(q.enqueued, job)
	return nil
}

func (q *fakeCleanupJobQueue) Dequeue(context.Context, time.Duration) (*domain.Job, error) {
	return nil, nil
}

func TestCleanupSchedulerEnqueueIfNeededCreatesJobWhenNoneExists(t *testing.T) {
	t.Parallel()

	repo := &fakeCleanupJobRepo{}
	queue := &fakeCleanupJobQueue{}
	scheduler := NewCleanupScheduler(repo, queue, time.Hour)
	scheduler.now = func() time.Time { return time.Date(2026, time.March, 14, 18, 30, 0, 0, time.UTC) }

	scheduler.enqueueIfNeeded(context.Background())

	if got, want := len(repo.createdJobs), 1; got != want {
		t.Fatalf("Create() count = %d, want %d", got, want)
	}
	if repo.createdJobs[0].Type != domain.JobTypeCleanup {
		t.Fatalf("Create() type = %q, want cleanup", repo.createdJobs[0].Type)
	}
	if got, want := len(queue.enqueued), 1; got != want {
		t.Fatalf("Enqueue() count = %d, want %d", got, want)
	}
}

func TestCleanupSchedulerEnqueueIfNeededSkipsQueuedCleanupJob(t *testing.T) {
	t.Parallel()

	repo := &fakeCleanupJobRepo{
		latest: &domain.Job{ID: uuid.New(), Type: domain.JobTypeCleanup, Status: domain.JobStatusQueued},
	}
	queue := &fakeCleanupJobQueue{}

	NewCleanupScheduler(repo, queue, time.Hour).enqueueIfNeeded(context.Background())

	if len(repo.createdJobs) != 0 {
		t.Fatalf("Create() count = %d, want 0", len(repo.createdJobs))
	}
	if len(queue.enqueued) != 0 {
		t.Fatalf("Enqueue() count = %d, want 0", len(queue.enqueued))
	}
}
