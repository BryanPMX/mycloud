package mime

import "strings"

var allowedMIMEs = map[string]struct{}{
	"image/jpeg":      {},
	"image/png":       {},
	"image/webp":      {},
	"image/heic":      {},
	"video/mp4":       {},
	"video/quicktime": {},
}

func IsAllowed(value string) bool {
	_, ok := allowedMIMEs[strings.ToLower(strings.TrimSpace(value))]
	return ok
}

func IsAllowedImage(value string) bool {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "image/jpeg", "image/png", "image/webp", "image/heic":
		return true
	default:
		return false
	}
}
