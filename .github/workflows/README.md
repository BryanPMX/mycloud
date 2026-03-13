# `.github/workflows`

GitHub Actions workflow files live here.

Current workflows cover CI plus GHCR image publishing for the API and worker.

For image-based deployments, configure `PORTAINER_STACK_WEBHOOK_URL` as an optional repository secret to trigger a Portainer redeploy after `latest` images are pushed from `main`.
