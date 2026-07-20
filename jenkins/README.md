# jenkins/

Dockerized Jenkins server, configured entirely as code (JCasC) — no manual click-ops setup. Fronted by Nginx with TLS, so GitHub webhooks have a real HTTPS endpoint to call.

## Deploy

1. Copy `.env.example` to `.env` and fill in real values:
   - `JENKINS_ADMIN_USER` / `JENKINS_ADMIN_PASSWORD` — the initial admin login (JCasC creates this user, no setup wizard)
   - `DOCKER_GID` — the host's `docker` group GID, so the `jenkins` user inside the container can use the mounted `docker.sock`. Get it with:

     ```bash
     getent group docker | cut -d: -f3
     ```

2. Bootstrap a certificate so Nginx has something to start with (self-signed first — see [ssl/README.md](../ssl/README.md)):

   ```bash
   bash ../ssl/obtain-cert.sh jenkins jenkins.<your-domain> --self-signed
   ```

3. Build and start:

   ```bash
   docker compose -f jenkins/docker-compose.yml up -d --build
   ```

4. Now that Nginx is up and serving the ACME challenge path, request the real Let's Encrypt certificate and reload:

   ```bash
   bash ../ssl/obtain-cert.sh jenkins jenkins.<your-domain>
   docker compose -f jenkins/docker-compose.yml exec nginx nginx -s reload
   ```

5. Log in at `https://jenkins.<your-domain>` with the credentials from `.env`.
6. Add credentials manually via **Manage Jenkins → Credentials** — never stored in this repo:
   - An SSH key with ID `deploy-ssh-key`, matching what [vars/standardDeployPipeline.groovy](../vars/standardDeployPipeline.groovy) expects for the deploy stage.
   - Username/password (or token) with ID `registry-credentials` for pushing to the [private registry](../docker/registry/).
7. Configure each application repo's GitHub webhook to `https://jenkins.<your-domain>/github-webhook/`.

## What's configured as code

- **`Dockerfile`** — extends the official `jenkins/jenkins:lts-jdk17` image with the Docker CLI, so pipeline stages can run `docker build` against the host's Docker daemon (Docker-outside-of-Docker, same trust model as the Portainer stack's `docker.sock` mount).
- **`plugins.txt`** — the plugin set, installed at image build time. Unpinned initially; pin exact versions once a first build has been verified working.
- **`casc.yaml`** — [Jenkins Configuration as Code](https://github.com/jenkinsci/configuration-as-code-plugin): system message, executor count, the admin user (sourced from env vars, never plaintext in the file), authorization, and the registration of the `infra-shared-library` global pipeline library (see [vars/](../vars/)).
- **`nginx.conf`** — TLS termination in front of Jenkins (which itself only speaks plain HTTP), plus the `/.well-known/acme-challenge/` passthrough certificates are obtained through.

## Pipeline

The actual `GitHub → Build → Docker Build → Push → Deploy via SSH` pipeline logic lives in the repo-root [vars/](../vars/) folder as a Jenkins Shared Library, not here — Jenkins requires `vars/` to sit at the library repo's root. Application repos consume it with a couple of lines; see [vars/README.md](../vars/README.md).

## Conventions

- Healthcheck (with `nginx` waiting on `jenkins`'s `service_healthy` condition, not just "started"), named volume, custom network, resource limits (`jenkins` ~2 CPU/2G for build headroom, its `nginx` ~0.5 CPU/128M) — same hardening baseline as every other stack in this repo.
- `jenkins` itself restarts `on-failure:5`, not `always` — a persistently crash-looping Jenkins (bad plugin, broken JCasC) shouldn't restart forever; capping retries forces a human to look. Its `nginx` stays `unless-stopped` since restarting it has no side effects. See [docker/app/README.md](../docker/app/README.md) for the same reasoning applied to `postgres`.
- `jenkins`'s `stop_grace_period` is 60s (may have running builds to let finish); `nginx`'s is 10s.
- Image build args and admin credentials come from a gitignored `.env` (see `.env.example`) — never committed.
- Jenkins itself is no longer published on a host port — only reachable through the `nginx` service on 80/443, same pattern used for every TLS-terminated service in this repo. Its `nginx.conf` adds rate limiting (10r/s, burst 20) and the same security headers as [nginx/app.conf](../nginx/app.conf), minus `Content-Security-Policy` (Jenkins manages its own CSP internally).
