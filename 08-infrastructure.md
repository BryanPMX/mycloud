# 08 — Infrastructure

Current implementation note on March 14, 2026:
- The checked-in local `docker-compose.yml` is intentionally slimmer than the full target deployment in this document, but it now includes the core backend services needed to exercise the current API and worker locally: API, worker, PostgreSQL, Redis, MinIO, and ClamAV.
- The checked-in [.env.example](/Users/bryanpmx/Documents/Projects/mycloud/.env.example) now points `CLAMAV_SOCKET` at `tcp://clamav:3310` for local scan parity. Existing developer `.env` files still need that value set before the worker will actually call ClamAV.
- The local compose stack now also includes Mailpit-friendly SMTP defaults so invite delivery can be tested end-to-end without external mail infrastructure.
- The full Nginx, monitoring, and host-level backup automation in this doc remain the target production shape. The repository now includes lighter-weight helper scripts in [scripts/init-minio.sh](/Users/bryanpmx/Documents/Projects/mycloud/scripts/init-minio.sh), [scripts/backup-postgres.sh](/Users/bryanpmx/Documents/Projects/mycloud/scripts/backup-postgres.sh), and [scripts/backup-minio.sh](/Users/bryanpmx/Documents/Projects/mycloud/scripts/backup-minio.sh) for local bootstrap and backups.
- Confirmed public domain plan for production: `mynube.live` for the Flutter web app, `api.mynube.live` for the Go API, `minio.mynube.live` for MinIO S3/presigned traffic, and `console.mynube.live` for the MinIO console/admin surface.
- Production env mapping should follow that domain plan: `APP_BASE_URL=https://mynube.live`, `MINIO_ENDPOINT=minio.mynube.live`, and `MINIO_SECURE=true`. The current invite flow uses `APP_BASE_URL` for email links, so it should point at the browser-facing app origin rather than the API origin.

---

## 1. Docker Compose

All services run in Docker containers on your Ubuntu server. Only Nginx is exposed externally (ports 80 and 443). Everything else communicates over an internal Docker network.

