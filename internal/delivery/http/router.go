package httpapi

import (
	"context"
	"github.com/yourorg/mycloud/internal/infrastructure/observability"
	"log/slog"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/yourorg/mycloud/internal/domain"

	"github.com/yourorg/mycloud/internal/delivery/http/handlers"
	"github.com/yourorg/mycloud/internal/delivery/http/middleware"
	wsdelivery "github.com/yourorg/mycloud/internal/delivery/ws"
	pkgauth "github.com/yourorg/mycloud/pkg/auth"
)

type Dependencies struct {
	DeleteAccount  gin.HandlerFunc
	FamilyHandler  *handlers.FamilyHandler
	Metrics        *observability.Metrics
	Ready          func(context.Context) error
	Users          domain.UserRepository
	TrustedProxies []string
	AppName        string
	AppEnv         string
	AllowedOrigins []string
	TokenService   pkgauth.Service
	AuthHandler    *handlers.AuthHandler
	UserHandler    *handlers.UserHandler
	ProgressHub    *wsdelivery.ProgressHub
	MediaHandler   *handlers.MediaHandler
	AlbumHandler   *handlers.AlbumHandler
	ShareHandler   *handlers.ShareHandler
	CommentHandler *handlers.CommentHandler
	AdminHandler   *handlers.AdminHandler
}

