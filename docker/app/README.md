# docker/app/

The staging/production application stack — Nginx, PostgreSQL, Next.js, .NET API — deployed together as one unit (see the top-level [README.md](../../README.md) repository structure for why this is one stack rather than four separate ones). Runs on the GCP VM per the Short Term roadmap.

## Bootstrap

1. Copy `.env.example` to `.env` and fill in real values (`DOMAIN_NAME`, `REGISTRY_URL`, `POSTGRES_*`). Required variables use Compose's `${VAR:?message}` syntax — if one is missing, `docker compose up` refuses to start with a clear error instead of silently running with an empty value.

2. Log in to the private registry (see [docker/registry/](../registry/)):

   ```bash
   docker login $REGISTRY_URL
   ```

3. Bootstrap a certificate so Nginx has something to start with (self-signed first — see [ssl/README.md](../../ssl/README.md)):

   ```bash
   bash ../../ssl/obtain-cert.sh app "$DOMAIN_NAME" --self-signed
   ```

4. Start it (pick the override file for the target environment):

   ```bash
   docker compose -f docker/app/docker-compose.yml -f docker/app/docker-compose.staging.yml up -d
   ```

5. Now that Nginx is up and serving the ACME challenge path, request the real Let's Encrypt certificate and reload:

   ```bash
   bash ../../ssl/obtain-cert.sh app "$DOMAIN_NAME"
   docker compose -f docker/app/docker-compose.yml -f docker/app/docker-compose.staging.yml exec nginx nginx -s reload
   ```

For production, swap `docker-compose.staging.yml` for `docker-compose.production.yml` everywhere above.

## Services

- **`nginx`** — TLS termination, gzip, security headers, routes `/api/` to the .NET API and everything else to Next.js (see [nginx/app.conf](../../nginx/app.conf)).
- **`postgres`** — no published port, reachable only from `dotnet-api` on `app_net`. Backup/restore automation is v0.6.0 (Operations) — out of scope here, just persistent storage via a named volume.
- **`nextjs`** / **`dotnet-api`** — pulled from the private registry, never built locally in this repo (app source lives in the application's own repo, per this repo's app/infra separation principle). Healthchecks assume the conventional Next.js port (3000) and an ASP.NET Core `/health` endpoint on port 8080 — adjust once the real app images exist if they differ.

## Environments

`docker-compose.yml` is the base (includes resource limits, since those are safe defaults regardless of environment); `docker-compose.staging.yml` and `docker-compose.production.yml` are override files (the pattern decided for this repo back at v0.1.0 — override files over Compose profiles) that only change `restart` policy:

- **Stateless services** (`nginx`, `nextjs`, `dotnet-api`) — `on-failure` in staging (visible failures while iterating), `always` in production (maximum uptime; safe because restarting them has no side effects).
- **`postgres`** — `on-failure:5` in *both* environments. An unbounded restart loop against a stateful service risks repeated disk I/O against a possibly-corrupt data directory; capping retries forces a human to look rather than crash-looping forever. (This is the plain Compose `restart:` field's `on-failure:N` form — the Swarm-only `deploy.restart_policy` block is not honored by plain `docker compose up` at all, so it's not used anywhere in this repo.)

## Conventions

Healthcheck (including `service_healthy` conditions in `depends_on`, not just "started"), restart policy, `stop_grace_period`, resource limits, named volume, custom network, pinned image tags — same hardening baseline as every other stack in this repo.
