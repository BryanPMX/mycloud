# 01 — System Architecture & Design Patterns

---

## 1. Architectural Style: Clean Architecture

FamilyCloud's backend follows **Clean Architecture** (Robert C. Martin). The fundamental rule is the **Dependency Rule**: source code dependencies must point only inward. Inner layers define interfaces; outer layers implement them.

```
┌──────────────────────────────────────────────┐
│              Delivery Layer                  │  ← Gin HTTP handlers, WebSocket, CLI
│  ┌────────────────────────────────────────┐  │
│  │          Application Layer             │  │  ← Use Cases (Commands + Queries)
│  │  ┌──────────────────────────────────┐  │  │
│  │  │         Domain Layer             │  │  │  ← Entities, Repository interfaces
│  │  │  (no external dependencies)      │  │  │
│  │  └──────────────────────────────────┘  │  │
│  └────────────────────────────────────────┘  │
│              Infrastructure Layer            │  ← Postgres, MinIO, Redis, FFmpeg
└──────────────────────────────────────────────┘
```

### Layer Responsibilities

#### Domain Layer (`/internal/domain`)
The core of the application. Has **zero external imports** — not even the Go standard library's `database/sql`. Contains:
- **Entities**: `User`, `Media`, `Album`, `Share`, `Comment`, `Job`
- **Repository interfaces**: `UserRepository`, `MediaRepository`, `AlbumRepository`, etc.
- **Domain errors**: `ErrNotFound`, `ErrForbidden`, `ErrQuotaExceeded`, etc.
- **Value objects**: `MediaStatus`, `UserRole`, `Permission`, `MimeType`
- **Domain events**: `MediaUploadedEvent`, `AlbumSharedEvent` (for future event sourcing)

```go
// domain/media.go — pure entity, zero framework imports
package domain

import (
    "time"

    "github.com/google/uuid"
)

type MediaStatus string

const (
    MediaStatusPending    MediaStatus = "pending"
    MediaStatusProcessing MediaStatus = "processing"
    MediaStatusReady      MediaStatus = "ready"
    MediaStatusFailed     MediaStatus = "failed"
)

type Media struct {
    ID           uuid.UUID
    OwnerID      uuid.UUID
    Filename     string
    MimeType     string
    SizeBytes    int64
    Width        int
    Height       int
    DurationSecs float64    // 0 for images
    OriginalKey  string     // MinIO object key
    ThumbKeys    ThumbKeys
    Status       MediaStatus
    TakenAt      *time.Time // from EXIF
    UploadedAt   time.Time
    Metadata     map[string]any // EXIF, codec info, etc.
}

type ThumbKeys struct {
    Small   string // 320px webp
    Medium  string // 800px webp
    Large   string // 1920px webp
    Poster  string // video poster frame
}

// Domain rule: only owner or explicit share grants access
func (m *Media) IsAccessibleBy(userID uuid.UUID, shares []Share) bool {
    if m.OwnerID == userID {
        return true
    }
    for _, s := range shares {
        if s.SharedWith == userID || s.SharedWith == uuid.Nil { // uuid.Nil = everyone
            return true
        }
    }
    return false
}
```

#### Application Layer (`/internal/application`)
Use cases. Each use case is a single struct with an `Execute` method. Follows **CQRS**:
- **Commands** mutate state: `UploadMediaCommand`, `CreateAlbumCommand`, `ShareAlbumCommand`
- **Queries** read state: `ListMediaQuery`, `GetAlbumQuery`, `SearchMediaQuery`

Commands and Queries depend only on domain interfaces — never on concrete infrastructure.

