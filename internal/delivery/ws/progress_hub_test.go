package ws

import (
	"encoding/json"
	"testing"

	"github.com/google/uuid"

	"github.com/yourorg/mycloud/internal/domain"
)

func TestComputeAcceptKeyMatchesRFC6455Example(t *testing.T) {
	t.Parallel()

	const key = "dGhlIHNhbXBsZSBub25jZQ=="
	const want = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="

	if got := computeAcceptKey(key); got != want {
		t.Fatalf("computeAcceptKey() = %q, want %q", got, want)
	}
}

func TestProgressHubBroadcastRoutesEventsToMatchingUser(t *testing.T) {
	t.Parallel()

	userID := uuid.New()
	otherUserID := uuid.New()
	hub := NewProgressHub(nil)

	matchingClient := &progressClient{
		hub:    hub,
		userID: userID,
		send:   make(chan websocketFrame, 1),
		done:   make(chan struct{}),
	}
	otherClient := &progressClient{
		hub:    hub,
		userID: otherUserID,
		send:   make(chan websocketFrame, 1),
		done:   make(chan struct{}),
	}
	hub.register(matchingClient)
	hub.register(otherClient)

	hub.broadcast(domain.MediaProgressEvent{
		Type:    domain.MediaProgressComplete,
		MediaID: uuid.MustParse("550e8400-e29b-41d4-a716-446655440000"),
		OwnerID: userID,
		Status:  "ready",
		ThumbURLs: domain.ThumbKeys{
			Small: "550e8400-e29b-41d4-a716-446655440000/small.webp",
		},
	})

	select {
	case frame := <-matchingClient.send:
		if frame.opcode != websocketTextFrame {
			t.Fatalf("broadcast opcode = %d, want %d", frame.opcode, websocketTextFrame)
		}

		var message map[string]any
		if err := json.Unmarshal(frame.payload, &message); err != nil {
			t.Fatalf("json.Unmarshal() error = %v", err)
		}
		if got, want := message["type"], string(domain.MediaProgressComplete); got != want {
			t.Fatalf("message.type = %v, want %q", got, want)
		}
		if got, want := message["status"], "ready"; got != want {
			t.Fatalf("message.status = %v, want %q", got, want)
		}
	default:
		t.Fatal("broadcast did not reach the matching user client")
	}

	select {
	case <-otherClient.send:
		t.Fatal("broadcast reached a different user")
	default:
	}
}

func TestMarshalProgressMessageOmitsEmptyThumbURLs(t *testing.T) {
	t.Parallel()

	payload, err := marshalProgressMessage(domain.MediaProgressEvent{
		Type:    domain.MediaProgressFailed,
		MediaID: uuid.MustParse("550e8400-e29b-41d4-a716-446655440000"),
		OwnerID: uuid.New(),
		Reason:  "virus detected",
	})
	if err != nil {
		t.Fatalf("marshalProgressMessage() error = %v", err)
	}

	var message map[string]any
	if err := json.Unmarshal(payload, &message); err != nil {
		t.Fatalf("json.Unmarshal() error = %v", err)
	}
	if _, ok := message["thumb_urls"]; ok {
		t.Fatal("marshalProgressMessage() included empty thumb_urls")
	}
}
