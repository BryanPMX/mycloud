# 02 — Go Backend

Current implementation note on March 14, 2026:
- This document started as the backend starter blueprint. The checked-in backend has expanded beyond the minimal tree below and now includes admin, favorites, comments, trash lifecycle, audit logging, self-service profile writes, avatar uploads, rate limiting, security headers, SMTP invite delivery, scheduled cleanup jobs, real thumbnail generation, richer metadata extraction, and Redis-backed WebSocket progress delivery.
- The main backend/database work remaining is now incremental hardening and polish rather than missing major slices.

---

## 1. Project Layout

```
mycloud/
├── cmd/
│   ├── server/
│   │   └── main.go               # HTTP server entry point — composition root
│   └── worker/
│       └── main.go               # Media worker entry point
├── internal/
│   ├── domain/
│   │   ├── user.go
│   │   ├── media.go
│   │   ├── album.go
│   │   ├── share.go
│   │   ├── comment.go
│   │   ├── job.go
│   │   ├── repositories.go       # All repository interfaces
│   │   ├── services.go           # StorageService, JobQueue, VirusScanner interfaces
│   │   ├── errors.go
│   │   └── events.go
│   ├── application/
│   │   ├── commands/
│   │   │   ├── upload_media.go
│   │   │   ├── complete_upload.go
│   │   │   ├── delete_media.go
│   │   │   ├── create_album.go
│   │   │   ├── add_to_album.go
│   │   │   ├── share_album.go
│   │   │   ├── revoke_share.go
│   │   │   ├── add_comment.go
│   │   │   └── delete_comment.go
│   │   └── queries/
│   │       ├── list_media.go
│   │       ├── get_media.go
│   │       ├── list_albums.go
│   │       ├── get_album.go
│   │       ├── search_media.go
│   │       ├── get_user_stats.go
│   │       └── admin_dashboard.go
│   ├── infrastructure/
│   │   ├── postgres/
│   │   │   ├── pool.go
│   │   │   ├── user_repository.go
│   │   │   ├── media_repository.go
│   │   │   ├── album_repository.go
│   │   │   ├── share_repository.go
│   │   │   ├── comment_repository.go
│   │   │   └── job_repository.go
│   │   ├── minio/
│   │   │   ├── client.go
│   │   │   └── storage_service.go
│   │   ├── redis/
│   │   │   ├── client.go
│   │   │   ├── session_store.go
│   │   │   └── job_queue.go
│   │   ├── worker/
│   │   │   ├── registry.go
│   │   │   ├── image_processor.go  # libvips via govips
│   │   │   ├── video_processor.go  # FFmpeg via os/exec
│   │   │   └── job_runner.go
│   │   └── clamav/
│   │       └── scanner.go
│   └── delivery/
│       ├── http/
│       │   ├── router.go
│       │   ├── middleware/
│       │   │   ├── auth.go
│       │   │   ├── request_id.go
│       │   │   ├── logger.go
│       │   │   ├── rate_limit.go
│       │   │   └── cors.go
│       │   └── handlers/
│       │       ├── auth_handler.go
│       │       ├── media_handler.go
│       │       ├── album_handler.go
│       │       ├── share_handler.go
│       │       ├── comment_handler.go
│       │       ├── user_handler.go
│       │       └── admin_handler.go
│       └── ws/
│           └── progress_hub.go     # Media processing status WebSocket
├── pkg/
│   ├── auth/
│   │   ├── jwt.go                  # Token generation and validation
│   │   └── password.go             # bcrypt helpers
│   ├── mime/
│   │   └── validator.go            # MIME type allow-list
│   ├── pagination/
│   │   └── cursor.go               # Keyset cursor encoding/decoding
│   └── config/
│       └── config.go               # Env-var config loading
├── migrations/
│   ├── 001_initial_schema.sql
│   ├── 002_add_jobs_table.sql
│   └── 003_add_comments.sql
├── docker-compose.yml
├── Dockerfile.api
├── Dockerfile.worker
├── go.mod
└── go.sum
```

