# jenkins/

Dockerized Jenkins server, configured entirely as code (JCasC) — no manual click-ops setup.

## Deploy

1. Copy `.env.example` to `.env` and fill in real values:
   - `JENKINS_ADMIN_USER` / `JENKINS_ADMIN_PASSWORD` — the initial admin login (JCasC creates this user, no setup wizard)
   - `DOCKER_GID` — the host's `docker` group GID, so the `jenkins` user inside the container can use the mounted `docker.sock`. Get it with:
     ```bash
     getent group docker | cut -d: -f3
     ```
2. Build and start:
   ```bash
   docker compose -f jenkins/docker-compose.yml up -d --build
   ```
3. Log in at `http://<host>:8080` with the credentials from `.env`.
4. Add deploy credentials manually via **Manage Jenkins → Credentials** (e.g. an SSH key with ID `deploy-ssh-key`, matching what [vars/standardDeployPipeline.groovy](../vars/standardDeployPipeline.groovy) expects). These are never stored in this repo.

## What's configured as code

- **`Dockerfile`** — extends the official `jenkins/jenkins:lts-jdk17` image with the Docker CLI, so pipeline stages can run `docker build` against the host's Docker daemon (Docker-outside-of-Docker, same trust model as the Portainer stack's `docker.sock` mount).
- **`plugins.txt`** — the plugin set, installed at image build time. Unpinned initially; pin exact versions once a first build has been verified working.
- **`casc.yaml`** — [Jenkins Configuration as Code](https://github.com/jenkinsci/configuration-as-code-plugin): system message, executor count, the admin user (sourced from env vars, never plaintext in the file), authorization, and the registration of the `infra-shared-library` global pipeline library (see [vars/](../vars/)).

## Pipeline

The actual `GitHub → Build → Docker Build → Deploy via SSH` pipeline logic lives in the repo-root [vars/](../vars/) folder as a Jenkins Shared Library, not here — Jenkins requires `vars/` to sit at the library repo's root. Application repos consume it with a couple of lines; see [vars/README.md](../vars/README.md).

## Conventions

- Healthcheck, restart policy, named volume, custom network — same as every other stack in this repo.
- Image build args and admin credentials come from a gitignored `.env` (see `.env.example`) — never committed.
- No triggers (webhook/polling) are configured yet: those are set up per application repo when it's onboarded (Multibranch Pipeline job pointing at that repo). Once [nginx/](../nginx/) fronts Jenkins with SSL (v0.4.0+), GitHub webhooks become the natural trigger; until then, builds are manual or SCM-polled.
