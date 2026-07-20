# docker/app/

The staging/production application stack — Nginx, PostgreSQL, Next.js, .NET API — deployed together as one unit (see the top-level [README.md](../../README.md) repository structure for why this is one stack rather than four separate ones). Runs on the GCP VM per the Short Term roadmap.

## Bootstrap

1. Copy `.env.example` to `.env` and fill in real values (`DOMAIN_NAME`, `REGISTRY_URL`, `POSTGRES_*`).

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

`docker-compose.yml` is the base; `docker-compose.staging.yml` and `docker-compose.production.yml` are override files (the pattern decided for this repo back at v0.1.0 — override files over Compose profiles). Production adds `restart: always` and resource limits; staging uses `restart: on-failure` for faster feedback while iterating.

## Conventions

Healthcheck, restart policy, named volume, custom network, pinned image tags — same as every other stack in this repo.