---

## 2. Go Module and Core Dependencies

```go
// go.mod
module github.com/yourorg/mycloud

go 1.22

require (
    github.com/gin-gonic/gin          v1.9.1
    github.com/google/uuid            v1.6.0
    github.com/jackc/pgx/v5           v5.5.5   // PostgreSQL driver + pgxpool
    github.com/jmoiron/sqlx           v1.3.5   // Struct scanning on top of pgx
    github.com/redis/go-redis/v9      v9.5.1
    github.com/minio/minio-go/v7      v7.0.70
    github.com/golang-jwt/jwt/v5      v5.2.1
    github.com/davidbyttow/govips/v2  v2.14.0  // libvips Go bindings
    golang.org/x/crypto               v0.22.0  // bcrypt
    github.com/prometheus/client_golang v1.19.0
    github.com/duosecurity/duo_api_golang v0.0.0 // optional 2FA
)
```

---

## 3. Domain Entities

### User

```go
// internal/domain/user.go
package domain

import (
    "time"
    "github.com/google/uuid"
)

type UserRole string

const (
    RoleMember UserRole = "member"
    RoleAdmin  UserRole = "admin"
)

type User struct {
    ID           uuid.UUID
    Email        string
    DisplayName  string
    AvatarKey    string    // MinIO object key, may be empty
    Role         UserRole
    PasswordHash string    // bcrypt, never exposed to clients
    StorageUsed  int64     // bytes, maintained by triggers
    QuotaBytes   int64     // default 20 GB, overrideable per user
    Active       bool
    CreatedAt    time.Time
    LastLoginAt  *time.Time
}

func (u *User) IsAdmin() bool { return u.Role == RoleAdmin }
func (u *User) StoragePercent() float64 {
    if u.QuotaBytes == 0 { return 0 }
    return float64(u.StorageUsed) / float64(u.QuotaBytes) * 100
}
func (u *User) HasQuotaFor(bytes int64) bool {
    return u.StorageUsed+bytes <= u.QuotaBytes
}
```

### Album

```go
// internal/domain/album.go
package domain

import (
    "time"
    "github.com/google/uuid"
)

type Album struct {
    ID           uuid.UUID
    OwnerID      uuid.UUID
    Name         string
    Description  string
    CoverMediaID *uuid.UUID // nil = use most recent media
    MediaCount   int        // denormalized for fast display
    CreatedAt    time.Time
    UpdatedAt    time.Time
}
```

### Share

```go
// internal/domain/share.go
package domain

import (
    "time"
    "github.com/google/uuid"
)

type Permission string

const (
    PermissionView     Permission = "view"
    PermissionContribute Permission = "contribute" // can upload to shared album
)

type Share struct {
    ID          uuid.UUID
    AlbumID     uuid.UUID
    SharedBy    uuid.UUID
    SharedWith  uuid.UUID   // uuid.Nil = shared with all family
    Permission  Permission
    ExpiresAt   *time.Time  // nil = never expires
    CreatedAt   time.Time
}

func (s *Share) IsExpired() bool {
    return s.ExpiresAt != nil && time.Now().After(*s.ExpiresAt)
}

func (s *Share) IsPublicToFamily() bool {
    return s.SharedWith == uuid.Nil
}
```

---

## 4. Repository Interfaces

