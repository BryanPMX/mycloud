# Deployment files

Use [the deployment runbook](../docs/deployment.md) before changing the live stack.

- `portainer-stack.npm.yml`: existing production project/networks, private admin ports, hardened API/worker and pinned MinIO.
- `portainer-stack.monitoring.yml`: additive **loopback-only** diagnostics ports for the existing host-network Prometheus.
- `portainer-stack.ssd.yml`: opt-in guarded SSD binds; apply only after approved preparation and verified migration. Never substitute it for copying existing data.
- `portainer.env.example`: public placeholders only; actual environment belongs in private Portainer/configuration storage.
- `storage/` and `systemd/`: preflight and optional independent-backup examples. They are not installed automatically.

Preserve project `mycloud` and existing volume names. Never expose the MinIO console or administration through NPM, remove live volumes, change unrelated workloads or format a device without explicit approval.
