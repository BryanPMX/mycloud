# Deploy

This directory contains deployment-oriented files that are separate from local development.

Recommended production topology for Mynube on March 14, 2026:
- self-host PostgreSQL, Redis, MinIO, API, worker, and ClamAV in the same Portainer stack
- host the Flutter web bundle on Vercel only if the backend remains reachable at the same-site production domains such as `mynube.live` plus `api.mynube.live`
- keep Redis internal to the stack; do not create a public proxy host for Redis
- publish only the HTTP surfaces through your reverse proxy: `mynube.live` later for Flutter web, `api.mynube.live` for the API, `minio.mynube.live` for presigned S3 traffic, and `console.mynube.live` for the MinIO console
- set `APP_BASE_URL=https://mynube.live` so invite emails point at the browser-facing app origin instead of the API origin
- keep internal MinIO traffic on the Docker network with `MINIO_ENDPOINT=minio:9000` and `MINIO_SECURE=false`, while exposing `MINIO_PUBLIC_ENDPOINT=minio.mynube.live` and `MINIO_PUBLIC_SECURE=true` for presigned browser URLs
- keep PostgreSQL and Redis private on the Docker network; they do not need public DNS records or proxy hosts

Vercel deployment notes on March 26, 2026:
- the website is a static Flutter web build and can be deployed from `flutter_app/build/web`
- the current Go API, Redis session store, Redis job queue, worker, MinIO, and ClamAV flow are not a good single-project Vercel target; keep them on the existing Docker or server stack
- production should use the custom frontend domain `https://mynube.live` so the browser app and `https://api.mynube.live` stay same-site for Strict auth cookies and browser websocket auth
- preview deployments on `*.vercel.app` should use `USE_DEMO_DATA=true` unless you intentionally relax the current same-site auth design
- direct browser routes such as `/media`, `/albums`, `/profile`, `/admin`, and `/login` need an SPA rewrite to `/index.html`

- `portainer-stack.yml` is the Compose stack intended for Portainer Git deployments.
- `portainer-stack.npm.yml` is the Portainer stack variant for servers that already use Nginx Proxy Manager on a shared external Docker network.
- `portainer.env.example` is the environment-variable template to load into Portainer.
- `nginx/mycloud.host-nginx.example.conf` is an example host-level nginx config for a server that already runs nginx outside Docker.
- The Portainer stack uses GHCR images for `api`, `worker`, and a one-shot `migrate` job so the database schema can initialize without bind-mounting repo files. The migrate image must bundle the SQL files under its working directory so `scripts/migrate.sh` can find `./migrations` at runtime.
