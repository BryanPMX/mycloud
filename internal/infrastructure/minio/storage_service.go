package minio

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	miniosdk "github.com/minio/minio-go/v7"

	"github.com/yourorg/mycloud/internal/domain"
)

type StorageService struct {
	core          *miniosdk.Core
	uploadsBucket string
	originalsBuck string
	thumbsBucket  string
	avatarsBucket string
}

func NewStorageService(core *miniosdk.Core, uploadsBucket, originalsBucket, thumbsBucket, avatarsBucket string) *StorageService {
	return &StorageService{
		core:          core,
		uploadsBucket: uploadsBucket,
		originalsBuck: originalsBucket,
		thumbsBucket:  thumbsBucket,
		avatarsBucket: avatarsBucket,
	}
}

func (s *StorageService) InitiateUpload(ctx context.Context, key, mimeType string) (string, error) {
	uploadID, err := s.core.NewMultipartUpload(ctx, s.uploadsBucket, key, miniosdk.PutObjectOptions{
		ContentType: mimeType,
	})
	if err != nil {
		return "", fmt.Errorf("initiate multipart upload: %w", err)
	}

	return uploadID, nil
}

func (s *StorageService) PresignUploadPart(ctx context.Context, key, uploadID string, partNum int, ttl time.Duration) (string, error) {
	params := make(url.Values)
	params.Set("partNumber", strconv.Itoa(partNum))
	params.Set("uploadId", uploadID)

	u, err := s.core.PresignHeader(ctx, http.MethodPut, s.uploadsBucket, key, ttl, params, nil)
	if err != nil {
		return "", fmt.Errorf("presign upload part %d: %w", partNum, err)
	}

	return u.String(), nil
}

func (s *StorageService) CompleteUpload(ctx context.Context, key, uploadID string, parts []domain.CompletedPart) error {
	completed := make([]miniosdk.CompletePart, len(parts))
	for i, part := range parts {
		completed[i] = miniosdk.CompletePart{
			PartNumber: part.PartNumber,
			ETag:       part.ETag,
		}
	}

	_, err := s.core.CompleteMultipartUpload(ctx, s.uploadsBucket, key, uploadID, completed, miniosdk.PutObjectOptions{})
	if err != nil {
		return fmt.Errorf("complete multipart upload: %w", err)
	}

	return nil
}

func (s *StorageService) AbortUpload(ctx context.Context, key, uploadID string) error {
	if err := s.core.AbortMultipartUpload(ctx, s.uploadsBucket, key, uploadID); err != nil {
		code := miniosdk.ToErrorResponse(err).Code
		if strings.EqualFold(code, "NoSuchUpload") {
			return nil
		}
		return fmt.Errorf("abort multipart upload: %w", err)
	}

	return nil
}

func (s *StorageService) UploadExists(ctx context.Context, key string) (bool, error) {
	_, err := s.core.StatObject(ctx, s.uploadsBucket, key, miniosdk.StatObjectOptions{})
	if err == nil {
		return true, nil
	}

	code := miniosdk.ToErrorResponse(err).Code
	if strings.EqualFold(code, "NotFound") || strings.EqualFold(code, "NoSuchKey") || strings.EqualFold(code, "NoSuchObject") {
		return false, nil
	}

	return false, fmt.Errorf("stat upload object: %w", err)
}

func (s *StorageService) DeleteUpload(ctx context.Context, key string) error {
	return s.removeObjectIfExists(ctx, s.uploadsBucket, key, "delete upload object")
}

func (s *StorageService) UploadAvatar(ctx context.Context, key, mimeType string, body io.Reader, size int64) error {
	if _, err := s.core.Client.PutObject(ctx, s.avatarsBucket, key, body, size, miniosdk.PutObjectOptions{
		ContentType: mimeType,
	}); err != nil {
		return fmt.Errorf("upload avatar object: %w", err)
	}

	return nil
}

