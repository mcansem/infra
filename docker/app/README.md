# docker/app/

The staging/production application stack — Nginx, PostgreSQL, a Next.js frontend (ISR), a .NET API — deployed together as one unit (see the top-level [README.md](../../README.md) repository structure for why this is one stack rather than four separate ones). Runs on the GCP VM per the Short Term roadmap.

## Bootstrap

1. Create `.env` — run `../../scripts/init-env.sh app` (see [scripts/README.md](../../scripts/README.md#init-envsh)) to generate `POSTGRES_PASSWORD` and `REVALIDATE_SECRET` and get prompted for the rest, or copy `.env.example` to `.env` by hand (`DOMAIN_NAME`, `REGISTRY_URL`, `WEB_IMAGE_NAME`, `APP_IMAGE_NAME`, `POSTGRES_*`, `REVALIDATE_SECRET`). Required variables use Compose's `${VAR:?message}` syntax either way — if one ends up missing, `docker compose up` refuses to start with a clear error instead of silently running with an empty value. Also create the host log directory `nginx` writes to (needed for Fail2ban, see [scripts/README.md](../../scripts/README.md)): `sudo mkdir -p /var/log/infra/app-nginx`.

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

- **`nginx`** — TLS termination, gzip, security headers, routes `/api/` to the .NET API and everything else to the Next.js frontend (see [nginx/app.conf](../../nginx/app.conf)).
- **`postgres`** — no published port, reachable only from `app` on `app_net`. Backup/restore automation is v0.6.0 (Operations) — out of scope here, just persistent storage via a named volume.
- **`app`** — the .NET API. Pulled from the private registry, never built locally in this repo (app source lives in the application's own repo, per this repo's app/infra separation principle). Healthcheck assumes an ASP.NET Core `/health` endpoint on port 8080 — adjust if the real app image differs.
- **`web`** — the Next.js frontend, running ISR (Incremental Static Regeneration): a persistent Node process (`next start`), not a build-time static export. This is why it's a separate container/image from `app` rather than baked into the API's `wwwroot` — content edits (via the app's admin panel) need to reach a running process to revalidate, not trigger a full rebuild-and-redeploy. Healthcheck assumes port 3000 — adjust if the real web image differs.

### Publish → revalidate

When content is edited through the admin panel and published, `app` calls `web`'s revalidate endpoint directly (`Publish__WebhookUrl`, `http://web:3000/api/revalidate?secret=...`) instead of triggering a Jenkins rebuild — the whole point of moving to ISR. Both services read the same `REVALIDATE_SECRET` from the one shared `.env`, so it can't drift out of sync between them. `web`'s own API calls back to `app` (`API_BASE_URL=http://app:8080/api`) go straight over `app_net`, not through nginx's public proxy.

`NEXT_PUBLIC_API_URL` is set to an empty string in every environment here (the client falls back to a same-origin relative `/api` path through nginx) — note that Next.js inlines `NEXT_PUBLIC_*` vars into the client bundle at *build* time, not container start, so this compose-level value only matters if a future environment needs the client hitting a genuinely different origin, at which point it has to become a `docker build --build-arg` instead.

Resource limits for `app`/`web` in `docker-compose.yml` are conservative placeholders, not yet measured against this codebase with `docker stats` on the real host — verify and adjust after the first real deploy (see `docs/platforms/google-cloud.md`).

## Environments

`docker-compose.yml` is the base (includes resource limits, since those are safe defaults regardless of environment); `docker-compose.staging.yml` and `docker-compose.production.yml` are override files (the pattern decided for this repo back at v0.1.0 — override files over Compose profiles) that only change `restart` policy:

- **Stateless services** (`nginx`, `app`, `web`) — `on-failure` in staging (visible failures while iterating), `always` in production (maximum uptime; safe because restarting them has no side effects).
- **`postgres`** — `on-failure:5` in *both* environments. An unbounded restart loop against a stateful service risks repeated disk I/O against a possibly-corrupt data directory; capping retries forces a human to look rather than crash-looping forever. (This is the plain Compose `restart:` field's `on-failure:N` form — the Swarm-only `deploy.restart_policy` block is not honored by plain `docker compose up` at all, so it's not used anywhere in this repo.)

## Conventions

Healthcheck (including `service_healthy` conditions in `depends_on`, not just "started"), restart policy, `stop_grace_period`, resource limits, named volume, custom network, pinned image tags — same hardening baseline as every other stack in this repo.
