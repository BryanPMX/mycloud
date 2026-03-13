package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"

	authcmd "github.com/yourorg/mycloud/internal/application/commands/auth"
	"github.com/yourorg/mycloud/internal/delivery/http/dto"
	"github.com/yourorg/mycloud/pkg/httpx"
)

type AuthHandler struct {
	loginHandler   *authcmd.LoginHandler
	refreshHandler *authcmd.RefreshHandler
	logoutHandler  *authcmd.LogoutHandler
	secureCookies  bool
	refreshTTL     int
}

func NewAuthHandler(
	loginHandler *authcmd.LoginHandler,
	refreshHandler *authcmd.RefreshHandler,
	logoutHandler *authcmd.LogoutHandler,
	secureCookies bool,
	refreshTTLSeconds int,
) *AuthHandler {
	return &AuthHandler{
		loginHandler:   loginHandler,
		refreshHandler: refreshHandler,
		logoutHandler:  logoutHandler,
		secureCookies:  secureCookies,
		refreshTTL:     refreshTTLSeconds,
	}
}

func (h *AuthHandler) Login(c *gin.Context) {
	var request struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := httpx.BindJSON(c, &request); err != nil {
		writeError(c, errInvalidInput())
		return
	}

	result, err := h.loginHandler.Execute(c.Request.Context(), authcmd.LoginCommand{
		Email:    request.Email,
		Password: request.Password,
	})
	if err != nil {
		writeError(c, err)
		return
	}

	h.setAuthCookies(c, result.AccessToken, result.RefreshToken, result.ExpiresIn)
	c.JSON(http.StatusOK, gin.H{
		"access_token":  result.AccessToken,
		"refresh_token": result.RefreshToken,
		"expires_in":    result.ExpiresIn,
		"user":          dto.ToUserResponse(result.User),
	})
}

func (h *AuthHandler) Refresh(c *gin.Context) {
	refreshToken := extractTokenFromBodyOrCookie(c, "refresh_token")

	result, err := h.refreshHandler.Execute(c.Request.Context(), authcmd.RefreshCommand{
		RefreshToken: refreshToken,
	})
	if err != nil {
		h.clearAuthCookies(c)
		writeError(c, err)
		return
	}

	h.setAuthCookies(c, result.AccessToken, result.RefreshToken, result.ExpiresIn)
	c.JSON(http.StatusOK, gin.H{
		"access_token":  result.AccessToken,
		"refresh_token": result.RefreshToken,
		"expires_in":    result.ExpiresIn,
	})
}

func (h *AuthHandler) Logout(c *gin.Context) {
	refreshToken := extractTokenFromBodyOrCookie(c, "refresh_token")
	if err := h.logoutHandler.Execute(c.Request.Context(), authcmd.LogoutCommand{
		RefreshToken: refreshToken,
	}); err != nil {
		writeError(c, err)
		return
	}

	h.clearAuthCookies(c)
	c.Status(http.StatusNoContent)
}

func (h *AuthHandler) setAuthCookies(c *gin.Context, accessToken, refreshToken string, accessTTLSeconds int) {
	c.SetSameSite(http.SameSiteStrictMode)
	c.SetCookie("access_token", accessToken, accessTTLSeconds, "/", "", h.secureCookies, true)
	c.SetCookie("refresh_token", refreshToken, h.refreshTTL, "/api/v1/auth", "", h.secureCookies, true)
}

func (h *AuthHandler) clearAuthCookies(c *gin.Context) {
	c.SetSameSite(http.SameSiteStrictMode)
	c.SetCookie("access_token", "", -1, "/", "", h.secureCookies, true)
	c.SetCookie("refresh_token", "", -1, "/api/v1/auth", "", h.secureCookies, true)
}

func extractTokenFromBodyOrCookie(c *gin.Context, field string) string {
	var payload map[string]string
	_ = c.ShouldBindJSON(&payload)
	if value := payload[field]; value != "" {
		return value
	}

	cookie, _ := c.Cookie(field)
	return cookie
}
