# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `scripts/validate-compose.sh`: runs `docker compose config` against every stack (and staging/production override combination), using each `.env.example` for dummy required-variable values — closes the "reviewed by eye only, no Docker on this machine" gap every phase before this one had to accept. Wired into CI as a new `compose-validate` job in `.github/workflows/lint.yml`, and runnable locally
- `scripts/init-env.sh`: creates the real `.env` files a role's stacks need — generates secrets automatically (`openssl rand -hex 24`, never typed or guessed), auto-detects `DOCKER_GID`, prompts for everything else with the `.env.example` value as the default, and keeps `GRAFANA_DOMAIN` consistent between `docker/observability/.env` and `docker/management-proxy/.env` (asked once, written to both). Every stack's README now points to it as the recommended way to bootstrap `.env`, with manual editing documented as the (equivalent) alternative
- A "Credentials" section in `docs/deployment.md` explaining why `.env` files are gitignored everywhere and how real values only ever exist locally, created after cloning — no secrets manager, nothing a credential could leak through except the host's own disk
- Swap file provisioning in `scripts/harden-host.sh` (1G on `management`, 512M on `app`/`agent`) — a safety net against worst-case simultaneous memory peaks on the small free-tier instances this repo targets, idempotent and documented in `scripts/README.md`
- `scripts/bootstrap.sh`: the step before every other script can run — installs `git` and Docker Engine (+ Compose plugin) on a completely fresh Ubuntu host, adds the invoking user to the `docker` group, clones this repo. Docker's version is deliberately unpinned (logged at install time instead), consistent with the one existing precedent for installing Docker packages in this repo (`jenkins/Dockerfile`); stops short of running `harden-host.sh` itself, since role selection stays a human decision. `docs/deployment.md`, every `docs/platforms/` doc, and the top-level README now point to it, with the download-then-read option presented ahead of a plain `curl | sudo bash` one-liner

### Fixed

All four found during the first real deploy (AWS `management` host, `t3.small`, Ubuntu 26.04):

