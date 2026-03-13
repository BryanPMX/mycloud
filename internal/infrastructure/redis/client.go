package redis

import (
	"context"
	"time"

	goredis "github.com/redis/go-redis/v9"
)

func NewClient(redisURL string) (*goredis.Client, error) {
	options, err := goredis.ParseURL(redisURL)
	if err != nil {
		return nil, err
	}

	client := goredis.NewClient(options)
	pingCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := client.Ping(pingCtx).Err(); err != nil {
		_ = client.Close()
		return nil, err
	}

	return client, nil
}
