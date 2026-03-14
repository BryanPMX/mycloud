# 06 — Authentication & Security

Current implementation status on March 14, 2026:
- Implemented now: JWT access/refresh tokens, bcrypt password verification, Redis-backed refresh session rotation plus admin-triggered session revocation, auth middleware, admin role middleware, request IDs, structured request logging, repository-enforced media visibility, application-layer album/share ownership checks, hashed invite acceptance, admin user-management routes, and `audit_log` writes for invite/admin actions
- Still planned from this design doc: rate limiting, security-header middleware, cleanup orchestration, and SMTP invite delivery

---

## 1. Authentication Strategy

MyCloud currently uses a standard **dual-token JWT scheme**:

- **Access token** — short-lived (15 min), stateless JWT with token type `access`. Mobile/native clients send it as `Authorization: Bearer ...`; web clients receive it as an `httpOnly` cookie.
- **Refresh token** — long-lived (30 days), JWT with token type `refresh` and a unique `jti`. Its `jti` is stored in Redis for rotation/revocation. Mobile stores the token in `flutter_secure_storage`; web keeps it in an `httpOnly` cookie.

Authentication stays inside the main Go API process. At family scale this avoids an unnecessary network hop and extra operational surface area while keeping the auth logic isolated in `pkg/auth` and the auth handlers.

The split means compromised access tokens expire quickly without requiring the user to re-login, while refresh tokens can be explicitly invalidated.

---

## 2. JWT Implementation

```go
// pkg/auth/jwt.go
package auth

import (
    "errors"
    "time"

    "github.com/golang-jwt/jwt/v5"
    "github.com/google/uuid"
)

type TokenType string

const (
    TokenTypeAccess  TokenType = "access"
    TokenTypeRefresh TokenType = "refresh"
)

type Claims struct {
    UserID uuid.UUID `json:"uid"`
    Role   string    `json:"role,omitempty"`
    Type   TokenType `json:"typ"`
    jwt.RegisteredClaims
}

type JWTService interface {
    GenerateAccessToken(userID uuid.UUID, role string) (string, error)
    GenerateRefreshToken(userID uuid.UUID) (string, error)
    ValidateAccessToken(tokenStr string) (*Claims, error)
    ValidateRefreshToken(tokenStr string) (*Claims, error)
}

type jwtService struct {
    secret         []byte
    accessTokenTTL time.Duration
    refreshTokenTTL time.Duration
}

func NewJWTService(secret string, accessTTL, refreshTTL time.Duration) JWTService {
    if len(secret) < 32 {
        panic("JWT secret must be at least 32 bytes")
    }
    return &jwtService{
        secret:          []byte(secret),
        accessTokenTTL:  accessTTL,
        refreshTokenTTL: refreshTTL,
    }
}

func (s *jwtService) GenerateAccessToken(userID uuid.UUID, role string) (string, error) {
    now := time.Now()
    claims := Claims{
        UserID: userID,
        Role:   role,
        Type:   TokenTypeAccess,
        RegisteredClaims: jwt.RegisteredClaims{
            IssuedAt:  jwt.NewNumericDate(now),
            ExpiresAt: jwt.NewNumericDate(now.Add(s.accessTokenTTL)),
            Issuer:    "mycloud",
            Subject:   userID.String(),
        },
    }
    token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
    return token.SignedString(s.secret)
}

func (s *jwtService) GenerateRefreshToken(userID uuid.UUID) (string, error) {
    // Refresh token carries minimal claims — just the user ID and a random jti
    // The jti is stored in Redis; revocation = delete from Redis
    now := time.Now()
    claims := Claims{
        UserID: userID,
        Type:   TokenTypeRefresh,
        RegisteredClaims: jwt.RegisteredClaims{
            ID:        uuid.NewString(), // jti — unique per refresh token
            IssuedAt:  jwt.NewNumericDate(now),
            ExpiresAt: jwt.NewNumericDate(now.Add(s.refreshTokenTTL)),
            Issuer:    "mycloud",
            Subject:   userID.String(),
        },
    }
    token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
    return token.SignedString(s.secret)
}

func (s *jwtService) ValidateAccessToken(tokenStr string) (*Claims, error) {
    return s.validate(tokenStr, TokenTypeAccess)
}

func (s *jwtService) ValidateRefreshToken(tokenStr string) (*Claims, error) {
    return s.validate(tokenStr, TokenTypeRefresh)
}

func (s *jwtService) validate(tokenStr string, expected TokenType) (*Claims, error) {
    token, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(t *jwt.Token) (any, error) {
        if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
            return nil, errors.New("unexpected signing method")
        }
        return s.secret, nil
    })
    if err != nil {
        return nil, err
    }
    claims, ok := token.Claims.(*Claims)
    if !ok || !token.Valid {
        return nil, errors.New("invalid token")
    }
    if claims.Type != expected {
        return nil, errors.New("unexpected token type")
    }
    return claims, nil
}
```

