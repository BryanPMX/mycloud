//go:build integration

package postgres

import (
	"context"
	"errors"
	"fmt"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yourorg/mycloud/internal/domain"
	"os"
	"sync"
	"testing"
	"time"
)

func testDB(t *testing.T) *pgxpool.Pool {
	t.Helper()
	raw := os.Getenv("MYCLOUD_TEST_DATABASE_URL")
	if raw == "" {
		t.Skip("MYCLOUD_TEST_DATABASE_URL is required")
	}
	cfg, err := pgxpool.ParseConfig(raw)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.ConnConfig.Database != "mycloud_validation" {
		t.Fatal("integration tests require the isolated mycloud_validation database")
	}
	db, err := pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(db.Close)
	return db
}
func testUser(t *testing.T, db *pgxpool.Pool, quota int64, role string) uuid.UUID {
	t.Helper()
	id := uuid.New()
	_, err := db.Exec(context.Background(), `INSERT INTO users(id,email,display_name,password_hash,quota_bytes,role) VALUES($1,$2,'Validation','not-a-login-hash',$3,$4)`, id, id.String()+"@validation.invalid", quota, role)
	if err != nil {
		t.Fatal(err)
	}
	return id
}
func testMedia(owner uuid.UUID, size int64) *domain.Media {
	return &domain.Media{ID: uuid.New(), OwnerID: owner, Filename: "private.jpg", MimeType: "image/jpeg", SizeBytes: size, OriginalKey: "validation/" + uuid.NewString(), Status: domain.MediaStatusReady, UploadedAt: time.Now().UTC(), Metadata: map[string]any{}}
}

func TestIntegrationPrivateMediaBoundaries(t *testing.T) {
	db := testDB(t)
	ctx := context.Background()
	owner := testUser(t, db, 1<<30, "member")
	member := testUser(t, db, 1<<30, "member")
	outsider := testUser(t, db, 1<<30, "admin")
	family, err := NewFamilyRepository(db).CreateFamily(ctx, owner, "Media permissions family")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(ctx, `INSERT INTO family_memberships(family_id,user_id,role) VALUES($1,$2,'member')`, family.ID, member); err != nil {
		t.Fatal(err)
	}
	repo := NewMediaRepository(db)
	item := testMedia(owner, 100)
	if err := repo.Create(ctx, item); err != nil {
		t.Fatal(err)
	}
	for _, id := range []uuid.UUID{member, outsider} {
		if _, err := repo.FindByIDForUser(ctx, item.ID, id); !errors.Is(err, domain.ErrNotFound) {
			t.Fatalf("private media leaked to %s: %v", id, err)
		}
	}
	album := uuid.New()
	_, err = db.Exec(ctx, `INSERT INTO albums(id,owner_id,name) VALUES($1,$2,'Private')`, album, owner)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(ctx, `INSERT INTO album_media(album_id,media_id,added_by) VALUES($1,$2,$3)`, album, item.ID, owner); err != nil {
		t.Fatal(err)
	}

	share := uuid.New()
	_, err = db.Exec(ctx, `INSERT INTO shares(id,album_id,shared_by,shared_with) VALUES($1,$2,$3,$4)`, share, album, owner, member)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := repo.FindByIDForUser(ctx, item.ID, member); err != nil {
		t.Fatal(err)
	}
	if _, err := repo.FindByIDForUser(ctx, item.ID, outsider); !errors.Is(err, domain.ErrNotFound) {
		t.Fatal("admin bypassed private sharing")
	}
	if _, err = db.Exec(ctx, `UPDATE shares SET expires_at=now()-interval '1 minute' WHERE id=$1`, share); err != nil {
		t.Fatal(err)
	}
	if _, err := repo.FindByIDForUser(ctx, item.ID, member); !errors.Is(err, domain.ErrNotFound) {
		t.Fatal("expired share retained access")
	}
	if _, err = db.Exec(ctx, `DELETE FROM shares WHERE id=$1`, share); err != nil {
		t.Fatal(err)
	}
	if _, err := repo.FindByIDForUser(ctx, item.ID, owner); err != nil {
		t.Fatal("unsharing removed original")
	}
	if err := repo.SoftDelete(ctx, item.ID, time.Now()); err != nil {
		t.Fatal(err)
	}
	if _, err := repo.FindByIDForUser(ctx, item.ID, owner); !errors.Is(err, domain.ErrNotFound) {
		t.Fatal("trash remained readable")
	}
}
func TestIntegrationQuotaReservationsAndAccounting(t *testing.T) {
	db := testDB(t)
	ctx := context.Background()
	owner := testUser(t, db, 20*1024*1024, "member")
	store := NewUploadSessionStore(db)
	var wg sync.WaitGroup
	var mu sync.Mutex
	var accepted []domain.UploadSession
	var failures []error
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			s := domain.UploadSession{MediaID: uuid.New(), OwnerID: owner, SizeBytes: 10 * 1024 * 1024, Filename: "large.mp4", MimeType: "video/mp4", ObjectKey: uuid.NewString(), UploadID: uuid.NewString(), CreatedAt: time.Now()}
			err := store.SaveUploadSession(ctx, s, time.Hour)
			mu.Lock()
			defer mu.Unlock()
			if err == nil {
				accepted = append(accepted, s)
			} else {
				failures = append(failures, err)
			}
		}()
	}
	wg.Wait()
	if len(accepted) != 1 {
		t.Fatalf("accepted %d concurrent uploads, want 1; errors %v", len(accepted), failures)
	}
	for _, err := range failures {
		if !errors.Is(err, domain.ErrQuotaExceeded) {
			t.Fatal(err)
		}
	}
	session := accepted[0]
	if _, err := store.GetUploadSession(ctx, session.MediaID); err != nil {
		t.Fatal(err)
	}
	repo := NewMediaRepository(db)
	item := testMedia(owner, session.SizeBytes)
	item.ID = session.MediaID
	item.DerivativeBytes = domain.DerivativeBudgetBytes
	if err := repo.Create(ctx, item); err != nil {
		t.Fatal(err)
	}
	if err := store.DeleteUploadSession(ctx, session.MediaID); err != nil {
		t.Fatal(err)
	}
	if err := repo.ApplyProcessingResult(ctx, item.ID, domain.MediaProcessingResult{DerivativeBytes: 200, Metadata: map[string]any{}}); err != nil {
		t.Fatal(err)
	}
	var used int64
	readUsed := func() int64 {
		if err := db.QueryRow(ctx, `SELECT storage_used FROM users WHERE id=$1`, owner).Scan(&used); err != nil {
			t.Fatal(err)
		}
		return used
	}
	charged := item.SizeBytes + 200
	if readUsed() != charged {
		t.Fatalf("usage=%d want=%d", used, charged)
	}
	if err := repo.SoftDelete(ctx, item.ID, time.Now()); err != nil {
		t.Fatal(err)
	}
	if readUsed() != charged {
		t.Fatal("trash incorrectly released quota")
	}
	if err := repo.HardDelete(ctx, item.ID); err != nil {
		t.Fatal(err)
	}
	if readUsed() != charged {
		t.Fatal("pending physical deletion released quota")
	}
	cleaner := &integrationCleaner{fail: true}
	if err := repo.DrainDeletions(ctx, cleaner); err == nil {
		t.Fatal("expected MinIO outage")
	}
	if readUsed() != charged {
		t.Fatal("failed deletion lost quota charge")
	}
	cleaner.fail = false
	if err := repo.DrainDeletions(ctx, cleaner); err != nil {
		t.Fatal(err)
	}
	if readUsed() != 0 {
		t.Fatal("successful deletion did not release quota")
	}
	if err := repo.DrainDeletions(ctx, cleaner); err != nil {
		t.Fatal(err)
	}
	if readUsed() != 0 {
		t.Fatal("duplicate deletion corrupted usage")
	}
}

