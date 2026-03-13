package worker

import (
	"context"
	"errors"
	"io"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type fakeJobQueue struct{}

func (q *fakeJobQueue) Enqueue(context.Context, *domain.Job) error {
	return nil
}

func (q *fakeJobQueue) Dequeue(context.Context, time.Duration) (*domain.Job, error) {
	return nil, nil
}

type fakeJobRepo struct {
	jobs      map[uuid.UUID]*domain.Job
	runningID uuid.UUID
	doneID    uuid.UUID
	failedID  uuid.UUID
	failMsg   string
}

func (r *fakeJobRepo) Create(context.Context, *domain.Job) error {
	return nil
}

func (r *fakeJobRepo) FindByID(_ context.Context, id uuid.UUID) (*domain.Job, error) {
	job, ok := r.jobs[id]
	if !ok {
		return nil, domain.ErrNotFound
	}

	return job, nil
}

func (r *fakeJobRepo) FindLatestByMediaAndType(context.Context, uuid.UUID, domain.JobType) (*domain.Job, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeJobRepo) MarkRunning(_ context.Context, id uuid.UUID, _ time.Time) error {
	r.runningID = id
	if job, ok := r.jobs[id]; ok {
		job.Status = domain.JobStatusRunning
	}
	return nil
}

func (r *fakeJobRepo) MarkDone(_ context.Context, id uuid.UUID, _ time.Time) error {
	r.doneID = id
	if job, ok := r.jobs[id]; ok {
		job.Status = domain.JobStatusDone
	}
	return nil
}

func (r *fakeJobRepo) MarkFailed(_ context.Context, id uuid.UUID, message string, _ time.Time) error {
	r.failedID = id
	r.failMsg = message
	if job, ok := r.jobs[id]; ok {
		job.Status = domain.JobStatusFailed
		job.Error = message
	}
	return nil
}

type fakeMediaRepo struct {
	media         *domain.Media
	statusHistory []domain.MediaStatus
	result        *domain.MediaProcessingResult
}

func (r *fakeMediaRepo) Create(context.Context, *domain.Media) error {
	return nil
}

func (r *fakeMediaRepo) FindByID(_ context.Context, id uuid.UUID) (*domain.Media, error) {
	if r.media == nil || r.media.ID != id {
		return nil, domain.ErrNotFound
	}

	return r.media, nil
}

func (r *fakeMediaRepo) FindByIDForUser(context.Context, uuid.UUID, uuid.UUID) (*domain.Media, error) {
	return nil, domain.ErrNotFound
}

func (r *fakeMediaRepo) ListVisibleToUser(context.Context, uuid.UUID, domain.ListMediaOptions) (domain.MediaPage, error) {
	return domain.MediaPage{}, nil
}

func (r *fakeMediaRepo) UpdateStatus(_ context.Context, id uuid.UUID, status domain.MediaStatus) error {
	if r.media == nil || r.media.ID != id {
		return domain.ErrNotFound
	}

	r.media.Status = status
	r.statusHistory = append(r.statusHistory, status)
	return nil
}

func (r *fakeMediaRepo) ApplyProcessingResult(_ context.Context, id uuid.UUID, result domain.MediaProcessingResult) error {
	if r.media == nil || r.media.ID != id {
		return domain.ErrNotFound
	}

	copied := result
	r.result = &copied
	r.media.Status = domain.MediaStatusReady
	r.media.ThumbKeys = result.ThumbKeys
	r.media.Metadata = result.Metadata
	return nil
}

type fakeStorageService struct {
	openBody      string
	openedKey     string
	promotedKey   string
	deletedUpload string
}

func (s *fakeStorageService) InitiateUpload(context.Context, string, string) (string, error) {
	return "", nil
}

func (s *fakeStorageService) PresignUploadPart(context.Context, string, string, int, time.Duration) (string, error) {
	return "", nil
}

func (s *fakeStorageService) CompleteUpload(context.Context, string, string, []domain.CompletedPart) error {
	return nil
}

func (s *fakeStorageService) AbortUpload(context.Context, string, string) error {
	return nil
}

func (s *fakeStorageService) UploadExists(context.Context, string) (bool, error) {
	return false, nil
}

func (s *fakeStorageService) DeleteUpload(_ context.Context, key string) error {
	s.deletedUpload = key
	return nil
}

func (s *fakeStorageService) OpenUpload(_ context.Context, key string) (io.ReadCloser, error) {
	s.openedKey = key
	return io.NopCloser(strings.NewReader(s.openBody)), nil
}

func (s *fakeStorageService) PromoteUpload(_ context.Context, key string) error {
	s.promotedKey = key
	return nil
}

type fakeScanner struct {
	clean  bool
	threat string
	err    error
}

func (s *fakeScanner) ScanReader(context.Context, io.Reader) (bool, string, error) {
	return s.clean, s.threat, s.err
}

type fakeKeyBuilder struct {
	keys domain.ThumbKeys
}

func (b *fakeKeyBuilder) BuildMediaObjectKey(uuid.UUID, uuid.UUID, string, string, time.Time) string {
	return ""
}

func (b *fakeKeyBuilder) BuildThumbKeys(uuid.UUID, string) domain.ThumbKeys {
	return b.keys
}

func TestJobRunnerProcessPromotesUploadAndMarksMediaReady(t *testing.T) {
	t.Parallel()

	mediaID := uuid.New()
	jobID := uuid.New()
	mediaRepo := &fakeMediaRepo{
		media: &domain.Media{
			ID:          mediaID,
			MimeType:    "video/mp4",
			OriginalKey: "owner/2026/03/media.mp4",
			Status:      domain.MediaStatusPending,
			Metadata: map[string]any{
				"source": "upload",
			},
		},
	}
	jobRepo := &fakeJobRepo{
		jobs: map[uuid.UUID]*domain.Job{
			jobID: {
				ID:      jobID,
				MediaID: &mediaID,
				Type:    domain.JobTypeProcessMedia,
				Status:  domain.JobStatusQueued,
			},
		},
	}
	storage := &fakeStorageService{openBody: "clean upload"}
	scanner := &fakeScanner{clean: true}
	keyBuilder := &fakeKeyBuilder{
		keys: domain.ThumbKeys{
			Small:  "small.webp",
			Medium: "medium.webp",
			Large:  "large.webp",
			Poster: "poster.webp",
		},
	}

	runner := NewJobRunner(&fakeJobQueue{}, jobRepo, mediaRepo, storage, scanner, keyBuilder, time.Second)
	runner.process(context.Background(), &domain.Job{ID: jobID})

	if jobRepo.runningID != jobID {
		t.Fatal("process() did not mark the job running")
	}
	if storage.openedKey != mediaRepo.media.OriginalKey {
		t.Fatal("process() did not open the staged upload")
	}
	if storage.promotedKey != mediaRepo.media.OriginalKey {
		t.Fatal("process() did not promote the staged upload")
	}
	if storage.deletedUpload != mediaRepo.media.OriginalKey {
		t.Fatal("process() did not clean up the staged upload after promotion")
	}
	if len(mediaRepo.statusHistory) == 0 || mediaRepo.statusHistory[0] != domain.MediaStatusProcessing {
		t.Fatal("process() did not mark the media row as processing")
	}
	if mediaRepo.result == nil || mediaRepo.result.ThumbKeys.Poster != "poster.webp" {
		t.Fatal("process() did not apply thumbnail keys")
	}
	processing, ok := mediaRepo.result.Metadata["processing"].(map[string]any)
	if !ok || processing["scan_status"] != "clean" {
		t.Fatal("process() did not record processing metadata")
	}
	if jobRepo.doneID != jobID {
		t.Fatal("process() did not mark the job done")
	}
}

func TestJobRunnerProcessFailsMediaWhenVirusDetected(t *testing.T) {
	t.Parallel()

	mediaID := uuid.New()
	jobID := uuid.New()
	mediaRepo := &fakeMediaRepo{
		media: &domain.Media{
			ID:          mediaID,
			MimeType:    "image/jpeg",
			OriginalKey: "owner/2026/03/photo.jpg",
			Status:      domain.MediaStatusPending,
		},
	}
	jobRepo := &fakeJobRepo{
		jobs: map[uuid.UUID]*domain.Job{
			jobID: {
				ID:      jobID,
				MediaID: &mediaID,
				Type:    domain.JobTypeProcessMedia,
				Status:  domain.JobStatusQueued,
			},
		},
	}
	storage := &fakeStorageService{openBody: "infected"}
	scanner := &fakeScanner{clean: false, threat: "EICAR-Test-Signature"}
	keyBuilder := &fakeKeyBuilder{}

	runner := NewJobRunner(&fakeJobQueue{}, jobRepo, mediaRepo, storage, scanner, keyBuilder, time.Second)
	runner.process(context.Background(), &domain.Job{ID: jobID})

	if mediaRepo.media.Status != domain.MediaStatusFailed {
		t.Fatalf("process() media status = %q, want failed", mediaRepo.media.Status)
	}
	if storage.promotedKey != "" {
		t.Fatal("process() promoted a virus-positive upload")
	}
	if storage.deletedUpload != mediaRepo.media.OriginalKey {
		t.Fatal("process() did not delete the infected staged upload")
	}
	if jobRepo.failedID != jobID || !strings.Contains(jobRepo.failMsg, "virus detected") {
		t.Fatal("process() did not mark the job failed with the virus reason")
	}
	if mediaRepo.result != nil {
		t.Fatal("process() should not apply a processing result on virus detection")
	}
}

func TestJobRunnerProcessFailsWhenScannerErrors(t *testing.T) {
	t.Parallel()

	mediaID := uuid.New()
	jobID := uuid.New()
	mediaRepo := &fakeMediaRepo{
		media: &domain.Media{
			ID:          mediaID,
			MimeType:    "image/jpeg",
			OriginalKey: "owner/2026/03/photo.jpg",
			Status:      domain.MediaStatusPending,
		},
	}
	jobRepo := &fakeJobRepo{
		jobs: map[uuid.UUID]*domain.Job{
			jobID: {
				ID:      jobID,
				MediaID: &mediaID,
				Type:    domain.JobTypeProcessMedia,
				Status:  domain.JobStatusQueued,
			},
		},
	}

	runner := NewJobRunner(
		&fakeJobQueue{},
		jobRepo,
		mediaRepo,
		&fakeStorageService{openBody: "upload"},
		&fakeScanner{err: errors.New("clamd unavailable")},
		&fakeKeyBuilder{},
		time.Second,
	)
	runner.process(context.Background(), &domain.Job{ID: jobID})

	if jobRepo.failedID != jobID {
		t.Fatal("process() did not mark the job failed on scanner error")
	}
	if mediaRepo.media.Status != domain.MediaStatusFailed {
		t.Fatal("process() did not mark media failed on scanner error")
	}
}
