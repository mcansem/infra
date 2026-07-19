# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/mcansem/infra/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/mcansem/infra/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/mcansem/infra/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/mcansem/infra/releases/tag/v0.1.0
