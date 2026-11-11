// Package backup creates private, checksummed, metadata-preserving MinIO snapshots.
package backup

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"time"

	minio "github.com/minio/minio-go/v7"
)

type Object struct {
	Bucket      string            `json:"bucket"`
	Key         string            `json:"key"`
	File        string            `json:"file"`
	Size        int64             `json:"size"`
	SHA256      string            `json:"sha256"`
	ETag        string            `json:"etag"`
	ContentType string            `json:"content_type"`
	Metadata    map[string]string `json:"metadata,omitempty"`
}
type Manifest struct {
	Version   int       `json:"version"`
	CreatedAt time.Time `json:"created_at"`
	Buckets   []string  `json:"buckets"`
	Objects   []Object  `json:"objects"`
}

var objectPath = regexp.MustCompile(`^objects/[0-9]{8}$`)
var snapshotName = regexp.MustCompile(`^snapshot-[0-9TZ]+-[a-zA-Z0-9]+$`)

func readManifest(root string) (Manifest, error) {
	var m Manifest
	data, err := os.ReadFile(filepath.Join(root, "manifest.json"))
	if err != nil {
		return m, err
	}
	if len(data) > 128*1024*1024 {
		return m, errors.New("manifest too large")
	}
	if err = json.Unmarshal(data, &m); err != nil {
		return m, err
	}
	if m.Version != 1 {
		return m, errors.New("unsupported manifest version")
	}
	return m, nil
}
func filePath(root, file string) (string, error) {
	infoDir, err := os.Lstat(filepath.Join(root, "objects"))
	if err != nil {
		return "", err
	}
	if !infoDir.IsDir() || infoDir.Mode()&os.ModeSymlink != 0 {
		return "", errors.New("invalid backup objects directory")
	}
	if !objectPath.MatchString(file) {
		return "", errors.New("invalid backup object path")
	}
	path := filepath.Join(root, filepath.FromSlash(file))
	info, err := os.Lstat(path)
	if err != nil {
		return "", err
	}
	if !info.Mode().IsRegular() {
		return "", errors.New("backup object is not a regular file")
	}
	return path, nil
}
func hashFile(path string) (string, int64, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", 0, err
	}
	defer file.Close()
	hash := sha256.New()
	n, err := io.Copy(hash, file)
	return hex.EncodeToString(hash.Sum(nil)), n, err
}
func Verify(root string) (Manifest, error) {
	m, err := readManifest(root)
	if err != nil {
		return m, err
	}
	buckets := map[string]bool{}
	for _, bucket := range m.Buckets {
		if bucket == "" || buckets[bucket] {
			return m, errors.New("invalid bucket list")
		}
		buckets[bucket] = true
	}
	for _, obj := range m.Objects {
		if !buckets[obj.Bucket] || obj.Key == "" {
			return m, errors.New("undeclared object bucket or empty key")
		}
	}
	seen := map[string]bool{}
	for _, obj := range m.Objects {
		if seen[obj.Bucket+"/"+obj.Key] {
			return m, errors.New("duplicate object in manifest")
		}
		seen[obj.Bucket+"/"+obj.Key] = true
		path, err := filePath(root, obj.File)
		if err != nil {
			return m, err
		}
		hash, n, err := hashFile(path)
		if err != nil {
			return m, err
		}
		if hash != obj.SHA256 || n != obj.Size {
			return m, errors.New("backup checksum or size mismatch")
		}
	}
	return m, nil
}
func Create(ctx context.Context, client *minio.Client, buckets []string, root string) (string, error) {
	if err := os.MkdirAll(root, 0700); err != nil {
		return "", err
	}
	if err := os.Chmod(root, 0700); err != nil {
		return "", err
	}
	staging, err := os.MkdirTemp(root, ".partial-")
	if err != nil {
		return "", err
	}
	defer os.RemoveAll(staging)
	if err = os.Mkdir(filepath.Join(staging, "objects"), 0700); err != nil {
		return "", err
	}
	previous := map[string]Object{}
	var previousRoot string
	if data, err := os.ReadFile(filepath.Join(root, "latest")); err == nil && snapshotName.Match(data) {
		previousRoot = filepath.Join(root, string(data))
		if m, err := readManifest(previousRoot); err == nil {
			for _, obj := range m.Objects {
				previous[obj.Bucket+"/"+obj.Key] = obj
			}
		}
	}
	manifest := Manifest{Version: 1, CreatedAt: time.Now().UTC(), Buckets: buckets, Objects: []Object{}}
	for _, bucket := range buckets {
		policy, err := client.GetBucketPolicy(ctx, bucket)
		if err != nil {
			return "", errors.New("cannot verify private source bucket")
		}
		if policy != "" {
			return "", errors.New("source bucket has a policy; review privacy before backup")
		}
		for info := range client.ListObjects(ctx, bucket, minio.ListObjectsOptions{Recursive: true}) {
			if info.Err != nil {
				return "", errors.New("object listing failed")
			}
			stat, err := client.StatObject(ctx, bucket, info.Key, minio.StatObjectOptions{})
			if err != nil {
				return "", errors.New("object stat failed")
			}
			file := fmt.Sprintf("objects/%08d", len(manifest.Objects))
			dest := filepath.Join(staging, filepath.FromSlash(file))
			obj := Object{Bucket: bucket, Key: info.Key, File: file, Size: stat.Size, ETag: stat.ETag, ContentType: stat.ContentType, Metadata: stat.UserMetadata}
			linked := false
			if old, ok := previous[bucket+"/"+info.Key]; ok && old.ETag == stat.ETag && old.Size == stat.Size {
				if path, err := filePath(previousRoot, old.File); err == nil {
					if err := os.Link(path, dest); err == nil {
						obj.SHA256 = old.SHA256
						linked = true
					}
				}
			}
			if !linked {
				source, err := client.GetObject(ctx, bucket, info.Key, minio.GetObjectOptions{})
				if err != nil {
					return "", errors.New("object read failed")
				}
				output, err := os.OpenFile(dest, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
				if err != nil {
					source.Close()
					return "", err
				}
				hash := sha256.New()
				n, copyErr := io.Copy(io.MultiWriter(output, hash), source)
				source.Close()
				syncErr := output.Sync()
				closeErr := output.Close()
				if err := errors.Join(copyErr, syncErr, closeErr); err != nil {
					return "", err
				}
				if n != stat.Size {
					return "", errors.New("source changed during backup")
				}
				obj.SHA256 = hex.EncodeToString(hash.Sum(nil))
			}
			manifest.Objects = append(manifest.Objects, obj)
		}
	}
	payload, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return "", err
	}
	if err = os.WriteFile(filepath.Join(staging, "manifest.json"), payload, 0600); err != nil {
		return "", err
	}
	if _, err = Verify(staging); err != nil {
		return "", err
	}
	name := "snapshot-" + manifest.CreatedAt.Format("20060102T150405Z") + "-" + filepath.Base(staging)[9:]
	final := filepath.Join(root, name)
	if err = os.Rename(staging, final); err != nil {
		return "", err
	}
	if err = os.WriteFile(filepath.Join(root, ".latest.partial"), []byte(name), 0600); err != nil {
		return "", err
	}
	if err = os.Rename(filepath.Join(root, ".latest.partial"), filepath.Join(root, "latest")); err != nil {
		return "", err
	}
	return final, nil
}

