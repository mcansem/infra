# docker/management-proxy/

TLS termination and name-based routing for every public-facing UI on the `management` host — Jenkins, Grafana, Uptime Kuma. Replaces what used to be `jenkins/nginx.conf` (a single catch-all vhost fronting only Jenkins) now that two more services share the host and need to share ports 80/443 too.

## Why this exists as its own stack

Only one process can bind a host's port 80/443. Once Grafana and Uptime Kuma needed to be reachable alongside Jenkins on the same host, a single nginx doing name-based virtual hosting (`jenkins.<domain>`, `grafana.<domain>`, `uptime.<domain>`) was the alternative to publishing them on non-standard ports. See `docker/observability/README.md`'s "Deployment order" section — this must come up last, after the two projects whose networks it joins.

## Bootstrap

1. Copy `.env.example` to `.env` — the three `*_DOMAIN` values here must match the ones in `jenkins/.env` (implicitly, via DNS) and `docker/observability/.env`'s `GRAFANA_DOMAIN`.

2. Bootstrap certificates for all three domains (self-signed first, same pattern as every other TLS service in this repo — see [ssl/README.md](../../ssl/README.md)):

   ```bash
   bash ../../ssl/obtain-cert.sh jenkins jenkins.<your-domain> --self-signed
   bash ../../ssl/obtain-cert.sh grafana grafana.<your-domain> --self-signed
   bash ../../ssl/obtain-cert.sh uptime-kuma uptime.<your-domain> --self-signed
   ```

   (`ssl/jenkins/` may already exist from before this stack existed — reused as-is if the domain hasn't changed.)

3. Start it (after `docker/monitoring-agent/`, `jenkins/`, and `docker/observability/` are already up — see their deployment-order notes):

   ```bash
   docker compose -f docker/management-proxy/docker-compose.yml up -d
   ```

4. Request the real Let's Encrypt certificates and reload:

   ```bash
   bash ../../ssl/obtain-cert.sh jenkins jenkins.<your-domain>
   bash ../../ssl/obtain-cert.sh grafana grafana.<your-domain>
   bash ../../ssl/obtain-cert.sh uptime-kuma uptime.<your-domain>
   docker compose -f docker/management-proxy/docker-compose.yml exec nginx nginx -s reload
   ```

## How the domain routing works

`nginx.conf.template` isn't a plain config file — it's processed by the official nginx image's `envsubst`-based templating at container startup (`/etc/nginx/templates/*.template` → `/etc/nginx/conf.d/`), substituting `${JENKINS_DOMAIN}`/`${GRAFANA_DOMAIN}`/`${UPTIME_KUMA_DOMAIN}` from `.env`. Nginx's own runtime variables (`$host`, `$remote_addr`, etc.) are left untouched, since they're never set as container environment variables — only the three domain variables above are.

## Conventions

Healthcheck, restart policy, `stop_grace_period`, resource limits, rate limiting, security headers — same baseline as every other nginx instance in this repo (see [nginx/app.conf](../../nginx/app.conf) for the original, single-vhost version of this pattern).
