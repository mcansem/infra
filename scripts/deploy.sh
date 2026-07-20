#!/usr/bin/env bash
#
# Manual/fallback deploy - the host-side counterpart to
# vars/standardDeployPipeline.groovy's "Deploy via SSH" stage, for when
# Jenkins isn't the one triggering deployment (down, app repo not yet
# onboarded, emergency manual intervention). Deliberately mirrors the
# pipeline's stage order so behavior doesn't diverge between the two paths:
# pull infra config -> pull images -> up -d -> wait for healthy -> roll
# back on failure.
#
# Usage:
#   scripts/deploy.sh <management|app|agent>
#   scripts/deploy.sh app <staging|production>

set -euo pipefail

log_info()    { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $*"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $*"; }
log_error()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

usage() {
  echo "Usage: $0 <management|app|agent>"
  echo "       $0 app <staging|production>"
}

pull_infra_repo() {
  log_info "Pulling latest infra repo changes..."
  git -C "$REPO_ROOT" pull --ff-only
}

wait_for_healthy() {
  local compose_file="$1"
  shift
  local extra_args=("$@")
  local max_wait=120
  local elapsed=0
  local container_id health all_healthy

  log_info "Waiting for services to report healthy (up to ${max_wait}s)..."
  while (( elapsed < max_wait )); do
    all_healthy=true
    while IFS= read -r container_id; do
      [[ -z "$container_id" ]] && continue
      health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container_id")"
      if [[ "$health" != "healthy" && "$health" != "none" ]]; then
        all_healthy=false
      fi
    done < <(docker compose -f "$compose_file" "${extra_args[@]}" ps -q)

    if [[ "$all_healthy" == true ]]; then
      log_success "All services healthy (or have no healthcheck)."
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  log_error "Services did not become healthy within ${max_wait}s."
  return 1
}

deploy_stack() {
  local compose_file="$1"
  shift
  local extra_args=("$@")
  local images image

  log_info "Tagging currently-running images as rollback targets..."
  images="$(docker compose -f "$compose_file" "${extra_args[@]}" config --images)"
  while IFS= read -r image; do
    [[ -z "$image" ]] && continue
    docker tag "$image" "${image}-rollback" 2>/dev/null || log_warning "Could not tag ${image} for rollback (not running yet?)"
  done <<< "$images"

  log_info "Pulling new images..."
  docker compose -f "$compose_file" "${extra_args[@]}" pull

  log_info "Starting updated stack..."
  docker compose -f "$compose_file" "${extra_args[@]}" up -d

  if wait_for_healthy "$compose_file" "${extra_args[@]}"; then
    log_success "Deployment successful."
    return 0
  fi

  log_error "Deployment failed health check - rolling back to previous images..."
  while IFS= read -r image; do
    [[ -z "$image" ]] && continue
    if docker image inspect "${image}-rollback" > /dev/null 2>&1; then
      docker tag "${image}-rollback" "$image"
    fi
  done <<< "$images"
  docker compose -f "$compose_file" "${extra_args[@]}" up -d
  log_warning "Rolled back to the previous images. Investigate the failed deployment before retrying."
  return 1
}

main() {
  local role="${1:-}"
  local compose_file=""
  local extra_args=()

  case "$role" in
    management)
      compose_file="${REPO_ROOT}/jenkins/docker-compose.yml"
      ;;
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
      compose_file="${REPO_ROOT}/docker/app/docker-compose.yml"
      extra_args=(-f "${REPO_ROOT}/docker/app/docker-compose.${env_name}.yml")
      ;;
    agent)
      compose_file="${REPO_ROOT}/docker/portainer/agent-compose.yml"
      ;;
    *)
      log_error "Unknown or missing role: '${role}'"
      usage
      exit 1
      ;;
  esac

  pull_infra_repo
  deploy_stack "$compose_file" "${extra_args[@]}"
}

main "$@"
