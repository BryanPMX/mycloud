package pagination

import (
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestTimeUUIDCursorRoundTrip(t *testing.T) {
	t.Parallel()

	now := time.Now().UTC().Truncate(time.Second)
	id := uuid.New()

	cursor, err := EncodeTimeUUID(now, id)
	if err != nil {
		t.Fatalf("EncodeTimeUUID() error = %v", err)
	}

	gotTime, gotID, err := DecodeTimeUUID(cursor)
	if err != nil {
		t.Fatalf("DecodeTimeUUID() error = %v", err)
	}
	if !gotTime.Equal(now) {
		t.Fatalf("DecodeTimeUUID() time = %s, want %s", gotTime, now)
	}
	if gotID != id {
		t.Fatalf("DecodeTimeUUID() id = %s, want %s", gotID, id)
	}
}

func TestDecodeTimeUUIDRejectsInvalidCursor(t *testing.T) {
	t.Parallel()

	if _, _, err := DecodeTimeUUID("not-a-cursor"); err == nil {
		t.Fatal("DecodeTimeUUID() error = nil, want failure")
	}
}
