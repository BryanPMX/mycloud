//go:build integration

package redis

import (
	"context"
	"github.com/google/uuid"
	goredis "github.com/redis/go-redis/v9"
	"os"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestIntegrationRefreshReplayIsAtomic(t *testing.T) {
	raw := os.Getenv("MYCLOUD_TEST_REDIS_URL")
	if raw == "" {
		t.Skip("isolated Redis URL required")
	}
	opts, err := goredis.ParseURL(raw)
	if err != nil {
		t.Fatal(err)
	}
	if opts.Addr != "127.0.0.1:56389" {
		t.Fatal("test requires isolated Redis port")
	}
	client := goredis.NewClient(opts)
	defer client.Close()
	store := NewSessionStore(client)
	ctx := context.Background()
	id := uuid.New()
	old := uuid.NewString()
	if err := store.StoreRefreshToken(ctx, id, old, time.Hour); err != nil {
		t.Fatal(err)
	}
	var successes atomic.Int32
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			ok, err := store.RotateRefreshToken(ctx, id, old, uuid.NewString(), time.Hour)
			if err != nil {
				t.Error(err)
			}
			if ok {
				successes.Add(1)
			}
		}()
	}
	wg.Wait()
	if successes.Load() != 1 {
		t.Fatalf("rotations=%d want=1", successes.Load())
	}
	if err := store.RevokeAllForUser(ctx, id); err != nil {
		t.Fatal(err)
	}
}
