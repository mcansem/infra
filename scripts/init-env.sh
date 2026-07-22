#!/usr/bin/env bash
#
# Interactively creates real .env files for a role's stacks, from their
# .env.example templates. Run this ON the target host, after cloning the
# repo there - it only ever writes local files, never transmits or stores
# anything elsewhere, and real credentials still never touch git.
#
# What it does with each value, so nothing is left to guess or invent:
#   - Secrets (passwords)  -> generated automatically (openssl rand), never
#                             typed or guessed by the operator. Printed once
#                             at the end - save them immediately.
#   - Derivable values      -> auto-detected (e.g. DOCKER_GID from the
#                             host's own `docker` group).
#   - Everything else        -> prompted for, with the .env.example value
#                             shown as the default (press Enter to accept).
#
# `management` role additionally keeps GRAFANA_DOMAIN consistent between
# docker/observability/.env and docker/management-proxy/.env - both must
# match (see docker/observability/.env.example's own comment) and this
# only asks for it once.
#
# Usage:
#   scripts/init-env.sh <management|app|agent>
#
# Never overwrites an existing .env without an explicit confirmation.

set -euo pipefail

log_info()    { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $*"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $*"; }
log_error()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATED_SECRETS=()

usage() {
  echo "Usage: $0 <management|app|agent>"
}

generate_secret() {
  openssl rand -hex 24
}

prompt() {
  local var_name="$1" default_value="$2" prompt_text="$3"
  local input
  read -r -p "${prompt_text} (${var_name}) [${default_value}]: " input
  echo "${input:-$default_value}"
}

confirm_overwrite() {
  local env_file="$1"
  if [[ ! -f "$env_file" ]]; then
    return 0
  fi
  log_warning "${env_file} already exists."
  local confirm
  read -r -p "Overwrite it? [y/N]: " confirm
  [[ "$confirm" =~ ^[Yy]$ ]]
}

write_env() {
  local env_file="$1"
  shift
  : > "$env_file"
  for line in "$@"; do
    echo "$line" >> "$env_file"
  done
  chmod 600 "$env_file"
  log_success "Wrote ${env_file}"
}

init_jenkins_env() {
  local env_file="${REPO_ROOT}/jenkins/.env"
  if ! confirm_overwrite "$env_file"; then
    log_warning "Skipping jenkins/.env"
    return
  fi

  local admin_user admin_password docker_gid
  admin_user="$(prompt JENKINS_ADMIN_USER admin 'Jenkins admin username')"
  admin_password="$(generate_secret)"

  docker_gid="$(getent group docker | cut -d: -f3 || true)"
  if [[ -z "$docker_gid" ]]; then
    log_warning "Could not auto-detect the 'docker' group GID (is Docker installed yet?) - using 999 as a placeholder. Fix jenkins/.env manually if that's wrong on this host."
    docker_gid=999
  else
    log_info "Auto-detected DOCKER_GID=${docker_gid}"
  fi

  write_env "$env_file" \
    "JENKINS_ADMIN_USER=${admin_user}" \
    "JENKINS_ADMIN_PASSWORD=${admin_password}" \
    "DOCKER_GID=${docker_gid}"

  GENERATED_SECRETS+=("jenkins/.env  JENKINS_ADMIN_PASSWORD=${admin_password}")
}

init_app_env() {
  local env_file="${REPO_ROOT}/docker/app/.env"
  if ! confirm_overwrite "$env_file"; then
    log_warning "Skipping docker/app/.env"
    return
  fi

  local domain registry_url web_tag api_tag pg_db pg_user pg_password
  domain="$(prompt DOMAIN_NAME app.example.com 'App public domain')"
  registry_url="$(prompt REGISTRY_URL registry.example.com:5000 'Private registry URL (host:port)')"
  web_tag="$(prompt WEB_IMAGE_TAG latest 'Web image tag')"
  api_tag="$(prompt API_IMAGE_TAG latest 'API image tag')"
  pg_db="$(prompt POSTGRES_DB app 'Postgres database name')"
  pg_user="$(prompt POSTGRES_USER app 'Postgres user')"
  pg_password="$(generate_secret)"

  write_env "$env_file" \
    "DOMAIN_NAME=${domain}" \
    "REGISTRY_URL=${registry_url}" \
    "WEB_IMAGE_TAG=${web_tag}" \
    "API_IMAGE_TAG=${api_tag}" \
    "POSTGRES_DB=${pg_db}" \
    "POSTGRES_USER=${pg_user}" \
    "POSTGRES_PASSWORD=${pg_password}"

  GENERATED_SECRETS+=("docker/app/.env  POSTGRES_PASSWORD=${pg_password}")
}

init_observability_env() {
  local grafana_domain="$1"
  local env_file="${REPO_ROOT}/docker/observability/.env"
  if ! confirm_overwrite "$env_file"; then
    log_warning "Skipping docker/observability/.env"
    return
  fi

  local admin_password
  admin_password="$(generate_secret)"

  write_env "$env_file" \
    "GRAFANA_ADMIN_PASSWORD=${admin_password}" \
    "GRAFANA_DOMAIN=${grafana_domain}"

  GENERATED_SECRETS+=("docker/observability/.env  GRAFANA_ADMIN_PASSWORD=${admin_password}")
}

init_management_proxy_env() {
  local grafana_domain="$1"
  local env_file="${REPO_ROOT}/docker/management-proxy/.env"
  if ! confirm_overwrite "$env_file"; then
    log_warning "Skipping docker/management-proxy/.env"
    return
  fi

  local jenkins_domain uptime_domain
  jenkins_domain="$(prompt JENKINS_DOMAIN jenkins.example.com 'Jenkins public domain')"
  uptime_domain="$(prompt UPTIME_KUMA_DOMAIN uptime.example.com 'Uptime Kuma public domain')"

  write_env "$env_file" \
    "JENKINS_DOMAIN=${jenkins_domain}" \
    "GRAFANA_DOMAIN=${grafana_domain}" \
    "UPTIME_KUMA_DOMAIN=${uptime_domain}"
}

print_summary() {
  if [[ ${#GENERATED_SECRETS[@]} -eq 0 ]]; then
    return
  fi
  echo
  log_warning "Generated secrets - save these now, they will not be shown again:"
  local entry
  for entry in "${GENERATED_SECRETS[@]}"; do
    echo "  ${entry}"
  done
}

main() {
  local role="${1:-}"

  case "$role" in
    management)
      init_jenkins_env
      local grafana_domain
      grafana_domain="$(prompt GRAFANA_DOMAIN grafana.example.com 'Grafana public domain (shared by docker/observability/.env and docker/management-proxy/.env)')"
      init_observability_env "$grafana_domain"
      init_management_proxy_env "$grafana_domain"
      ;;
    app)
      init_app_env
      ;;
    agent)
      log_info "Role 'agent' has no .env files to create - the Portainer Agent needs no credentials."
      ;;
    *)
      log_error "Unknown or missing role: '${role}'"
      usage
      exit 1
      ;;
  esac

  print_summary
  log_success "Done for role '${role}'."
}

main "$@"
