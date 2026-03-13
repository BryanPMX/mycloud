package minio

import (
	"context"
	"fmt"
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
}

func NewStorageService(core *miniosdk.Core, uploadsBucket string) *StorageService {
	return &StorageService{
		core:          core,
		uploadsBucket: uploadsBucket,
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
	if err := s.core.RemoveObject(ctx, s.uploadsBucket, key, miniosdk.RemoveObjectOptions{}); err != nil {
		return fmt.Errorf("delete upload object: %w", err)
	}

	return nil
}