```yaml
# docker-compose.yml
version: "3.9"

networks:
  fc-internal:
    driver: bridge

volumes:
  postgres_data:
  redis_data:
  minio_data:
  prometheus_data:
  grafana_data:
  clamav_data:

services:

  # ── Reverse Proxy ────────────────────────────────────────────────────────
  nginx:
    image: nginx:1.25-alpine
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - ./nginx/logs:/var/log/nginx
    depends_on:
      - api
      - minio
    networks:
      - fc-internal

  # ── Go API Server ─────────────────────────────────────────────────────────
  api:
    build:
      context: .
      dockerfile: Dockerfile.api
    restart: always
    env_file: .env
    environment:
      PORT: "8080"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      minio:
        condition: service_healthy
    networks:
      - fc-internal
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/health"]
      interval: 15s
      timeout: 5s
      retries: 3

  # ── Media Worker ──────────────────────────────────────────────────────────
  worker:
    build:
      context: .
      dockerfile: Dockerfile.worker
    restart: always
    env_file: .env
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      minio:
        condition: service_healthy
      clamav:
        condition: service_healthy
    networks:
      - fc-internal
    deploy:
      resources:
        limits:
          memory: 2G   # FFmpeg can be memory-hungry during video processing
          cpus: "2.0"

  # ── PostgreSQL ────────────────────────────────────────────────────────────
  postgres:
    image: postgres:16-alpine
    restart: always
    env_file: .env
    environment:
      POSTGRES_DB:       mycloud
      POSTGRES_USER:     ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./migrations:/docker-entrypoint-initdb.d:ro  # auto-apply on first run
    networks:
      - fc-internal
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d mycloud"]
      interval: 10s
      timeout: 5s
      retries: 5
    command: >
      postgres
        -c max_connections=100
        -c shared_buffers=512MB
        -c effective_cache_size=1GB
        -c maintenance_work_mem=128MB
        -c checkpoint_completion_target=0.9
        -c wal_buffers=16MB
        -c default_statistics_target=100
        -c log_min_duration_statement=1000

  # ── Redis ─────────────────────────────────────────────────────────────────
  redis:
    image: redis:7-alpine
    restart: always
    command: >
      redis-server
        --requirepass ${REDIS_PASSWORD}
        --maxmemory 512mb
        --maxmemory-policy noeviction
        --save 60 1000
        --appendonly yes
    volumes:
      - redis_data:/data
    networks:
      - fc-internal
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 3s
      retries: 3

  # ── MinIO ─────────────────────────────────────────────────────────────────
  minio:
    image: minio/minio:latest
    restart: always
    env_file: .env
    environment:
      MINIO_ROOT_USER:     ${MINIO_ACCESS_KEY}
      MINIO_ROOT_PASSWORD: ${MINIO_SECRET_KEY}
      MINIO_BROWSER_REDIRECT_URL: "http://localhost:9001"
    command: server /data --console-address ":9001"
    volumes:
      - minio_data:/data
    networks:
      - fc-internal
    healthcheck:
      test: ["CMD", "mc", "ready", "local"]
      interval: 15s
      timeout: 5s
      retries: 3
    # MinIO console (port 9001) is NOT exposed externally.
    # Access via SSH tunnel: ssh -L 9001:minio:9001 user@your-server.com

  # ── ClamAV ────────────────────────────────────────────────────────────────
  clamav:
    image: clamav/clamav:stable
    restart: always
    volumes:
      - clamav_data:/var/lib/clamav
    networks:
      - fc-internal
    healthcheck:
      test: ["CMD", "clamdscan", "--ping", "5"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 120s  # ClamAV takes time to load virus definitions

  # ── Prometheus ────────────────────────────────────────────────────────────
  prometheus:
    image: prom/prometheus:latest
    restart: always
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--storage.tsdb.retention.time=90d"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    networks:
      - fc-internal

  # ── Grafana ───────────────────────────────────────────────────────────────
  grafana:
    image: grafana/grafana:latest
    restart: always
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD}
      GF_SERVER_ROOT_URL: "https://monitoring.your-server.com"
    volumes:
      - grafana_data:/var/lib/grafana
      - ./monitoring/grafana/provisioning:/etc/grafana/provisioning:ro
    networks:
      - fc-internal
    depends_on:
      - prometheus
```

---

## 2. Dockerfiles

### API

```dockerfile
# Dockerfile.api — multi-stage build for a minimal final image
FROM golang:1.22-alpine AS builder

# Install libvips build dependencies
RUN apk add --no-cache vips-dev gcc musl-dev

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go build -ldflags="-w -s" -o /bin/api ./cmd/server

# Final stage
FROM alpine:3.19
RUN apk add --no-cache vips ca-certificates tzdata

COPY --from=builder /bin/api /bin/api

RUN addgroup -S fc && adduser -S fc -G fc
USER fc

EXPOSE 8080
ENTRYPOINT ["/bin/api"]
```

### Worker

```dockerfile
# Dockerfile.worker
FROM golang:1.22-alpine AS builder
RUN apk add --no-cache vips-dev gcc musl-dev ffmpeg

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -ldflags="-w -s" -o /bin/worker ./cmd/worker

FROM alpine:3.19
RUN apk add --no-cache vips ffmpeg ca-certificates tzdata

COPY --from=builder /bin/worker /bin/worker

RUN addgroup -S fc && adduser -S fc -G fc
USER fc

ENTRYPOINT ["/bin/worker"]
```

---

## 3. Environment Variables (.env)

