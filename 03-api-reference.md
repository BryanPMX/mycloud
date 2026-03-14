# 03 — REST API Reference

Current implementation status on March 14, 2026:
- Implemented now: `GET /health`, `GET /ws/progress`, `POST /api/v1/auth/login`, `POST /api/v1/auth/refresh`, `POST /api/v1/auth/logout`, `POST /api/v1/auth/invite/accept`, `GET /api/v1/users/me`, `PATCH /api/v1/users/me`, `PUT /api/v1/users/me/avatar`, `GET /api/v1/media`, `GET /api/v1/media/search`, `GET /api/v1/media/trash`, `DELETE /api/v1/media/trash`, `GET /api/v1/media/:id`, `GET /api/v1/media/:id/url`, `GET /api/v1/media/:id/thumb`, `DELETE /api/v1/media/:id`, `POST /api/v1/media/:id/restore`, `DELETE /api/v1/media/:id/permanent`, `POST /api/v1/media/:id/favorite`, `DELETE /api/v1/media/:id/favorite`, `POST /api/v1/media/upload/init`, `POST /api/v1/media/upload/:id/part-url`, `POST /api/v1/media/upload/:id/complete`, `DELETE /api/v1/media/upload/:id`, `GET /api/v1/albums`, `POST /api/v1/albums`, `GET /api/v1/albums/:id`, `PATCH /api/v1/albums/:id`, `DELETE /api/v1/albums/:id`, `GET /api/v1/albums/:id/media`, `POST /api/v1/albums/:id/media`, `DELETE /api/v1/albums/:id/media/:mediaId`, `GET /api/v1/albums/:id/shares`, `POST /api/v1/albums/:id/shares`, `DELETE /api/v1/albums/:id/shares/:shareId`, `GET /api/v1/media/:id/comments`, `POST /api/v1/media/:id/comments`, `DELETE /api/v1/media/:id/comments/:commentId`, `GET /api/v1/admin/users`, `POST /api/v1/admin/users/invite`, `PATCH /api/v1/admin/users/:id`, `DELETE /api/v1/admin/users/:id`, `GET /api/v1/admin/stats`
- Planned later: the remaining endpoints below unless otherwise noted

All API endpoints live under `/api/v1/`. All request/response bodies are `application/json`.
Authenticated endpoints accept either `Authorization: Bearer <access_token>` (mobile/native) or the `access_token` httpOnly cookie (web).

---

## Conventions

