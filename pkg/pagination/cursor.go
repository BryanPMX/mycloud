package pagination

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
)

type TimeUUIDCursor struct {
	CreatedAt time.Time `json:"created_at"`
	ID        uuid.UUID `json:"id"`
}

func EncodeTimeUUID(createdAt time.Time, id uuid.UUID) (string, error) {
	payload, err := json.Marshal(TimeUUIDCursor{
		CreatedAt: createdAt.UTC(),
		ID:        id,
	})
	if err != nil {
		return "", err
	}

	return base64.RawURLEncoding.EncodeToString(payload), nil
}

func DecodeTimeUUID(raw string) (time.Time, uuid.UUID, error) {
	if raw == "" {
		return time.Time{}, uuid.Nil, errors.New("cursor is required")
	}

	data, err := base64.RawURLEncoding.DecodeString(raw)
	if err != nil {
		return time.Time{}, uuid.Nil, err
	}

	var cursor TimeUUIDCursor
	if err := json.Unmarshal(data, &cursor); err != nil {
		return time.Time{}, uuid.Nil, err
	}
	if cursor.ID == uuid.Nil || cursor.CreatedAt.IsZero() {
		return time.Time{}, uuid.Nil, errors.New("cursor is invalid")
	}

	return cursor.CreatedAt.UTC(), cursor.ID, nil
}
