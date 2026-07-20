#!/usr/bin/env bash
#
# Back up whatever a given host role is responsible for, verify each
# backup immediately, and rotate old ones. Local backups only - off-host
# replication (rsync/rclone/etc.) is documented in docs/backup.md, not
# scripted here, since the right destination varies per deployment.
#
# Usage:
#   scripts/backup.sh <management|app|agent>
#
# Env vars:
#   BACKUP_DIR       default: /var/backups/infra
#   RETENTION_DAYS   default: 7
#
# Idempotent/safe to re-run: each run just adds a new timestamped backup
# and re-applies rotation.

set -euo pipefail

log_info()    { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $*"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $*"; }
log_error()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

load_app_env() {
  local env_file="${REPO_ROOT}/docker/app/.env"
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
  else
    log_error "docker/app/.env not found - cannot determine POSTGRES_* credentials."
    exit 1
  fi
}

backup_postgres() {
  local backup_dir="$1"
  local compose_file="${REPO_ROOT}/docker/app/docker-compose.yml"
  local timestamp dump_file
  timestamp="$(date +%Y%m%d-%H%M%S)"
  dump_file="${backup_dir}/postgres-${timestamp}.dump"

  log_info "Backing up Postgres database '${POSTGRES_DB}'..."
  docker compose -f "$compose_file" exec -T postgres \
    pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -Fc > "$dump_file"

  log_info "Verifying dump integrity..."
  if docker run --rm -v "${dump_file}:/backup.dump:ro" postgres:16-alpine \
      pg_restore --list /backup.dump > /dev/null 2>&1; then
    log_success "Postgres backup verified: ${dump_file}"
  else
    log_error "Postgres backup verification FAILED: ${dump_file}"
    return 1
  fi
}

backup_volume() {
  local volume_name="$1"
  local backup_dir="$2"
  local timestamp archive_name archive_file
  timestamp="$(date +%Y%m%d-%H%M%S)"
  archive_name="${volume_name}-${timestamp}.tar.gz"
  archive_file="${backup_dir}/${archive_name}"

  log_info "Backing up volume '${volume_name}'..."
  docker run --rm \
    -v "${volume_name}:/data:ro" \
    -v "${backup_dir}:/backup" \
    alpine tar czf "/backup/${archive_name}" -C /data .

  log_info "Verifying archive integrity..."
  if tar tzf "$archive_file" > /dev/null 2>&1; then
    log_success "Volume backup verified: ${archive_file}"
  else
    log_error "Volume backup verification FAILED: ${archive_file}"
    return 1
  fi
}

rotate_backups() {
  local backup_dir="$1"
  local retention_days="$2"
  log_info "Rotating backups older than ${retention_days} days in ${backup_dir}..."
  find "$backup_dir" -maxdepth 1 -type f \( -name '*.dump' -o -name '*.tar.gz' \) -mtime "+${retention_days}" -print -delete
}

main() {
  local role="${1:-}"
  case "$role" in
    management|app|agent) ;;
    *)
      log_error "Usage: $0 <management|app|agent>"
      exit 1
      ;;
  esac

  local backup_dir="${BACKUP_DIR:-/var/backups/infra}"
  local retention_days="${RETENTION_DAYS:-7}"
  mkdir -p "$backup_dir"

  log_info "Starting backup for role '${role}' -> ${backup_dir}"

  case "$role" in
    app)
      load_app_env
      backup_postgres "$backup_dir"
      ;;
    management)
      backup_volume "jenkins_home" "$backup_dir"
      backup_volume "portainer_data" "$backup_dir"
      backup_volume "registry_data" "$backup_dir"
      ;;
    agent)
      log_warning "Role 'agent' has no persistent state to back up (Portainer Agent is stateless)."
      ;;
  esac

  rotate_backups "$backup_dir" "$retention_days"
  log_success "Backup complete for role '${role}'."
}

main "$@"
