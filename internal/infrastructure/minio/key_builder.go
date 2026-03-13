package minio

import (
	"fmt"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

type KeyBuilder struct{}

func NewKeyBuilder() *KeyBuilder {
	return &KeyBuilder{}
}

func (b *KeyBuilder) BuildMediaObjectKey(ownerID, mediaID uuid.UUID, filename, mimeType string, now time.Time) string {
	ts := now.UTC()
	return fmt.Sprintf("%s/%04d/%02d/%s%s",
		ownerID.String(),
		ts.Year(),
		int(ts.Month()),
		mediaID.String(),
		normalizedExtension(filename, mimeType),
	)
}

func (b *KeyBuilder) BuildThumbKeys(mediaID uuid.UUID, mimeType string) domain.ThumbKeys {
	keys := domain.ThumbKeys{
		Small:  fmt.Sprintf("%s/small.webp", mediaID.String()),
		Medium: fmt.Sprintf("%s/medium.webp", mediaID.String()),
		Large:  fmt.Sprintf("%s/large.webp", mediaID.String()),
	}
	if strings.HasPrefix(strings.ToLower(strings.TrimSpace(mimeType)), "video/") {
		keys.Poster = fmt.Sprintf("%s/poster.webp", mediaID.String())
	}

	return keys
}

func normalizedExtension(filename, mimeType string) string {
	raw := strings.ToLower(strings.TrimSpace(filepath.Ext(filename)))
	if ext := sanitizeExtension(raw); ext != "" {
		return ext
	}

	return sanitizeExtension(extensionFromMIME(mimeType))
}

func sanitizeExtension(value string) string {
	if value == "" {
		return ""
	}

	var b strings.Builder
	b.WriteByte('.')
	for _, r := range strings.TrimPrefix(value, ".") {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
		}
	}

	if b.Len() == 1 {
		return ""
	}

	return b.String()
}

func extensionFromMIME(mimeType string) string {
	switch strings.ToLower(strings.TrimSpace(mimeType)) {
	case "image/jpeg":
		return ".jpg"
	case "image/png":
		return ".png"
	case "image/webp":
		return ".webp"
	case "image/heic":
		return ".heic"
	case "video/mp4":
		return ".mp4"
	case "video/quicktime":
		return ".mov"
	default:
		return ""
	}
}
