# Vercel web deployment

This repository can deploy the Flutter web client to Vercel, while the Go API stack remains self-hosted.

## What belongs on Vercel

- the built Flutter web assets from `flutter_app/build/web`

## What should stay off Vercel

- `cmd/server` because it depends on long-lived HTTP plus websocket behavior and shared runtime state
- `cmd/worker` because it needs Redis-backed background jobs, ClamAV, FFmpeg, and MinIO promotion flows
- PostgreSQL, Redis, MinIO, and ClamAV

## Why production should use `mynube.live`

The web client relies on:

- Strict auth cookies issued by the API
- browser websocket auth that cannot add custom headers on web
- same-site requests between `mynube.live` and `api.mynube.live`

That means:

- production should use `https://mynube.live` on Vercel
- the API should stay at `https://api.mynube.live`
- preview deployments on `*.vercel.app` should normally set `USE_DEMO_DATA=true`

## Included repo support

- `vercel.json` configures the Vercel install command, build command, output directory, and SPA rewrites
- `scripts/vercel-install.sh` installs Flutter into `.vercel/flutter` and runs `flutter pub get`
- `scripts/vercel-build.sh` builds the site and defaults preview deployments to demo mode
- `scripts/deploy-web.sh` now forwards `USE_DEMO_DATA` into the Flutter web build

## Recommended Vercel environment variables

Production:

- `APP_NAME=Mynube`
- `APP_BASE_URL=https://mynube.live`
- `API_BASE_URL=https://api.mynube.live/api/v1`
- `WS_BASE_URL=wss://api.mynube.live/ws/progress`
- `APP_ENV=production`
- `USE_DEMO_DATA=false`

Preview:

- `APP_ENV=preview`
- `USE_DEMO_DATA=true`

## Backend settings to keep aligned

On the API deployment:

- `APP_BASE_URL=https://mynube.live`
- `ALLOWED_ORIGINS=https://mynube.live`

If you later add more trusted browser origins, include them in `ALLOWED_ORIGINS`, but remember that cross-site preview domains still do not match the current Strict-cookie plus browser-websocket auth design.

## Deploy flow

1. Import the repository into Vercel.
2. Keep the project root at the repository root so Vercel can read `vercel.json`.
3. Add the production environment variables above.
4. Attach the custom domain `mynube.live` to the Vercel project.
5. Deploy.
6. Confirm `/`, `/login`, `/media`, `/albums`, `/profile`, and `/admin` all load the Flutter app.
7. Confirm the API allows `https://mynube.live` in `ALLOWED_ORIGINS`.