// Restore refuses all nonempty buckets before it writes any data. Run against an
// isolated target; it never removes or overwrites primary objects.
func Restore(ctx context.Context, client *minio.Client, root, prefix string) error {
	m, err := Verify(root)
	if err != nil {
		return err
	}
	for _, bucket := range m.Buckets {
		target := prefix + bucket
		exists, err := client.BucketExists(ctx, target)
		if err != nil {
			return err
		}
		if !exists {
			if err = client.MakeBucket(ctx, target, minio.MakeBucketOptions{}); err != nil {
				return err
			}
		}
		policy, err := client.GetBucketPolicy(ctx, target)
		if err != nil || policy != "" {
			return errors.New("restore target must be private")
		}
		listCtx, cancel := context.WithCancel(ctx)
		objects := client.ListObjects(listCtx, target, minio.ListObjectsOptions{Recursive: true, MaxKeys: 1})
		for obj := range objects {
			cancel()
			if obj.Err != nil {
				return obj.Err
			}
			return errors.New("restore target is not empty")
		}
		cancel()
	}
	for _, obj := range m.Objects {
		path, err := filePath(root, obj.File)
		if err != nil {
			return err
		}
		file, err := os.Open(path)
		if err != nil {
			return err
		}
		_, err = client.PutObject(ctx, prefix+obj.Bucket, obj.Key, file, obj.Size, minio.PutObjectOptions{ContentType: obj.ContentType, UserMetadata: obj.Metadata})
		file.Close()
		if err != nil {
			return errors.New("restore write failed")
		}
		// Read the restored object back and verify real bytes, not multipart ETags.
		source, err := client.GetObject(ctx, prefix+obj.Bucket, obj.Key, minio.GetObjectOptions{})
		if err != nil {
			return err
		}
		hash := sha256.New()
		n, err := io.Copy(hash, source)
		source.Close()
		if err != nil {
			return err
		}
		if n != obj.Size || hex.EncodeToString(hash.Sum(nil)) != obj.SHA256 {
			return errors.New("restored object verification failed")
		}
	}
	return nil
}

// Prune removes only this tool's verified-format snapshot directories older than
// the retention window, after a new verified snapshot has become latest.
func Prune(root string, days int) error {
	if days < 1 {
		return errors.New("retention must be positive")
	}
	latest, err := os.ReadFile(filepath.Join(root, "latest"))
	if err != nil {
		return err
	}
	if !snapshotName.Match(latest) {
		return errors.New("invalid latest snapshot")
	}
	if _, err = Verify(filepath.Join(root, string(latest))); err != nil {
		return err
	}
	entries, err := os.ReadDir(root)
	if err != nil {
		return err
	}
	cutoff := time.Now().Add(-time.Duration(days) * 24 * time.Hour)
	for _, entry := range entries {
		if !entry.IsDir() || entry.Name() == string(latest) || !snapshotName.MatchString(entry.Name()) {
			continue
		}
		path := filepath.Join(root, entry.Name())
		manifest, err := readManifest(path)
		if err != nil {
			continue
		}
		if manifest.CreatedAt.Before(cutoff) {
			if err = os.RemoveAll(path); err != nil {
				return err
			}
		}
	}
	return nil
}