```go
// internal/domain/repositories.go
package domain

import (
    "context"
    "time"
    "github.com/google/uuid"
)

// ── Users ──────────────────────────────────────────────────────────────────

type UserRepository interface {
    Create(ctx context.Context, u *User) error
    FindByID(ctx context.Context, id uuid.UUID) (*User, error)
    FindByEmail(ctx context.Context, email string) (*User, error)
    Update(ctx context.Context, u *User) error
    UpdateStorageUsed(ctx context.Context, id uuid.UUID, deltaBytes int64) error
    SetActive(ctx context.Context, id uuid.UUID, active bool) error
    List(ctx context.Context) ([]*User, error) // admin only
}

// ── Media ──────────────────────────────────────────────────────────────────

type MediaRepository interface {
    Create(ctx context.Context, m *Media) error
    FindByID(ctx context.Context, id uuid.UUID) (*Media, error)
    FindByIDForUser(ctx context.Context, id, userID uuid.UUID) (*Media, error)
    List(ctx context.Context, ownerID uuid.UUID, opts ListOptions) (MediaPage, error)
    ListSharedWith(ctx context.Context, userID uuid.UUID, opts ListOptions) (MediaPage, error)
    Search(ctx context.Context, q SearchQuery) (MediaPage, error)
    UpdateStatus(ctx context.Context, id uuid.UUID, status MediaStatus, r *ProcessingResult) error
    SetThumbKeys(ctx context.Context, id uuid.UUID, keys ThumbKeys) error
    SoftDelete(ctx context.Context, id uuid.UUID) error
    HardDelete(ctx context.Context, id uuid.UUID) error // admin or scheduled cleanup
}

type ListOptions struct {
    Cursor    string
    Limit     int
    SortBy    string     // "uploaded_at" | "taken_at" | "filename" | "size_bytes"
    SortOrder string     // "asc" | "desc"
    MimeTypes []string
    AlbumID   *uuid.UUID
    DateFrom  *time.Time
    DateTo    *time.Time
    Favorites bool
}

type SearchQuery struct {
    OwnerID   uuid.UUID
    Text      string
    ListOptions
}

type MediaPage struct {
    Items      []*Media
    NextCursor string
    Total      int64
}

type ProcessingResult struct {
    Width        int
    Height       int
    DurationSecs float64
    ThumbKeys    ThumbKeys
    Metadata     map[string]any
}

// ── Albums ─────────────────────────────────────────────────────────────────

type AlbumRepository interface {
    Create(ctx context.Context, a *Album) error
    FindByID(ctx context.Context, id uuid.UUID) (*Album, error)
    FindByIDForUser(ctx context.Context, id, userID uuid.UUID) (*Album, error)
    ListByOwner(ctx context.Context, ownerID uuid.UUID) ([]*Album, error)
    ListSharedWith(ctx context.Context, userID uuid.UUID) ([]*Album, error)
    Update(ctx context.Context, a *Album) error
    AddMedia(ctx context.Context, albumID, mediaID uuid.UUID) error
    RemoveMedia(ctx context.Context, albumID, mediaID uuid.UUID) error
    ListMedia(ctx context.Context, albumID uuid.UUID, opts ListOptions) (MediaPage, error)
    Delete(ctx context.Context, id uuid.UUID) error
}

// ── Shares ─────────────────────────────────────────────────────────────────

type ShareRepository interface {
    Create(ctx context.Context, s *Share) error
    FindByAlbum(ctx context.Context, albumID uuid.UUID) ([]*Share, error)
    FindForUser(ctx context.Context, userID uuid.UUID) ([]*Share, error)
    Revoke(ctx context.Context, id uuid.UUID) error
    RevokeAll(ctx context.Context, albumID uuid.UUID) error
}

// ── Comments ───────────────────────────────────────────────────────────────

type CommentRepository interface {
    Create(ctx context.Context, c *Comment) error
    FindByMedia(ctx context.Context, mediaID uuid.UUID) ([]*Comment, error)
    Delete(ctx context.Context, id, requestingUserID uuid.UUID) error // owner or admin
}
```

---

## 5. Service Interfaces