---

## 3. Password Hashing

```go
// pkg/auth/password.go
package auth

import (
    "errors"

    "golang.org/x/crypto/bcrypt"
)

const bcryptCost = 12 // ~300ms on modern hardware — high enough to resist brute force

func HashPassword(password string) (string, error) {
    if len(password) < 8 {
        return "", errors.New("password must be at least 8 characters")
    }
    b, err := bcrypt.GenerateFromPassword([]byte(password), bcryptCost)
    return string(b), err
}

func CheckPassword(hash, password string) bool {
    err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
    return err == nil
}
```

Passwords are **never stored in plaintext**, never logged, and never returned by any API endpoint. The `users` table row is never serialized directly to JSON — a separate DTO struct is used that omits `password_hash`.

---

## 4. Redis Session Store

Refresh tokens are stored in Redis with a `TTL`. Revocation = `DEL` the key for that token `jti`. This makes rotation/revocation O(1).

```go
// internal/infrastructure/redis/session_store.go
package redis

import (
    "context"
    "fmt"
    "time"

    "github.com/google/uuid"
    "github.com/redis/go-redis/v9"
)

type SessionStore struct{ rdb *redis.Client }

func NewSessionStore(rdb *redis.Client) *SessionStore {
    return &SessionStore{rdb: rdb}
}

// Key scheme: session:{user_id}:{jti}
func sessionKey(userID uuid.UUID, jti string) string {
    return fmt.Sprintf("session:%s:%s", userID, jti)
}

// Key pattern for revoking all sessions for a user (on password change)
func userSessionPattern(userID uuid.UUID) string {
    return fmt.Sprintf("session:%s:*", userID)
}

func (s *SessionStore) StoreRefreshToken(ctx context.Context, userID uuid.UUID, jti string, ttl time.Duration) error {
    // Value is "1" — we only care about existence, not the value
    return s.rdb.Set(ctx, sessionKey(userID, jti), "1", ttl).Err()
}

func (s *SessionStore) ValidateRefreshToken(ctx context.Context, userID uuid.UUID, jti string) (bool, error) {
    val, err := s.rdb.Exists(ctx, sessionKey(userID, jti)).Result()
    if err != nil { return false, err }
    return val > 0, nil
}

func (s *SessionStore) RevokeRefreshToken(ctx context.Context, userID uuid.UUID, jti string) error {
    return s.rdb.Del(ctx, sessionKey(userID, jti)).Err()
}

func (s *SessionStore) RevokeAllForUser(ctx context.Context, userID uuid.UUID) error {
    // Use SCAN to find and delete all session keys for this user
    // Avoids KEYS pattern (blocks Redis) — SCAN is non-blocking
    var cursor uint64
    for {
        keys, next, err := s.rdb.Scan(ctx, cursor, userSessionPattern(userID), 100).Result()
        if err != nil { return err }
        if len(keys) > 0 {
            if err := s.rdb.Del(ctx, keys...).Err(); err != nil { return err }
        }
        cursor = next
        if cursor == 0 { break }
    }
    return nil
}
```

---

## 5. Auth Handler

