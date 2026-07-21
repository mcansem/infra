# Disaster Recovery

The authoritative runbook for "a host is gone." Pulls together what's otherwise scattered across [backup.md](backup.md), [restore.md](restore.md), and [platforms/homelab.md](platforms/homelab.md) into one incident-shaped procedure, and states explicit objectives that none of those documents commit to on their own.

## Objectives

- **RPO (Recovery Point Objective) ≈ 24 hours.** The recommended backup cadence ([scripts/README.md](../scripts/README.md#recommended-cron-schedule)) is daily. Worst case, a host lost right before its next scheduled backup loses just under a day of data. Run `scripts/backup.sh <role>` manually before any planned risky change (a major update, a migration) to shrink this window to zero for that specific event.
- **RTO (Recovery Time Objective) — an estimate, not a tested SLA.** This repository has not yet been through a real host-loss scenario. Based on the steps below: host provisioning (~10–30 min, provider-dependent), `scripts/harden-host.sh` (~5 min), bringing up all stacks including certificate bootstrap (~15–20 min), restore (~5–15 min depending on data size) — call it **under two hours**, with the explicit caveat that it's a paper estimate until it's actually rehearsed.

## Procedure: a host is lost

1. **Provision a replacement** — see the relevant [platforms/](platforms/) guide for the provider.
2. **Harden it:**

   ```bash
   git clone <this-repo-url> infra && cd infra
   sudo scripts/harden-host.sh <role>
   ```

3. **Bring up the stacks** the role runs, in the order documented in each stack's own README (for `management`: `docker/monitoring-agent/` → `jenkins/` → `docker/registry/` → `docker/portainer/` → `docker/observability/` → `docker/management-proxy/`, per [docker/observability/README.md](../docker/observability/README.md#deployment-order-management-host); for `app`: [docker/app/README.md](../docker/app/README.md)'s bootstrap, self-signed cert first).
4. **Restore the most recent verified backup** — copy it onto the new host from wherever it was replicated off-host (see [backup.md](backup.md#off-host-replication)), then:

   ```bash
   scripts/restore.sh <role> <timestamp> --yes-i-am-sure
   ```

   See [restore.md](restore.md) for what this does per volume and the validation it runs afterward.
5. **Obtain real certificates** if the replacement host is new to Let's Encrypt (a fresh host has no certificate material) — the self-signed-first, then real-cert bootstrap already covered in each stack's README.
6. **Re-point DNS** at the new host's IP if it changed.
7. **Verify** — confirm the stack's own healthchecks are green (`docker compose ps`), and if this was the `management` host, confirm Grafana/Uptime Kuma/Jenkins are all reachable through the management proxy and that at least one Jenkins build succeeds end to end.

## Partial-loss scenarios

Not every incident is a full host loss. See [runbooks.md](runbooks.md) for narrower playbooks tied to specific alerts (`HostDown`, `DiskSpaceLow`, `ContainerMissing`) — those are usually resolved without a full restore.

## What backup does *not* cover

Application source code lives in its own repo (`portfolio/` in the running example) and is protected by Git/GitHub itself, not by anything in this repository. Losing the `app` host loses running containers and the database — not the application's own source history.
