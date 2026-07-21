# docker/

Compose stacks are grouped by concern, each in its own subfolder with its own lifecycle — not one monolithic `docker-compose.yml`.

## portainer/

Docker management UI (Portainer CE), fulfilling the spec's requirement that one Portainer instance should manage multiple Docker hosts whenever possible.

- **`docker-compose.yml`** — Portainer **server**. Deployed once, on the management host (the AWS EC2 host, per the Short Term roadmap):

  ```bash
  docker compose -f docker/portainer/docker-compose.yml up -d
  ```

  On first run, open `https://<host>:9443` and set the admin password within Portainer's default 5-minute window — after that the instance locks and requires a CLI reset.

- **`agent-compose.yml`** — Portainer **Agent**. Deployed on every *remote* Docker host you want the server to manage (e.g. the Google Cloud VM, Oracle Cloud host):

  ```bash
  docker compose -f docker/portainer/agent-compose.yml up -d
  ```

  Then, in the Portainer UI, add a new **Environment** pointing to `<remote-host-ip>:9001`.

Other stacks live alongside `portainer/` here — see each folder's own README: [`registry/`](registry/) (private Docker registry), [`app/`](app/) (the staging/production application stack), [`monitoring-agent/`](monitoring-agent/) (Node Exporter + cAdvisor, every host), [`observability/`](observability/) (Prometheus, Alertmanager, Grafana, Uptime Kuma — `management` host), [`management-proxy/`](management-proxy/) (TLS + name-based routing for Jenkins/Grafana/Uptime Kuma, also `management` host).

## Conventions

- Every service defines a healthcheck, an explicit restart policy, `stop_grace_period`, resource limits, named volumes, and a custom network — no anonymous volumes or reliance on the default bridge network.
- Images are pinned to a specific version tag, never `latest`, for reproducibility.
- Portainer images specifically use the `-alpine` tag variant: the default image is built `FROM scratch` (no shell, no `wget`), which means a Docker-native `HEALTHCHECK` cannot run against it at all. The alpine variant ships `sh`/`wget` so the healthcheck actually works.
- Restart policy follows the same stateless/stateful split explained in [docker/app/README.md](app/README.md#environments): Portainer and its Agent are stateless-enough to restart freely (`unless-stopped`); anything holding a database restarts with a bounded `on-failure:N` instead.