func NewRouter(deps Dependencies) *gin.Engine {
	if deps.AppEnv == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()
	if err := router.SetTrustedProxies(deps.TrustedProxies); err != nil {
		panic("invalid trusted proxy configuration")
	}
	router.Use(middleware.BodyLimit(5 * 1024 * 1024))
	router.Use(func(c *gin.Context) {
		defer func() {
			if recover() != nil {
				slog.Error("http_panic")
				c.AbortWithStatus(http.StatusInternalServerError)
			}
		}()
		c.Next()
	})
	if deps.Metrics != nil {
		router.Use(deps.Metrics.Middleware())
	}
	router.Use(middleware.RequestID())
	router.Use(middleware.CORS(deps.AllowedOrigins))
	router.Use(middleware.SecurityHeaders(deps.AppEnv == "production"))
	router.Use(middleware.StructuredLogger())

	loginRateLimit := middleware.NewRateLimiter(middleware.RateLimitConfig{
		Name:    "auth_login",
		Limit:   5,
		Window:  15 * time.Minute,
		KeyFunc: middleware.ClientIPKey,
	})
	refreshRateLimit := middleware.NewRateLimiter(middleware.RateLimitConfig{
		Name:    "auth_refresh",
		Limit:   20,
		Window:  time.Minute,
		KeyFunc: middleware.ClientIPKey,
	})
	protectedRateLimit := middleware.NewRateLimiter(middleware.RateLimitConfig{
		Name:    "api_user",
		Limit:   300,
		Window:  time.Minute,
		KeyFunc: middleware.UserIDOrIPKey,
	})
	uploadInitRateLimit := middleware.NewRateLimiter(middleware.RateLimitConfig{
		Name:    "media_upload_init",
		Limit:   50,
		Window:  time.Hour,
		KeyFunc: middleware.UserIDOrIPKey,
	})
	partURLRateLimit := middleware.NewRateLimiter(middleware.RateLimitConfig{
		Name:    "media_upload_part",
		Limit:   300,
		Window:  time.Minute,
		KeyFunc: middleware.UserIDOrIPKey,
	})

	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "ok",
			"service": deps.AppName,
		})
	})
	router.GET("/health/ready", func(c *gin.Context) {
		ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
		defer cancel()
		if deps.Ready != nil && deps.Ready(ctx) != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"status": "unavailable"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": "ready"})
	})

	if deps.ProgressHub != nil {
		chain := []gin.HandlerFunc{middleware.RequireAuth(deps.TokenService)}
		if deps.Users != nil {
			chain = append(chain, middleware.RequireActiveAccount(deps.Users))
		}
		chain = append(chain, deps.ProgressHub.Handle)
		router.GET("/ws/progress", chain...)
	}

	v1 := router.Group("/api/v1")
	authGroup := v1.Group("/auth")
	authGroup.POST("/login", loginRateLimit, deps.AuthHandler.Login)
	authGroup.POST("/refresh", refreshRateLimit, deps.AuthHandler.Refresh)
	authGroup.POST("/logout", deps.AuthHandler.Logout)
	authGroup.POST("/invite/accept", loginRateLimit, deps.AuthHandler.AcceptInvite)

	protected := v1.Group("/")
	protected.Use(middleware.RequireAuth(deps.TokenService))
	if deps.Users != nil {
		protected.Use(middleware.RequireActiveAccount(deps.Users))
	}
	protected.Use(protectedRateLimit)
	if deps.DeleteAccount != nil {
		protected.POST("/users/me/delete", middleware.NewRateLimiter(middleware.RateLimitConfig{
			Name: "account_delete", Limit: 5, Window: 15 * time.Minute, KeyFunc: middleware.UserIDOrIPKey,
		}), deps.DeleteAccount)
	}
	protected.GET("/users/me", deps.UserHandler.GetMe)
	protected.PATCH("/users/me", deps.UserHandler.UpdateMe)
	protected.PUT("/users/me/avatar", deps.UserHandler.UpdateAvatar)
	protected.GET("/users/directory", deps.UserHandler.ListDirectory)
	protected.GET("/users/:id/avatar", deps.UserHandler.GetAvatarURL)
	protected.GET("/media", deps.MediaHandler.List)
	protected.GET("/media/search", deps.MediaHandler.Search)
	protected.GET("/media/trash", deps.MediaHandler.ListTrash)
	protected.DELETE("/media/trash", deps.MediaHandler.EmptyTrash)
	protected.POST("/media/:id/favorite", deps.MediaHandler.Favorite)
	protected.DELETE("/media/:id/favorite", deps.MediaHandler.Unfavorite)
	protected.POST("/media/upload/init", uploadInitRateLimit, deps.MediaHandler.InitUpload)
	protected.POST("/media/upload/:id/part-url", partURLRateLimit, deps.MediaHandler.PresignPart)
	protected.POST("/media/upload/:id/complete", deps.MediaHandler.CompleteUpload)
	protected.DELETE("/media/upload/:id", deps.MediaHandler.AbortUpload)
	protected.GET("/media/:id", deps.MediaHandler.Get)
	protected.GET("/media/:id/url", deps.MediaHandler.GetDownloadURL)
	protected.GET("/media/:id/thumb", deps.MediaHandler.GetThumbURL)
	protected.POST("/media/:id/restore", deps.MediaHandler.Restore)
	protected.DELETE("/media/:id/permanent", deps.MediaHandler.PermanentDelete)
	protected.DELETE("/media/:id", deps.MediaHandler.Delete)
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

	if h := deps.FamilyHandler; h != nil {
		protected.GET("/families", h.List)
		protected.POST("/families", h.Create)
		protected.POST("/families/invitations/accept", middleware.NewRateLimiter(middleware.RateLimitConfig{
			Name: "family_invitation_accept", Limit: 5, Window: 15 * time.Minute, KeyFunc: middleware.UserIDOrIPKey,
		}), h.Accept)
		protected.GET("/families/:familyID/members", h.Members)
		protected.DELETE("/families/:familyID/members/:userID", h.RemoveMember)
		protected.POST("/families/:familyID/invitations", uploadInitRateLimit, h.Invite)
		protected.GET("/families/:familyID/posts", h.Feed)
		protected.POST("/families/:familyID/posts", h.Post)
		protected.DELETE("/families/:familyID/posts/:postID", h.Unshare)
	}

	admin := protected.Group("/admin")
	admin.Use(middleware.RequireRole("admin"))
	admin.GET("/users", deps.AdminHandler.ListUsers)
	admin.POST("/users/invite", deps.AdminHandler.InviteUser)
	admin.PATCH("/users/:id", deps.AdminHandler.UpdateUser)
	admin.DELETE("/users/:id", deps.AdminHandler.DeactivateUser)
	admin.GET("/stats", deps.AdminHandler.SystemStats)

	return router
}