```go
// internal/delivery/http/handlers/auth_handler.go
package handlers

type AuthHandler struct {
    userRepo     domain.UserRepository
    sessionStore domain.SessionStore
    jwtSvc       auth.JWTService
    accessTTL    time.Duration
    refreshTTL   time.Duration
}

func (h *AuthHandler) Login(c *gin.Context) {
    var req struct {
        Email    string `json:"email" binding:"required,email"`
        Password string `json:"password" binding:"required"`
    }
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    user, err := h.userRepo.FindByEmail(c.Request.Context(), req.Email)
    if err != nil || !user.Active {
        // Constant-time response regardless of whether email exists (prevents enumeration)
        time.Sleep(200 * time.Millisecond)
        c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid email or password"})
        return
    }

    if !auth.CheckPassword(user.PasswordHash, req.Password) {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid email or password"})
        return
    }

    accessToken, err := h.jwtSvc.GenerateAccessToken(user.ID, string(user.Role))
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "token generation failed"})
        return
    }

    refreshToken, err := h.jwtSvc.GenerateRefreshToken(user.ID)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "token generation failed"})
        return
    }

    // Parse refresh jti to use as the Redis session key
    claims, _ := h.jwtSvc.ValidateRefreshToken(refreshToken)
    _ = h.sessionStore.StoreRefreshToken(c.Request.Context(), user.ID, claims.ID, h.refreshTTL)
    setAuthCookies(c, accessToken, refreshToken, h.accessTTL, h.refreshTTL)

    // Update last_login_at
    now := time.Now()
    user.LastLoginAt = &now
    _ = h.userRepo.Update(c.Request.Context(), user)

    c.JSON(http.StatusOK, gin.H{
        "access_token":  accessToken,
        "refresh_token": refreshToken,
        "expires_in":    int(h.accessTTL.Seconds()),
        "user":          toUserDTO(user),
    })
}

func (h *AuthHandler) RefreshToken(c *gin.Context) {
    refreshToken, err := extractRefreshToken(c) // body on mobile, cookie on web
    if err != nil {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "missing refresh token"})
        return
    }

    claims, err := h.jwtSvc.ValidateRefreshToken(refreshToken)
    if err != nil {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid refresh token"})
        return
    }

    // Check Redis — is this token still valid (not revoked)?
    valid, err := h.sessionStore.ValidateRefreshToken(c.Request.Context(), claims.UserID, claims.ID)
    if err != nil || !valid {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "refresh token revoked or expired"})
        return
    }

    // Token rotation: revoke old, issue new
    _ = h.sessionStore.RevokeRefreshToken(c.Request.Context(), claims.UserID, claims.ID)

    user, _ := h.userRepo.FindByID(c.Request.Context(), claims.UserID)
    newAccess, _ := h.jwtSvc.GenerateAccessToken(user.ID, string(user.Role))
    newRefresh, _ := h.jwtSvc.GenerateRefreshToken(user.ID)
    newClaims, _ := h.jwtSvc.ValidateRefreshToken(newRefresh)
    _ = h.sessionStore.StoreRefreshToken(c.Request.Context(), user.ID, newClaims.ID, h.refreshTTL)
    setAuthCookies(c, newAccess, newRefresh, h.accessTTL, h.refreshTTL)

    c.JSON(http.StatusOK, gin.H{
        "access_token":  newAccess,
        "refresh_token": newRefresh,
        "expires_in":    int(h.accessTTL.Seconds()),
    })
}

func setAuthCookies(c *gin.Context, accessToken, refreshToken string, accessTTL, refreshTTL time.Duration) {
    c.SetSameSite(http.SameSiteStrictMode)
    c.SetCookie("access_token", accessToken, int(accessTTL.Seconds()), "/", "", true, true)
    c.SetCookie("refresh_token", refreshToken, int(refreshTTL.Seconds()), "/api/v1/auth", "", true, true)
}

func extractRefreshToken(c *gin.Context) (string, error) {
    var req struct {
        RefreshToken string `json:"refresh_token"`
    }
    _ = c.ShouldBindJSON(&req)
    if req.RefreshToken != "" {
        return req.RefreshToken, nil
    }
    if cookie, err := c.Cookie("refresh_token"); err == nil {
        return cookie, nil
    }
    return "", errors.New("missing refresh token")
}
```

Web clients rely on the cookies above and do not persist tokens in browser storage. Mobile/native clients consume the JSON token fields and store them in Keychain/Keystore via `flutter_secure_storage`.

### Cookie Settings for Web

- `access_token` — `HttpOnly; Secure; SameSite=Strict; Path=/`
- `refresh_token` — `HttpOnly; Secure; SameSite=Strict; Path=/api/v1/auth`
- Because the app is same-site with the API, `SameSite=Strict` prevents cross-site requests from carrying auth cookies while still allowing normal app navigation.

---

## 6. Authorization: Per-Resource Access Control

Authorization is enforced at the repository layer. Every "fetch for user" method includes an ownership/share check in SQL — the HTTP handler never receives a resource it shouldn't, so it never needs to check afterward.