```go
// application/commands/init_upload.go
package commands

type InitUploadCommand struct {
    OwnerID   uuid.UUID
    Filename  string
    MimeType  string
    SizeBytes int64
}

type InitUploadHandler struct {
    mediaRepo domain.MediaRepository
    userRepo  domain.UserRepository
    storage   domain.StorageService
}

type InitUploadResult struct {
    Media    *domain.Media
    UploadID string
}

func (h *InitUploadHandler) Execute(ctx context.Context, cmd InitUploadCommand) (*InitUploadResult, error) {
    // 1. Load user and check quota
    user, err := h.userRepo.FindByID(ctx, cmd.OwnerID)
    if err != nil {
        return nil, err
    }
    // Quota includes items in Trash until they are permanently deleted.
    if user.StorageUsed+cmd.SizeBytes > user.QuotaBytes {
        return nil, domain.ErrQuotaExceeded
    }

    // 2. Validate MIME type
    if !domain.IsAllowedMIME(cmd.MimeType) {
        return nil, domain.ErrUnsupportedMediaType
    }

    // 3. Generate staged storage key and create pending record
    media := domain.NewPendingMedia(cmd.OwnerID, cmd.Filename, cmd.MimeType, cmd.SizeBytes)
    if err := h.mediaRepo.Create(ctx, media); err != nil {
        return nil, err
    }

    // 4. Start multipart upload in the staging bucket.
    uploadID, err := h.storage.InitiateUpload(ctx, media.OriginalKey, cmd.MimeType)
    if err != nil {
        return nil, err
    }

    return &InitUploadResult{Media: media, UploadID: uploadID}, nil
}
```

`CompleteUploadHandler` finalizes the multipart upload and only then enqueues the background processing job. This keeps virus scanning and thumbnail generation tied to a completed object, not to upload initialization.

#### Infrastructure Layer (`/internal/infrastructure`)
Concrete implementations of domain interfaces. Each sub-package implements exactly one interface:
- `postgres/` → `UserRepository`, `MediaRepository`, `AlbumRepository`, `ShareRepository`
- `minio/` → `StorageService`
- `redis/` → `SessionStore`, `JobQueue`, `Cache`
- `worker/` → `MediaProcessor` (FFmpeg, libvips)
- `clamav/` → `VirusScanner`

#### Delivery Layer (`/internal/delivery`)
Thin translation layer. HTTP handlers convert `*gin.Context` into command/query structs, call the use case, and convert the result into JSON. They contain **zero business logic**.

---

## 2. SOLID Principles Applied

### Single Responsibility Principle
Each struct has exactly one reason to change:
- `InitUploadHandler` — starts an upload session. It does not scan files, send notifications, or render JSON.
- `CompleteUploadHandler` — finalizes the staged upload and enqueues background processing.
- `PostgresMediaRepository` — reads/writes media rows. It does not validate business rules.
- `GinMediaHandler` — translates HTTP ↔ use case. It does not call Postgres directly.

When you need to add email notifications for uploads, you add a `NotificationService` — you do not modify the upload handlers.

### Open/Closed Principle
The `MediaProcessor` interface allows adding new processors (HEIC, RAW, AVIF) without modifying existing ones:

```go
// domain/processor.go
type MediaProcessor interface {
    CanProcess(mimeType string) bool
    Process(ctx context.Context, job ProcessingJob) (*ProcessingResult, error)
}

// infrastructure/worker/image_processor.go — handles JPEG, PNG, WebP
// infrastructure/worker/video_processor.go — handles MP4, MOV, MKV
// infrastructure/worker/heic_processor.go  — add later without touching video_processor
```

A `ProcessorRegistry` iterates and dispatches:
```go
type ProcessorRegistry struct{ processors []domain.MediaProcessor }
func (r *ProcessorRegistry) Find(mimeType string) domain.MediaProcessor {
    for _, p := range r.processors {
        if p.CanProcess(mimeType) { return p }
    }
    return nil
}
```

### Liskov Substitution Principle
Every repository interface is substitutable. The test suite uses `InMemoryMediaRepository` — the same use case code runs against it without modification. Production uses `PostgresMediaRepository`. Both satisfy `domain.MediaRepository` completely.

