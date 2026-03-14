package httpapi

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/yourorg/mycloud/internal/delivery/http/handlers"
	"github.com/yourorg/mycloud/internal/delivery/http/middleware"
	pkgauth "github.com/yourorg/mycloud/pkg/auth"
)

type Dependencies struct {
	AppName        string
	AppEnv         string
	TokenService   pkgauth.Service
	AuthHandler    *handlers.AuthHandler
	UserHandler    *handlers.UserHandler
	MediaHandler   *handlers.MediaHandler
	AlbumHandler   *handlers.AlbumHandler
	ShareHandler   *handlers.ShareHandler
	CommentHandler *handlers.CommentHandler
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
	protected.POST("/media/:id/favorite", deps.MediaHandler.Favorite)
	protected.DELETE("/media/:id/favorite", deps.MediaHandler.Unfavorite)
	protected.POST("/media/upload/init", deps.MediaHandler.InitUpload)
	protected.POST("/media/upload/:id/part-url", deps.MediaHandler.PresignPart)
	protected.POST("/media/upload/:id/complete", deps.MediaHandler.CompleteUpload)
	protected.GET("/albums", deps.AlbumHandler.List)
	protected.POST("/albums", deps.AlbumHandler.Create)
	protected.GET("/albums/:id", deps.AlbumHandler.Get)
	protected.PATCH("/albums/:id", deps.AlbumHandler.Update)
	protected.DELETE("/albums/:id", deps.AlbumHandler.Delete)
	protected.GET("/albums/:id/media", deps.AlbumHandler.ListMedia)
	protected.POST("/albums/:id/media", deps.AlbumHandler.AddMedia)
	protected.DELETE("/albums/:id/media/:mediaId", deps.AlbumHandler.RemoveMedia)
	protected.GET("/albums/:id/shares", deps.ShareHandler.List)
	protected.POST("/albums/:id/shares", deps.ShareHandler.Create)
	protected.DELETE("/albums/:id/shares/:shareId", deps.ShareHandler.Delete)
	protected.GET("/media/:id/comments", deps.CommentHandler.List)
	protected.POST("/media/:id/comments", deps.CommentHandler.Create)
	protected.DELETE("/media/:id/comments/:commentId", deps.CommentHandler.Delete)

	return router
}
