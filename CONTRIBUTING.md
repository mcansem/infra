# Contributing

This is a solo-maintained infrastructure repository, but it follows disciplined conventions so history stays readable and releases stay predictable.

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

| Prefix | Use for |
|---|---|
| `feat:` | New capability (e.g. a new script, a new compose service) |
| `fix:` | Bug fix |
| `docs:` | Documentation-only changes |
| `refactor:` | Code change that neither fixes a bug nor adds a feature |
| `chore:` | Maintenance work (deps, formatting, housekeeping) |
| `ci:` | CI/CD configuration changes |
| `build:` | Changes to build/tooling |

## Release Process

Every roadmap phase (see [docs/project-specification.md](docs/project-specification.md)) results in:

1. One pull request (if applicable)
2. One `CHANGELOG.md` entry under [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format
3. One git tag matching the released version (e.g. `v0.2.0`)
4. One GitHub release

Versions follow [Semantic Versioning](https://semver.org/).

## Bash Scripting Standards

All scripts under `scripts/` must:

- Start with `set -euo pipefail`
- Be parameter-driven by environment: `./script.sh <ci|staging|production>`
- Be idempotent — safe to run multiple times
- Prefer functions over duplicated logic
- Use colored, leveled logging (`INFO`, `SUCCESS`, `WARNING`, `ERROR`)
- Pass `shellcheck` (enforced by CI)

## Docker Standards

- Use Docker Compose (base file + per-environment overrides)
- Every service must define healthchecks and a restart policy
- Use named volumes and custom networks — no default bridge network reliance
- Follow a clean, consistent naming convention across services
