package minio

import (
	"context"
	"fmt"

	miniosdk "github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

func NewCore(ctx context.Context, endpoint, accessKey, secretKey string, secure bool, buckets ...string) (*miniosdk.Core, error) {
	core, err := miniosdk.NewCore(endpoint, &miniosdk.Options{
		Creds:  credentials.NewStaticV4(accessKey, secretKey, ""),
		Secure: secure,
	})
	if err != nil {
		return nil, fmt.Errorf("create minio core: %w", err)
	}

	for _, bucket := range buckets {
		exists, err := core.BucketExists(ctx, bucket)
		if err != nil {
			return nil, fmt.Errorf("check bucket %q: %w", bucket, err)
		}
		if exists {
			continue
		}

		if err := core.MakeBucket(ctx, bucket, miniosdk.MakeBucketOptions{}); err != nil {
			return nil, fmt.Errorf("create bucket %q: %w", bucket, err)
		}
	}

	return core, nil
}
