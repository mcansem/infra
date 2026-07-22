# jenkins/

Dockerized Jenkins server, configured entirely as code (JCasC) — no manual click-ops setup. Not published on any host port itself — reachable only through [docker/management-proxy/](../docker/management-proxy/), which terminates TLS for it (and for Grafana/Uptime Kuma, which share the same host — see that folder's README for why).

## Deploy

1. Create `.env` — run `../scripts/init-env.sh management` (see [scripts/README.md](../scripts/README.md#init-envsh)) to generate `JENKINS_ADMIN_PASSWORD` and auto-detect `DOCKER_GID`, or copy `.env.example` to `.env` by hand and fill it in yourself:
   - `JENKINS_ADMIN_USER` / `JENKINS_ADMIN_PASSWORD` — the initial admin login (JCasC creates this user, no setup wizard)
   - `DOCKER_GID` — the host's `docker` group GID, so the `jenkins` user inside the container can use the mounted `docker.sock`. Get it with:

     ```bash
     getent group docker | cut -d: -f3
     ```

2. Build and start:

   ```bash
   docker compose -f jenkins/docker-compose.yml up -d --build
   ```

3. Bring up [docker/management-proxy/](../docker/management-proxy/) (its own README covers certificate bootstrap) to get `https://jenkins.<your-domain>` working.

4. Log in with the credentials from `.env`.
5. Add credentials manually via **Manage Jenkins → Credentials** — never stored in this repo:
   - An SSH key with ID `deploy-ssh-key`, matching what [vars/standardDeployPipeline.groovy](../vars/standardDeployPipeline.groovy) expects for the deploy stage.
   - Username/password (or token) with ID `registry-credentials` for pushing to the [private registry](../docker/registry/).
6. Configure each application repo's GitHub webhook to `https://jenkins.<your-domain>/github-webhook/`.

## What's configured as code

- **`Dockerfile`** — extends the official `jenkins/jenkins:lts-jdk17` image with the Docker CLI, so pipeline stages can run `docker build` against the host's Docker daemon (Docker-outside-of-Docker, same trust model as the Portainer stack's `docker.sock` mount).
- **`plugins.txt`** — the plugin set, installed at image build time. Unpinned initially; pin exact versions once a first build has been verified working.
- **`casc.yaml`** — [Jenkins Configuration as Code](https://github.com/jenkinsci/configuration-as-code-plugin): system message, executor count, the admin user (sourced from env vars, never plaintext in the file), authorization, and the registration of the `infra-shared-library` global pipeline library (see [vars/](../vars/)).

## Pipeline

The actual `GitHub → Build → Docker Build → Push → Deploy via SSH` pipeline logic lives in the repo-root [vars/](../vars/) folder as a Jenkins Shared Library, not here — Jenkins requires `vars/` to sit at the library repo's root. Application repos consume it with a couple of lines; see [vars/README.md](../vars/README.md).

## Conventions

- Healthcheck, named volume, custom network, resource limits (~2 CPU/2G, for build headroom) — same hardening baseline as every other stack in this repo.
- Restarts `on-failure:5`, not `always` — a persistently crash-looping Jenkins (bad plugin, broken JCasC) shouldn't restart forever; capping retries forces a human to look. See [docker/app/README.md](../docker/app/README.md) for the same reasoning applied to `postgres`.
- `stop_grace_period` is 60s — may have running builds to let finish.
- Image build args and admin credentials come from a gitignored `.env` (see `.env.example`) — never committed.
