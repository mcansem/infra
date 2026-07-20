#!/usr/bin/env bash
#
# Restore a backup produced by scripts/backup.sh. Destructive - overwrites
# live data - so it requires an explicit --yes-i-am-sure flag. Without it,
# the script only prints what it would do and exits.
#
# Usage:
#   scripts/restore.sh <management|app|agent> <timestamp> [--yes-i-am-sure]
#
# <timestamp> matches a backup.sh filename, e.g. 20260719-143000 from
# postgres-20260719-143000.dump.
#
# Env vars:
#   BACKUP_DIR   default: /var/backups/infra

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

restore_postgres() {
  local backup_dir="$1"
  local timestamp="$2"
  local compose_file="${REPO_ROOT}/docker/app/docker-compose.yml"
  local dump_file="${backup_dir}/postgres-${timestamp}.dump"

  if [[ ! -f "$dump_file" ]]; then
    log_error "Backup dump not found: ${dump_file}"
    return 1
  fi

  log_info "Restoring Postgres database '${POSTGRES_DB}' from ${dump_file}..."
  docker compose -f "$compose_file" exec -T postgres \
    pg_restore --clean --if-exists -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" < "$dump_file"

  log_success "Postgres restore complete."
}

validate_postgres_restore() {
  local compose_file="${REPO_ROOT}/docker/app/docker-compose.yml"

  log_info "Validating restore: checking Postgres accepts connections..."
  if ! docker compose -f "$compose_file" exec -T postgres \
      pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" > /dev/null 2>&1; then
    log_error "Postgres is not accepting connections after restore."
    return 1
  fi

  local table_count
  table_count="$(docker compose -f "$compose_file" exec -T postgres \
    psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -tAc \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema');" \
    | tr -d '[:space:]')"

  if [[ "${table_count:-0}" -gt 0 ]]; then
    log_success "Restore validated: ${table_count} table(s) present."
  else
    log_warning "Postgres is reachable but no user tables were found - confirm this is expected."
  fi
}

restore_volume_service() {
  local volume_name="$1"
  local backup_dir="$2"
  local timestamp="$3"
  local compose_file="$4"
  local service_name="$5"
  local archive_name="${volume_name}-${timestamp}.tar.gz"
  local archive_file="${backup_dir}/${archive_name}"

  if [[ ! -f "$archive_file" ]]; then
    log_error "Backup archive not found: ${archive_file}"
    return 1
  fi

  log_info "Stopping '${service_name}' before restoring its volume..."
  docker compose -f "$compose_file" stop "$service_name"

  log_info "Restoring volume '${volume_name}' from ${archive_file}..."
  docker run --rm \
    -v "${volume_name}:/data" \
    -v "${backup_dir}:/backup:ro" \
    alpine sh -c "rm -rf /data/* /data/..?* /data/.[!.]* 2>/dev/null; tar xzf /backup/${archive_name} -C /data"

  log_info "Restarting '${service_name}'..."
  docker compose -f "$compose_file" up -d "$service_name"

  log_success "Volume '${volume_name}' restored and '${service_name}' restarted."
}

print_dry_run() {
  local role="$1" timestamp="$2" backup_dir="$3"
  log_warning "DRY RUN (pass --yes-i-am-sure to actually restore). Role '${role}', timestamp '${timestamp}':"
  case "$role" in
    app)
      echo "  - Restore Postgres from ${backup_dir}/postgres-${timestamp}.dump (overwrites the live database)"
      ;;
    management)
      echo "  - Restore jenkins_home from ${backup_dir}/jenkins_home-${timestamp}.tar.gz (stops/restarts jenkins)"
      echo "  - Restore portainer_data from ${backup_dir}/portainer_data-${timestamp}.tar.gz (stops/restarts portainer)"
      echo "  - Restore registry_data from ${backup_dir}/registry_data-${timestamp}.tar.gz (stops/restarts registry)"
      ;;
    agent)
      echo "  - Nothing to restore (Portainer Agent is stateless)."
      ;;
  esac
}

main() {
  local role="${1:-}"
  local timestamp="${2:-}"
  local confirmed=false

  for arg in "$@"; do
    if [[ "$arg" == "--yes-i-am-sure" ]]; then
      confirmed=true
    fi
  done

  case "$role" in
    management|app|agent) ;;
    *)
      log_error "Usage: $0 <management|app|agent> <timestamp> [--yes-i-am-sure]"
      exit 1
      ;;
  esac

  if [[ -z "$timestamp" ]]; then
    log_error "Usage: $0 <management|app|agent> <timestamp> [--yes-i-am-sure]"
    exit 1
  fi

  local backup_dir="${BACKUP_DIR:-/var/backups/infra}"

  if [[ "$confirmed" != true ]]; then
    print_dry_run "$role" "$timestamp" "$backup_dir"
    exit 0
  fi

  log_warning "Proceeding with DESTRUCTIVE restore for role '${role}'..."

  case "$role" in
    app)
      load_app_env
      restore_postgres "$backup_dir" "$timestamp"
      validate_postgres_restore
      ;;
    management)
      restore_volume_service "jenkins_home" "$backup_dir" "$timestamp" "${REPO_ROOT}/jenkins/docker-compose.yml" "jenkins"
      restore_volume_service "portainer_data" "$backup_dir" "$timestamp" "${REPO_ROOT}/docker/portainer/docker-compose.yml" "portainer"
      restore_volume_service "registry_data" "$backup_dir" "$timestamp" "${REPO_ROOT}/docker/registry/docker-compose.yml" "registry"
      ;;
    agent)
      log_warning "Nothing to restore for role 'agent'."
      ;;
  esac

  log_success "Restore complete for role '${role}'."
}

main "$@"