### Interface Segregation Principle
Interfaces are kept narrow:
```go
// NOT this — one god interface:
type MediaStore interface {
    Create(ctx, media) error
    FindByID(ctx, id) (*Media, error)
    ListByOwner(ctx, ownerID) ([]*Media, error)
    Search(ctx, query) ([]*Media, error)
    Delete(ctx, id) error
    UpdateStatus(ctx, id, status) error
    // ... 10 more methods
}

// YES — split by consumer:
type MediaWriter interface {
    Create(ctx context.Context, m *Media) error
    UpdateStatus(ctx context.Context, id uuid.UUID, status MediaStatus) error
    Delete(ctx context.Context, id uuid.UUID) error
}

type MediaReader interface {
    FindByID(ctx context.Context, id uuid.UUID) (*Media, error)
    ListByOwner(ctx context.Context, ownerID uuid.UUID, opts ListOptions) ([]*Media, error)
    Search(ctx context.Context, q SearchQuery) ([]*Media, error)
}
```

The `UploadMediaHandler` imports only `MediaWriter`. The `ListMediaHandler` imports only `MediaReader`. Neither can accidentally call methods it shouldn't.

### Dependency Inversion Principle
High-level modules (use cases) depend on abstractions (interfaces), not on concrete infrastructure. All wiring happens in `main.go` — the composition root:

```go
// cmd/server/main.go — the ONLY place that knows about concrete types
func main() {
    cfg := config.Load()

    // Infrastructure
    db     := postgres.NewPool(cfg.DatabaseURL)
    rdb    := redis.NewClient(cfg.RedisURL)
    minio  := minio.NewClient(cfg.MinioEndpoint, cfg.MinioKey, cfg.MinioSecret)
    clam   := clamav.NewScanner(cfg.ClamAVSocket)

    // Repositories (implement domain interfaces)
    userRepo  := postgres.NewUserRepository(db)
    mediaRepo := postgres.NewMediaRepository(db)
    albumRepo := postgres.NewAlbumRepository(db)
    shareRepo := postgres.NewShareRepository(db)

    // Services
    storage    := minio.NewStorageService(minio, cfg.OriginalsBucket, cfg.ThumbsBucket)
    jobQueue   := redis.NewJobQueue(rdb)
    sessionStore := redis.NewSessionStore(rdb)

    // Use cases (depend only on interfaces)
    uploadHandler := commands.NewUploadMediaHandler(mediaRepo, userRepo, storage, jobQueue, clam)
    listHandler   := queries.NewListMediaHandler(mediaRepo, shareRepo)
    // ...

    // HTTP delivery
    router := delivery.NewRouter(uploadHandler, listHandler, /* ... */, cfg)
    router.Run(cfg.Port)
}
```

---

## 3. CQRS Pattern

Commands and Queries are strictly separated. This provides several benefits:
- **Commands** can emit domain events for async side effects (notifications, analytics).
- **Queries** can use optimized read models (denormalized views, cached projections).
- Each is independently testable.
- Easier to move to separate services later if load demands it.

```
HTTP POST /api/v1/media/upload/init
    → delivery.MediaHandler.InitUpload
    → commands.InitUploadHandler.Execute()
    → mediaRepo.Create() + storage.InitiateUpload()
    ← 201 Created { media_id, upload_id }

Client uploads parts directly to MinIO via presigned URLs

HTTP POST /api/v1/media/upload/:id/complete
    → delivery.MediaHandler.CompleteUpload
    → commands.CompleteUploadHandler.Execute()
    → storage.CompleteUpload() + jobQueue.Enqueue()
    ← 200 OK { id: "uuid", status: "pending" }

HTTP GET /api/v1/media?album=xxx&page=2
    → delivery.ListMediaHandler
    → queries.ListMediaHandler.Execute()
    → mediaRepo.ListByOwner() + shareRepo.FindSharedWith()
    ← 200 OK { items: [...], next_cursor: "..." }
```

---

## 4. Repository Pattern

All data access goes through repository interfaces. The repository is responsible for:
1. Translating domain entities to/from persistence models.
2. Enforcing ownership filters at the query level (not in the use case).
3. Handling pagination via cursors (not page offsets — cursors are stable under concurrent inserts).

