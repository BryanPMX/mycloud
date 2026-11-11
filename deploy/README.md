# Deployment files

Use [the deployment runbook](../docs/deployment.md) before changing the live stack.

- `portainer-stack.npm.yml`: existing production project/networks, private admin/metrics ports, hardened API/worker and pinned MinIO. It defaults to the existing named volume; after verified migration Portainer can select `MYCLOUD_MINIO_STORAGE_FILE=storage/minio-ssd.yml`.
- `portainer-stack.monitoring.yml`: compatible **loopback-only** diagnostics override for Compose CLI; the NPM primary file already provides these bindings.
- `portainer-stack.ssd.yml`: opt-in guarded SSD binds; apply only after approved preparation and verified migration. Never substitute it for copying existing data.
- `portainer.env.example`: public placeholders only; actual environment belongs in private Portainer/configuration storage.
- `storage/` and `systemd/`: named-volume/guarded-SSD Compose components, preflight and optional independent-backup examples. They are not installed automatically.

Preserve project `mycloud` and existing volume names. Never expose the MinIO console or administration through NPM, remove live volumes, change unrelated workloads or format a device without explicit approval.
