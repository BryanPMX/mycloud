package redis

import (
	"context"
	"encoding/json"
	"fmt"

	goredis "github.com/redis/go-redis/v9"

	"github.com/yourorg/mycloud/internal/domain"
)

const mediaProgressChannel = "events:media_progress"

type MediaProgressBus struct {
	client *goredis.Client
}

func NewMediaProgressBus(client *goredis.Client) *MediaProgressBus {
	return &MediaProgressBus{client: client}
}

func (b *MediaProgressBus) PublishMediaProgress(ctx context.Context, event domain.MediaProgressEvent) error {
	payload, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("marshal media progress event: %w", err)
	}

	if err := b.client.Publish(ctx, mediaProgressChannel, payload).Err(); err != nil {
		return fmt.Errorf("publish media progress event: %w", err)
	}

	return nil
}

func (b *MediaProgressBus) SubscribeMediaProgress(ctx context.Context, handler func(domain.MediaProgressEvent)) error {
	pubsub := b.client.Subscribe(ctx, mediaProgressChannel)
	defer pubsub.Close()

	channel := pubsub.Channel()
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case message, ok := <-channel:
			if !ok {
				return nil
			}

			var event domain.MediaProgressEvent
			if err := json.Unmarshal([]byte(message.Payload), &event); err != nil {
				continue
			}
			handler(event)
		}
	}
}
