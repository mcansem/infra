# Roadmap

Single source of truth for phase-by-phase scope, status, and how the roadmap has changed over time. For the overall vision, philosophy, and coding standards, see [project-specification.md](project-specification.md).

## Guiding Principles

> Write once, deploy anywhere.

Infrastructure code should not change depending on where it is deployed. Cloud providers (AWS, Google Cloud, Oracle Cloud, future Homelab) are deployment targets, not repository features.

- Infrastructure-as-Code
- Cloud-agnostic
- Modular
- Idempotent
- Reusable
- Production-ready
- Automation-first
- Self-hosting friendly
- Future-proof for Homelab

## Deployment Journey

### Short term

```text
GitHub → AWS EC2 (Ubuntu, Docker, Jenkins, Portainer)
       → Google Cloud VM (Ubuntu, Docker, Nginx, PostgreSQL, Next.js, .NET API)
       → Oracle Cloud (Production)
```

### Long term

```text
GitHub → Homelab → Oracle Cloud (Production)
```

Jenkins will eventually migrate from AWS to the homelab; the repository is designed with this migration in mind — see the Platform Integration (v0.8.0) phase below.

## Phases

### v0.1.0 — Repository Foundation (Released)

README, CHANGELOG, LICENSE (MIT), CONTRIBUTING, folder structure, basic documentation, GitHub Actions lint CI (markdownlint + shellcheck), issue/PR templates.

### v0.2.0 — Docker Infrastructure (Released)

Docker, Compose, custom networks, named volumes, Portainer CE server + Agent stack (one Portainer instance managing multiple Docker hosts).

### v0.3.0 — CI/CD (Released)

Jenkins in Docker, configured entirely as code (JCasC), declarative pipeline (`GitHub → Build → Docker Build → Deploy via SSH`) as a Jenkins Shared Library for reuse across application repos.

### v0.4.0 — Staging Environment (Released)

Nginx, PostgreSQL, Next.js, .NET API, SSL. Also added during implementation (prerequisites for pulling real images): a self-hosted private Docker Registry (no Docker Hub/GHCR dependency), TLS in front of Jenkins for GitHub webhooks, and `ssl/obtain-cert.sh` (Let's Encrypt webroot / self-signed) as the shared certificate mechanism every TLS-terminating service uses.

### v0.5.0 — Production Hardening (Released)

Renamed from "Oracle Deployment" — see [Revision History](#revision-history). Cloud-agnostic hardening applied uniformly across every stack:

- Healthcheck dependency chain
- Graceful shutdown
- Restart strategy separation (stateful vs stateless)
- Resource limits
- Environment validation (`${VAR:?}`)
- Production compose overrides
- Fail-fast startup validation
- Security headers
- Rate limiting
- UFW firewall configuration
- Fail2ban configuration
- Production security defaults

### v0.6.0 — Operations (In Progress)

- `backup.sh`
- `restore.sh`
- `update.sh`
- `cleanup.sh`
- `deploy.sh` — manual/fallback counterpart to `vars/standardDeployPipeline.groovy`'s SSH deploy stage, for when Jenkins isn't the one triggering deployment
- Backup verification
- Restore validation
- Maintenance automation
- Log cleanup
- Optional log rotation
- Operational documentation

### v0.7.0 — Observability (Planned)

- Uptime Kuma
- Prometheus
- Grafana
- Node Exporter
- cAdvisor
- Alerting
- Monitoring dashboards
- Service health visualization

Covers both infrastructure metrics and external service availability.

### v0.8.0 — Platform Integration (Planned)

Renamed from "Platform Migration" — see [Revision History](#revision-history). Documentation and deployment guidance, not infrastructure changes:

- Multi-target deployment guidance (AWS, Google Cloud, Oracle Cloud, Homelab)
- Environment-specific examples
- Self-hosted Jenkins support
- Internal infrastructure

The infrastructure itself must remain identical across providers.

### v0.9.0 — Documentation (Planned)

Complete documentation set:

- `architecture.md`
- `deployment.md`
- `backup.md`
- `restore.md`
- `recovery.md`
- `roadmap.md` (this document)
- `project-specification.md`
- Architecture diagrams
- Operational runbooks
- Onboarding documentation

### v1.0.0 — Production Ready Stable Release (Planned)

Final stabilization pass.

## Out of Scope for v1.0.0

Kubernetes, Terraform, and Ansible are intentionally excluded from the v1 roadmap. They are not rejected permanently — they belong to a future v2.x roadmap, after the Docker-based infrastructure reaches a stable v1.0.0 release.

## Revision History

### Revision #1 — v0.5.0: Oracle Deployment → Production Hardening

Reason: Oracle Cloud is only a deployment target. The repository itself must remain cloud-agnostic.

### Revision #2 — v0.8.0: Platform Migration → Platform Integration

Reason: The repository supports multiple deployment targets simultaneously rather than migrating between them.

### Revision #3 — Production Hardening expansion

Added: UFW, Fail2ban, production security defaults.

Reason: Host-level security belongs to Production Hardening.

### Revision #4 — Observability expansion

Added: Uptime Kuma, Node Exporter, cAdvisor.

Reason: Infrastructure monitoring and service availability monitoring should complement each other.
