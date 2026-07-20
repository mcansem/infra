# docker/monitoring-agent/

Node Exporter (host metrics) + cAdvisor (per-container metrics) — deployed identically on every host regardless of role (`management`, `app`, `agent`), since both just expose local metrics for a central Prometheus (see [docker/observability/](../observability/)) to scrape.

```bash
docker compose -f docker/monitoring-agent/docker-compose.yml up -d
```

## Localhost-only by default

Neither exporter has any authentication. Both are published as `127.0.0.1:<port>:<port>` — reachable only from the host itself, never from the network — until you deliberately opt in to cross-host scraping.

## Opt-in: cross-host scraping

Once a host's real IP is known and Prometheus needs to reach it remotely (e.g. `app`/`agent` hosts, scraped from the `management` host):

1. Change the port mapping in this file from `127.0.0.1:9100:9100` / `127.0.0.1:8080:8080` to `9100:9100` / `8080:8080` (binds to all interfaces).
2. Restrict access with UFW, scoped to the Prometheus host's specific IP — never open these ports globally:

   ```bash
   sudo ufw allow from <prometheus-host-ip> to any port 9100 proto tcp
   sudo ufw allow from <prometheus-host-ip> to any port 8080 proto tcp
   ```

3. Uncomment the corresponding scrape target in `docker/observability/prometheus/prometheus.yml`.

This is a deliberate two-step manual process, not scripted — `scripts/harden-host.sh`'s default port table intentionally does not include these, since opening them without knowing the real source IP would mean choosing between leaving metrics world-readable or guessing wrong.

## Conventions

Healthcheck (Node Exporter only — see the compose file's comment on why cAdvisor's is omitted), restart policy, `stop_grace_period`, resource limits, pinned image tags — same hardening baseline as every other stack in this repo. No named volumes: both exporters are stateless, reading live from bind-mounted host paths.