### Authentication
```
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

For browser clients, the server can send `access_token` / `refresh_token` cookies automatically. Those cookies are `HttpOnly` and `SameSite=Strict`; in production they should also be `Secure`.

### Pagination
List endpoints use **keyset (cursor) pagination** — stable under concurrent inserts.
```json
{
  "items": [...],
  "next_cursor": "eyJ1cGxvYWRlZF9hdCI6IjIwMjQtMDYtMTVUMTA6MDA6MDBaIiwiaWQiOiJ1dWlkIn0=",
  "total": 1432
}
```
Pass `?cursor=<next_cursor>` to get the next page. Empty `next_cursor` = last page.

### Errors
```json
{
  "error": "human-readable message",
  "code":  "QUOTA_EXCEEDED"
}
```

| HTTP Status | Meaning |
|-------------|---------|
| 400 | Bad request — validation failed |
| 401 | Missing or invalid token |
| 403 | Authenticated but not authorized for this resource |
| 404 | Resource not found |
| 413 | File too large |
| 415 | MIME type not supported |
| 422 | Virus detected in upload |
| 429 | Rate limited |
| 500 | Internal server error |

### Media DTO
All media endpoints return this shape (abbreviated fields omitted where noted).
Current implementation note on March 14, 2026: `is_favorite` is populated from the favorites table, `deleted_at` / `purges_at` are included for trashed items, and `thumb_urls` still expose stored object keys. Use `GET /media/:id/url` and `GET /media/:id/thumb` for presigned reads.
```json
{
  "id":            "uuid",
  "owner_id":      "uuid",
  "filename":      "IMG_4231.heic",
  "mime_type":     "image/heic",
  "size_bytes":    8421376,
  "width":         4032,
  "height":        3024,
  "duration_secs": 0,
  "status":        "ready",
  "is_favorite":   true,
  "taken_at":      "2024-05-20T14:30:00Z",
  "uploaded_at":   "2024-06-15T10:00:00Z",
  "deleted_at":    null,
  "purges_at":     null,
  "thumb_urls": {
    "small":  "550e8400-e29b-41d4-a716-446655440000/small.webp",
    "medium": "550e8400-e29b-41d4-a716-446655440000/medium.webp",
    "large":  "550e8400-e29b-41d4-a716-446655440000/large.webp",
    "poster": null
  }
}
```

---

## Auth

### POST /auth/login
Authenticate with email and password. Returns access + refresh tokens for mobile/native clients and also sets auth cookies for web clients.

**Request**
```json
{
  "email":    "grandma@family.com",
  "password": "hunter2"
}
```

**Response 200**
```json
{
  "access_token":  "eyJ...",
  "refresh_token": "eyJ...",
  "expires_in":    900,
  "user": {
    "id":           "uuid",
    "email":        "grandma@family.com",
    "display_name": "Grandma Rose",
    "role":         "member",
    "storage_used": 5368709120,
    "quota_bytes":  21474836480
  }
}
```

**Set-Cookie (web)**
```
Set-Cookie: access_token=...; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=900
Set-Cookie: refresh_token=...; HttpOnly; Secure; SameSite=Strict; Path=/api/v1/auth; Max-Age=2592000
```

Mobile/native clients use the JSON token fields. Flutter web ignores them and relies on cookies.

**Response 401**
```json
{ "error": "invalid email or password" }
```

---

### POST /auth/refresh
Exchange a valid refresh token for a new access token. Mobile/native clients send the refresh token in the request body; web clients use the `refresh_token` cookie.

**Request** *(mobile/native)*
```json
{ "refresh_token": "eyJ..." }
```

**Response 200**
```json
{
  "access_token":  "eyJ...",
  "refresh_token": "eyJ...",
  "expires_in":    900
}
```

Web clients also receive rotated `Set-Cookie` headers for both auth cookies.

---

### POST /auth/logout
Revoke the current refresh token.

**Request** *(mobile/native)*
```json
{ "refresh_token": "eyJ..." }
```

Web clients may call the endpoint with an empty body; the server revokes the `refresh_token` cookie value and clears both cookies.

**Response 204** — no body.

---

### POST /auth/invite/accept
Accept an admin-generated invite link. Sets password and activates the account.

Current implementation note on March 14, 2026: this endpoint is live now. It validates the stored sha256 invite hash, activates the account, clears invite fields, creates a fresh auth session, and records an `audit_log` entry.

**Request**
```json
{
  "token":        "invite-token-from-email",
  "display_name": "Cousin Marco",
  "password":     "secure-password-123"
}
```

**Response 200** — same shape as `/auth/login`.

---

## Users

### GET /users/me
Get the authenticated user's profile.

**Response 200**
```json
{
  "id":            "uuid",
  "email":         "user@family.com",
  "display_name":  "Dad",
  "avatar_url":    "users/550e8400-e29b-41d4-a716-446655440000/avatar-20260314T160509.png",
  "role":          "member",
  "storage_used":  12884901888,
  "quota_bytes":   21474836480,
  "storage_pct":   60.0,
  "created_at":    "2024-01-01T00:00:00Z",
  "last_login_at": "2024-06-15T09:00:00Z"
}
```

Current implementation note on March 14, 2026: `avatar_url` currently exposes the stored avatar object key, matching the other avatar-bearing DTOs in the API. A separate avatar-read surface or presigned avatar URLs can still be added later if we want the field to become a fully qualified URL.

---

### PATCH /users/me
Update display name.

**Request**
```json
{ "display_name": "Papa" }
```

**Response 200** — updated user object.

Current implementation note on March 14, 2026: unknown JSON fields are rejected, and blank display names return `400 Bad Request`.

---

### PUT /users/me/avatar
Upload a new avatar image. Body is raw binary. Max 5 MB.

**Headers**
```
Content-Type: image/jpeg
Content-Length: 204800
```

**Response 200**
```json
{ "avatar_url": "users/550e8400-e29b-41d4-a716-446655440000/avatar-20260314T160509.jpg" }
```

Current implementation note on March 14, 2026: the API accepts `image/jpeg`, `image/png`, `image/webp`, and `image/heic`; uploads over 5 MB return `413 Payload Too Large`. Replacing an avatar best-effort deletes the previous avatar object from `fc-avatars`.

---

## Media

### GET /media
List the authenticated user's own media plus media shared with them.

Current implementation note on March 14, 2026: `cursor`, `limit`, and `favorites` are live today. The other filters below remain planned.

**Query Parameters**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `cursor` | string | — | Pagination cursor |
| `limit` | int | 50 | Max 100 |
| `sort_by` | string | `uploaded_at` | `uploaded_at`, `taken_at`, `filename`, `size_bytes` |
| `sort_order` | string | `desc` | `asc` or `desc` |
| `mime` | string | — | `image/*` or `video/*` |
| `album_id` | uuid | — | Filter to a specific album |
| `date_from` | ISO8601 | — | Filter by taken_at |
| `date_to` | ISO8601 | — | Filter by taken_at |
| `favorites` | bool | false | Only favorited items |

**Response 200**
```json
{
  "items":       [{ /* media DTO */ }],
  "next_cursor": "base64string",
  "total":       342
}
```

---

### GET /media/search
Full-text search across filenames and metadata.

Current implementation note on March 14, 2026: `q`, `cursor`, and `limit` are live today. Search uses the new Postgres `search_vector` support and still paginates by `uploaded_at` / `id`; the broader sort/filter options below remain planned.

**Query Parameters**

| Param | Type | Description |
|-------|------|-------------|
| `q` | string | Search query (required) |
| `cursor`, `limit`, `sort_by`, `sort_order` | — | Same as GET /media |

**Response 200** — same shape as GET /media.

---

### POST /media/upload/init
Initiate a direct-to-MinIO multipart upload session.

**Request**
```json
{
  "filename":   "vacation-video.mp4",
  "mime_type":  "video/mp4",
  "size_bytes": 2147483648
}
```

**Response 201**
```json
{
  "media_id":        "uuid",
  "upload_id":       "minio-multipart-upload-id",
  "key":             "userId/2024/06/uuid.mp4",
  "part_size_bytes": 5242880,
  "part_url_ttl":    900
}
```

**Errors**
- `409 Conflict` — storage quota exceeded.
- `415 Unsupported Media Type` — MIME type not in allow-list.

---

### POST /media/upload/:id/part-url
Get a presigned PUT URL for one multipart upload part.

**Request**
```json
{
  "upload_id":   "minio-multipart-upload-id",
  "part_number": 1
}
```

**Response 200**
```json
{
  "url":        "https://minio.your-server.com/fc-uploads/...?partNumber=1&uploadId=...",
  "expires_at": "2024-06-15T10:15:00Z"
}
```

The client then uploads the raw chunk **directly to MinIO**:

```http
PUT https://minio.your-server.com/fc-uploads/...?partNumber=1&uploadId=...
Content-Type: application/octet-stream
Content-Length: 5242880
```

MinIO responds with `200 OK` or `204 No Content` and an `ETag` header. The client must capture that `ETag` for the completion step.

---

### POST /media/upload/:id/complete
Finalize a staged multipart upload. The API persists the `media` row as `pending`, creates a `process_media` job, and enqueues background processing.

**Request**
```json
{
  "upload_id": "minio-multipart-upload-id",
  "parts": [
    { "part_number": 1, "etag": "\"abc123\"" },
    { "part_number": 2, "etag": "\"def456\"" }
  ]
}
```

**Response 200**
```json
{
  "id":        "uuid",
  "status":    "pending",
  "filename":  "vacation-video.mp4",
  "size_bytes": 2147483648
}
```

The current worker slice scans the staged object, promotes it into the originals bucket, fills metadata plus thumbnail keys, and now emits realtime processing events over `/ws/progress`. Actual thumbnail file generation is still planned, so `GET /media/:id/thumb` can still return `404` until real objects exist in `fc-thumbs`.

---

### DELETE /media/upload/:id
Abort an in-progress upload and clean up MinIO.

**Response 204** — no body.

---

### GET /media/:id
Get metadata for one media item. User must own it or have an active share.

**Response 200** — full media DTO.

---

### GET /media/:id/url
Get a short-lived presigned download URL for the original file.

**Query Parameters**

| Param | Default | Description |
|-------|---------|-------------|
| `ttl` | `3600` | URL lifetime in seconds (max 86400) |

**Response 200**
```json
{
  "url":        "https://minio.your-server.com/fc-originals/...?X-Amz-Signature=...",
  "expires_at": "2024-06-15T11:00:00Z"
}
```

---

### GET /media/:id/thumb
Get presigned thumbnail URL(s).

**Query Parameters**

| Param | Values | Description |
|-------|--------|-------------|
| `size` | `small`, `medium`, `large`, `poster` | Which thumbnail (default: `medium`) |
| `ttl` | `300` | URL lifetime in seconds (max 3600) |

**Response 200**
```json
{
  "url":        "https://minio.your-server.com/fc-thumbs/...?X-Amz-Signature=...",
  "expires_at": "2024-06-15T11:00:00Z"
}
```

All thumbnails are private. Every thumbnail URL is presigned and short-lived.
Current implementation note on March 14, 2026: the endpoint is live, but the worker still only records thumbnail keys today. Until actual thumbnail files are generated into `fc-thumbs`, this endpoint will return `404`.

---

### DELETE /media/:id
Move a media item to Trash. Only the owner or an admin may delete.

**Response 204** — no body.

Trashed media:
- stays restorable for 30 days
- is hidden from normal `/media` listings
- still counts against quota until permanently deleted

---

### GET /media/trash
List the authenticated user's trashed media.

**Response 200**
```json
{
  "items": [
    {
      "id":        "uuid",
      "filename":  "vacation-video.mp4",
      "deleted_at":"2024-06-15T10:00:00Z",
      "purges_at": "2024-07-15T10:00:00Z"
    }
  ],
  "next_cursor": "",
  "total": 12
}
```

---

### POST /media/:id/restore
Restore a trashed media item to the main library.

**Response 204**

---

### DELETE /media/:id/permanent
Permanently delete one trashed media item. This removes the original and thumbnails and frees quota.

**Response 204**

---

### DELETE /media/trash
Empty the authenticated user's Trash. Permanently deletes all trashed media owned by that user.

**Response 204**

---

### POST /media/:id/favorite
Mark a media item as a favorite.

**Response 204**

---

### DELETE /media/:id/favorite
Remove a media item from favorites.

**Response 204**

---

## Albums

### GET /albums
List all albums owned by the user plus albums shared with them.

**Response 200**
```json
{
  "owned": [
    {
      "id":            "uuid",
      "owner_id":      "uuid",
      "name":          "Summer 2024",
      "description":   "Family holiday in Sardinia",
      "cover_media_id": "uuid",
      "media_count":   84,
      "created_at":    "2024-06-01T00:00:00Z",
      "updated_at":    "2024-06-01T00:00:00Z"
    }
  ],
  "shared_with_me": [...]
}
```

---

### POST /albums
Create a new album.

**Request**
```json
{
  "name":        "Christmas 2024",
  "description": "Holiday gathering at Grandma's"
}
```

**Response 201**
```json
{
  "id":            "uuid",
  "owner_id":      "uuid",
  "name":          "Christmas 2024",
  "description":   "Holiday gathering at Grandma's",
  "cover_media_id": null,
  "media_count":   0,
  "created_at":    "2024-06-15T10:00:00Z",
  "updated_at":    "2024-06-15T10:00:00Z"
}
```

---

### GET /albums/:id
Get album details. User must own it or have an active share.

**Response 200** — same album object shape returned by `POST /albums` and `GET /albums`.

---

### PATCH /albums/:id
Update album name, description, or cover.

**Request**
```json
{
  "name":          "Updated Name",
  "description":   "Updated description",
  "cover_media_id": "uuid"
}
```

All fields optional. **Response 200** — updated album object.

---

### DELETE /albums/:id
Delete an album. Does NOT delete the media within it (media has independent lifecycle).

**Response 204**

---

### GET /albums/:id/media
List media within an album. Same query parameters as GET /media.

**Response 200** — same paginated shape as `GET /media`.

---

### POST /albums/:id/media
Add existing media items to an album.

**Request**
```json
{ "media_ids": ["uuid1", "uuid2", "uuid3"] }
```

**Response 200**
```json
{ "added": 3, "already_in_album": 0 }
```

---

### DELETE /albums/:id/media/:mediaId
Remove one media item from an album.

**Response 204**

---

## Shares

### POST /albums/:id/shares
Share an album with a family member or all family members.

**Request**
```json
{
  "shared_with": "uuid",         // omit to share with entire family
  "permission":  "view",         // "view" | "contribute"
  "expires_at":  "2025-01-01T00:00:00Z"  // optional
}
```

**Response 201**
```json
{
  "id":           "uuid",
  "album_id":     "uuid",
  "shared_by":    "uuid",
  "shared_with":  "uuid",
  "recipient": {
    "id":           "uuid",
    "display_name": "Grandma Rose",
    "avatar_url":   "avatars/grandma.webp"
  },
  "permission":   "view",
  "expires_at":   "2025-01-01T00:00:00Z",
  "created_at":   "2024-06-15T10:00:00Z"
}
```

If `shared_with` is omitted, the API creates a family-wide share using the all-zero UUID sentinel and returns a `recipient.display_name` of `Entire family`.

---

### GET /albums/:id/shares
List all active shares for an album.

**Response 200**
```json
{
  "shares": [
    {
      "id":           "uuid",
      "album_id":     "uuid",
      "shared_by":    "uuid",
      "shared_with":  "uuid",
      "recipient": {
        "id":           "uuid",
        "display_name": "Grandma Rose",
        "avatar_url":   "avatars/grandma.webp"
      },
      "permission":   "view",
      "expires_at":   null,
      "created_at":   "2024-06-01T00:00:00Z"
    }
  ]
}
```

---

### DELETE /albums/:id/shares/:shareId
Revoke a share.

**Response 204**

---

## Comments

### GET /media/:id/comments
List comments on a media item.

**Response 200**
```json
{
  "comments": [
    {
      "id":         "uuid",
      "author":     { "id": "uuid", "display_name": "Uncle Bob", "avatar_url": "..." },
      "body":       "Great shot!",
      "created_at": "2024-06-15T10:30:00Z"
    }
  ]
}
```

---

### POST /media/:id/comments
Add a comment. User must be able to see the media.

**Request**
```json
{ "body": "Love this photo!" }
```

**Response 201** — comment object.

---

### DELETE /media/:id/comments/:commentId
Delete a comment. Only the author or an admin may delete.

**Response 204**

---

## Admin

All admin endpoints require `Role: admin`.

### GET /admin/users
List all registered users.

**Response 200**
```json
{
  "users": [
    {
      "id":           "uuid",
      "email":        "user@family.com",
      "display_name": "Dad",
      "role":         "member",
      "storage_used": 5368709120,
      "quota_bytes":  21474836480,
      "active":       true,
      "created_at":   "2024-01-01T00:00:00Z",
      "last_login_at":"2024-06-14T18:00:00Z"
    }
  ]
}
```

---

### POST /admin/users/invite
Send an invite link to a new family member.

Current implementation note on March 14, 2026: this endpoint is live now. The backend generates a 72-hour invite token, stores only the sha256 hash, returns the `invite_url`, and writes an `audit_log` entry. SMTP delivery is still planned, so the current response also includes `expires_at`.

**Request**
```json
{
  "email":      "newmember@family.com",
  "role":       "member",
  "quota_gb":   20
}
```

**Response 201**
```json
{
  "user_id":    "uuid",
  "invite_url": "https://your-app.com/accept?token=xxx",
  "expires_at": "2026-03-17T18:00:00Z"
}
```

The current backend returns the invite URL directly. Email transport is still planned.

---

### PATCH /admin/users/:id
Update user role, quota, or active status.

Current implementation note on March 14, 2026: this endpoint is live now. Role, `quota_bytes`, and `active` are supported today; self-demotion and self-deactivation are rejected. Successful writes record an `audit_log` row.

**Request**
```json
{
  "role":       "admin",
  "quota_bytes": 42949672960,
  "active":      true
}
```

All fields optional. **Response 200** — updated user object.

---

### DELETE /admin/users/:id
Deactivate a user account. Their media is retained but they can no longer log in.

Current implementation note on March 14, 2026: this endpoint is live now. It reuses the admin update flow, revokes refresh sessions, clears any outstanding invite token, and records an `audit_log` row.

**Response 204**

---

### GET /admin/stats
System-wide statistics.

Current implementation note on March 14, 2026: this endpoint is live now. It returns total/active users, aggregate quota usage, visible media counts, and pending job count from PostgreSQL.

**Response 200**
```json
{
  "users": {
    "total":  52,
    "active": 48
  },
  "storage": {
    "total_bytes":   1099511627776,
    "used_bytes":    429496729600,
    "free_bytes":    670014898176,
    "pct_used":      39.1
  },
  "media": {
    "total_items":   18432,
    "total_images":  15210,
    "total_videos":  3222,
    "pending_jobs":  3
  }
}
```

---

### POST /admin/maintenance/cleanup
Trigger a cleanup job: remove orphaned MinIO objects, clean expired shares, and purge trashed media older than 30 days.

Current implementation note on March 14, 2026: this endpoint is still planned.

**Response 202**
```json
{ "job_id": "uuid", "message": "cleanup job enqueued" }
```

---

## WebSocket — Upload Progress

### GET /ws/progress
Authenticated WebSocket connection. The client receives progress events during media processing.

Upload progress is tracked client-side because file chunks go directly to MinIO. The WebSocket is only for server-side processing status.

Current implementation note on March 14, 2026: this endpoint is live now. The API authenticates the initial upgrade using the same bearer-token or `access_token` cookie flow as the REST API, then fans out worker events received over Redis pub/sub. Events are currently scoped to the uploading owner.

**Messages received from server**

Processing started (virus scan + thumbnails):
```json
{
  "type":     "processing_started",
  "media_id": "uuid"
}
```

Processing complete:
```json
{
  "type":     "processing_complete",
  "media_id": "uuid",
  "status":   "ready",
  "thumb_urls": {
    "small":  "550e8400-e29b-41d4-a716-446655440000/small.webp",
    "medium": "550e8400-e29b-41d4-a716-446655440000/medium.webp",
    "large":  "550e8400-e29b-41d4-a716-446655440000/large.webp"
  }
}
```

Current implementation note on March 14, 2026: `thumb_urls` currently expose stored thumbnail keys, not presigned URLs. That matches the rest of the current backend while real thumbnail generation is still pending.

Processing failed:
```json
{
  "type":     "processing_failed",
  "media_id": "uuid",
  "reason":   "virus detected"
}
```