```go
// internal/domain/services.go
package domain

import (
    "context"
    "io"
    "time"
    "github.com/google/uuid"
)

// StorageService abstracts MinIO
type StorageService interface {
    // Initiate a multipart upload in the staging bucket.
    InitiateUpload(ctx context.Context, key string, mimeType string) (uploadID string, err error)
    // Generate a presigned PUT URL for one multipart part.
    PresignUploadPart(ctx context.Context, bucket, key, uploadID string, part int, ttl time.Duration) (url string, err error)
    // Finalize multipart upload in the staging bucket.
    CompleteUpload(ctx context.Context, key, uploadID string, parts []CompletedPart) error
    // Abort and clean up a failed multipart upload.
    AbortUpload(ctx context.Context, key, uploadID string) error
    // Generate a time-limited presigned GET URL for a client to download.
    PresignGet(ctx context.Context, bucket, key string, ttl time.Duration) (string, error)
    // Store a thumbnail or processed output.
    PutObject(ctx context.Context, bucket, key string, r io.Reader, size int64, mimeType string) error
    // Stream an object for scanning or processing.
    GetObject(ctx context.Context, bucket, key string) (io.ReadCloser, error)
    // Delete an object.
    Delete(ctx context.Context, bucket, key string) error
    // Copy or promote a clean upload from staging into permanent storage.
    Copy(ctx context.Context, srcBucket, srcKey, dstBucket, dstKey string) error
}

// JobQueue abstracts the best-effort Redis queue used for background jobs.
type JobQueue interface {
    Enqueue(ctx context.Context, job *Job) error
    Dequeue(ctx context.Context, timeout time.Duration) (*Job, error)
    Ack(ctx context.Context, jobID uuid.UUID) error
    Fail(ctx context.Context, jobID uuid.UUID, err error) error
}

// VirusScanner abstracts ClamAV
type VirusScanner interface {
    ScanReader(ctx context.Context, r io.Reader) (clean bool, threat string, err error)
}

// SessionStore abstracts Redis for refresh token management
type SessionStore interface {
    StoreRefreshToken(ctx context.Context, userID uuid.UUID, token string, ttl time.Duration) error
    ValidateRefreshToken(ctx context.Context, userID uuid.UUID, token string) (bool, error)
    RevokeRefreshToken(ctx context.Context, userID uuid.UUID, token string) error
    RevokeAllForUser(ctx context.Context, userID uuid.UUID) error // on password change
}
```

---

## 6. HTTP Router and Middleware