```go
// The repository method includes the authorization check in the WHERE clause.
// If the resource doesn't exist OR the user doesn't have access, both return ErrNotFound.
// (We return 404, not 403, to avoid leaking that a resource exists at all.)

func (r *PostgresMediaRepository) FindByIDForUser(ctx context.Context, id, userID uuid.UUID) (*domain.Media, error) {
    const q = `
        SELECT m.*
        FROM   media m
        WHERE  m.id = $1
          AND  m.deleted_at IS NULL
          AND (
            m.owner_id = $2
            OR EXISTS (
              SELECT 1
              FROM   album_media am
              JOIN   shares s ON s.album_id = am.album_id
              WHERE  am.media_id = m.id
                AND  s.shared_with IN ($2, '00000000-0000-0000-0000-000000000000'::uuid)
                AND  (s.expires_at IS NULL OR s.expires_at > NOW())
            )
          )
    `
    var row mediaRow
    if err := r.db.GetContext(ctx, &row, q, id, userID); err != nil {
        if errors.Is(err, sql.ErrNoRows) {
            return nil, domain.ErrNotFound
        }
        return nil, err
    }
    return row.toDomain()
}
```

**Mutation authorization** (delete, edit) is done in the use case:

```go
// application/commands/delete_media.go
func (h *DeleteMediaHandler) Execute(ctx context.Context, cmd DeleteMediaCommand) error {
    media, err := h.mediaRepo.FindByIDForUser(ctx, cmd.MediaID, cmd.RequestingUserID)
    if err != nil { return err } // ErrNotFound if no access

    // Only the owner can delete (not just any viewer)
    if media.OwnerID != cmd.RequestingUserID {
        user, _ := h.userRepo.FindByID(ctx, cmd.RequestingUserID)
        if !user.IsAdmin() {
            return domain.ErrForbidden
        }
    }
    // ... proceed with deletion
}
```

---

## 7. Security Headers (Nginx + Go)

### Nginx

```nginx
# Applied to all responses
add_header X-Frame-Options          "DENY"                always;
add_header X-Content-Type-Options   "nosniff"             always;
add_header Referrer-Policy          "strict-origin"       always;
add_header Permissions-Policy       "camera=(), microphone=(), geolocation=()" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header Content-Security-Policy  "default-src 'self'; img-src 'self' blob: data: https://minio.your-server.com; media-src 'self' blob: https://minio.your-server.com; connect-src 'self' wss://your-server.com https://minio.your-server.com; script-src 'self'; style-src 'self' 'unsafe-inline';" always;
```

### Go Middleware

```go
// internal/delivery/http/middleware/security_headers.go
func SecurityHeaders() gin.HandlerFunc {
    return func(c *gin.Context) {
        c.Header("X-Request-ID", c.GetString("request_id"))
        // Nginx handles the major headers; Go adds request-scoped ones
        c.Next()
    }
}
```

---

## 8. Rate Limiting Strategy

| Endpoint | Limit | Window |
|----------|-------|--------|
| `POST /auth/login` | 5 attempts | per IP, per 15 minutes |
| `POST /auth/refresh` | 20 requests | per user, per minute |
| `POST /media/upload/init` | 50 uploads | per user, per hour |
| `POST /media/upload/:id/part-url` | 300 requests | per user, per minute |
| All other API | 300 requests | per user, per minute |

Login rate limiting uses an exponential backoff stored in Redis:

```go
func (m *LoginRateLimiter) CheckAndIncrement(ctx context.Context, ip string) error {
    key := fmt.Sprintf("login_attempts:%s", ip)
    count, _ := m.rdb.Incr(ctx, key).Result()
    if count == 1 {
        m.rdb.Expire(ctx, key, 15*time.Minute)
    }
    if count > 5 {
        ttl, _ := m.rdb.TTL(ctx, key).Result()
        return fmt.Errorf("too many login attempts, try again in %.0f seconds", ttl.Seconds())
    }
    return nil
}
```

---

## 9. Invite Flow

Users are added by admin invitation only — there is no public registration.

Current implementation note on March 14, 2026: the backend now issues hashed 72-hour invite tokens, exposes `POST /api/v1/admin/users/invite` and `POST /api/v1/auth/invite/accept`, and records invite/admin actions in `audit_log`. The current API returns `invite_url` directly; SMTP delivery remains planned.

```
Admin calls POST /admin/users/invite { email, role, quota_gb }
    → Generate a cryptographically random 32-byte token
    → Hash it (sha256) and store the hash in users.invite_token with a 72h expiry
    → Send the plaintext token in an email as a link: https://app.mycloud.example/accept?token=xxx
    → Recipient clicks link → Flutter web app calls POST /auth/invite/accept
    → Server fetches user by email, compares sha256(token) == stored hash (constant-time)
    → If match: set password, clear invite_token, activate account
    → Return access + refresh tokens and set auth cookies (user is now logged in)
```

