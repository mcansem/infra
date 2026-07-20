# Restore

Restoring a backup produced by [backup.md](backup.md) / [scripts/backup.sh](../scripts/backup.sh), via [scripts/restore.sh](../scripts/restore.sh).

## The safety gate

`restore.sh` is destructive — it overwrites live data — so by default it does **nothing** except print what it would do:

```bash
scripts/restore.sh <management|app|agent> <timestamp>
```

This is always a dry run. To actually restore, add the flag explicitly:

```bash
scripts/restore.sh <management|app|agent> <timestamp> --yes-i-am-sure
```

`<timestamp>` matches a backup filename, e.g. `20260719-143000` from `postgres-20260719-143000.dump` — list `$BACKUP_DIR` (default `/var/backups/infra`) to find one.

There is no partial/interactive confirmation prompt by design — either you pass the flag because you've already decided, or you don't and nothing happens. This matches the same philosophy as `scripts/harden-host.sh`'s `--harden-ssh`: dangerous, irreversible actions require an explicit, unambiguous opt-in, not a `y/N` prompt that's easy to reflexively confirm.

## What happens, per role

- **`app`**: `pg_restore --clean --if-exists` replays the dump into the running Postgres container, dropping and recreating objects as needed.
- **`management`**: for each of `jenkins_home`, `portainer_data`, `registry_data` — the owning service is stopped, the volume's contents are cleared and replaced from the tar archive, then the service is restarted.
- **`agent`**: nothing to restore.

## Validation

After a Postgres restore, the script automatically checks:

1. The database accepts connections (`pg_isready`).
2. At least one user table exists (a schema-agnostic sanity check — there's no real application schema yet to check against specifically; once one exists, this is a reasonable place to add app-specific checks).

If validation fails, investigate before assuming the restore succeeded — a restore that "completes" without error but leaves an empty or unreachable database is worse than an obvious failure.

## Disaster recovery walkthrough

A full "lost the host" scenario, tying together [backup.md](backup.md)'s Disaster Recovery section:

1. Provision a replacement host.
2. `git clone` this repo onto it.
3. `sudo scripts/harden-host.sh <role>` — firewall, Fail2ban, security defaults.
4. Bring up the relevant stack(s) per their own README (`docker/app/README.md`, `jenkins/README.md`, etc.) — including obtaining a fresh TLS certificate, since a new host has no certificate material.
5. Copy the most recent verified backup onto the new host (from wherever it was replicated off-host — see [backup.md](backup.md#off-host-replication)).
6. `scripts/restore.sh <role> <timestamp> --yes-i-am-sure`.
7. Confirm the validation output, then re-point DNS at the new host's IP if it changed.

## Manual verification (no host to test against from this machine)

- Run `restore.sh` **without** `--yes-i-am-sure` and confirm it only prints, never acts.
- Run it **with** the flag against a disposable/throwaway target and confirm the validation step reports success before trusting a real restore.
