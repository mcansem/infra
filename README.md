# infra

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Lint](https://github.com/mcansem/infra/actions/workflows/lint.yml/badge.svg)](https://github.com/mcansem/infra/actions/workflows/lint.yml)
[![Release](https://img.shields.io/github/v/release/mcansem/infra?include_prereleases)](https://github.com/mcansem/infra/releases)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)
[![Changelog](https://img.shields.io/badge/Keep%20a%20Changelog-1.1.0-orange.svg)](CHANGELOG.md)

Reusable, environment-agnostic infrastructure repository for deploying and operating applications across cloud, self-hosted, and homelab environments.

## Vision

This repository is **not** a project-specific deployment repo. It is a reusable infrastructure platform meant to serve multiple applications and servers over time, supporting:

- Cloud deployments
- Self-hosted deployments
- Homelab deployments
- CI/CD
- Staging and Production environments
- Disaster Recovery

## Philosophy

Application code and infrastructure code are always kept separate.

| Repository | Contains |
|---|---|
| `portfolio/` (example app repo) | Next.js, .NET 10 |
| `infra/` (this repo) | Infrastructure, Docker, Jenkins, Nginx, Bash scripts, SSL, deployment, documentation |

Infrastructure defined here must remain reusable regardless of which application consumes it.

## Roadmap

**Short term**

```
GitHub → AWS EC2 (Ubuntu, Docker, Jenkins, Portainer)
       → Google Cloud VM (Ubuntu, Docker, Nginx, PostgreSQL, Next.js, .NET API)
       → Oracle Cloud (Production)
```

**Long term**

```
GitHub → Homelab → Oracle Cloud (Production)
```

Jenkins will eventually migrate from AWS to the homelab; the repository is designed with this migration in mind.

## Repository Structure

```
infra/
├── scripts/    # Parameter-driven install/deploy/backup/update scripts
├── docker/     # Compose files and per-environment overrides
├── jenkins/    # Dockerized Jenkins + declarative pipelines
├── nginx/      # Reverse proxy, SSL termination, security headers
├── ssl/        # Certificate material (runtime only, not committed)
├── docs/       # Architecture, deployment, backup, restore, recovery docs
└── .github/    # Issue/PR templates, CI workflows
```

Each folder contains its own `README.md` describing its purpose and current status.

## Versioning Strategy

This project follows [Semantic Versioning](https://semver.org/) from the very first commit. See [CHANGELOG.md](CHANGELOG.md) for release history and [docs/project-specification.md](docs/project-specification.md) for the full technical specification and version-by-version roadmap (v0.1.0 → v1.0.0).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for commit conventions and the release process.

## License

[MIT](LICENSE)
