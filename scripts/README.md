# scripts/

Parameter-driven Bash automation. `install.sh`/`deploy.sh`/`backup.sh`/`update.sh` land here in later phases (v0.6.0, Operations); `harden-host.sh` is the first script, part of v0.5.0 (Production Hardening).

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