```go
// internal/delivery/http/router.go
package http

import (
    "github.com/gin-gonic/gin"
    "github.com/yourorg/mycloud/internal/delivery/http/handlers"
    "github.com/yourorg/mycloud/internal/delivery/http/middleware"
)

func NewRouter(deps Dependencies, cfg Config) *gin.Engine {
    if cfg.Production {
        gin.SetMode(gin.ReleaseMode)
    }
    r := gin.New() // not gin.Default() — we control our own middleware stack

    // Global middleware (order matters)
    r.Use(middleware.Recovery())         // panic → 500, never crash the server
    r.Use(middleware.RequestID())        // inject X-Request-ID
    r.Use(middleware.StructuredLogger()) // log every request with request_id
    r.Use(middleware.CORS(cfg.AllowedOrigins))
    r.Use(middleware.SecurityHeaders())  // X-Frame-Options, CSP, etc.

    // Prometheus metrics endpoint (unauthenticated, but only accessible from localhost via Nginx ACL)
    r.GET("/metrics", gin.WrapH(deps.MetricsHandler))
    r.GET("/health", handlers.Health)

    api := r.Group("/api/v1")

    // ── Auth (no JWT required) ──────────────────────────────────────────
    auth := api.Group("/auth")
    {
        auth.POST("/login",         deps.AuthHandler.Login)
        auth.POST("/refresh",       deps.AuthHandler.RefreshToken)
        auth.POST("/logout",        deps.AuthHandler.Logout)
        auth.POST("/invite/accept", deps.AuthHandler.AcceptInvite) // from admin invite link
    }

    // ── Authenticated routes ────────────────────────────────────────────
    authed := api.Group("/", middleware.Auth(deps.JWTService))

    // Users
    users := authed.Group("/users")
    {
        users.GET("/me",             deps.UserHandler.GetMe)
        users.PATCH("/me",           deps.UserHandler.UpdateMe)
        users.PUT("/me/avatar",      deps.UserHandler.UploadAvatar)
    }

    // Media
    media := authed.Group("/media")
    {
        media.GET("",                deps.MediaHandler.List)             // list with filters
        media.GET("/search",         deps.MediaHandler.Search)
        media.GET("/trash",          deps.MediaHandler.ListTrash)
        media.DELETE("/trash",       deps.MediaHandler.EmptyTrash)
        media.POST("/upload/init",   deps.MediaHandler.InitUpload)       // start direct multipart upload
        media.POST("/upload/:id/part-url", deps.MediaHandler.PresignUploadPart)
        media.POST("/upload/:id/complete", deps.MediaHandler.CompleteUpload)
        media.DELETE("/upload/:id",  deps.MediaHandler.AbortUpload)
        media.GET("/:id",            deps.MediaHandler.Get)              // metadata
        media.GET("/:id/url",        deps.MediaHandler.GetDownloadURL)   // presigned URL
        media.GET("/:id/thumb",      deps.MediaHandler.GetThumbURL)      // thumbnail presigned URL
        media.POST("/:id/favorite",  deps.MediaHandler.Favorite)
        media.DELETE("/:id/favorite", deps.MediaHandler.Unfavorite)
        media.POST("/:id/restore",   deps.MediaHandler.Restore)
        media.DELETE("/:id/permanent", deps.MediaHandler.PermanentDelete)
        media.DELETE("/:id",         deps.MediaHandler.Delete)
    }

    // Albums
    albums := authed.Group("/albums")
    {
        albums.GET("",               deps.AlbumHandler.List)
        albums.POST("",              deps.AlbumHandler.Create)
        albums.GET("/:id",           deps.AlbumHandler.Get)
        albums.PATCH("/:id",         deps.AlbumHandler.Update)
        albums.DELETE("/:id",        deps.AlbumHandler.Delete)
        albums.GET("/:id/media",     deps.AlbumHandler.ListMedia)
        albums.POST("/:id/media",    deps.AlbumHandler.AddMedia)
        albums.DELETE("/:id/media/:mediaId", deps.AlbumHandler.RemoveMedia)
        albums.POST("/:id/shares",   deps.ShareHandler.Create)
        albums.GET("/:id/shares",    deps.ShareHandler.List)
        albums.DELETE("/:id/shares/:shareId", deps.ShareHandler.Revoke)
    }

    // Comments
    authed.GET("/media/:id/comments",        deps.CommentHandler.List)
    authed.POST("/media/:id/comments",       deps.CommentHandler.Create)
    authed.DELETE("/media/:id/comments/:cid",deps.CommentHandler.Delete)

    // Admin routes (require RoleAdmin)
    admin := authed.Group("/admin", middleware.RequireRole("admin"))
    {
        admin.GET("/users",             deps.AdminHandler.ListUsers)
        admin.POST("/users/invite",     deps.AdminHandler.InviteUser)
        admin.PATCH("/users/:id",       deps.AdminHandler.UpdateUser)
        admin.DELETE("/users/:id",      deps.AdminHandler.DeactivateUser)
        admin.GET("/stats",             deps.AdminHandler.SystemStats)
        admin.POST("/maintenance/cleanup", deps.AdminHandler.TriggerCleanup)
    }

    // WebSocket — media processing notifications
    authed.GET("/ws/progress", deps.ProgressHub.Handle)

    return r
}
```

---

## 7. Middleware

### Auth Middleware

