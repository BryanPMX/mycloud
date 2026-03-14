package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
)

const inviteTokenBytes = 32

func GenerateInviteToken() (string, error) {
	buf := make([]byte, inviteTokenBytes)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}

	return base64.RawURLEncoding.EncodeToString(buf), nil
}

func HashInviteToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func CompareInviteTokenHashes(expected, actual string) bool {
	return subtle.ConstantTimeCompare([]byte(expected), []byte(actual)) == 1
}
