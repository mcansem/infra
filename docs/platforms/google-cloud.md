# Google Cloud — app host (staging)

Runs the [docker/app/](../../docker/app/) stack — Nginx, PostgreSQL, a Next.js frontend (`web`, ISR), and a .NET API (`app`) — the `app` role, `staging` environment. Per the Short Term roadmap in [docs/roadmap.md](../roadmap.md), this is where the application stack lives today; production eventually moves to [Oracle Cloud](oracle-cloud.md).

## Provisioning

1. **Compute Engine VM** — Ubuntu LTS. `docker/app/docker-compose.yml`'s resource limits (plus `docker/monitoring-agent/`'s, also on this host) sum to roughly 800M/2.1 CPU at their ceilings — deliberately sized to fit an `e2-micro` (2 vCPU/1G), the actual free-tier target this repo is built against. `scripts/harden-host.sh app` also provisions a 512M swap file as a safety net against worst-case simultaneous peaks (see [scripts/README.md](../../scripts/README.md#swap)). **`web`'s 220M is a provisional estimate** — no built ISR image existed yet to measure real RSS against when this was written; verify with `docker stats` after the first real deploy and adjust. If it turns out not to fit, the next instance size up (`e2-small`, 2 vCPU/2G) is no longer within GCP's Always Free tier — a real cost tradeoff, not a free bump, so worth confirming the estimate first rather than defaulting to it.
2. **Firewall rules** — a VPC firewall rule allowing the same ports `scripts/harden-host.sh app` manages at the OS level: `22` (SSH), `80`/`443` (the app's own Nginx). Same defense-in-depth reasoning as the AWS doc — cloud-level and host-level firewalls should agree.
3. **Static external IP** — reserve one. `app.<domain>` needs somewhere stable to point, and if this host is ever added as a Prometheus scrape target from the `management` host (see [docker/monitoring-agent/README.md](../../docker/monitoring-agent/README.md)), that opt-in is scoped to a specific source IP too.
4. **SSH access** — via `gcloud compute ssh` or an uploaded key, confirm connectivity before proceeding.

## From here, it's the same as every other host

Nothing installed yet (no `git`, no Docker)? `scripts/bootstrap.sh` gets a fresh Ubuntu host to this point — see [docs/deployment.md](../deployment.md#getting-a-host-ready-in-the-first-place) for the download-and-read-first version.

```bash
git clone <this-repo-url> infra && cd infra
sudo scripts/harden-host.sh app
```

Then [docker/app/README.md](../../docker/app/README.md)'s bootstrap sequence, using `docker-compose.staging.yml`. Nothing past this point is GCP-specific.
