package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

func CORS(allowedOrigins []string) gin.HandlerFunc {
	allowed := make(map[string]struct{}, len(allowedOrigins))
	for _, origin := range allowedOrigins {
		trimmed := strings.TrimRight(strings.TrimSpace(origin), "/")
		if trimmed == "" {
			continue
		}
		allowed[trimmed] = struct{}{}
	}

	const (
		allowMethods        = "GET, POST, PUT, PATCH, DELETE, OPTIONS"
		defaultAllowHeaders = "Accept, Authorization, Content-Type, X-Request-ID"
		exposeHeaders       = "X-Request-ID"
	)

	return func(c *gin.Context) {
		origin := strings.TrimRight(strings.TrimSpace(c.GetHeader("Origin")), "/")
		if origin != "" {
			if _, ok := allowed[origin]; ok {
				headers := c.Writer.Header()
				addVaryHeader(headers, "Origin")
				addVaryHeader(headers, "Access-Control-Request-Headers")
				headers.Set("Access-Control-Allow-Origin", origin)
				headers.Set("Access-Control-Allow-Credentials", "true")
				headers.Set("Access-Control-Allow-Methods", allowMethods)
				headers.Set("Access-Control-Expose-Headers", exposeHeaders)
				headers.Set("Access-Control-Max-Age", "600")

				requestHeaders := strings.TrimSpace(c.GetHeader("Access-Control-Request-Headers"))
				if requestHeaders == "" {
					requestHeaders = defaultAllowHeaders
				}
				headers.Set("Access-Control-Allow-Headers", requestHeaders)
			}
		}

		if c.Request.Method == http.MethodOptions {
			if origin == "" {
				c.AbortWithStatus(http.StatusNoContent)
				return
			}
			if _, ok := allowed[origin]; !ok {
				c.AbortWithStatus(http.StatusForbidden)
				return
			}
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}

func addVaryHeader(headers http.Header, value string) {
	existing := headers.Values("Vary")
	for _, entry := range existing {
		for _, current := range strings.Split(entry, ",") {
			if strings.EqualFold(strings.TrimSpace(current), value) {
				return
			}
		}
	}

	headers.Add("Vary", value)
}