func (s *StorageService) DeleteAvatar(ctx context.Context, key string) error {
	return s.removeObjectIfExists(ctx, s.avatarsBucket, key, "delete avatar object")
}

func (s *StorageService) OpenUpload(ctx context.Context, key string) (io.ReadCloser, error) {
	obj, err := s.core.Client.GetObject(ctx, s.uploadsBucket, key, miniosdk.GetObjectOptions{})
	if err != nil {
		return nil, fmt.Errorf("get upload object: %w", err)
	}

	return obj, nil
}

func (s *StorageService) PromoteUpload(ctx context.Context, key string) error {
	if _, err := s.core.CopyObject(
		ctx,
		s.uploadsBucket,
		key,
		s.originalsBuck,
		key,
		nil,
		miniosdk.CopySrcOptions{},
		miniosdk.PutObjectOptions{},
	); err != nil {
		return fmt.Errorf("promote upload object: %w", err)
	}

	return nil
}

func (s *StorageService) PresignOriginalDownload(ctx context.Context, key string, ttl time.Duration) (string, error) {
	u, err := s.core.Client.PresignedGetObject(ctx, s.originalsBuck, key, ttl, nil)
	if err != nil {
		return "", fmt.Errorf("presign original download: %w", err)
	}

	return u.String(), nil
}

func (s *StorageService) PresignThumbnail(ctx context.Context, key string, ttl time.Duration) (string, error) {
	u, err := s.core.Client.PresignedGetObject(ctx, s.thumbsBucket, key, ttl, nil)
	if err != nil {
		return "", fmt.Errorf("presign thumbnail: %w", err)
	}

	return u.String(), nil
}

func (s *StorageService) OriginalExists(ctx context.Context, key string) (bool, error) {
	return s.objectExists(ctx, s.originalsBuck, key, "stat original object")
}

func (s *StorageService) ThumbnailExists(ctx context.Context, key string) (bool, error) {
	return s.objectExists(ctx, s.thumbsBucket, key, "stat thumbnail object")
}

func (s *StorageService) DeleteMediaAssets(ctx context.Context, media *domain.Media) error {
	if media == nil {
		return nil
	}

	var joined error
	if media.OriginalKey != "" {
		joined = errors.Join(
			joined,
			s.removeObjectIfExists(ctx, s.uploadsBucket, media.OriginalKey, "delete staged media object"),
			s.removeObjectIfExists(ctx, s.originalsBuck, media.OriginalKey, "delete original media object"),
		)
	}

	for _, key := range []string{
		media.ThumbKeys.Small,
		media.ThumbKeys.Medium,
		media.ThumbKeys.Large,
		media.ThumbKeys.Poster,
	} {
		if key == "" {
			continue
		}
		joined = errors.Join(joined, s.removeObjectIfExists(ctx, s.thumbsBucket, key, "delete thumbnail object"))
	}

	return joined
}

func (s *StorageService) objectExists(ctx context.Context, bucket, key, action string) (bool, error) {
	if _, err := s.core.StatObject(ctx, bucket, key, miniosdk.StatObjectOptions{}); err != nil {
		if isObjectNotFound(err) {
			return false, nil
		}
		return false, fmt.Errorf("%s: %w", action, err)
	}

	return true, nil
}

func (s *StorageService) removeObjectIfExists(ctx context.Context, bucket, key, action string) error {
	if key == "" {
		return nil
	}
	if err := s.core.RemoveObject(ctx, bucket, key, miniosdk.RemoveObjectOptions{}); err != nil && !isObjectNotFound(err) {
		return fmt.Errorf("%s: %w", action, err)
	}

	return nil
}

func isObjectNotFound(err error) bool {
	code := miniosdk.ToErrorResponse(err).Code
	return strings.EqualFold(code, "NotFound") ||
		strings.EqualFold(code, "NoSuchKey") ||
		strings.EqualFold(code, "NoSuchObject")
}
