# Google Cloud — app host (staging)

Runs the [docker/app/](../../docker/app/) stack — Nginx, PostgreSQL, Next.js, .NET API — the `app` role, `staging` environment. Per the Short Term roadmap in [docs/roadmap.md](../roadmap.md), this is where the application stack lives today; production eventually moves to [Oracle Cloud](oracle-cloud.md).

## Provisioning

1. **Compute Engine VM** — Ubuntu LTS. The `app` stack's own resource limits (`docker/app/docker-compose.yml`) total roughly 3.5 CPU/2G across `nginx`+`postgres`+`nextjs`+`dotnet-api` at their ceilings; an `e2-medium` (2 vCPU/4G) is a reasonable starting point for staging traffic levels, sized up as needed.
2. **Firewall rules** — a VPC firewall rule allowing the same ports `scripts/harden-host.sh app` manages at the OS level: `22` (SSH), `80`/`443` (the app's own Nginx). Same defense-in-depth reasoning as the AWS doc — cloud-level and host-level firewalls should agree.
3. **Static external IP** — reserve one. `app.<domain>` needs somewhere stable to point, and if this host is ever added as a Prometheus scrape target from the `management` host (see [docker/monitoring-agent/README.md](../../docker/monitoring-agent/README.md)), that opt-in is scoped to a specific source IP too.
4. **SSH access** — via `gcloud compute ssh` or an uploaded key, confirm connectivity before proceeding.

## From here, it's the same as every other host

```bash
git clone <this-repo-url> infra && cd infra
sudo scripts/harden-host.sh app
```

Then [docker/app/README.md](../../docker/app/README.md)'s bootstrap sequence, using `docker-compose.staging.yml`. Nothing past this point is GCP-specific.
