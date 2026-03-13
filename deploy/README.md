# Deploy

This directory contains deployment-oriented files that are separate from local development.

- `portainer-stack.yml` is the Compose stack intended for Portainer Git deployments.
- `portainer.env.example` is the environment-variable template to load into Portainer.
- `nginx/mycloud.host-nginx.example.conf` is an example host-level nginx config for a server that already runs nginx outside Docker.
- The Portainer stack uses GHCR images for `api`, `worker`, and a one-shot `migrate` job so the database schema can initialize without bind-mounting repo files.
