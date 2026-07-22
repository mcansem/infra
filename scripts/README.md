# scripts/

Parameter-driven Bash automation for host hardening (v0.5.0) and day-to-day operations (v0.6.0): `harden-host.sh`, `backup.sh`, `restore.sh`, `update.sh`, `cleanup.sh`, `deploy.sh`. Plus `bootstrap.sh` (pre-hardening host setup), `init-env.sh` (credential bootstrap), and `validate-compose.sh` (a CI-focused check rather than something you'd run on a host).

Conventions (see [CONTRIBUTING.md](../CONTRIBUTING.md)):

- Environment/role-driven: `./script.sh <role>`
- `set -euo pipefail`
- Idempotent and safe to re-run
- Functions over duplicated logic
- Colored, leveled logging (`INFO`, `SUCCESS`, `WARNING`, `ERROR`)

## bootstrap.sh

The step before every other script in this directory can run: on a completely fresh Ubuntu host with nothing installed, installs `git` and Docker Engine (+ Compose plugin) from Docker's official apt repo, adds the invoking (`sudo`) user to the `docker` group, and clones this repo. Deliberately stops there — it does not chain into `harden-host.sh`, since picking a role is a decision this script shouldn't make for you.

```bash
sudo scripts/bootstrap.sh
# or, to clone a fork/mirror:
sudo REPO_URL=https://github.com/you/infra.git scripts/bootstrap.sh
```

Docker's version is intentionally **not pinned** — installed via `apt-get install docker-ce ...` with whatever's current in Docker's apt repo, same as the one existing precedent for installing Docker packages in this repo (`jenkins/Dockerfile`). This repo pins container image tags for stack reproducibility; the host's Docker Engine itself is treated like any other OS package, same reasoning as `unattended-upgrades` below being left unpinned. The installed version is always logged at `SUCCESS` level, so it's the first thing you'd check if a version-specific issue ever came up.

After it finishes: `usermod -aG docker` only takes effect in a new session — log out and back in, or run `newgrp docker`, before using `docker` without `sudo`.

Idempotent: skips the Docker install entirely if `docker` is already on `PATH`; refuses to overwrite an existing clone directory rather than clobbering it.

## harden-host.sh

Host-level (not Docker) production hardening: a swap file, UFW firewall, Fail2ban, `unattended-upgrades`, and an opt-in SSH lockdown.

```bash
sudo scripts/harden-host.sh <management|app|agent> [--harden-ssh]
```

### Roles

Different hosts in this repo's deployment run different stacks, so the firewall rules differ per role:

| Role | Host (per [docs/roadmap.md](../docs/roadmap.md)) | Runs | Ports opened (besides SSH) |
|---|---|---|---|
| `management` | AWS EC2 | Portainer, Jenkins (+ its nginx), private Registry | 9443, 80, 443, 5000 |
| `app` | Google Cloud VM | `docker/app/` stack | 80, 443 |
| `agent` | any remote host Portainer manages | Portainer Agent only | 9001 |

### Swap

The `management` and `app` roles target small free-tier instances (AWS `t3.small` 2GB, Google Cloud `e2-micro` 1GB per [docs/roadmap.md](../docs/roadmap.md)). Each Docker stack's `deploy.resources.limits.memory` values are sized to realistic usage with headroom to spare under normal conditions, but a worst-case simultaneous peak across every container on a host can still exceed physical RAM. A swap file (1G on `management`, 512M on both `app` and `agent`) is the safety net for that case: it turns a hard, unpredictable OOM-kill (which could take out anything on the host, including `sshd`) into graceful, if slower, degradation. It is not a substitute for the memory limits themselves, and not a performance feature — swapping is expected to be rare, not routine. Created at `/swapfile`, persisted via `/etc/fstab`, idempotent (skips if already active, re-enables if present but inactive).

### Safety: SSH first, always

The script allows SSH (port 22, plus whatever port the *current* SSH session is actually using, auto-detected) **before** setting any default-deny firewall policy. This ordering is not configurable — it's the difference between a safe run and permanently locking yourself out of a remote host.

### `--harden-ssh` is opt-in for the same reason

Disabling password authentication and root login is real hardening, but it is the single most dangerous thing this script can do: get it wrong (no key configured, wrong user, etc.) and there is no way back in short of a cloud provider's console/recovery access. **Do not pass `--harden-ssh` until you have confirmed, from a second terminal, that you can already log in with an SSH key.** The script backs up `/etc/ssh/sshd_config` before touching it and warns if a cloud-image drop-in under `/etc/ssh/sshd_config.d/` might override the change.

### Fail2ban jails

Configured via [fail2ban/jail.local](fail2ban/jail.local): `sshd` (bundled filter, no changes needed), `nginx-limit-req` (bans IPs that repeatedly trip the rate limiting in `nginx/app.conf`/`docker/management-proxy/nginx.conf.template`), and `nginx-botsearch` (bundled scanner/bot-probe filter). Both nginx jails read from `/var/log/infra/<service>/`, which `docker/app/docker-compose.yml` (app host) and `docker/management-proxy/docker-compose.yml` (management host) bind-mount out of their `nginx` containers — see those files' `logs:` volumes.

`harden-host.sh` creates the right directory for the role automatically (`app-nginx` for `app`, `management-proxy` for `management`, nothing for `agent`) — and, critically, **pre-creates empty `access.log`/`error.log` files in it too**, not just the directory. `jail.local`'s `logpath` is a glob; if those files don't exist yet (nginx itself hasn't run a `docker compose up` at the point `harden-host.sh` runs), fail2ban silently fails to pick up the jail instead of erroring loudly. No manual step needed either way.

If nginx fails to start with a log permission error, `chmod 777` on the directory is an acceptable pragmatic fix for log data.

Not included: a custom Jenkins-login jail. No bundled Fail2ban filter exists for Jenkins' log format, and hand-writing one without a running Jenkins to test the regex against risks a filter that silently never matches. Left as a future addition.

### Manual verification (no host to test against from this machine)

After running on a real host:

```bash
ufw status verbose        # only the role's expected ports should be open
fail2ban-client status    # all three jails should be listed and active
```

Confirm your existing SSH session is still connected throughout — if it drops before you've verified `ufw status`, you have a firewall problem to fix immediately (console access, not another SSH attempt).

## init-env.sh

```bash
scripts/init-env.sh <management|app|agent>
```

Creates the real `.env` files each role's stacks need, from their `.env.example` templates — run this on the target host, after cloning the repo there. Real credentials never touch git; `.env` files are gitignored everywhere, so a fresh `git clone`/`git pull` only ever brings in the dummy `.env.example` values. This script exists so filling in the real ones isn't a fully manual, error-prone process:

- **Secrets** (`JENKINS_ADMIN_PASSWORD`, `POSTGRES_PASSWORD`, `GRAFANA_ADMIN_PASSWORD`) are generated automatically (`openssl rand -hex 24`) — never typed or guessed. Printed once in a summary at the end; save them immediately, they're not shown again and aren't written anywhere else.
- **Derivable values** (`DOCKER_GID`) are auto-detected from the host (`getent group docker`), falling back to a placeholder with a warning if Docker isn't installed yet.
- **Everything else** (domains, image tags, database names) is prompted for, with the `.env.example` value shown as the default — press Enter to accept it.
- For `management`, `GRAFANA_DOMAIN` is asked once and written identically to both `docker/observability/.env` and `docker/management-proxy/.env` — those two must match (see the comment in `docker/observability/.env.example`), and filling them in separately by hand is exactly the kind of thing that's easy to get inconsistent.
- Never overwrites an existing `.env` without an explicit confirmation prompt.

You can still edit `.env` files by hand instead (copy `.env.example`, fill it in with an editor) — this script is a convenience, not a requirement; the underlying mechanism (a file that only ever exists locally on the host, never in git) is the same either way.

## backup.sh

```bash
scripts/backup.sh <management|app|agent>
```

Backs up whatever the role is responsible for, verifies each backup immediately, and rotates old ones — all local, under `BACKUP_DIR` (default `/var/backups/infra`), retained for `RETENTION_DAYS` (default 7):

- **`app`** — `pg_dump -Fc` of the Postgres database (reads credentials from `docker/app/.env`). Not a filesystem-level tar of `postgres_data` — that risks inconsistency on a live database; a logical dump is the correct, portable approach.
- **`management`** — `jenkins_home`, `portainer_data`, `registry_data`, each tarred via a throwaway container mounting the volume read-only.
- **`agent`** — nothing to do; the Portainer Agent holds no state of its own.

Verification happens right after each backup: `pg_restore --list` on the dump (fails fast on a corrupt dump, run inside a throwaway `postgres:16-alpine` container — no host `postgresql-client` dependency), `tar tzf` on each archive.

**Off-host replication is intentionally not scripted.** Where you copy verified local backups (S3, another host via rsync/rclone, etc.) varies per deployment and shouldn't be hardcoded into a cloud-agnostic script — see [docs/backup.md](../docs/backup.md) for example patterns.

## restore.sh

```bash
scripts/restore.sh <management|app|agent> <timestamp> [--yes-i-am-sure]
```

`<timestamp>` matches a `backup.sh` filename, e.g. `20260719-143000` from `postgres-20260719-143000.dump`.

**Destructive by design, so it's a dry run unless `--yes-i-am-sure` is passed** — without the flag it only prints what it would do (same spirit as `harden-host.sh`'s `--harden-ssh`: never silently overwrite live data). With it: `pg_restore --clean --if-exists` for Postgres, or stop-container → clear-volume → untar → restart for each named volume.

Validation after a Postgres restore (roadmap item): confirms the database accepts connections and has at least one user table — kept schema-agnostic since no application schema exists yet to check against specifically.

## update.sh

```bash
sudo scripts/update.sh <management|app|agent>
sudo scripts/update.sh app <staging|production>
```

On-demand: full `apt upgrade`, `docker compose pull && up -d` for every stack the role runs, a light `docker image prune -f`, and an idempotent re-install of the logrotate config below. Distinct from `harden-host.sh`'s `unattended-upgrades`, which only auto-applies the *security* update track continuously in the background — this is the operator-triggered full upgrade.

## cleanup.sh

```bash
scripts/cleanup.sh
```

Periodic disk hygiene, independent of role: `docker system prune -af` (stopped containers, unused networks, dangling images) and build-cache pruning older than `BUILD_CACHE_DAYS` (default 7). **Never passes `--volumes`** — cleanup never touches volume data; that's what `restore.sh`'s confirmation gate exists for, not an implicit prune. Reports disk usage before and after.

## deploy.sh

```bash
scripts/deploy.sh <management|app|agent>
scripts/deploy.sh app <staging|production>
```

The manual/fallback counterpart to [vars/standardDeployPipeline.groovy](../vars/standardDeployPipeline.groovy)'s "Deploy via SSH" stage — for when Jenkins isn't the one triggering deployment (down, an app repo not yet onboarded, emergency manual intervention). Deliberately mirrors the pipeline's stage order: pull the infra repo's own latest config → tag currently-running images as rollback targets → pull new images → `up -d` → wait up to 120s for every container to report healthy (or have no healthcheck) → on failure, re-tag the rollback images back and restart, then exit non-zero for the operator to investigate.

## Logrotate

[logrotate/infra-nginx.conf](logrotate/infra-nginx.conf) rotates the file-based nginx logs added in v0.5.0 for Fail2ban (`/var/log/infra/*/*.log`) — daily, compressed, 14 days kept, `copytruncate` (no need to signal the nginx process inside its container to reopen files). Installed to `/etc/logrotate.d/infra-nginx` idempotently by `update.sh` on every run, rather than requiring a one-off manual step.

## Recommended cron schedule

Not auto-installed into crontab — add these yourself once a host is configured (`crontab -e` as root):

```text
0 3 * * *   /path/to/infra/scripts/backup.sh <role>
0 4 * * 0   /path/to/infra/scripts/update.sh <role>
30 4 * * 0  /path/to/infra/scripts/cleanup.sh
```

(daily backup, weekly update, weekly cleanup shortly after — adjust the role/environment arguments and paths for the actual host)

## validate-compose.sh

```bash
scripts/validate-compose.sh
```

Runs `docker compose config` against every `docker-compose.yml` (and staging/production override combination) in this repo, using each stack's `.env.example` for dummy values where a stack requires `${VAR:?}` variables — never overwrites a real `.env` if one already exists. Wired into CI ([.github/workflows/lint.yml](../.github/workflows/lint.yml)'s `compose-validate` job) so every PR gets an automatic syntax/structure check, closing the "reviewed by eye only, no Docker on this machine" gap every phase before v1.0.0 had to accept. Also runnable locally, anywhere Docker is available.
