# docker/observability/

Prometheus, Alertmanager, Grafana, and Uptime Kuma — the `management` host's monitoring stack. See [docker/monitoring-agent/](../monitoring-agent/) for the Node Exporter/cAdvisor agents this scrapes, and [docker/management-proxy/](../management-proxy/) for how Grafana/Uptime Kuma get a public URL.

## Why Prometheus and Alertmanager have no public URL

Neither has meaningful built-in authentication — publishing either through the management proxy would leak metrics and alert state to anyone who finds the subdomain. Grafana and Uptime Kuma both have real login systems, so they're the public-facing pieces; Prometheus/Alertmanager stay reachable only over `observability_net`, plus an SSH tunnel for ad-hoc debugging (`ssh -L 9090:localhost:9090 <management-host>`, then browse `localhost:9090` locally).

## Deployment order (management host)

Compose can't express dependencies across separate compose projects, so order matters:

1. [docker/monitoring-agent/](../monitoring-agent/) — creates `monitoring_agent_net`, which `prometheus` here joins to scrape `node-exporter`/`cadvisor` by container name (their host-published `127.0.0.1` ports aren't reachable from inside another container — see that folder's README).
2. [jenkins/](../jenkins/) — creates `jenkins_net`.
3. This stack — creates `observability_net`.
4. [docker/management-proxy/](../management-proxy/) — joins both `jenkins_net` and `observability_net`, so it must come last.

## Bootstrap

1. Copy `.env.example` to `.env` and fill in `GRAFANA_ADMIN_PASSWORD` / `GRAFANA_DOMAIN` (the latter must match `docker/management-proxy/.env`'s `GRAFANA_DOMAIN`).

2. Start it (after steps 1–2 above):

   ```bash
   docker compose -f docker/observability/docker-compose.yml up -d
   ```

3. Once [docker/management-proxy/](../management-proxy/) is up and `https://<grafana-domain>` resolves, log in to Grafana with the admin password from `.env`. The Prometheus datasource is already provisioned (`grafana/provisioning/datasources/prometheus.yml`) — no manual setup needed.

## Dashboards

Not vendored into this repo — importing a large third-party dashboard JSON blob isn't worth maintaining when Grafana's own import-by-ID feature does it in two clicks. Once logged in: **Dashboards → New → Import**, and enter one of these well-known community dashboard IDs:

- **1860** — Node Exporter Full
- **19908** (or search "cAdvisor") — cAdvisor container metrics

Select the Prometheus datasource (already provisioned) when prompted.

## Alerting

`prometheus/alert-rules.yml` ships three defaults: host down, disk >85% full, a container missing from cAdvisor's metrics for over a minute. `alertmanager/alertmanager.yml` has a no-op `null` receiver by default — alerts are visible in Alertmanager's and Grafana's UI, but nothing is sent externally until you wire up a real receiver (Slack/Discord/email/etc.), which is deliberately not committed here since it needs deployment-specific credentials. See the comment at the top of `alertmanager.yml`.

## Conventions

Healthcheck, restart policy, `stop_grace_period`, resource limits, named volumes, pinned image tags — same hardening baseline as every other stack in this repo.
