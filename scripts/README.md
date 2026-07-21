# scripts/

Parameter-driven Bash automation for host hardening (v0.5.0) and day-to-day operations (v0.6.0): `harden-host.sh`, `backup.sh`, `restore.sh`, `update.sh`, `cleanup.sh`, `deploy.sh`. Plus `validate-compose.sh`, a CI-focused check rather than something you'd run on a host.

Conventions (see [CONTRIBUTING.md](../CONTRIBUTING.md)):

- Environment/role-driven: `./script.sh <role>`
- `set -euo pipefail`
- Idempotent and safe to re-run
- Functions over duplicated logic
- Colored, leveled logging (`INFO`, `SUCCESS`, `WARNING`, `ERROR`)

## harden-host.sh

Host-level (not Docker) production hardening: UFW firewall, Fail2ban, `unattended-upgrades`, and an opt-in SSH lockdown.

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

### Safety: SSH first, always

The script allows SSH (port 22, plus whatever port the *current* SSH session is actually using, auto-detected) **before** setting any default-deny firewall policy. This ordering is not configurable — it's the difference between a safe run and permanently locking yourself out of a remote host.

### `--harden-ssh` is opt-in for the same reason

Disabling password authentication and root login is real hardening, but it is the single most dangerous thing this script can do: get it wrong (no key configured, wrong user, etc.) and there is no way back in short of a cloud provider's console/recovery access. **Do not pass `--harden-ssh` until you have confirmed, from a second terminal, that you can already log in with an SSH key.** The script backs up `/etc/ssh/sshd_config` before touching it and warns if a cloud-image drop-in under `/etc/ssh/sshd_config.d/` might override the change.

### Fail2ban jails

Configured via [fail2ban/jail.local](fail2ban/jail.local): `sshd` (bundled filter, no changes needed), `nginx-limit-req` (bans IPs that repeatedly trip the rate limiting in `nginx/app.conf`/`jenkins/nginx.conf`), and `nginx-botsearch` (bundled scanner/bot-probe filter). Both nginx jails read from `/var/log/infra/<service>/`, which `docker/app/docker-compose.yml` and `jenkins/docker-compose.yml` bind-mount out of their `nginx` containers — see those files' `logs:` volumes. Create those host directories before first `docker compose up` (e.g. `sudo mkdir -p /var/log/infra/app-nginx /var/log/infra/jenkins-nginx`); if nginx fails to start with a log permission error, `chmod 777` on the directory is an acceptable pragmatic fix for log data.

Not included: a custom Jenkins-login jail. No bundled Fail2ban filter exists for Jenkins' log format, and hand-writing one without a running Jenkins to test the regex against risks a filter that silently never matches. Left as a future addition.

### Manual verification (no host to test against from this machine)

After running on a real host:

```bash
ufw status verbose        # only the role's expected ports should be open
fail2ban-client status    # all three jails should be listed and active
```

Confirm your existing SSH session is still connected throughout — if it drops before you've verified `ufw status`, you have a firewall problem to fix immediately (console access, not another SSH attempt).

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