```go
// domain/repositories.go
type MediaRepository interface {
    Create(ctx context.Context, m *Media) error
    FindByID(ctx context.Context, id uuid.UUID) (*Media, error)
    FindByIDForUser(ctx context.Context, id, userID uuid.UUID) (*Media, error) // ownership enforced in SQL
    ListByOwner(ctx context.Context, ownerID uuid.UUID, opts ListOptions) (MediaPage, error)
    ListSharedWith(ctx context.Context, userID uuid.UUID, opts ListOptions) (MediaPage, error)
    Search(ctx context.Context, q SearchQuery) (MediaPage, error)
    UpdateStatus(ctx context.Context, id uuid.UUID, status MediaStatus, result *ProcessingResult) error
    IncrementOwnerStorage(ctx context.Context, ownerID uuid.UUID, bytes int64) error
    Delete(ctx context.Context, id uuid.UUID) error
}

type ListOptions struct {
    Cursor    string    // base64-encoded (uploaded_at, id) for stable keyset pagination
    Limit     int       // max 100
    SortBy    string    // "uploaded_at" | "taken_at" | "filename"
    SortOrder string    // "asc" | "desc"
    MimeTypes []string  // filter: "image/*", "video/*"
    AlbumID   *uuid.UUID
    DateFrom  *time.Time
    DateTo    *time.Time
}

type MediaPage struct {
    Items      []*Media
    NextCursor string // empty = no more pages
    Total      int64  // approximate count (for progress display)
}
```

---

## 5. Event-Driven Side Effects

Use cases should not directly call notification services, analytics, or audit loggers — this creates hidden coupling. Instead, use case commands return domain events:

```go
type UploadResult struct {
    Media  *domain.Media
    Events []domain.DomainEvent
}

// Events are dispatched by the delivery layer after the command succeeds:
result, err := h.uploadHandler.Execute(ctx, cmd)
if err == nil {
    for _, evt := range result.Events {
        h.eventBus.Publish(ctx, evt)
    }
}
```

Initial events:
- `MediaUploadedEvent` → triggers media processing job
- `AlbumSharedEvent` → triggers in-app notification to recipients
- `CommentAddedEvent` → triggers notification to media owner

The event bus starts as a simple in-process dispatcher. It can be replaced with Redis pub/sub or a message queue later without changing any use case code.

---

## 6. Error Handling Strategy

Domain errors are typed constants. HTTP handlers map them to status codes in one place:

```go
// domain/errors.go
var (
    ErrNotFound             = errors.New("not found")
    ErrForbidden            = errors.New("forbidden")
    ErrQuotaExceeded        = errors.New("storage quota exceeded")
    ErrUnsupportedMediaType = errors.New("unsupported media type")
    ErrVirusDetected        = errors.New("virus detected in upload")
    ErrUploadSessionExpired = errors.New("upload session expired")
)

// delivery/http/errors.go — single mapping, used by all handlers
func httpError(c *gin.Context, err error) {
    switch {
    case errors.Is(err, domain.ErrNotFound):
        c.JSON(http.StatusNotFound, errorBody(err))
    case errors.Is(err, domain.ErrForbidden):
        c.JSON(http.StatusForbidden, errorBody(err))
    case errors.Is(err, domain.ErrQuotaExceeded):
        c.JSON(http.StatusPaymentRequired, errorBody(err))
    case errors.Is(err, domain.ErrUnsupportedMediaType):
        c.JSON(http.StatusUnsupportedMediaType, errorBody(err))
    case errors.Is(err, domain.ErrVirusDetected):
        c.JSON(http.StatusUnprocessableEntity, errorBody(err))
    default:
        // log the internal error, return opaque 500
        slog.Error("internal error", "err", err)
        c.JSON(http.StatusInternalServerError, gin.H{"error": "internal server error"})
    }
}
```

---

## 7. Observability

Every request is traced with a `request_id` (UUID) injected as middleware:

```go
func RequestID() gin.HandlerFunc {
    return func(c *gin.Context) {
        id := c.GetHeader("X-Request-ID")
        if id == "" { id = uuid.NewString() }
        c.Set("request_id", id)
        c.Header("X-Request-ID", id)
        c.Next()
    }
}
```

Structured logging uses `log/slog` (Go 1.21+) with the request ID on every log line. Prometheus metrics are exported from `/metrics` (scraped by the monitoring stack). Gin's request duration middleware records HTTP latency histograms by route and status code.
