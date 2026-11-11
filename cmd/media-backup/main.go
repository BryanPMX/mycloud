package main

import (
	"context"
	"fmt"
	minio "github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"github.com/yourorg/mycloud/internal/infrastructure/backup"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
)

func main() {
	if run() != nil {
		fmt.Fprintln(os.Stderr, "Media backup operation failed; no successful snapshot was reported. Check target availability, permissions and configuration.")
		os.Exit(1)
	}
}
func run() error {
	if len(os.Args) != 3 {
		return fmt.Errorf("usage: media-backup create|verify|restore /absolute/path")
	}
	mode, root := os.Args[1], os.Args[2]
	if !strings.HasPrefix(root, "/") {
		return fmt.Errorf("absolute backup path required")
	}
	if mode == "verify" {
		_, err := backup.Verify(root)
		if err == nil {
			fmt.Println("Media snapshot checksums verified.")
		}
		return err
	}
	endpoint, key, secret := os.Getenv("MINIO_ENDPOINT"), os.Getenv("MINIO_ACCESS_KEY"), os.Getenv("MINIO_SECRET_KEY")
	if endpoint == "" || key == "" || secret == "" {
		return fmt.Errorf("MinIO configuration required")
	}
	client, err := minio.New(endpoint, &minio.Options{Creds: credentials.NewStaticV4(key, secret, ""), Secure: os.Getenv("MINIO_SECURE") == "true"})
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	switch mode {
	case "create":
		if os.Getenv("BACKUP_WRITES_PAUSED") != "yes" {
			return fmt.Errorf("pause API and worker writes before snapshot")
		}
		buckets := []string{}
		for _, pair := range [][2]string{{"MINIO_UPLOADS_BUCKET", "fc-uploads"}, {"MINIO_ORIGINALS_BUCKET", "fc-originals"}, {"MINIO_THUMBS_BUCKET", "fc-thumbs"}, {"MINIO_AVATARS_BUCKET", "fc-avatars"}} {
			value := os.Getenv(pair[0])
			if value == "" {
				value = pair[1]
			}
			buckets = append(buckets, value)
		}
		path, err := backup.Create(ctx, client, buckets, root)
		if err == nil {
			days := 14
			if value := os.Getenv("MEDIA_BACKUP_RETENTION_DAYS"); value != "" {
				days, err = strconv.Atoi(value)
			}
			if err == nil {
				err = backup.Prune(root, days)
			}
		}
		if err == nil {
			fmt.Printf("Verified media snapshot: %s\n", path)
		}
		return err
	case "restore":
		if os.Getenv("RESTORE_CONFIRM") != "isolated-empty-target" {
			return fmt.Errorf("explicit isolated restore acknowledgement required")
		}
		err := backup.Restore(ctx, client, root, os.Getenv("RESTORE_BUCKET_PREFIX"))
		if err == nil {
			fmt.Println("Media restore and byte verification passed.")
		}
		return err
	default:
		return fmt.Errorf("unknown backup operation")
	}
}