```go
// internal/delivery/http/middleware/auth.go
package middleware

import (
    "net/http"
    "strings"

    "github.com/gin-gonic/gin"
    "github.com/yourorg/mycloud/pkg/auth"
)

const UserIDKey = "user_id"
const UserRoleKey = "user_role"

func Auth(jwtSvc auth.JWTService) gin.HandlerFunc {
    return func(c *gin.Context) {
        token := ""
        header := c.GetHeader("Authorization")
        if strings.HasPrefix(header, "Bearer ") {
            token = strings.TrimPrefix(header, "Bearer ")
        } else if cookie, err := c.Cookie("access_token"); err == nil {
            token = cookie
        }

        if token == "" {
            c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing access token"})
            return
        }

        claims, err := jwtSvc.ValidateAccessToken(token)
        if err != nil {
            c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
            return
        }

        c.Set(UserIDKey, claims.UserID)
        c.Set(UserRoleKey, claims.Role)
        c.Next()
    }
}

func RequireRole(role string) gin.HandlerFunc {
    return func(c *gin.Context) {
        userRole, _ := c.Get(UserRoleKey)
        if userRole != role {
            c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "insufficient permissions"})
            return
        }
        c.Next()
    }
}
```

### Rate Limiting Middleware

```go
// internal/delivery/http/middleware/rate_limit.go
package middleware

import (
    "net/http"
    "sync"
    "time"

    "github.com/gin-gonic/gin"
    "golang.org/x/time/rate"
)

// Per-IP rate limiter using token bucket algorithm.
// For production, replace with Redis-backed distributed limiter.

type ipLimiter struct {
    limiters sync.Map
}

func (il *ipLimiter) get(ip string) *rate.Limiter {
    v, _ := il.limiters.LoadOrStore(ip, rate.NewLimiter(rate.Every(time.Second), 60))
    return v.(*rate.Limiter)
}

var globalLimiter = &ipLimiter{}

func RateLimit() gin.HandlerFunc {
    return func(c *gin.Context) {
        limiter := globalLimiter.get(c.ClientIP())
        if !limiter.Allow() {
            c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
                "error":       "rate limit exceeded",
                "retry_after": 1,
            })
            return
        }
        c.Next()
    }
}
```

---

## 8. Chunked Upload Flow (Server Side)

Large files (photos and especially videos) must be uploaded in chunks to support:
- Pause and resume on mobile
- Progress tracking
- Recovery from network interruptions

The server-side flow uses MinIO's native multipart upload API, but the binary data flows directly from the client to MinIO:

```go
// internal/delivery/http/handlers/media_handler.go (excerpts)

// 1. Client calls POST /api/v1/media/upload/init
// Returns: { media_id, upload_id, key, part_size_bytes }
func (h *MediaHandler) InitUpload(c *gin.Context) {
    var req InitUploadRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    userID := mustUserID(c)
    result, err := h.initUpload.Execute(c.Request.Context(), commands.InitUploadCommand{
        OwnerID:   userID,
        Filename:  req.Filename,
        MimeType:  req.MimeType,
        SizeBytes: req.SizeBytes,
    })
    if err != nil {
        httpError(c, err)
        return
    }

    c.JSON(http.StatusCreated, InitUploadResponse{
        MediaID:  result.Media.ID,
        UploadID: result.UploadID,
        Key:      result.Media.OriginalKey,
        PartSizeBytes: 5 * 1024 * 1024,
    })
}

// 2. Client requests a presigned URL for each part, then uploads that part directly to MinIO.
// Body: { upload_id, part_number }
// Returns: { url, expires_at }
func (h *MediaHandler) PresignUploadPart(c *gin.Context) {
    var req struct {
        UploadID   string `json:"upload_id" binding:"required"`
        PartNumber int    `json:"part_number" binding:"required,min=1"`
    }
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    result, err := h.presignUploadPart.Execute(c.Request.Context(), commands.PresignUploadPartCommand{
        MediaID:    mustUUID(c, "id"),
        OwnerID:    mustUserID(c),
        UploadID:   req.UploadID,
        PartNumber: req.PartNumber,
    })
    if err != nil {
        httpError(c, err)
        return
    }

    c.JSON(http.StatusOK, gin.H{
        "url":        result.URL,
        "expires_at": result.ExpiresAt,
    })
}

// 3. Client calls POST /api/v1/media/upload/:id/complete
// Body: { upload_id, parts: [{ part_number, etag }] }
// Triggers: ClamAV scan → thumbnail generation
func (h *MediaHandler) CompleteUpload(c *gin.Context) {
    var req CompleteUploadRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    media, err := h.completeUpload.Execute(c.Request.Context(), commands.CompleteUploadCommand{
        MediaID:  mustUUID(c, "id"),
        UploadID: req.UploadID,
        Parts:    req.Parts,
        OwnerID:  mustUserID(c),
    })
    if err != nil {
        httpError(c, err)
        return
    }

    c.JSON(http.StatusOK, toMediaDTO(media))
}
```

