package redis

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	goredis "github.com/redis/go-redis/v9"

	"github.com/yourorg/mycloud/internal/domain"
)

type UploadSessionStore struct {
	client *goredis.Client
}

func NewUploadSessionStore(client *goredis.Client) *UploadSessionStore {
	return &UploadSessionStore{client: client}
}

func (s *UploadSessionStore) SaveUploadSession(ctx context.Context, session domain.UploadSession, ttl time.Duration) error {
	payload, err := json.Marshal(session)
	if err != nil {
		return err
	}

	return s.client.Set(ctx, uploadSessionKey(session.MediaID), payload, ttl).Err()
}

func (s *UploadSessionStore) GetUploadSession(ctx context.Context, mediaID uuid.UUID) (*domain.UploadSession, error) {
	payload, err := s.client.Get(ctx, uploadSessionKey(mediaID)).Bytes()
	if err == goredis.Nil {
		return nil, domain.ErrNotFound
	}
	if err != nil {
		return nil, err
	}

	var session domain.UploadSession
	if err := json.Unmarshal(payload, &session); err != nil {
		return nil, err
	}

	return &session, nil
}

func (s *UploadSessionStore) DeleteUploadSession(ctx context.Context, mediaID uuid.UUID) error {
	return s.client.Del(ctx, uploadSessionKey(mediaID)).Err()
}

func uploadSessionKey(mediaID uuid.UUID) string {
	return fmt.Sprintf("upload_session:%s", mediaID.String())
}
