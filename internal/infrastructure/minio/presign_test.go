package minio

import (
	"context"
	"net/url"
	"testing"
	"time"
)

func TestPresigningDoesNotContactPublicEndpoint(t *testing.T) {
	client, err := NewClient("unreachable.validation.invalid:9000", "validation", "validation-secret", false, "us-east-1")
	if err != nil {
		t.Fatal(err)
	}
	storage := NewStorageService(nil, client, "fc-uploads", "fc-originals", "fc-thumbs", "fc-avatars")
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	signed, err := storage.PresignUploadPart(ctx, "users/asset/original", "upload-id", 1, 5*time.Minute)
	if err != nil {
		t.Fatal("presigning contacted the public object endpoint", err)
	}
	parsed, err := url.Parse(signed)
	if err != nil {
		t.Fatal(err)
	}
	if parsed.Host != "unreachable.validation.invalid:9000" {
		t.Fatal("wrong public endpoint")
	}
	if _, err = storage.PresignOriginalDownload(ctx, "users/asset/original", 5*time.Minute); err != nil {
		t.Fatal(err)
	}
}
