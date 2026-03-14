package maintenance

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type fakeMediaMaintenanceRepo struct {
	before  time.Time
	deleted []*domain.Media
	err     error
}

func (r *fakeMediaMaintenanceRepo) DeleteExpiredTrash(_ context.Context, before time.Time) ([]*domain.Media, error) {
	r.before = before
	if r.err != nil {
		return nil, r.err
	}
	return r.deleted, nil
}

type fakeShareMaintenanceRepo struct {
	before time.Time
	count  int
	err    error
}

func (r *fakeShareMaintenanceRepo) DeleteExpired(_ context.Context, before time.Time) (int, error) {
	r.before = before
	if r.err != nil {
		return 0, r.err
	}
	return r.count, nil
}

type fakeMediaCleaner struct {
	deleted []*domain.Media
	err     error
}

func (c *fakeMediaCleaner) DeleteMediaAssets(_ context.Context, media *domain.Media) error {
	c.deleted = append(c.deleted, media)
	return c.err
}

func TestRunCleanupHandlerExecutePurgesExpiredMediaAndShares(t *testing.T) {
	t.Parallel()

	now := time.Date(2026, time.March, 14, 18, 0, 0, 0, time.UTC)
	mediaRepo := &fakeMediaMaintenanceRepo{
		deleted: []*domain.Media{
			{ID: uuid.New()},
			{ID: uuid.New()},
		},
	}
	shareRepo := &fakeShareMaintenanceRepo{count: 3}
	cleaner := &fakeMediaCleaner{}

	handler := NewRunCleanupHandler(mediaRepo, shareRepo, cleaner)
	handler.now = func() time.Time { return now }

	result, err := handler.Execute(context.Background())
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got, want := result.PurgedMediaCount, 2; got != want {
		t.Fatalf("PurgedMediaCount = %d, want %d", got, want)
	}
	if got, want := result.DeletedShareCount, 3; got != want {
		t.Fatalf("DeletedShareCount = %d, want %d", got, want)
	}
	if got, want := mediaRepo.before, now.Add(-domain.TrashRetentionWindow); !got.Equal(want) {
		t.Fatalf("DeleteExpiredTrash() before = %v, want %v", got, want)
	}
	if got, want := shareRepo.before, now; !got.Equal(want) {
		t.Fatalf("DeleteExpired() before = %v, want %v", got, want)
	}
	if got, want := len(cleaner.deleted), 2; got != want {
		t.Fatalf("DeleteMediaAssets() count = %d, want %d", got, want)
	}
}

func TestRunCleanupHandlerExecuteReturnsCleanerErrors(t *testing.T) {
	t.Parallel()

	handler := NewRunCleanupHandler(
		&fakeMediaMaintenanceRepo{deleted: []*domain.Media{{ID: uuid.New()}}},
		&fakeShareMaintenanceRepo{},
		&fakeMediaCleaner{err: errors.New("delete object")},
	)

	if _, err := handler.Execute(context.Background()); err == nil {
		t.Fatal("Execute() error = nil, want cleanup failure")
	}
}
