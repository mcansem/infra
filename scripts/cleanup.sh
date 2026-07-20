#!/usr/bin/env bash
#
# Periodic Docker disk-hygiene maintenance, independent of host role.
# Deliberately never touches volumes - that's what restore.sh's explicit
# confirmation gate is for, not an implicit prune here.
#
# Usage:
#   scripts/cleanup.sh
#
# Env vars:
#   BUILD_CACHE_DAYS   prune build cache older than this many days (default: 7)

set -euo pipefail

log_info()    { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $*"; }

report_disk_usage() {
  local label="$1"
  log_info "Docker disk usage (${label}):"
  docker system df
}

main() {
  local build_cache_days="${BUILD_CACHE_DAYS:-7}"
  local build_cache_hours=$((build_cache_days * 24))

  report_disk_usage "before"

  # `docker system prune` only ever removes volumes if --volumes is passed
  # explicitly - it is deliberately never passed here.
  log_info "Pruning stopped containers, unused networks, and dangling images..."
  docker system prune -af

  log_info "Pruning build cache older than ${build_cache_days} days..."
  docker builder prune -af --filter "until=${build_cache_hours}h"

  report_disk_usage "after"

  log_success "Cleanup complete."
}

main "$@"