The invite token is never stored in plaintext. The comparison is constant-time (`crypto/subtle.ConstantTimeCompare`) to prevent timing attacks.

---

## 10. ClamAV Integration

```go
// internal/infrastructure/clamav/scanner.go
package clamav

import (
    "context"
    "fmt"
    "io"
    "net"
    "strings"
    "time"
)

type Scanner struct{ socketPath string }

func NewScanner(socketPath string) *Scanner {
    return &Scanner{socketPath: socketPath}
}

// ScanReader streams data to clamd via Unix socket. Returns (clean, threatName, error).
// Uses INSTREAM command which avoids writing the file to disk.
func (s *Scanner) ScanReader(ctx context.Context, r io.Reader) (bool, string, error) {
    conn, err := net.DialTimeout("unix", s.socketPath, 5*time.Second)
    if err != nil {
        return false, "", fmt.Errorf("connect to clamd: %w", err)
    }
    defer conn.Close()

    // Send INSTREAM command
    _, _ = conn.Write([]byte("nINSTREAM\n"))

    // Stream data in 1 MB chunks, prefixed with chunk size as big-endian uint32
    buf := make([]byte, 1024*1024)
    for {
        n, readErr := r.Read(buf)
        if n > 0 {
            // Write 4-byte big-endian length prefix
            length := [4]byte{byte(n >> 24), byte(n >> 16), byte(n >> 8), byte(n)}
            _, _ = conn.Write(length[:])
            _, _ = conn.Write(buf[:n])
        }
        if readErr == io.EOF { break }
        if readErr != nil { return false, "", readErr }
    }

    // Terminate stream with zero-length chunk
    _, _ = conn.Write([]byte{0, 0, 0, 0})

    // Read response
    resp := make([]byte, 256)
    conn.SetReadDeadline(time.Now().Add(30 * time.Second))
    n, err := conn.Read(resp)
    if err != nil { return false, "", fmt.Errorf("read clamd response: %w", err) }

    response := strings.TrimSpace(string(resp[:n]))
    if strings.HasSuffix(response, "OK") { return true, "", nil }
    if strings.Contains(response, "FOUND") {
        parts := strings.Fields(response)
        threat := ""
        if len(parts) >= 2 { threat = parts[len(parts)-2] }
        return false, threat, nil
    }
    return false, "", fmt.Errorf("unexpected clamd response: %s", response)
}
```

---

## 11. Security Checklist

| # | Item | Implementation |
|---|------|---------------|
| 1 | Passwords hashed with bcrypt (cost 12) | `pkg/auth/password.go` |
| 2 | Short-lived JWT access tokens (15 min) | `pkg/auth/jwt.go` |
| 3 | Refresh tokens stored in Redis with revocation | `redis/session_store.go` |
| 4 | Tokens stored securely on device (keychain/keystore) | Flutter `flutter_secure_storage` |
| 5 | Per-resource authorization in SQL (not application layer) | `postgres/media_repository.go` |
| 6 | MIME type validated server-side (magic bytes) | `pkg/mime/validator.go` |
| 7 | ClamAV virus scan before files move to permanent storage | `clamav/scanner.go` |
| 8 | Presigned URLs for originals (short TTL, require auth) | `minio/storage_service.go` |
| 9 | TLS 1.2+ enforced at Nginx | `nginx.conf` |
| 10 | HSTS header with 1-year max-age | `nginx.conf` |
| 11 | CSP header restricting script sources | `nginx.conf` |
| 12 | Rate limiting on login (5 attempts / 15 min) | Planned |
| 13 | Login response burns bcrypt work on missing accounts (reduces email enumeration) | `commands/auth/login.go` |
| 14 | Invite token stored as sha256 hash | `commands/invite_user.go` |
| 15 | Token comparison is constant-time | `pkg/auth/invite.go` |
| 16 | All secrets in `.env` file, excluded from git | `.gitignore` |
| 17 | No secrets in logs or error messages | `slog` structured logging rules |
| 18 | Audit log of invite/admin-sensitive actions | `audit_log` table |
| 19 | Soft delete with 30-day recovery window | `media.deleted_at` |
| 20 | Admin-only user management routes | `middleware.RequireRole("admin")` |