---

## 9. Media Worker (Background Processor)

The worker is a separate binary. It uses a best-effort Redis `BRPOP` queue, which is sufficient at family scale and keeps the operational model simple.

```go
// cmd/worker/main.go
func main() {
    cfg := config.Load()

    db    := postgres.NewPool(cfg.DatabaseURL)
    rdb   := redis.NewClient(cfg.RedisURL)
    minio := minio.NewClient(cfg.MinioEndpoint, cfg.MinioKey, cfg.MinioSecret)

    mediaRepo := postgres.NewMediaRepository(db)
    jobQueue  := redis.NewJobQueue(rdb)
    storage   := minio.NewStorageService(minio, cfg.UploadsBucket, cfg.OriginalsBucket, cfg.ThumbsBucket)
    clam      := clamav.NewScanner(cfg.ClamAVSocket)

    registry := worker.NewRegistry(
        worker.NewImageProcessor(storage, mediaRepo),
        worker.NewVideoProcessor(storage, mediaRepo, cfg.FFmpegPath),
    )

    runner := worker.NewJobRunner(jobQueue, mediaRepo, storage, registry, clam)

    slog.Info("media worker started")
    runner.Run(context.Background()) // blocks, processes jobs in loop
}
```

```go
// internal/infrastructure/worker/job_runner.go
func (r *JobRunner) Run(ctx context.Context) {
    for {
        job, err := r.queue.Dequeue(ctx, 5*time.Second)
        if err != nil {
            if errors.Is(err, context.Canceled) { return }
            slog.Error("dequeue error", "err", err)
            continue
        }
        if job == nil { continue } // timeout, loop

        go r.process(ctx, job) // concurrent processing — tune goroutine pool as needed
    }
}

func (r *JobRunner) process(ctx context.Context, job *domain.Job) {
    slog.Info("processing job", "job_id", job.ID, "media_id", job.MediaID)

    if err := r.mediaRepo.UpdateStatus(ctx, job.MediaID, domain.MediaStatusProcessing, nil); err != nil {
        slog.Error("status update failed", "err", err)
        return
    }

    // Step 1: virus scan the staged upload.
    obj, err := r.storage.GetObject(ctx, cfg.UploadsBucket, job.ObjectKey)
    if err != nil { r.fail(ctx, job, err); return }
    defer obj.Close()

    clean, threat, err := r.scanner.ScanReader(ctx, obj)
    if err != nil { r.fail(ctx, job, err); return }
    if !clean {
        slog.Warn("virus detected", "media_id", job.MediaID, "threat", threat)
        r.mediaRepo.UpdateStatus(ctx, job.MediaID, domain.MediaStatusFailed, nil)
        r.storage.Delete(ctx, cfg.UploadsBucket, job.ObjectKey)
        r.queue.Fail(ctx, job.ID, fmt.Errorf("virus: %s", threat))
        return
    }

    // Step 2: promote the clean upload to permanent storage.
    if err := r.storage.Copy(ctx, cfg.UploadsBucket, job.ObjectKey, cfg.OriginalsBucket, job.ObjectKey); err != nil {
        r.fail(ctx, job, err)
        return
    }
    _ = r.storage.Delete(ctx, cfg.UploadsBucket, job.ObjectKey)

    // Step 3: find and run appropriate processor
    proc := r.registry.Find(job.MimeType)
    if proc == nil {
        r.fail(ctx, job, domain.ErrUnsupportedMediaType)
        return
    }

    result, err := proc.Process(ctx, domain.ProcessingJob{
        MediaID:   job.MediaID,
        ObjectKey: job.ObjectKey,
        MimeType:  job.MimeType,
    })
    if err != nil { r.fail(ctx, job, err); return }

    // Step 4: commit results
    if err := r.mediaRepo.UpdateStatus(ctx, job.MediaID, domain.MediaStatusReady, result); err != nil {
        r.fail(ctx, job, err)
        return
    }

    r.queue.Ack(ctx, job.ID)
    slog.Info("job complete", "job_id", job.ID, "media_id", job.MediaID)
}
```

