//go:build integration

package backup

import (
	"bytes"
	"context"
	"encoding/json"
	"github.com/google/uuid"
	minio "github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestIntegrationMediaBackupRestoreAndCorruption(t *testing.T) {
	if os.Getenv("MYCLOUD_TEST_MINIO_ENDPOINT") != "127.0.0.1:59039" {
		t.Skip("isolated MinIO endpoint required")
	}
	client, err := minio.New("127.0.0.1:59039", &minio.Options{Creds: credentials.NewStaticV4("validation", "validation-only-local", ""), Secure: false})
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	bucket := "validation-" + uuid.NewString()
	if err = client.MakeBucket(ctx, bucket, minio.MakeBucketOptions{}); err != nil {
		t.Fatal(err)
	}
	data := []byte("private photo binary fixture")
	key := "users/owner/media/original.jpg"
	if _, err = client.PutObject(ctx, bucket, key, bytes.NewReader(data), int64(len(data)), minio.PutObjectOptions{ContentType: "image/jpeg", UserMetadata: map[string]string{"source": "validation"}}); err != nil {
		t.Fatal(err)
	}
	root := t.TempDir()
	snapshot, err := Create(ctx, client, []string{bucket}, root)
	if err != nil {
		t.Fatal(err)
	}
	manifest, err := Verify(snapshot)
	if err != nil {
		t.Fatal(err)
	}
	if len(manifest.Objects) != 1 {
		t.Fatal("wrong backup count")
	}
	second, err := Create(ctx, client, []string{bucket}, root)
	if err != nil {
		t.Fatal(err)
	}
	originalInfo, _ := os.Stat(filepath.Join(snapshot, "objects/00000000"))
	linkedInfo, _ := os.Stat(filepath.Join(second, "objects/00000000"))
	if !os.SameFile(originalInfo, linkedInfo) {
		t.Fatal("unchanged objects were not reused in the incremental snapshot")
	}
	if err = Restore(ctx, client, second, "restored-"); err != nil {
		t.Fatal(err)
	}
	stat, err := client.StatObject(ctx, "restored-"+bucket, key, minio.StatObjectOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if stat.ContentType != "image/jpeg" || stat.UserMetadata["Source"] != "validation" && stat.UserMetadata["source"] != "validation" {
		t.Fatalf("restored metadata mismatch: %v", stat.UserMetadata)
	}
	if err = Restore(ctx, client, second, ""); err == nil || !strings.Contains(err.Error(), "not empty") {
		t.Fatal("restore should refuse nonempty primary bucket")
	}
	// Replacing the file breaks the hard link so the earlier snapshot stays valid.
	path := filepath.Join(second, "objects/00000000")
	if err = os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(path, []byte("corrupt"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err = Verify(second); err == nil {
		t.Fatal("corruption was not detected")
	}
	if _, err = Verify(snapshot); err != nil {
		t.Fatal("earlier snapshot was modified")
	}
	// A manifest cannot bypass destination emptiness checks with an undeclared bucket.
	rogue := manifest
	rogue.Objects[0].Bucket = "undeclared-primary"
	payload, _ := json.Marshal(rogue)
	if err = os.WriteFile(filepath.Join(snapshot, "manifest.json"), payload, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err = Verify(snapshot); err == nil {
		t.Fatal("undeclared bucket should be rejected")
	}
}
