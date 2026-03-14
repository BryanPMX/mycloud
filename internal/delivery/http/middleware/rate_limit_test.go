package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

func TestRateLimiterBlocksAfterLimit(t *testing.T) {
	t.Parallel()

	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(NewRateLimiter(RateLimitConfig{
		Name:   "test_login",
		Limit:  2,
		Window: time.Minute,
		KeyFunc: func(*gin.Context) string {
			return "192.0.2.10"
		},
	}))
	router.GET("/", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	for i := 0; i < 2; i++ {
		recorder := httptest.NewRecorder()
		request := httptest.NewRequest(http.MethodGet, "/", nil)
		router.ServeHTTP(recorder, request)
		if recorder.Code != http.StatusNoContent {
			t.Fatalf("request %d status = %d, want %d", i+1, recorder.Code, http.StatusNoContent)
		}
	}

	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/", nil)
	router.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusTooManyRequests {
		t.Fatalf("third request status = %d, want %d", recorder.Code, http.StatusTooManyRequests)
	}
}

func TestUserIDOrIPKeyPrefersAuthenticatedUser(t *testing.T) {
	t.Parallel()

	gin.SetMode(gin.TestMode)
	recorder := httptest.NewRecorder()
	context, _ := gin.CreateTestContext(recorder)
	context.Request = httptest.NewRequest(http.MethodGet, "/", nil)

	userID := uuid.New()
	context.Set(contextUserIDKey, userID)

	if got, want := UserIDOrIPKey(context), userID.String(); got != want {
		t.Fatalf("UserIDOrIPKey() = %q, want %q", got, want)
	}
}

func TestSecurityHeadersAddsExpectedDefaults(t *testing.T) {
	t.Parallel()

	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(SecurityHeaders(true))
	router.GET("/", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/", nil)
	router.ServeHTTP(recorder, request)

	if got, want := recorder.Header().Get("X-Frame-Options"), "DENY"; got != want {
		t.Fatalf("X-Frame-Options = %q, want %q", got, want)
	}
	if got, want := recorder.Header().Get("X-Content-Type-Options"), "nosniff"; got != want {
		t.Fatalf("X-Content-Type-Options = %q, want %q", got, want)
	}
	if got, want := recorder.Header().Get("Strict-Transport-Security"), "max-age=31536000; includeSubDomains"; got != want {
		t.Fatalf("Strict-Transport-Security = %q, want %q", got, want)
	}
}
