package main

import (
	"context"
	"fmt"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	minio "github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	minioinfra "github.com/yourorg/mycloud/internal/infrastructure/minio"
	"os"
	"strings"
	"time"
)

type asset struct {
	id                uuid.UUID
	key, mime, status string
	size, derivatives int64
	keys              []string
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "Storage reconciliation did not complete. Check configuration, missing objects and maintenance acknowledgement.")
		os.Exit(1)
	}
}
func run() error {
	apply := len(os.Args) == 2 && os.Args[1] == "--apply"
	if len(os.Args) > 2 || len(os.Args) == 2 && !apply {
		return fmt.Errorf("usage: reconcile-storage [--apply]")
	}
	if apply && os.Getenv("RECONCILE_WRITES_PAUSED") != "yes" {
		return fmt.Errorf("pause API and worker writes first")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()
	db, err := pgxpool.New(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		return err
	}
	defer db.Close()
	client, err := minio.New(os.Getenv("MINIO_ENDPOINT"), &minio.Options{Creds: credentials.NewStaticV4(os.Getenv("MINIO_ACCESS_KEY"), os.Getenv("MINIO_SECRET_KEY"), ""), Secure: os.Getenv("MINIO_SECURE") == "true"})
	if err != nil {
		return err
	}
	bucket := func(key, fallback string) string {
		if value := strings.TrimSpace(os.Getenv(key)); value != "" {
			return value
		}
		return fallback
	}
	originals := bucket("MINIO_ORIGINALS_BUCKET", "fc-originals")
	uploads := bucket("MINIO_UPLOADS_BUCKET", "fc-uploads")
	thumbs := bucket("MINIO_THUMBS_BUCKET", "fc-thumbs")
	rows, err := db.Query(ctx, `SELECT id,original_key,mime_type,status,size_bytes,derivative_bytes FROM media ORDER BY owner_id,id`)
	if err != nil {
		return err
	}
	var items []asset
	for rows.Next() {
		var a asset
		if err = rows.Scan(&a.id, &a.key, &a.mime, &a.status, &a.size, &a.derivatives); err != nil {
			rows.Close()
			return err
		}
		keys := minioinfra.NewKeyBuilder().BuildThumbKeys(a.id, a.mime)
		a.keys = []string{keys.Small, keys.Medium, keys.Large, keys.Poster}
		items = append(items, a)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	actual := func(bucket, key string) (int64, bool, error) {
		info, err := client.StatObject(ctx, bucket, key, minio.StatObjectOptions{})
		if err != nil {
			code := minio.ToErrorResponse(err).Code
			if code == "NoSuchKey" || code == "NotFound" {
				return 0, false, nil
			}
			return 0, false, err
		}
		return info.Size, true, nil
	}
	missing := 0
	drift := 0
	for i := range items {
		a := &items[i]
		size, exists, err := actual(originals, a.key)
		if err != nil {
			return err
		}
		if !exists {
			size, exists, err = actual(uploads, a.key)
			if err != nil {
				return err
			}
		}
		if !exists && a.status == "ready" {
			missing++
			fmt.Printf("Missing ready asset: %s\n", a.id)
			continue
		}
		var derivatives int64
		for _, key := range a.keys {
			if key == "" {
				continue
			}
			n, _, err := actual(thumbs, key)
			if err != nil {
				return err
			}
			derivatives += n
		}
		// Pending processing still reserves its bounded derivative budget.
		if a.status == "pending" || a.status == "processing" {
			if derivatives < 8*1024*1024 {
				derivatives = 8 * 1024 * 1024
			}
		}
		if a.size != size || a.derivatives != derivatives {
			drift++
			fmt.Printf("Usage drift for asset %s: original=%d derivatives=%d\n", a.id, size, derivatives)
		}
		a.size = size
		a.derivatives = derivatives
	}
	fmt.Printf("Inspected %d assets; drift=%d; missing_ready=%d.\n", len(items), drift, missing)
	if missing > 0 {
		return fmt.Errorf("restore missing ready originals before applying reconciliation")
	}
	if !apply {
		return nil
	}
	tx, err := db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(684306104); SET LOCAL mycloud.storage_reconcile='on'`); err != nil {
		return err
	}
	for _, a := range items {
		if _, err = tx.Exec(ctx, `UPDATE media SET size_bytes=$2,derivative_bytes=$3 WHERE id=$1`, a.id, a.size, a.derivatives); err != nil {
			return err
		}
	}
	_, err = tx.Exec(ctx, `UPDATE users u SET storage_used=COALESCE((SELECT sum(size_bytes+derivative_bytes) FROM media WHERE owner_id=u.id),0)+COALESCE((SELECT sum(charged_bytes) FROM media_deletions WHERE owner_id=u.id),0)`)
	if err != nil {
		return err
	}
	if err = tx.Commit(ctx); err != nil {
		return err
	}
	fmt.Println("Storage usage reconciled; existing quotas were preserved.")
	return nil
}
