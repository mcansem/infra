# Google Cloud — app host (staging)

Runs the [docker/app/](../../docker/app/) stack — Nginx, PostgreSQL, and `app` (a single image: Next.js static export served by the .NET API) — the `app` role, `staging` environment. Per the Short Term roadmap in [docs/roadmap.md](../roadmap.md), this is where the application stack lives today; production eventually moves to [Oracle Cloud](oracle-cloud.md).

## Provisioning

1. **Compute Engine VM** — Ubuntu LTS. `docker/app/docker-compose.yml`'s resource limits (plus `docker/monitoring-agent/`'s, also on this host) sum to roughly 616M/1.6 CPU at their ceilings — deliberately sized to fit an `e2-micro` (2 vCPU/1G), the actual free-tier target this repo is built against. `scripts/harden-host.sh app` also provisions a 512M swap file as a safety net against worst-case simultaneous peaks (see [scripts/README.md](../../scripts/README.md#swap)). Size up if staging traffic genuinely demands it.
2. **Firewall rules** — a VPC firewall rule allowing the same ports `scripts/harden-host.sh app` manages at the OS level: `22` (SSH), `80`/`443` (the app's own Nginx). Same defense-in-depth reasoning as the AWS doc — cloud-level and host-level firewalls should agree.
3. **Static external IP** — reserve one. `app.<domain>` needs somewhere stable to point, and if this host is ever added as a Prometheus scrape target from the `management` host (see [docker/monitoring-agent/README.md](../../docker/monitoring-agent/README.md)), that opt-in is scoped to a specific source IP too.
4. **SSH access** — via `gcloud compute ssh` or an uploaded key, confirm connectivity before proceeding.

## From here, it's the same as every other host

```bash
git clone <this-repo-url> infra && cd infra
sudo scripts/harden-host.sh app
```

Then [docker/app/README.md](../../docker/app/README.md)'s bootstrap sequence, using `docker-compose.staging.yml`. Nothing past this point is GCP-specific.