type integrationCleaner struct{ fail bool }

func (c *integrationCleaner) DeleteMediaAssets(context.Context, *domain.Media) error {
	if c.fail {
		return fmt.Errorf("simulated storage outage")
	}
	return nil
}
func TestIntegrationAtomicJobClaimAndRecovery(t *testing.T) {
	db := testDB(t)
	ctx := context.Background()
	owner := testUser(t, db, 1<<30, "member")
	media := testMedia(owner, 100)
	media.Status = domain.MediaStatusPending
	if err := NewMediaRepository(db).Create(ctx, media); err != nil {
		t.Fatal(err)
	}
	repo := NewJobRepository(db)
	jobs, err := repo.RecoverJobs(ctx)
	if err != nil {
		t.Fatal(err)
	}
	var jobID uuid.UUID
	for _, job := range jobs {
		found, err := repo.FindByID(ctx, job.ID)
		if err != nil {
			t.Fatal(err)
		}
		if found.MediaID != nil && *found.MediaID == media.ID {
			jobID = job.ID
		}
	}
	if jobID == uuid.Nil {
		t.Fatal("pending media crash window was not repaired")
	}
	var wg sync.WaitGroup
	var mu sync.Mutex
	claimed := 0
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if repo.MarkRunning(ctx, jobID, time.Now()) == nil {
				mu.Lock()
				claimed++
				mu.Unlock()
			}
		}()
	}
	wg.Wait()
	if claimed != 1 {
		t.Fatalf("claims=%d want=1", claimed)
	}
	if _, err := db.Exec(ctx, `UPDATE jobs SET started_at=now()-interval '15 minutes' WHERE id=$1`, jobID); err != nil {
		t.Fatal(err)
	}
	if _, err := repo.RecoverJobs(ctx); err != nil {
		t.Fatal(err)
	}
	job, err := repo.FindByID(ctx, jobID)
	if err != nil {
		t.Fatal(err)
	}
	if job.Status != domain.JobStatusQueued {
		t.Fatal("crashed worker job was not recovered")
	}
}
