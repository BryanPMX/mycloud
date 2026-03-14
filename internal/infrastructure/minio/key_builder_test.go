package minio

import (
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestKeyBuilderBuildMediaObjectKeyUsesFilenameExtension(t *testing.T) {
	t.Parallel()

	builder := NewKeyBuilder()
	ownerID := uuid.MustParse("11111111-1111-1111-1111-111111111111")
	mediaID := uuid.MustParse("22222222-2222-2222-2222-222222222222")

	key := builder.BuildMediaObjectKey(ownerID, mediaID, "Family Clip.MP4", "video/mp4", time.Date(2026, time.March, 13, 12, 0, 0, 0, time.UTC))
	want := "11111111-1111-1111-1111-111111111111/2026/03/22222222-2222-2222-2222-222222222222.mp4"
	if key != want {
		t.Fatalf("BuildMediaObjectKey() = %q, want %q", key, want)
	}
}

func TestKeyBuilderBuildMediaObjectKeyFallsBackToMIMEExtension(t *testing.T) {
	t.Parallel()

	builder := NewKeyBuilder()
	key := builder.BuildMediaObjectKey(uuid.New(), uuid.New(), "upload", "image/heic", time.Date(2026, time.March, 13, 12, 0, 0, 0, time.UTC))
	if len(key) < len(".heic") || key[len(key)-5:] != ".heic" {
		t.Fatalf("BuildMediaObjectKey() = %q, want .heic suffix", key)
	}
}

func TestKeyBuilderBuildThumbKeysIncludesPosterForVideo(t *testing.T) {
	t.Parallel()

	builder := NewKeyBuilder()
	mediaID := uuid.MustParse("22222222-2222-2222-2222-222222222222")

	keys := builder.BuildThumbKeys(mediaID, "video/mp4")
	if keys.Small != "22222222-2222-2222-2222-222222222222/small.webp" {
		t.Fatalf("BuildThumbKeys() small = %q", keys.Small)
	}
	if keys.Poster != "22222222-2222-2222-2222-222222222222/poster.webp" {
		t.Fatalf("BuildThumbKeys() poster = %q", keys.Poster)
	}
}

func TestKeyBuilderBuildAvatarObjectKeyUsesUserScopeAndImageExtension(t *testing.T) {
	t.Parallel()

	builder := NewKeyBuilder()
	userID := uuid.MustParse("11111111-1111-1111-1111-111111111111")

	key := builder.BuildAvatarObjectKey(userID, "image/png", time.Date(2026, time.March, 14, 16, 5, 9, 0, time.UTC))
	want := "users/11111111-1111-1111-1111-111111111111/avatar-20260314T160509.png"
	if key != want {
		t.Fatalf("BuildAvatarObjectKey() = %q, want %q", key, want)
	}
}
