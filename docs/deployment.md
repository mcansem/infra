# Deployment

## The flow

Every deployment path in this repo — the Jenkins pipeline and the manual fallback alike — follows the same shape:

```text
Git Pull → Docker Pull → Docker Compose Up → Health Check → Rollback (on failure)
```

Two places implement it, deliberately kept in step with each other:

- **[vars/standardDeployPipeline.groovy](../vars/standardDeployPipeline.groovy)** — the automated path. An application repo's Jenkinsfile calls this Shared Library function; Jenkins checks out the app, builds and pushes its image, then SSHes into the target host to pull and restart.
- **[scripts/deploy.sh](../scripts/deploy.sh)** — the manual/fallback path, run directly on a host. For when Jenkins isn't the one triggering deployment: it's down, an application repo hasn't been onboarded to it yet, or someone needs to intervene by hand. Tags the currently-running images before pulling, waits for the new containers to report healthy, and automatically re-tags back and restarts if they don't.

## Roles and environments

`scripts/harden-host.sh`, `scripts/update.sh`, and `scripts/deploy.sh` all take the same role vocabulary, established in v0.5.0 (Production Hardening) and used consistently since:

| Role | Runs | Environment argument |
|---|---|---|
| `management` | Portainer, Jenkins, private Registry, the observability stack | none needed — always one environment |
| `app` | The `docker/app/` staging/production stack | `staging` or `production` (selects the matching compose override) |
| `agent` | Portainer Agent only | none needed |

## Getting a host ready in the first place

The steps above assume a reachable Ubuntu host with SSH access already exists. Getting there is the only part that's genuinely different per cloud provider — see:

- [platforms/aws.md](platforms/aws.md) — the `management` host
- [platforms/google-cloud.md](platforms/google-cloud.md) — the `app` host (staging today)
- [platforms/oracle-cloud.md](platforms/oracle-cloud.md) — the `app` host (production target)
- [platforms/homelab.md](platforms/homelab.md) — migrating Jenkins off AWS long-term

Once a host is reachable, every provider converges on the same next steps: `scripts/harden-host.sh <role>`, then each relevant stack's own README (`docker/portainer/`, `jenkins/`, `docker/registry/`, `docker/observability/`, `docker/management-proxy/` for `management`; `docker/app/` for `app`; `docker/portainer/agent-compose.yml` for `agent`) — the infrastructure itself never changes based on where it's running.

See [docs/roadmap.md](roadmap.md) for the current high-level roadmap.
