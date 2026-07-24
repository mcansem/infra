# Onboarding a New Application Repo

How an application repository (`portfolio/` in the running example throughout [project-specification.md](project-specification.md)'s Main Philosophy — a Next.js frontend running ISR + a .NET Minimal API, two images) starts using this infrastructure. Application code and infrastructure code stay in separate repos by design; this is the contract between them.

## What the app repo needs

1. **A Jenkinsfile calling the shared library** — the full parameter list is documented in [vars/README.md](../vars/README.md); don't duplicate it here, just the shape. `portfolio/` builds two images from one repo, so it uses `images` rather than the single-image `imageName`:

   ```groovy
   @Library('infra-shared-library') _

   standardDeployPipeline(
       targetEnv: 'staging',
       targetHost: 'staging.example.com',
       images: [
           [name: 'portfolio-web', context: 'frontend'],
           [name: 'portfolio-app', context: 'backend'],
       ],
       registryUrl: 'https://registry.example.com:5000'
   )
   ```

2. **A Dockerfile per image, each producing a working container** — this repo's Jenkins builds them (`Docker Build & Push` stage, one `docker build` per entry in `images`), but the Dockerfiles themselves live in the app repo. `portfolio/`'s `web` runs ISR (Incremental Static Regeneration) — a persistent Next.js Node process (`next start`), not a build-time static export — because content edited through the app's admin panel needs to reach a running process to revalidate, not trigger a full rebuild-and-redeploy. Each image needs to:
   - Listen on a predictable port (the existing `docker/app/docker-compose.yml` assumes `3000` for `web`, `8080` for `app` — matching those avoids a compose change; different ports just mean updating that file).
   - Expose a health endpoint `docker/app/`'s healthchecks can hit (`/` for `web` is fine; `/health` for `app` — again, matching existing assumptions avoids a compose change).
3. **A GitHub webhook** pointed at `https://jenkins.<domain>/github-webhook/`, per [jenkins/README.md](../jenkins/README.md).
4. **Registry credentials** — the app repo doesn't need its own; Jenkins already holds `registry-credentials` (see [jenkins/README.md](../jenkins/README.md)) and injects them via the shared library's `Docker Build & Push` stage.

## If the app doesn't fit the existing shape

`docker/app/docker-compose.yml` currently assumes exactly one web service (`web`) and one API service (`app`) sharing one Postgres database. A genuinely different application (a different language/framework, a single-image app, an additional service, no database) means editing that compose file directly — add or remove a service following the same conventions every other service in this repo follows (healthcheck, `stop_grace_period`, resource limits, `restart` per the stateless/stateful split in [docker/app/README.md](../docker/app/README.md#environments), pinned image tag pulled from the private registry, no published port unless it needs to be reached directly by `nginx/app.conf`). This is an infrastructure change, not an application-repo change — it belongs in a PR against this repo, following the same phase-by-phase workflow every other change here has used.

## New subdomain, new certificate

A genuinely new application (not just a new deploy of the existing `portfolio` app) reachable at its own subdomain needs the same TLS bootstrap every other service in this repo has gone through — see [ssl/README.md](../ssl/README.md): self-signed first, then the real Let's Encrypt certificate once the domain's DNS points at the host and the relevant nginx is already up to serve the ACME challenge.

## Summary checklist

- [ ] Dockerfile(s) in the app repo, producing image(s) on the expected port(s)
- [ ] Jenkinsfile calling `standardDeployPipeline` with the right `imageName` (or `images`)/`targetHost`/`registryUrl`
- [ ] GitHub webhook configured
- [ ] `docker/app/docker-compose.yml` already has a matching service, or a PR against this repo adds one
- [ ] DNS + certificate bootstrap done for any new subdomain