```bash
# .env — NEVER commit to git. Copy .env.example and fill in.

# PostgreSQL
POSTGRES_USER=mycloud
POSTGRES_PASSWORD=change-me-strong-password-here
DATABASE_URL=postgres://mycloud:change-me-strong-password-here@postgres:5432/mycloud?sslmode=disable

# Redis
REDIS_PASSWORD=change-me-redis-password
REDIS_URL=redis://:change-me-redis-password@redis:6379/0

# MinIO
MINIO_ACCESS_KEY=change-me-minio-access-key
MINIO_SECRET_KEY=change-me-minio-secret-key-long
MINIO_ENDPOINT=minio:9000
MINIO_SECURE=false
MINIO_UPLOADS_BUCKET=fc-uploads
MINIO_ORIGINALS_BUCKET=fc-originals
MINIO_THUMBS_BUCKET=fc-thumbs

# JWT
JWT_SECRET=change-me-256-bit-random-base64-encoded-secret-here
JWT_ACCESS_TTL_MINUTES=15
JWT_REFRESH_TTL_DAYS=30

# App
PRODUCTION=true
DEFAULT_QUOTA_GB=20
MAX_UPLOAD_BYTES=10737418240

# ClamAV
CLAMAV_SOCKET=/var/run/clamav/clamd.ctl

# Monitoring
GRAFANA_PASSWORD=change-me-grafana-admin-password

# Email (for invite notifications)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-app@gmail.com
SMTP_PASS=your-app-password
SMTP_FROM=MyCloud <your-app@gmail.com>

# Allowed CORS origins
ALLOWED_ORIGINS=https://your-domain.com,https://app.your-domain.com
```

Generate the JWT secret:
```bash
openssl rand -base64 32
```

---

## 4. Nginx Configuration

```nginx
# nginx/nginx.conf
worker_processes auto;
error_log /var/log/nginx/error.log warn;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time rid=$sent_http_x_request_id';
    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    keepalive_timeout 65;
    gzip on;
    gzip_types text/plain application/json application/javascript text/css;

    # Rate limiting zones
    limit_req_zone $binary_remote_addr zone=api:10m rate=300r/m;
    limit_req_zone $binary_remote_addr zone=auth:10m rate=5r/m;
    limit_req_zone $binary_remote_addr zone=upload:10m rate=50r/h;

    include /etc/nginx/conf.d/*.conf;
}
```

```nginx
# nginx/conf.d/mycloud.conf

# Redirect HTTP → HTTPS
server {
    listen 80;
    server_name your-domain.com app.your-domain.com;
    return 301 https://$host$request_uri;
}

# Main app + API
server {
    listen 443 ssl http2;
    server_name your-domain.com app.your-domain.com;

    ssl_certificate     /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_stapling        on;
    ssl_stapling_verify on;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options            "DENY"                                always;
    add_header X-Content-Type-Options     "nosniff"                             always;
    add_header Referrer-Policy            "strict-origin"                       always;
    add_header Permissions-Policy         "camera=(), microphone=(), geolocation=()" always;
    add_header Content-Security-Policy    "default-src 'self'; img-src 'self' blob: data: https://minio.your-domain.com; media-src 'self' blob: https://minio.your-domain.com; connect-src 'self' wss://your-domain.com https://minio.your-domain.com; script-src 'self'; style-src 'self' 'unsafe-inline';" always;

    # API routes
    location /api/ {
        limit_req zone=api burst=50 nodelay;

        proxy_pass         http://api:8080;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;

        # API handles JSON, metadata, and small binary uploads (for example avatars).
        # Media files upload directly to MinIO via presigned URLs.
        client_max_body_size 20m;
        proxy_read_timeout   300s;
        proxy_send_timeout   300s;
    }

    # Stricter rate limit for auth
    location /api/v1/auth/login {
        limit_req zone=auth burst=3 nodelay;
        proxy_pass http://api:8080;
        proxy_http_version 1.1;
        proxy_set_header Host            $host;
        proxy_set_header X-Real-IP       $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # WebSocket for media processing status
    location /api/v1/ws/ {
        proxy_pass         http://api:8080;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    $http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host       $host;
        proxy_read_timeout 86400s;  # keep WebSocket alive
    }

    # Flutter web app (static files)
    location / {
        root /var/www/mycloud;
        try_files $uri $uri/ /index.html;  # SPA fallback
        expires 1h;

        # Immutable cache for hashed assets (Flutter web generates these)
        location ~* \.(js|css|wasm|ico|png|webp|woff2)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }
}

# MinIO (for presigned uploads/downloads — served via its own subdomain)
server {
    listen 443 ssl http2;
    server_name minio.your-domain.com;

    ssl_certificate     /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    # All media buckets stay private.
    # MinIO validates short-lived presigned URLs for upload/download access.
    location / {
        proxy_pass         http://minio:9000;
        proxy_http_version 1.1;
        proxy_set_header   Host       minio:9000;
        proxy_set_header   X-Real-IP  $remote_addr;

        # Large file downloads
        proxy_buffering          off;
        proxy_request_buffering  off;
        proxy_max_temp_file_size 0;
    }
}
```

