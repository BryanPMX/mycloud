package handlers

import (
	"errors"
	"github.com/gin-gonic/gin"
	usercmd "github.com/yourorg/mycloud/internal/application/commands/users"
	"github.com/yourorg/mycloud/internal/delivery/http/middleware"
	"github.com/yourorg/mycloud/internal/domain"
	"net/http"
)

func ChangePassword(handler *usercmd.ChangePasswordHandler) gin.HandlerFunc {
	return func(c *gin.Context) {
		var request struct {
			Current string `json:"current_password"`
			Next    string `json:"new_password"`
		}
		if c.ShouldBindJSON(&request) != nil {
			writeError(c, domain.ErrInvalidInput)
			return
		}
		id, _ := middleware.UserIDFromContext(c)
		if err := handler.Execute(c.Request.Context(), id, request.Current, request.Next); err != nil {
			if errors.Is(err, domain.ErrInvalidCredentials) {
				c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"code": "CURRENT_PASSWORD_INCORRECT", "error": "Your current password does not match."})
				return
			}
			writeError(c, err)
			return
		}
		c.SetCookie("access_token", "", -1, "/", "", true, true)
		c.SetCookie("refresh_token", "", -1, "/api/v1/auth", "", true, true)
		c.Status(http.StatusNoContent)
	}
}