---

## 10. Configuration

All configuration is loaded from environment variables. Never hardcode secrets.

```go
// pkg/config/config.go
package config

import (
    "log"
    "os"
    "strconv"
)

type Config struct {
    Port           string
    Production     bool
    DatabaseURL    string
    RedisURL       string
    MinioEndpoint  string
    MinioKey       string
    MinioSecret    string
    MinioSecure    bool
    UploadsBucket  string
    OriginalsBucket string
    ThumbsBucket   string
    JWTSecret      string   // 256-bit random, base64-encoded
    JWTAccessTTL   int      // minutes, default 15
    JWTRefreshTTL  int      // days, default 30
    AllowedOrigins []string
    ClamAVSocket   string
    FFmpegPath     string
    MaxUploadBytes int64    // per file, default 10 GB
    DefaultQuotaGB int64    // per user, default 20
}

func Load() Config {
    return Config{
        Port:           getEnv("PORT", "8080"),
        Production:     getEnvBool("PRODUCTION", false),
        DatabaseURL:    requireEnv("DATABASE_URL"),
        RedisURL:       requireEnv("REDIS_URL"),
        MinioEndpoint:  requireEnv("MINIO_ENDPOINT"),
        MinioKey:       requireEnv("MINIO_ACCESS_KEY"),
        MinioSecret:    requireEnv("MINIO_SECRET_KEY"),
        MinioSecure:    getEnvBool("MINIO_SECURE", true),
        UploadsBucket:  getEnv("MINIO_UPLOADS_BUCKET", "fc-uploads"),
        OriginalsBucket: getEnv("MINIO_ORIGINALS_BUCKET", "fc-originals"),
        ThumbsBucket:   getEnv("MINIO_THUMBS_BUCKET", "fc-thumbs"),
        JWTSecret:      requireEnv("JWT_SECRET"),
        JWTAccessTTL:   getEnvInt("JWT_ACCESS_TTL_MINUTES", 15),
        JWTRefreshTTL:  getEnvInt("JWT_REFRESH_TTL_DAYS", 30),
        ClamAVSocket:   getEnv("CLAMAV_SOCKET", "/var/run/clamav/clamd.ctl"),
        FFmpegPath:     getEnv("FFMPEG_PATH", "/usr/bin/ffmpeg"),
        MaxUploadBytes: getEnvInt64("MAX_UPLOAD_BYTES", 10*1024*1024*1024),
        DefaultQuotaGB: getEnvInt64("DEFAULT_QUOTA_GB", 20),
    }
}

func requireEnv(key string) string {
    v := os.Getenv(key)
    if v == "" { log.Fatalf("required env var %s is not set", key) }
    return v
}
func getEnv(key, def string) string {
    if v := os.Getenv(key); v != "" { return v }
    return def
}
func getEnvBool(key string, def bool) bool {
    if v := os.Getenv(key); v != "" {
        b, _ := strconv.ParseBool(v)
        return b
    }
    return def
}
func getEnvInt(key string, def int) int {
    if v := os.Getenv(key); v != "" {
        i, _ := strconv.Atoi(v)
        return i
    }
    return def
}
func getEnvInt64(key string, def int64) int64 {
    if v := os.Getenv(key); v != "" {
        i, _ := strconv.ParseInt(v, 10, 64)
        return i
    }
    return def
}
```
