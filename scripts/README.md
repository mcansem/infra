# scripts/

> Status: empty. Landing in v0.1.0 (this folder), populated starting v0.2.0+.

This folder will hold parameter-driven Bash automation: `install.sh`, `deploy.sh`, `backup.sh`, `update.sh`.

Conventions (see [CONTRIBUTING.md](../CONTRIBUTING.md)):

- Environment-driven: `./script.sh <ci|staging|production>`
- `set -euo pipefail`
- Idempotent and safe to re-run
- Functions over duplicated logic
- Colored, leveled logging (`INFO`, `SUCCESS`, `WARNING`, `ERROR`)
