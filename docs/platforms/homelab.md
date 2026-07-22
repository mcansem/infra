# Homelab — long-term Jenkins migration

Per the Long Term roadmap in [docs/roadmap.md](../roadmap.md): "Jenkins will eventually migrate from AWS to Homelab." This document is a migration guide, not a fresh-deploy guide like the other three — it walks through moving an already-running `management` host from AWS to self-hosted hardware, exercising the backup/restore tooling built in v0.6.0 end to end.

## Prerequisite: reachability

A residential/homelab network typically has no static public IP, unlike a cloud VM. Direct port-forwarding onto a home router is possible but not recommended (dynamic IP, ISP terms of service, and none of the UFW source-IP-scoping this repo relies on elsewhere works cleanly through NAT). The recommended approach is a tunnel — [Tailscale](https://tailscale.com/) or [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) are the two most common choices. This is a **recommendation, not something this repo implements as code** — v0.8.0 is documentation-only per [docs/roadmap.md](../roadmap.md), and picking/configuring a tunnel provider is a real infrastructure decision that deserves its own pass once it's actually time to migrate, not a default baked in ahead of need.

## Migration procedure

Assumes the AWS `management` host (see [aws.md](aws.md)) is already up and running, and the homelab machine is provisioned with Ubuntu and reachable (directly or via the tunnel above).

1. **Back up the AWS host:**

   ```bash
   scripts/backup.sh management
   ```

   Produces verified, timestamped archives of `jenkins_home`, `portainer_data`, and `registry_data` under `/var/backups/infra` (see [backup.md](../backup.md)).

2. **Copy the backup to the homelab host** — `rsync`/`scp`, whatever's reachable given the tunnel setup from the prerequisite step.

3. **Harden the homelab host** — if it's a fresh Ubuntu install with nothing on it yet, `scripts/bootstrap.sh` gets `git`/Docker installed and this repo cloned first (see [docs/deployment.md](../deployment.md#getting-a-host-ready-in-the-first-place)):

   ```bash
   git clone <this-repo-url> infra && cd infra
   sudo scripts/harden-host.sh management
   ```

4. **Bring up the stacks** that need to exist before a restore can target them — `docker/monitoring-agent/`, `jenkins/`, `docker/registry/`, `docker/portainer/`, `docker/observability/`, `docker/management-proxy/` (same order as [aws.md](aws.md)).

5. **Restore onto the homelab host:**

   ```bash
   scripts/restore.sh management <timestamp> --yes-i-am-sure
   ```

   (See [restore.md](../restore.md) for what this does per volume, and why the flag is required.)

6. **DNS cutover** — repoint `jenkins.<domain>`, `grafana.<domain>`, `uptime.<domain>` at the homelab host's (tunnel) address. Obtain fresh certificates there first if the domains are new to that host — see [docker/management-proxy/README.md](../../docker/management-proxy/README.md).

7. **Verify**, then decommission the AWS `management` host once the homelab instance has been confirmed stable — Jenkins builds succeeding, Grafana/Uptime Kuma reachable, webhooks from application repos still delivering.

## What doesn't move

The `app` role (staging on GCP, production on Oracle Cloud per [google-cloud.md](google-cloud.md)/[oracle-cloud.md](oracle-cloud.md)) stays on cloud infrastructure — only the `management` role (and specifically Jenkins, per the roadmap's own framing) is the long-term homelab candidate. This is "self-hosted Jenkins support": the infrastructure code doesn't change at all to make this possible, because it was already cloud-agnostic from v0.5.0 onward — only the host it happens to run on does.