---

## 5. Monitoring

### Prometheus Configuration

```yaml
# monitoring/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'api'
    static_configs:
      - targets: ['api:8080']
    metrics_path: '/metrics'

  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']

  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']

  - job_name: 'minio'
    static_configs:
      - targets: ['minio:9000']
    metrics_path: '/minio/v2/metrics/cluster'

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

rule_files:
  - '/etc/prometheus/alerts.yml'
```

### Alert Rules

```yaml
# monitoring/alerts.yml
groups:
  - name: mycloud
    rules:
      - alert: DiskSpaceWarning
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.20
        for: 5m
        annotations:
          summary: "Disk space below 20%"

      - alert: DiskSpaceCritical
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.10
        for: 1m
        annotations:
          summary: "CRITICAL: Disk space below 10%"

      - alert: APIDown
        expr: up{job="api"} == 0
        for: 1m
        annotations:
          summary: "MyCloud API is down"

      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.05
        for: 5m
        annotations:
          summary: "High 5xx error rate on API"

      - alert: JobQueueBacklog
        expr: mycloud_pending_jobs > 50
        for: 10m
        annotations:
          summary: "Media processing job queue is backed up"

      - alert: VirusDetected
        expr: increase(mycloud_virus_detected_total[1h]) > 0
        annotations:
          summary: "Virus detected in a file upload"
```

### Prometheus Metrics (Go API)

```go
// internal/delivery/http/middleware/metrics.go
package middleware

import (
    "strconv"
    "time"

    "github.com/gin-gonic/gin"
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promauto"
)

var (
    httpDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
        Name:    "http_request_duration_seconds",
        Help:    "HTTP request duration",
        Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10},
    }, []string{"method", "route", "status"})

    httpTotal = promauto.NewCounterVec(prometheus.CounterOpts{
        Name: "http_requests_total",
        Help: "Total HTTP requests",
    }, []string{"method", "route", "status"})

    UploadBytesTotal = promauto.NewCounter(prometheus.CounterOpts{
        Name: "mycloud_upload_bytes_total",
        Help: "Total bytes uploaded",
    })

    VirusDetectedTotal = promauto.NewCounter(prometheus.CounterOpts{
        Name: "mycloud_virus_detected_total",
        Help: "Number of virus-detected uploads",
    })

    PendingJobs = promauto.NewGauge(prometheus.GaugeOpts{
        Name: "mycloud_pending_jobs",
        Help: "Number of pending media processing jobs",
    })
)

func Metrics() gin.HandlerFunc {
    return func(c *gin.Context) {
        start := time.Now()
        c.Next()
        duration := time.Since(start)
        status := strconv.Itoa(c.Writer.Status())
        route := c.FullPath()
        if route == "" { route = "unknown" }
        httpDuration.WithLabelValues(c.Request.Method, route, status).Observe(duration.Seconds())
        httpTotal.WithLabelValues(c.Request.Method, route, status).Inc()
    }
}
```

---

## 6. Backup Strategy

Three-tier backup: Postgres WAL archiving, MinIO bucket versioning, and nightly rsync to a separate disk.

Current implementation note on March 14, 2026: the repository-level scripts now cover the first practical local step here. `scripts/backup-postgres.sh` writes a timestamped compressed SQL dump using `DATABASE_URL`, and `scripts/backup-minio.sh` mirrors the MinIO buckets into a timestamped backup directory using `mc`. The cron and rsync examples below are still the fuller production-target design.

