#!/usr/bin/env bash
#
# On-demand host + Docker stack updates for a given role: full apt
# upgrade (distinct from harden-host.sh's unattended-upgrades, which only
# auto-applies the security track in the background), docker compose
# pull+up for every stack the role runs, and a light image prune.
# Also ensures the logrotate config is installed (cheap to re-copy every
# run).
#
# Usage:
#   sudo scripts/update.sh <management|app|agent>
#   sudo scripts/update.sh app <staging|production>   # app role needs to know which override is live

set -euo pipefail

log_info()    { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $*"; }
log_error()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

usage() {
  echo "Usage: sudo $0 <management|app|agent>"
  echo "       sudo $0 app <staging|production>"
}

pull_and_up() {
  local compose_file="$1"
  shift
  local extra_args=("$@")

  log_info "Updating stack: ${compose_file}"
  docker compose -f "$compose_file" "${extra_args[@]}" pull
  docker compose -f "$compose_file" "${extra_args[@]}" up -d
}

install_logrotate_config() {
  log_info "Installing logrotate config..."
  cp "${SCRIPT_DIR}/logrotate/infra-nginx.conf" /etc/logrotate.d/infra-nginx
}

main() {
  if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (sudo)."
    exit 1
  fi

  local role="${1:-}"

  case "$role" in
    management|agent) ;;
    app)
      local env_name="${2:-}"
      case "$env_name" in
        staging|production) ;;
        *)
          log_error "Role 'app' requires an environment: staging or production."
          usage
          exit 1
          ;;
      esac
      ;;
    *)
      log_error "Unknown or missing role: '${role}'"
      usage
      exit 1
      ;;
  esac

  log_info "Running apt update/upgrade..."
  apt-get update -y
  apt-get upgrade -y

  case "$role" in
    management)
      pull_and_up "${REPO_ROOT}/jenkins/docker-compose.yml"
      pull_and_up "${REPO_ROOT}/docker/portainer/docker-compose.yml"
      pull_and_up "${REPO_ROOT}/docker/registry/docker-compose.yml"
      ;;
    app)
      pull_and_up "${REPO_ROOT}/docker/app/docker-compose.yml" \
        -f "${REPO_ROOT}/docker/app/docker-compose.${env_name}.yml"
      ;;
    agent)
      pull_and_up "${REPO_ROOT}/docker/portainer/agent-compose.yml"
      ;;
  esac

  log_info "Pruning dangling images from this update..."
  docker image prune -f

  install_logrotate_config

  log_success "Update complete for role '${role}'."
}

main "$@"
