# Backup

Local, verified, rotated backups via [scripts/backup.sh](../scripts/backup.sh). See that script and [scripts/README.md](../scripts/README.md) for the exact commands — this document covers strategy and the parts that live outside the script itself.

## What's backed up, per host role

| Role | What | Method |
|---|---|---|
| `app` | PostgreSQL database | `pg_dump -Fc` (logical dump, not a filesystem-level volume copy — see below) |
| `management` | `jenkins_home`, `portainer_data`, `registry_data` | tar of each named volume, via a throwaway container |
| `agent` | nothing | Portainer Agent holds no state of its own |

**Why `pg_dump`, not a volume tar, for Postgres:** a filesystem-level backup of a *live* database's data directory risks capturing an inconsistent state (in-flight writes, WAL not yet checkpointed). `pg_dump` talks to the running server and produces a consistent, portable logical backup instead — the standard, correct approach for a running Postgres instance.

## Verification

Every backup is checked immediately, not just written and trusted:

- Postgres dumps: `pg_restore --list` against the file (run inside a throwaway `postgres:16-alpine` container, so the host itself needs no `postgresql-client` install) — fails fast on a corrupt or truncated dump.
- Volume archives: `tar tzf` against the file.

If verification fails, `backup.sh` exits non-zero and leaves the bad file in place for inspection rather than silently rotating it away.

## Retention

`find <backup-dir> -mtime +<RETENTION_DAYS> -delete`, default 7 days, configurable via the `RETENTION_DAYS` environment variable. Rotation runs at the end of every `backup.sh` invocation, regardless of whether that run's own backup succeeded, so a string of failures doesn't also fill the disk with unrotated old backups.

## Scheduling

Not automated by this repo — add a cron entry once a host is configured. See [scripts/README.md](../scripts/README.md#recommended-cron-schedule) for the recommended line.

## Off-host replication

`backup.sh`'s job stops at a verified local backup. Where you copy it beyond the host is an operational choice that varies per deployment, and this repo stays cloud-agnostic rather than hardcoding one destination. Two common patterns, layered on top via cron, not scripted here:

```text
# rsync to another host (e.g. the eventual homelab)
0 4 * * * rsync -az --delete /var/backups/infra/ backup-host:/srv/infra-backups/

# rclone to any S3-compatible object storage (AWS S3, Backblaze B2, MinIO, ...)
0 4 * * * rclone sync /var/backups/infra/ remote:infra-backups/
```

Either requires its own one-time setup (SSH key trust for `rsync`, an `rclone config` remote) outside the scope of this document.

## Disaster recovery

If a host is lost entirely: provision a replacement, re-clone this repo, run [scripts/harden-host.sh](../scripts/harden-host.sh) for the role, bring up the relevant stack(s), restore the most recent verified backup (see [restore.md](restore.md)), and re-point DNS/`ssl/obtain-cert.sh` at the new host if its IP changed.