### Nightly Database Backup

```bash
#!/bin/bash
# /opt/mycloud/scripts/backup-postgres.sh
# Run via cron: 0 2 * * * /opt/mycloud/scripts/backup-postgres.sh

set -euo pipefail

BACKUP_DIR=/mnt/backups/postgres
DATE=$(date +%Y-%m-%d)
KEEP_DAYS=30

mkdir -p "$BACKUP_DIR"

docker exec mycloud-postgres-1 pg_dump \
  -U "$POSTGRES_USER" \
  -d mycloud \
  --format=custom \
  --compress=9 \
  > "$BACKUP_DIR/mycloud-$DATE.dump"

# Remove backups older than KEEP_DAYS
find "$BACKUP_DIR" -name "*.dump" -mtime "+$KEEP_DAYS" -delete

echo "Backup complete: $BACKUP_DIR/mycloud-$DATE.dump"
```

### MinIO Versioning

Enable versioning on `fc-originals` so that overwrites/deletions can be recovered:
```bash
mc version enable myminio/fc-originals
mc ilm add myminio/fc-originals \
  --noncurrent-expire-days 90   # purge old versions after 90 days
```

### Nightly Rsync to Separate Disk

```bash
#!/bin/bash
# /opt/mycloud/scripts/backup-minio.sh
# Assumes a second disk is mounted at /mnt/backup-disk

rsync -av --delete \
  /var/lib/docker/volumes/mycloud_minio_data/_data/ \
  /mnt/backup-disk/minio-backup/

rsync -av --delete \
  /var/lib/docker/volumes/mycloud_postgres_data/_data/ \
  /mnt/backup-disk/postgres-backup/
```

### Crontab

```cron
# /etc/cron.d/mycloud
0 2 * * * root /opt/mycloud/scripts/backup-postgres.sh >> /var/log/mycloud-backup.log 2>&1
30 2 * * * root /opt/mycloud/scripts/backup-minio.sh >> /var/log/mycloud-backup.log 2>&1
0 3 * * 0 root docker exec mycloud-clamav-1 freshclam  # weekly virus def update
```

---

## 7. SSL with Let's Encrypt

```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Obtain certificates (Nginx must be running on port 80)
sudo certbot certonly --nginx \
  -d your-domain.com \
  -d app.your-domain.com \
  -d minio.your-domain.com \
  --email admin@family.com \
  --agree-tos

# Certbot auto-renews every 12 hours via a systemd timer. Verify:
sudo systemctl status certbot.timer

# Test renewal
sudo certbot renew --dry-run
```

---

## 8. Deployment Workflow

```bash
# Initial deployment
git clone https://github.com/yourorg/mycloud.git /opt/mycloud
cd /opt/mycloud
cp .env.example .env
# Fill in all values in .env

docker compose pull
docker compose up -d

# Apply DB migrations
docker compose exec api migrate -path ./migrations -database "$DATABASE_URL" up

# Deploy Flutter web app
cd flutter_app
flutter build web --release
rsync -av --delete build/web/ /var/www/mycloud/

# Update (rolling)
git pull
docker compose build api worker
docker compose up -d --no-deps api worker
# Zero-downtime: Nginx keeps serving while new container starts; health check gates traffic

# View logs
docker compose logs -f api
docker compose logs -f worker

# Restart a specific service
docker compose restart api
```

---

## 9. Resource Budget

| Service | RAM Reserved | CPU |
|---------|-------------|-----|
| nginx | 50 MB | 0.1 |
| api | 256 MB | 0.5 |
| worker | 2 GB peak | 2.0 |
| postgres | 768 MB | 0.5 |
| redis | 128 MB | 0.1 |
| minio | 512 MB | 0.5 |
| clamav | 512 MB | 0.25 |
| prometheus | 512 MB | 0.25 |
| grafana | 256 MB | 0.1 |
| **Total** | **~5 GB** | **~4.3 cores** |

With 16 GB RAM and a modern multi-core CPU, this leaves substantial headroom for your existing services, the OS, and burst processing of large video files.
