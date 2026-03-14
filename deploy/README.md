# Deploy

This directory contains deployment-oriented files that are separate from local development.

Recommended production topology for Mynube on March 14, 2026:
- self-host PostgreSQL, Redis, MinIO, API, worker, and ClamAV in the same Portainer stack
- keep Redis internal to the stack; do not create a public proxy host for Redis
- publish only the HTTP surfaces through your reverse proxy: `mynube.live` later for Flutter web, `api.mynube.live` for the API, `minio.mynube.live` for presigned S3 traffic, and `console.mynube.live` for the MinIO console
- set `APP_BASE_URL=https://mynube.live` so invite emails point at the browser-facing app origin instead of the API origin
- keep internal MinIO traffic on the Docker network with `MINIO_ENDPOINT=minio:9000` and `MINIO_SECURE=false`, while exposing `MINIO_PUBLIC_ENDPOINT=minio.mynube.live` and `MINIO_PUBLIC_SECURE=true` for presigned browser URLs
- keep PostgreSQL and Redis private on the Docker network; they do not need public DNS records or proxy hosts

- `portainer-stack.yml` is the Compose stack intended for Portainer Git deployments.
- `portainer-stack.npm.yml` is the Portainer stack variant for servers that already use Nginx Proxy Manager on a shared external Docker network.
- `portainer.env.example` is the environment-variable template to load into Portainer.
- `nginx/mycloud.host-nginx.example.conf` is an example host-level nginx config for a server that already runs nginx outside Docker.
- The Portainer stack uses GHCR images for `api`, `worker`, and a one-shot `migrate` job so the database schema can initialize without bind-mounting repo files.
