#!/usr/bin/env bash
#
# Validates that every docker-compose.yml (and override combination) in
# this repo can actually be parsed and resolved by `docker compose
# config`, using each stack's .env.example for required-variable
# substitution (dummy values - never real ones, and never overwrites a
# real .env if one already exists locally).
#
# This is the one thing that can be verified without a real host: it
# catches YAML/syntax errors and missing required `${VAR:?}` variables
# automatically, closing the "reviewed by eye only" gap every phase up to
# this one has had to accept.
#
# Usage:
#   scripts/validate-compose.sh
#
# Run locally (needs Docker) or in CI (see .github/workflows/lint.yml).

set -euo pipefail

log_info()    { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $*"; }
log_error()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

validate() {
  local label="$1"
  shift
  local compose_args=()
  local env_dir=""

  for arg in "$@"; do
    compose_args+=(-f "${REPO_ROOT}/${arg}")
    if [[ -z "$env_dir" ]]; then
      env_dir="${REPO_ROOT}/$(dirname "$arg")"
    fi
  done

  local created_env=false
  if [[ -f "${env_dir}/.env.example" && ! -f "${env_dir}/.env" ]]; then
    cp "${env_dir}/.env.example" "${env_dir}/.env"
    created_env=true
  fi

  log_info "Validating ${label}..."
  if docker compose "${compose_args[@]}" config --quiet; then
    log_success "${label} OK"
  else
    log_error "${label} FAILED"
    FAILED=1
  fi

  if [[ "$created_env" == true ]]; then
    rm -f "${env_dir}/.env"
  fi
}

validate "portainer"        docker/portainer/docker-compose.yml
validate "portainer agent"  docker/portainer/agent-compose.yml
validate "registry"         docker/registry/docker-compose.yml
validate "monitoring-agent" docker/monitoring-agent/docker-compose.yml
validate "jenkins"          jenkins/docker-compose.yml
validate "app (staging)"    docker/app/docker-compose.yml docker/app/docker-compose.staging.yml
validate "app (production)" docker/app/docker-compose.yml docker/app/docker-compose.production.yml
validate "observability"    docker/observability/docker-compose.yml
validate "management-proxy" docker/management-proxy/docker-compose.yml

if [[ "$FAILED" -eq 1 ]]; then
  log_error "One or more compose stacks failed validation."
  exit 1
fi

log_success "All compose stacks validated."
