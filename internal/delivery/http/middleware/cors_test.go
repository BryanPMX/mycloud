package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestCORSAllowsConfiguredOrigin(t *testing.T) {
	t.Parallel()

	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(CORS([]string{"https://mynube.live"}))
	router.GET("/", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/", nil)
	request.Header.Set("Origin", "https://mynube.live")
	router.ServeHTTP(recorder, request)

	if got, want := recorder.Header().Get("Access-Control-Allow-Origin"), "https://mynube.live"; got != want {
		t.Fatalf("Access-Control-Allow-Origin = %q, want %q", got, want)
	}
	if got, want := recorder.Header().Get("Access-Control-Allow-Credentials"), "true"; got != want {
		t.Fatalf("Access-Control-Allow-Credentials = %q, want %q", got, want)
	}
}

func TestCORSRejectsPreflightForUnknownOrigin(t *testing.T) {
	t.Parallel()

	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(CORS([]string{"https://mynube.live"}))
	router.OPTIONS("/", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodOptions, "/", nil)
	request.Header.Set("Origin", "https://evil.example")
	request.Header.Set("Access-Control-Request-Method", http.MethodGet)
	router.ServeHTTP(recorder, request)

	if got, want := recorder.Code, http.StatusForbidden; got != want {
		t.Fatalf("preflight status = %d, want %d", got, want)
	}
}
