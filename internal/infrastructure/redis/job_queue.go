package redis

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	goredis "github.com/redis/go-redis/v9"

	"github.com/yourorg/mycloud/internal/domain"
)

const jobQueueKey = "jobs:queue"

type JobQueue struct {
	client *goredis.Client
}

func NewJobQueue(client *goredis.Client) *JobQueue {
	return &JobQueue{client: client}
}

func (q *JobQueue) Enqueue(ctx context.Context, job *domain.Job) error {
	payload, err := json.Marshal(job)
	if err != nil {
		return fmt.Errorf("marshal job payload: %w", err)
	}

	if err := q.client.LPush(ctx, jobQueueKey, payload).Err(); err != nil {
		return fmt.Errorf("enqueue job: %w", err)
	}

	return nil
}

func (q *JobQueue) Dequeue(ctx context.Context, timeout time.Duration) (*domain.Job, error) {
	values, err := q.client.BRPop(ctx, timeout, jobQueueKey).Result()
	if err == nil {
		if len(values) != 2 {
			return nil, fmt.Errorf("unexpected BRPOP response length %d", len(values))
		}

		var job domain.Job
		if err := json.Unmarshal([]byte(values[1]), &job); err != nil {
			return nil, fmt.Errorf("decode queued job: %w", err)
		}

		return &job, nil
	}

	if errors.Is(err, goredis.Nil) {
		return nil, nil
	}
	if errors.Is(err, context.Canceled) {
		return nil, ctx.Err()
	}

	return nil, fmt.Errorf("dequeue job: %w", err)
}
