package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	pkgauth "github.com/yourorg/mycloud/pkg/auth"
)

const (
	contextUserIDKey = "auth.user_id"
	contextRoleKey   = "auth.role"
)

func RequireAuth(tokenService pkgauth.Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		rawToken := extractAccessToken(c)
		if rawToken == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": "missing token",
				"code":  "MISSING_TOKEN",
			})
			return
		}

		details, err := tokenService.ValidateAccessToken(rawToken)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": "invalid token",
				"code":  "INVALID_TOKEN",
			})
			return
		}

		c.Set(contextUserIDKey, details.UserID)
		c.Set(contextRoleKey, details.Role)
		c.Next()
	}
}

func UserIDFromContext(c *gin.Context) (uuid.UUID, bool) {
	value, ok := c.Get(contextUserIDKey)
	if !ok {
		return uuid.Nil, false
	}

	userID, ok := value.(uuid.UUID)
	return userID, ok
}

func extractAccessToken(c *gin.Context) string {
	header := strings.TrimSpace(c.GetHeader("Authorization"))
	if strings.HasPrefix(strings.ToLower(header), "bearer ") {
		return strings.TrimSpace(header[7:])
	}

	if cookie, err := c.Cookie("access_token"); err == nil {
		return strings.TrimSpace(cookie)
	}

	return ""
}