- `scripts/harden-host.sh` now creates the role's nginx log directory (`app-nginx`/`management-proxy`) *and* pre-touches empty `access.log`/`error.log` in it, not just the directory. `jail.local`'s `logpath` is a glob, and if it matches zero files at the point `harden-host.sh` runs (nginx itself hasn't started yet) — an empty directory isn't enough — fail2ban doesn't just skip the affected jail, it refuses to start *at all* (`Have not found any log file for nginx-limit-req jail`, exit 255), taking the `sshd` jail down with it. No more manual `mkdir`/`touch` step — see `scripts/README.md`, which also had a stale reference to a `jenkins-nginx` directory left over from before v0.7.0's management-proxy refactor, now fixed
- `ssl/obtain-cert.sh --self-signed` now sets `-addext "subjectAltName=DNS:<domain>"`. A CN-only certificate (the previous behavior) is rejected outright by Go's TLS client — which includes the Docker daemon and CLI — since Go 1.15 (`x509: certificate relies on legacy Common Name field, use SANs instead`), making the registry (or any self-signed service two Docker daemons talk to) unusable before a real domain exists
- `docker/registry/`'s healthcheck now also accepts wget exit code 6 as healthy. The comment justifying exit 0/8 assumed GNU wget's documented exit-code table, but this image's BusyBox wget doesn't follow it exactly — it returns 6, not 8, for the bare 401 an unauthenticated request to `/v2/` always gets with `REGISTRY_AUTH=htpasswd` enabled. The registry was never actually unhealthy (confirmed via real `docker login`/push/pull), just misreported in Portainer
- `docker/management-proxy/` and `docker/app/`'s nginx healthchecks now hit `https://localhost/` directly (with `--no-check-certificate`, same pattern already used for the registry's own healthcheck) instead of `http://localhost/`. The port-80 server block 301-redirects to `https://$host/`, and wget (without an explicit `--header`) sends `Host: localhost` — but no certificate here has `localhost` in its SAN, so wget's TLS hostname verification fails following that redirect even though nginx itself is completely healthy. `docker/app/`'s copy of this bug hadn't been hit yet (GCP host not deployed at time of writing) but shares the identical root cause
- Follow-up to the registry healthcheck fix above, after it still showed unhealthy live: this image's BusyBox wget doesn't have GNU wget's exit-code granularity at all — confirmed via `docker exec ... wget ...; echo $?` on the real host, every HTTP error (401 included) returns a flat exit `1`, not 6 or 8. Exit-code matching can't distinguish "server up, correctly demanding auth" from "server unreachable" with this wget, so the healthcheck no longer tries to: it greps wget's `-S` response-status output for any `2xx`/`4xx` status line instead, which is present regardless of wget's own exit code and absent only when the connection itself fails
- Follow-up to the management-proxy/app nginx healthcheck fix above, after management-proxy still showed unhealthy live (`wget: can't connect to remote host: Connection refused` on `[::1]:443`, confirmed via `docker exec`): both healthchecks now hit `127.0.0.1`, not `localhost`. `docker logs` on the real container showed the base nginx image's `10-listen-on-ipv6-by-default.sh` entrypoint script *does* patch `conf.d/default.conf` to add an IPv6 listen directive, but `20-envsubst-on-templates.sh` runs after it and regenerates that same file fresh from `nginx.conf.template`, silently discarding the patch — nginx ends up IPv4-only despite the image trying to make it dual-stack, and `wget`'s "localhost" resolves to `::1` first. Real external traffic is unaffected (Docker's port-publish NAT maps both `0.0.0.0`/`[::]` host ports down to the container's one IPv4 address regardless); this was purely a loopback-resolution quirk in the healthcheck itself
- One more management-proxy follow-up, after fixing the above still left it unhealthy (`403 Forbidden` from `https://127.0.0.1/`, confirmed via `docker exec`): `nginx.conf.template` only ever defined three named vhosts (jenkins/grafana/uptime-kuma domains), no default. A request with no matching SNI/Host — exactly what the loopback healthcheck sends — fell through to the first server block (Jenkins), which then rejected it with its *own* 403 (Jenkins validates the Host header it's proxied as a reverse-proxy anti-spoofing measure), even though nginx itself was completely healthy. Added an explicit `default_server` block that answers `200` directly with no backend involved, so the healthcheck no longer depends on any backend's own Host-header validation quirks. Real traffic is unaffected — it always carries a real domain in the Host header, never hitting this block

### Changed

- Every stack's `deploy.resources.limits.memory`/`cpus` revised down to realistic usage: the previous values summed to roughly 2.5x the physical RAM of both the `management` (AWS `t3.small`, 2GB) and `app` (Google Cloud `e2-micro`, 1GB) target hosts. `jenkins` also gains an explicit `-XX:MaxRAMPercentage`/`-XX:MinRAMPercentage` so its JVM heap scales off the container's cgroup limit instead of assuming host RAM. `docs/platforms/aws.md`'s instance-sizing guidance updated to match (it still referenced pre-revision totals and recommended a larger instance than the actual free-tier host this repo targets)
- `docker/app/`'s `nextjs` and `dotnet-api` services collapsed into a single `app` service/image: the real application is a 3-stage Dockerfile (Next.js static export → .NET publish → export copied into the API's `wwwroot`), one ASP.NET Core process serving both, not two containers. `nginx/app.conf` now proxies everything to one upstream instead of splitting `/api/` from the rest. `docker/app/.env.example`'s `WEB_IMAGE_TAG`/`API_IMAGE_TAG` replaced with a single `APP_IMAGE_NAME` (required, no default — this repo isn't tied to one project's naming) and `APP_IMAGE_TAG`; `scripts/init-env.sh` and every affected doc (`docker/app/README.md`, `nginx/README.md`, `docs/architecture.md`, `docs/onboarding.md`, `docs/platforms/google-cloud.md`, `docs/platforms/oracle-cloud.md`) updated to match
- Partial revert of the single-container consolidation directly above: `portfolio/`'s frontend moved from a build-time static export to ISR (Incremental Static Regeneration), which needs a persistent Next.js Node process, not something bakeable into the API's `wwwroot` at build time. `docker/app/docker-compose.yml` splits back into `app` (.NET API, 220M) and `web` (Next.js, 220M — a provisional estimate, no built ISR image existed yet to measure real RSS against; verify with `docker stats` after the first real deploy) sharing one Postgres, `nginx/app.conf` splits `/api/` from everything else again, and `docker/app/.env.example` gains `WEB_IMAGE_NAME`/`WEB_IMAGE_TAG` alongside `APP_IMAGE_NAME`/`APP_IMAGE_TAG`. The reason for reverting: static export + build-time content fetch meant every admin-panel content edit needed a full CI/CD cycle to appear, making the admin panel's CRUD purpose largely moot — today's build-time cold-start/networking problems (frontend build stage having no live backend to fetch from) were a symptom of that, not the root issue. `vars/standardDeployPipeline.groovy` gains an `images` list parameter (alongside the existing single-image `imageName`, kept for backward compatibility) so one app repo can build/push more than one image per deploy — `docs/onboarding.md` and `vars/README.md` updated with the two-image example. `docs/platforms/google-cloud.md`'s resource-sizing math updated (roughly 800M/2.1 CPU at ceilings, still fits `e2-micro`'s 1G with headroom) and now flags that the next free-tier-adjacent instance size is not actually free, in case `web`'s real measured footprint doesn't hold
- Finalized the `web`/`app` split above against `portfolio/`'s actual contract: build contexts are `frontend` and `backend/Portfolio.Api` (corrected from placeholder `backend` in `vars/standardDeployPipeline.groovy`, `vars/README.md`, `docs/onboarding.md`). Added a generated `REVALIDATE_SECRET` to `scripts/init-env.sh app` (same pattern as `POSTGRES_PASSWORD` — never typed by a human), written once to `docker/app/.env` and injected into both `app` (`Publish__WebhookUrl=http://web:3000/api/revalidate?secret=...`, fired when content is published) and `web` (checks it on incoming revalidate requests), so the two can't drift out of sync — simpler than `GRAFANA_DOMAIN`'s cross-*file* sync since both services already share one `.env` here. `web` also gains `API_BASE_URL=http://app:8080/api` (internal Docker network, bypassing nginx's public proxy for server-side ISR fetches) and `NEXT_PUBLIC_API_URL=""` (relative-path fallback for the client bundle — noted as build-time-baked by Next.js, not something this compose file's runtime env can actually override if it ever needs to vary per environment). `buildArgs` support added in the change above is kept, not removed, even though `portfolio/` ends up not using it (everything is a runtime env var post-ISR) — it's a general pipeline capability, not portfolio-specific, and removing a zero-cost, already-shipped, optional parameter would be premature narrowing of a shared library other apps may still need

## [0.9.0] - 2026-07-21

### Added

- `docs/runbooks.md`: one playbook per Prometheus alert (`HostDown`, `DiskSpaceLow`, `ContainerMissing`) — what it means, likely causes, concrete investigate/fix commands
- `docs/onboarding.md`: how a new application repo starts using this infrastructure — Jenkinsfile shape, image/port expectations, what to do if it doesn't fit the existing `docker/app/` service shape, new-subdomain certificate bootstrap
- `docs/architecture.md`: real content replacing the v0.1.0 stub — three Mermaid diagrams (component/data-flow, externally-reachable network topology matching `scripts/harden-host.sh`'s `role_ports()`, CI/CD sequence matching `vars/standardDeployPipeline.groovy`'s stage order), rendered natively by GitHub
- `docs/recovery.md`: real content replacing the v0.1.0 stub — the authoritative host-lost runbook (consolidating what was scattered across `backup.md`/`restore.md`/`platforms/homelab.md`), plus explicit RPO (~24h, tied to the recommended daily backup cadence) and RTO (an honest estimate — under two hours — explicitly caveated as untested, not a real SLA)

### Changed

- `docs/project-specification.md`'s Documentation section gains `runbooks.md`, `onboarding.md`

## [0.8.0] - 2026-07-21

### Added

- `docs/deployment.md`: real content, replacing the v0.1.0 stub — the general deploy flow, the `management`/`app`/`agent` role vocabulary, and links out to per-provider host provisioning
- `docs/platforms/aws.md`, `docs/platforms/google-cloud.md`, `docs/platforms/oracle-cloud.md`, `docs/platforms/homelab.md`: what's genuinely provider-specific (getting from nothing to a reachable Ubuntu host) for each target in the roadmap's deployment journey; everything past that point is identical across providers by design, so these docs deliberately don't re-describe it
- `docs/platforms/homelab.md` is a migration guide (AWS → self-hosted), not a fresh-deploy guide — walks through `scripts/backup.sh`/`scripts/restore.sh` end to end as the actual migration mechanism

### Changed

- `docs/project-specification.md`'s Documentation section gains `platforms/`

## [0.7.0] - 2026-07-21

### Added

- `docker/monitoring-agent/`: Node Exporter (host metrics) + cAdvisor (per-container metrics), deployed identically on every host role. Both bind to `127.0.0.1` only by default (neither has any authentication) — cross-host Prometheus scraping is a documented, source-IP-scoped manual opt-in, not scripted
- `docker/observability/`: Prometheus, Alertmanager, Grafana, Uptime Kuma on the `management` host. Prometheus/Alertmanager stay internal-only (no meaningful auth of their own); Grafana/Uptime Kuma get a public URL through the new management proxy. Three default alert rules (host down, disk >85%, container missing) with a no-op Alertmanager receiver — wiring a real notification channel needs deployment-specific credentials that don't belong in this repo. Grafana's Prometheus datasource is provisioned as code; dashboards are a documented two-click import (Node Exporter Full, cAdvisor) rather than vendored JSON
- `docker/management-proxy/`: TLS termination and name-based vhost routing (`jenkins.<domain>`, `grafana.<domain>`, `uptime.<domain>`) for every public UI on the `management` host, replacing the single-vhost `jenkins/nginx.conf`. Domain names are injected via the official nginx image's `envsubst` templating, not hardcoded

### Changed

- `scripts/harden-host.sh`: `role_ports()` documents why the exporter ports are deliberately not in the default UFW allowlist
- `jenkins/docker-compose.yml`: the `nginx` service moved out to `docker/management-proxy/` (see above) — `jenkins/` is Jenkins-only again, still not published on a host port itself

## [0.6.0] - 2026-07-21

### Added

- `scripts/backup.sh` — local, verified, rotated backups per host role (`pg_dump -Fc` for Postgres, volume tars for `jenkins_home`/`portainer_data`/`registry_data`); off-host replication is documented (`docs/backup.md`), not scripted, since the destination varies per deployment
- `scripts/restore.sh` — restores a backup; destructive, so it's a dry run unless `--yes-i-am-sure` is passed; validates Postgres connectivity and table presence after a restore
- `scripts/update.sh` — on-demand `apt upgrade` + `docker compose pull/up` per role, image prune, idempotent logrotate config install
- `scripts/cleanup.sh` — periodic `docker system prune`/build-cache prune, never touches volumes
- `scripts/deploy.sh` — manual/fallback counterpart to `vars/standardDeployPipeline.groovy`'s SSH deploy stage (pull infra config → tag rollback images → pull → up → wait-for-healthy → roll back on failure), for when Jenkins isn't the one triggering deployment
- `scripts/logrotate/infra-nginx.conf` — rotates the file-based nginx logs added in v0.5.0 for Fail2ban
- Real content for `docs/backup.md` and `docs/restore.md` (stubs since v0.1.0), including a disaster-recovery walkthrough

### Changed

- `docs/roadmap.md`: v0.6.0 gains `deploy.sh` (confirmed with the user — its functional twin already existed as the Jenkins pipeline's deploy stage, but a standalone fallback is valuable when Jenkins itself isn't available); v0.5.0 status corrected to Released
- `docs/project-specification.md`'s Operations section gains `restore.sh`/`cleanup.sh` entries, matching `docs/roadmap.md`

## [0.5.0] - 2026-07-20

### Added

- `docs/roadmap.md`: single source of truth for phase-by-phase scope/status and roadmap revision history (previously duplicated inside `project-specification.md`'s "Versioning Strategy" section, which is why syncing the v0.5.0/v0.8.0 renames took careful edits); includes a Guiding Principles section ("write once, deploy anywhere") and an explicit Out of Scope section (Kubernetes, Terraform, Ansible — deferred to v2.x)
- `scripts/harden-host.sh`: host-level (not Docker) production hardening — UFW firewall (role-driven port sets for `management`/`app`/`agent` hosts, SSH always allowed before any default-deny policy), Fail2ban (`sshd` + `nginx-limit-req` + `nginx-botsearch` jails via `scripts/fail2ban/jail.local`), `unattended-upgrades`, and an opt-in-only `--harden-ssh` flag (disables password/root SSH login — never runs automatically, given the lockout risk)

### Changed

- `docs/project-specification.md`: v0.5.0 renamed from "Oracle Deployment" to "Production Hardening" (cloud-agnostic — a cloud provider is a deployment target, not a repo feature); v0.8.0 renamed from "Platform Migration" to "Platform Integration"
- Roadmap scope expanded per an architecture change request: v0.5.0 (Production Hardening) now also covers UFW, Fail2ban, and production security defaults; v0.6.0 (Operations) expanded to `restore.sh`/`cleanup.sh`, backup/restore verification, log cleanup and rotation; v0.7.0 (Observability) expanded to Uptime Kuma, Node Exporter, cAdvisor; v0.9.0 (Documentation) expanded to cover `roadmap.md`/`project-specification.md` themselves, architecture diagrams, runbooks, onboarding docs. Scope changes only — no new code in this pass, see `docs/roadmap.md`'s Revision History for the full reasoning.
- `README.md` and `docs/project-specification.md` no longer embed the roadmap inline — both now point to `docs/roadmap.md`
- `docs/project-specification.md`: added a Guiding Principles section and an Out of Scope section; `Repository Structure` now lists `vars/` (missing since v0.3.0)
- Production hardening applied across all four existing stacks (`docker/portainer/`, `docker/registry/`, `jenkins/`, `docker/app/`):
  - Healthcheck-based `depends_on` (`condition: service_healthy`) wherever one service must be actually ready before another starts, not just started
  - `stop_grace_period` on every service, tuned to what each process needs to drain cleanly
  - Resource limits (`deploy.resources.limits`) on every service that didn't already have them
  - Restart policy now distinguishes stateless services (`unless-stopped`/`always`) from stateful/expensive-to-crash-loop ones (`postgres`, `jenkins` itself use bounded `on-failure:5`, never `always`) — `deploy.restart_policy` is not used anywhere, since it's Swarm-only and silently ignored by plain `docker compose up`
  - `docker/app/`'s required `.env` values (`POSTGRES_*`, `REGISTRY_URL`) now use Compose's `${VAR:?message}` syntax — missing values fail startup immediately with a clear error instead of running with empty config
  - `nginx/app.conf` and `jenkins/nginx.conf`: added rate limiting (`limit_req`) and a `Permissions-Policy` header; `nginx/app.conf` also gets a conservative starter `Content-Security-Policy` (omitted for Jenkins, which manages its own CSP)
- `nginx/app.conf` and `jenkins/nginx.conf` now also log to a file (`/var/log/nginx-file/`), not just stdout — Fail2ban runs on the host and needs a file to tail; `docker/app/docker-compose.yml` and `jenkins/docker-compose.yml` bind-mount that path out to `/var/log/infra/<service>/` on the host

## [0.4.0] - 2026-07-20

### Added

- Private Docker Registry (`docker/registry/docker-compose.yml`), self-hosted, htpasswd-authenticated, TLS-terminated
- `ssl/obtain-cert.sh`: shared Let's Encrypt (webroot) / self-signed certificate helper used by every TLS-terminating service in this repo
- Jenkins fronted by TLS-terminating Nginx (`jenkins/nginx.conf`), enabling HTTPS GitHub webhooks; Jenkins itself no longer publishes a host port directly
- Staging/production app stack (`docker/app/`): Nginx + PostgreSQL + Next.js + .NET API deployed as one unit, base compose plus `docker-compose.staging.yml`/`docker-compose.production.yml` overrides
- `nginx/app.conf`: TLS termination, gzip, security headers, routes `/api/` to the .NET API and everything else to Next.js

### Changed

- `vars/standardDeployPipeline.groovy`: `Docker Build` stage now also pushes to the private registry (new `registryUrl` / `registryCredentialsId` params)
- ShellCheck CI job now scans all `**/*.sh` files repo-wide, not just `scripts/**/*.sh` (needed once shell scripts started appearing outside `scripts/`, e.g. `ssl/obtain-cert.sh`)

## [0.3.0] - 2026-07-20

### Added

- Jenkins server stack (`jenkins/docker-compose.yml`), configured entirely via JCasC (`jenkins/casc.yaml`)
- Jenkins Shared Library (`vars/standardDeployPipeline.groovy`): GitHub -> Build -> Docker Build -> Deploy via SSH, parametrized by target environment/host

## [0.2.0] - 2026-07-20

### Added

- Portainer CE management stack (`docker/portainer/docker-compose.yml`), deployed on the management host
- Portainer Agent stack (`docker/portainer/agent-compose.yml`), deployed on remote hosts to be managed

## [0.1.0] - 2026-07-20

### Added

- Initial repository structure (`scripts/`, `docker/`, `jenkins/`, `nginx/`, `ssl/`, `docs/`, `.github/`)
- `README.md` with project vision, philosophy, and roadmap
- `CONTRIBUTING.md` with commit conventions and release process
- `LICENSE` (MIT)
- `.gitignore` and `.editorconfig`
- Documentation stubs: `architecture.md`, `deployment.md`, `backup.md`, `restore.md`, `recovery.md`
- GitHub Actions lint workflow (shellcheck + markdownlint)
- Issue and pull request templates
- README badges (license, lint status, release, Conventional Commits, Keep a Changelog)

[Unreleased]: https://github.com/mcansem/infra/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/mcansem/infra/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/mcansem/infra/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/mcansem/infra/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/mcansem/infra/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/mcansem/infra/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/mcansem/infra/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/mcansem/infra/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/mcansem/infra/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/mcansem/infra/releases/tag/v0.1.0
