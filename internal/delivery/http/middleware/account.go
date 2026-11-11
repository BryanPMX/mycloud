package middleware

import (
	"github.com/gin-gonic/gin"
	"github.com/yourorg/mycloud/internal/domain"
	"net/http"
)

// RequireActiveAccount checks current database state, including revoked admin roles.
func RequireActiveAccount(users domain.UserRepository) gin.HandlerFunc {
	return func(c *gin.Context) {
		id, ok := UserIDFromContext(c)
		if !ok {
			c.AbortWithStatus(http.StatusUnauthorized)
			return
		}
		user, err := users.FindByID(c.Request.Context(), id)
		version, _ := c.Get(contextAuthVersionKey)
		currentVersion, _ := version.(int64)
		if err != nil || !user.Active || user.AuthVersion != currentVersion {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "inactive account", "code": "UNAUTHORIZED"})
			return
		}
		c.Set(contextRoleKey, string(user.Role))
		c.Next()
	}
}

func BodyLimit(bytes int64) gin.HandlerFunc {
	return func(c *gin.Context) { c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, bytes); c.Next() }
}
