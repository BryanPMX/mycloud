package httpapi

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/yourorg/mycloud/internal/delivery/http/handlers"
	"github.com/yourorg/mycloud/internal/delivery/http/middleware"
	pkgauth "github.com/yourorg/mycloud/pkg/auth"
)

type Dependencies struct {
	AppName      string
	AppEnv       string
	TokenService pkgauth.Service
	AuthHandler  *handlers.AuthHandler
	UserHandler  *handlers.UserHandler
	MediaHandler *handlers.MediaHandler
}

func NewRouter(deps Dependencies) *gin.Engine {
	if deps.AppEnv == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()
	router.Use(gin.Recovery())
	router.Use(middleware.RequestID())
	router.Use(middleware.StructuredLogger())

	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "ok",
			"service": deps.AppName,
		})
	})

	v1 := router.Group("/api/v1")
	authGroup := v1.Group("/auth")
	authGroup.POST("/login", deps.AuthHandler.Login)
	authGroup.POST("/refresh", deps.AuthHandler.Refresh)
	authGroup.POST("/logout", deps.AuthHandler.Logout)

	protected := v1.Group("/")
	protected.Use(middleware.RequireAuth(deps.TokenService))
	protected.GET("/users/me", deps.UserHandler.GetMe)
	protected.GET("/media", deps.MediaHandler.List)

	return router
}
