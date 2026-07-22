#!/usr/bin/env bash
#
# One-shot bootstrap for a completely fresh Ubuntu host: installs git and
# Docker Engine (+ Compose plugin), then clones this repo. Nothing past
# that - scripts/harden-host.sh <role> is a separate, deliberate step, not
# chained automatically. Role selection stays a conscious human decision.
#
# Usage:
#   sudo scripts/bootstrap.sh
#   sudo REPO_URL=https://github.com/you/infra.git scripts/bootstrap.sh
#
# Idempotent: safe to re-run - skips Docker install if already present,
# refuses to clobber an existing clone directory.

set -euo pipefail

log_info()    { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $*"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $*"; }
log_error()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

REPO_URL="${REPO_URL:-https://github.com/mcansem/infra.git}"
CLONE_DIR="${CLONE_DIR:-infra}"

check_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (sudo)."
    exit 1
  fi
}

check_ubuntu() {
  if [[ ! -f /etc/os-release ]] || ! grep -q '^ID=ubuntu' /etc/os-release; then
    log_error "This script only supports Ubuntu. See scripts/README.md for manual install steps on other distros."
    exit 1
  fi
  log_info "Detected: $(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')"
}

check_internet() {
  if ! curl -fsS --connect-timeout 5 https://github.com >/dev/null 2>&1; then
    log_error "No internet access (couldn't reach https://github.com). Check networking before retrying."
    exit 1
  fi
}

install_base_packages() {
  log_info "Installing base packages (git, curl, ca-certificates)..."
  apt-get update -y
  apt-get install -y git curl ca-certificates
  log_success "Base packages installed."
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log_info "Docker already installed ($(docker --version)), skipping."
    return
  fi

  # Official apt repo, not get.docker.com's curl|sh - and deliberately NOT
  # pinned to a specific version. This repo pins container image tags for
  # stack reproducibility, but the host's Docker Engine itself is treated
  # like any other OS package (same reasoning as harden-host.sh leaving
  # unattended-upgrades unpinned) - matches the one existing precedent for
  # installing Docker packages in this repo, jenkins/Dockerfile.
  log_info "Installing Docker Engine from the official apt repository..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  systemctl enable --now docker

  # Logged explicitly (not pinned): if a version-specific bug ever gets
  # reported, this is the first thing anyone will need to know.
  log_success "Docker installed: $(docker --version)"
}

verify_compose_plugin() {
  if ! docker compose version >/dev/null 2>&1; then
    log_error "docker compose plugin not working - check that the docker-compose-plugin package installed correctly."
    exit 1
  fi
  log_success "Compose plugin OK: $(docker compose version)"
}

add_user_to_docker_group() {
  if [[ -z "${SUDO_USER:-}" ]]; then
    log_warning "No non-root invoking user detected (\$SUDO_USER unset) - skipping docker group setup. Add your user manually: usermod -aG docker <user>."
    return
  fi

  if id -nG "$SUDO_USER" | grep -qw docker; then
    log_info "$SUDO_USER is already in the docker group."
  else
    usermod -aG docker "$SUDO_USER"
    log_success "Added $SUDO_USER to the docker group."
    log_warning "This only takes effect in a NEW session - log out and back in, or run 'newgrp docker', before using docker without sudo."
  fi
}

clone_repo() {
  if [[ -d "$CLONE_DIR" ]]; then
    log_warning "'$CLONE_DIR' already exists - skipping clone. Remove it or set CLONE_DIR to clone somewhere else."
    return
  fi

  log_info "Cloning ${REPO_URL} into ${CLONE_DIR}..."
  git clone "$REPO_URL" "$CLONE_DIR"

  if [[ -n "${SUDO_USER:-}" ]]; then
    chown -R "${SUDO_USER}:${SUDO_USER}" "$CLONE_DIR"
  fi
  log_success "Cloned into ${CLONE_DIR}."
}

main() {
  check_root
  check_ubuntu
  check_internet
  install_base_packages
  install_docker
  verify_compose_plugin
  add_user_to_docker_group
  clone_repo

  log_success "Bootstrap complete."
  log_info "Next step - a conscious choice, not automated here:"
  log_info "  cd ${CLONE_DIR} && sudo scripts/harden-host.sh <management|app|agent>"
}

main "$@"
