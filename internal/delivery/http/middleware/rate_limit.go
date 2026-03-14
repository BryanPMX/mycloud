package middleware

import (
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

type RateLimitConfig struct {
	Name    string
	Limit   int
	Window  time.Duration
	KeyFunc func(*gin.Context) string
}

type rateWindow struct {
	count   int
	resetAt time.Time
}

type fixedWindowLimiter struct {
	mu          sync.Mutex
	buckets     map[string]rateWindow
	nextCleanup time.Time
}

func NewRateLimiter(config RateLimitConfig) gin.HandlerFunc {
	limiter := &fixedWindowLimiter{
		buckets: make(map[string]rateWindow),
	}

	return func(c *gin.Context) {
		if c.Request.Method == http.MethodOptions {
			c.Next()
			return
		}

		key := "anonymous"
		if config.KeyFunc != nil {
			if raw := strings.TrimSpace(config.KeyFunc(c)); raw != "" {
				key = raw
			}
		}

		allowed, remaining, resetAt := limiter.allow(config.Name+":"+key, config.Limit, config.Window, time.Now().UTC())
		c.Header("X-RateLimit-Limit", strconv.Itoa(config.Limit))
		c.Header("X-RateLimit-Remaining", strconv.Itoa(remaining))
		c.Header("X-RateLimit-Reset", strconv.FormatInt(resetAt.Unix(), 10))
		if allowed {
			c.Next()
			return
		}

		retryAfter := int(time.Until(resetAt).Seconds())
		if retryAfter < 1 {
			retryAfter = 1
		}
		c.Header("Retry-After", strconv.Itoa(retryAfter))
		c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
			"error": "rate limit exceeded",
			"code":  "RATE_LIMITED",
		})
	}
}

func ClientIPKey(c *gin.Context) string {
	return strings.TrimSpace(c.ClientIP())
}

func UserIDOrIPKey(c *gin.Context) string {
	if userID, ok := UserIDFromContext(c); ok {
		return userID.String()
	}

	return ClientIPKey(c)
}

func (l *fixedWindowLimiter) allow(key string, limit int, window time.Duration, now time.Time) (bool, int, time.Time) {
	l.mu.Lock()
	defer l.mu.Unlock()

	if limit <= 0 || window <= 0 {
		return true, 0, now
	}
	if l.nextCleanup.IsZero() || !now.Before(l.nextCleanup) {
		for bucketKey, bucket := range l.buckets {
			if !now.Before(bucket.resetAt) {
				delete(l.buckets, bucketKey)
			}
		}
		l.nextCleanup = now.Add(window)
	}

	bucket, ok := l.buckets[key]
	if !ok || !now.Before(bucket.resetAt) {
		bucket = rateWindow{
			count:   0,
			resetAt: now.Add(window),
		}
	}
	bucket.count++
	l.buckets[key] = bucket

	remaining := limit - bucket.count
	if remaining < 0 {
		remaining = 0
	}

	return bucket.count <= limit, remaining, bucket.resetAt
}
