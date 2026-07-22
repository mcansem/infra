# AWS — management host

Runs Portainer, Jenkins, the private Docker Registry, and the observability stack (Prometheus/Alertmanager/Grafana/Uptime Kuma) — the `management` role. Per the Short Term roadmap in [docs/roadmap.md](../roadmap.md), this is the first host in the deployment journey.

## Provisioning

1. **EC2 instance** — Ubuntu LTS (24.04 or the current LTS at deploy time). Every management-host service's `deploy.resources.limits` sums to roughly 1.9G/4.2 CPU at their ceilings (Jenkins alone capped at 768M/1.5 CPU in `jenkins/docker-compose.yml`) — deliberately sized to fit a `t3.small` (2 vCPU/2G), the actual free-tier target this repo is built against. `scripts/harden-host.sh management` also provisions a 1G swap file as a safety net against worst-case simultaneous peaks (see [scripts/README.md](../../scripts/README.md#swap)). Go larger only if Jenkins build concurrency genuinely demands it.
2. **Elastic IP** — allocate and associate one. A static IP is assumed everywhere else in this repo: `scripts/harden-host.sh`'s UFW rules for cross-host Prometheus scraping are scoped to specific source IPs (see [docker/monitoring-agent/README.md](../../docker/monitoring-agent/README.md)), and DNS records for `jenkins.<domain>`/`grafana.<domain>`/`uptime.<domain>` need somewhere stable to point.
3. **EBS volume** — the default root volume holds container images, `jenkins_home`, and — via `scripts/backup.sh` — a growing set of local backups (rotated, but still accumulate between runs). Size with that growth in mind, not just the base OS footprint.
4. **Security Group** — open the *same* ports `scripts/harden-host.sh management` will manage at the OS level: `22` (SSH), `80`/`443` (the management proxy), `9443` (Portainer), `5000` (the private Registry). This is deliberate defense in depth — AWS's network-level firewall and UFW's host-level firewall should agree on the same allowlist, not rely on just one of them.
5. **SSH key pair** — create or reuse one, confirm you can connect before doing anything else.

## From here, it's the same as every other host

```bash
git clone <this-repo-url> infra && cd infra
sudo scripts/harden-host.sh management
```

Then each stack's own README, in the order documented in [docker/observability/README.md](../../docker/observability/README.md#deployment-order-management-host): `docker/monitoring-agent/`, `jenkins/`, `docker/registry/`, `docker/portainer/`, `docker/observability/`, `docker/management-proxy/` last. Nothing past this point is AWS-specific — that's the point.
