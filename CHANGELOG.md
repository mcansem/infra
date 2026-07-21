# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/mcansem/infra/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/mcansem/infra/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/mcansem/infra/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/mcansem/infra/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/mcansem/infra/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/mcansem/infra/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/mcansem/infra/releases/tag/v0.1.0
