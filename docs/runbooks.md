# Operational Runbooks

One playbook per alert defined in [docker/observability/prometheus/alert-rules.yml](../docker/observability/prometheus/alert-rules.yml). An alert with no runbook is just noise — this is the other half of v0.7.0's alerting work. For a full host loss rather than one of these narrower scenarios, see [recovery.md](recovery.md).

## HostDown

**Fires when:** `up{job=~"node-exporter.*"} == 0` for 5 minutes — Prometheus can no longer scrape a host's Node Exporter.

### Likely causes, roughly in order of likelihood

1. The `node-exporter` container stopped or is unhealthy on the target host.
2. The host itself is down, out of memory, or its Docker daemon crashed.
3. Network path between Prometheus and that host changed (firewall rule reverted, IP changed after a reprovision — see [docker/monitoring-agent/README.md](../docker/monitoring-agent/README.md)'s cross-host scraping opt-in).

### Investigate

```bash
# On the affected host:
docker compose -f docker/monitoring-agent/docker-compose.yml ps
docker compose -f docker/monitoring-agent/docker-compose.yml logs node-exporter

# From the management host, confirm reachability (only meaningful if
# cross-host scraping was opted into for this host):
curl -sf http://<host-ip>:9100/metrics > /dev/null && echo reachable || echo unreachable
```

**Fix:** `docker compose -f docker/monitoring-agent/docker-compose.yml up -d` if the container simply stopped. If the host itself is unreachable over SSH too, treat this as a potential full host loss — see [recovery.md](recovery.md).

## DiskSpaceLow

**Fires when:** a filesystem is over 85% full for 10 minutes.

### Likely causes

1. Accumulated Docker images/build cache — `scripts/cleanup.sh` hasn't run recently (see [scripts/README.md](../scripts/README.md#recommended-cron-schedule) for the recommended weekly cadence).
2. Backups piling up faster than `scripts/backup.sh`'s rotation removes them (check `RETENTION_DAYS`).
3. Runaway application logs — check `/var/log/infra/*/` (rotated by `scripts/logrotate/infra-nginx.conf`, but only if that config was actually installed — `scripts/update.sh` does this idempotently on every run).

### Investigate

```bash
df -h
docker system df
du -sh /var/backups/infra/* 2>/dev/null | sort -rh | head
du -sh /var/log/infra/*/* 2>/dev/null | sort -rh | head
```

**Fix:** `scripts/cleanup.sh` for Docker's own disk usage (never touches volumes — see its own doc comment). For backups, confirm `RETENTION_DAYS` is set sensibly and rotation is actually running. For logs, confirm the logrotate config landed in `/etc/logrotate.d/infra-nginx` and re-run `scripts/update.sh` if not.

## ContainerMissing

**Fires when:** cAdvisor hasn't reported metrics for a named container in over 60 seconds, for 5 minutes straight — it stopped or was removed.

### Likely causes

1. The container crashed and its restart policy gave up — check `restart:` in the relevant `docker-compose.yml`. Services with `on-failure:5` (`postgres`, `jenkins` — see [docker/app/README.md](../docker/app/README.md#environments)) intentionally stop retrying after 5 attempts rather than crash-looping forever.
2. Someone ran `docker stop`/`docker rm` manually and didn't restart it.
3. A `docker compose up -d` elsewhere recreated the container under a different name (rare, but changes cAdvisor's view of it).

### Investigate

```bash
docker ps -a --filter "name=<container-name>"
docker logs <container-name> --tail 100
```

**Fix:** If it stopped due to exhausting `on-failure:N` retries, the underlying problem needs fixing first (bad config, corrupt data) — restarting blindly just repeats the failure. Once the root cause is addressed: `docker compose -f <the relevant compose file> up -d <service>`.
