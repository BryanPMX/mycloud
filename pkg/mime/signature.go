package mime

import (
	"bytes"
	"net/http"
)

// MatchesSignature checks bytes independently of filename and S3 content type.
// Container parsing and bounded decoding remain the worker's responsibility.
func MatchesSignature(mimeType string, header []byte) bool {
	switch mimeType {
	case "image/jpeg", "image/png", "image/webp":
		return http.DetectContentType(header) == mimeType
	case "video/mp4", "video/quicktime", "image/heic":
		if len(header) < 12 || !bytes.Equal(header[4:8], []byte("ftyp")) {
			return false
		}
		brand := string(header[8:12])
		if mimeType == "image/heic" {
			return brand == "heic" || brand == "heix" || brand == "hevc" || brand == "hevx" || brand == "mif1"
		}
		if mimeType == "video/quicktime" {
			return brand == "qt  "
		}
		return brand == "isom" || brand == "iso2" || brand == "mp41" || brand == "mp42" || brand == "avc1" || brand == "M4V " || brand == "MSNV"
	}
	return false
}
