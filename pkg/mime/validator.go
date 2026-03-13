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
