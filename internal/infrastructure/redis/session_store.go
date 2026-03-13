package redis

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	goredis "github.com/redis/go-redis/v9"
)

type SessionStore struct {
	client *goredis.Client
}

func NewSessionStore(client *goredis.Client) *SessionStore {
	return &SessionStore{client: client}
}

func (s *SessionStore) StoreRefreshToken(ctx context.Context, userID uuid.UUID, jti string, ttl time.Duration) error {
	return s.client.Set(ctx, sessionKey(userID, jti), "1", ttl).Err()
}

func (s *SessionStore) ValidateRefreshToken(ctx context.Context, userID uuid.UUID, jti string) (bool, error) {
	result, err := s.client.Exists(ctx, sessionKey(userID, jti)).Result()
	if err != nil {
		return false, err
	}

	return result == 1, nil
}

func (s *SessionStore) RevokeRefreshToken(ctx context.Context, userID uuid.UUID, jti string) error {
	return s.client.Del(ctx, sessionKey(userID, jti)).Err()
}

func sessionKey(userID uuid.UUID, jti string) string {
	return fmt.Sprintf("session:%s:%s", userID.String(), jti)
}
