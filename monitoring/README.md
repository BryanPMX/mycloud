# Integrate with existing monitoring

Do not deploy another monitoring stack. `server-hp` already runs host-network Prometheus, private Grafana/Alertmanager and exporters.

Apply the optional MyCloud monitoring override to publish API/worker diagnostics at **127.0.0.1:19090/19091**. Merge the two jobs and rules into the existing Prometheus configuration after backing it up and validating with `promtool`. Keep all existing jobs, routes, exporters and private listeners.

Import `dashboards/familycloud-overview.json` into the existing Grafana, selecting its Prometheus datasource. Verify request/error rate, latency, readiness, queue/jobs, storage, database pool and backup-age panels. The optional backup timer writes a success metric to the existing Node Exporter textfile collector only when configured.

Application metrics use bounded route/status/job labels. They never label users, emails, filenames or object IDs. Port 9090 inside application containers is diagnostics, not a public API endpoint. See [deployment](../docs/deployment.md) and [backup/restore](../docs/backup-restore.md).
