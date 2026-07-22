#!/usr/bin/env bash
#
# Host-level production hardening: UFW firewall, Fail2ban, unattended
# security upgrades, a swap file, and (opt-in only) SSH lockdown.
#
# Usage:
#   sudo scripts/harden-host.sh <management|app|agent> [--harden-ssh]
#
# Roles (see scripts/README.md for the full port table):
#   management  - Portainer + Jenkins (+ its nginx) + private Registry host
#   app         - the docker/app/ staging/production stack host
#   agent       - a host running only the Portainer Agent
#
# Swap: the management/app roles target small free-tier instances (see
# docs/roadmap.md) where container memory limits, summed, run close to or
# above physical RAM by design - a safety net against worst-case
# simultaneous peaks, not a substitute for right-sized limits. See
# scripts/README.md.
#
# Idempotent: safe to re-run. UFW rules and enable are no-ops if already
# applied; fail2ban config is simply overwritten with the same content;
# apt installs skip already-installed packages.
#
# SAFETY: this script always allows SSH before touching any default-deny
# firewall policy. --harden-ssh (disabling password auth / root login) is
# NEVER run automatically - see scripts/README.md before using it.

set -euo pipefail

log_info()    { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $*"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $*"; }
log_error()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "Usage: sudo $0 <management|app|agent> [--harden-ssh]"
}

detect_ssh_port() {
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    echo "${SSH_CONNECTION}" | awk '{print $4}'
  else
    echo "22"
  fi
}

role_ports() {
  # Node Exporter (9100) and cAdvisor (8080) from docker/monitoring-agent/
  # are deliberately NOT listed here - they bind to 127.0.0.1 only by
  # default (no auth on either), so there's nothing to open by default.
  # Enabling cross-host Prometheus scraping is a manual, source-IP-scoped
  # opt-in - see docker/monitoring-agent/README.md.
  case "$1" in
    management) echo "9443/tcp 80/tcp 443/tcp 5000/tcp" ;;
    app)        echo "80/tcp 443/tcp" ;;
    agent)      echo "9001/tcp" ;;
    *)          echo "" ;;
  esac
}

swap_size_mb() {
  case "$1" in
    management) echo 1024 ;;
    app)        echo 512 ;;
    agent)      echo 512 ;;
    *)          echo 512 ;;
  esac
}

nginx_log_dir() {
  case "$1" in
    management) echo "management-proxy" ;;
    app)        echo "app-nginx" ;;
    agent)      echo "" ;;
    *)          echo "" ;;
  esac
}

configure_ufw() {
  local role="$1"
  local ssh_port
  ssh_port="$(detect_ssh_port)"

  log_info "Allowing SSH before touching default policy (port 22, plus current session port ${ssh_port} if different)..."
  ufw allow 22/tcp comment 'SSH (baseline)'
  if [[ "$ssh_port" != "22" ]]; then
    ufw allow "${ssh_port}/tcp" comment 'SSH (current session)'
  fi

  log_info "Setting default policy: deny incoming, allow outgoing..."
  ufw default deny incoming
  ufw default allow outgoing

  local ports
  ports="$(role_ports "$role")"
  log_info "Allowing role '${role}' ports: ${ports}"
  for port in $ports; do
    ufw allow "$port"
  done

  log_info "Enabling UFW..."
  ufw --force enable

  log_success "UFW configured:"
  ufw status verbose
}

configure_swap() {
  local role="$1"
  local size_mb
  size_mb="$(swap_size_mb "$role")"

  if swapon --show=NAME --noheadings 2>/dev/null | grep -q '^/swapfile$'; then
    log_info "Swap already active at /swapfile, skipping."
    return
  fi

  if [[ -f /swapfile ]]; then
    log_warning "/swapfile exists but isn't active - enabling it."
    swapon /swapfile
    return
  fi

  log_info "Creating ${size_mb}M swap file at /swapfile..."
  fallocate -l "${size_mb}M" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count="$size_mb" status=none
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile

  if ! grep -q '^/swapfile' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi

  log_success "Swap enabled:"
  swapon --show
}

configure_nginx_log_dirs() {
  local role="$1"
  local dir
  dir="$(nginx_log_dir "$role")"

  if [[ -z "$dir" ]]; then
    log_info "Role '${role}' has no nginx of its own, skipping log directory setup."
    return
  fi

  local host_dir="/var/log/infra/${dir}"
  # fail2ban's jail.local logpath is a glob (/var/log/infra/*/{access,error}.log)
  # - if the files don't exist yet when fail2ban starts (nginx itself hasn't
  # run a single `docker compose up` yet at this point in the flow), the
  # jail silently fails to pick them up. Create them empty now so fail2ban
  # always has something to watch from the start; nginx's bind mount just
  # writes into the same files once it's up.
  log_info "Ensuring nginx log directory exists: ${host_dir}"
  mkdir -p "$host_dir"
  touch "${host_dir}/access.log" "${host_dir}/error.log"

  log_success "${host_dir} ready (access.log, error.log)."
}

configure_fail2ban() {
  log_info "Installing fail2ban jail configuration..."
  cp "${SCRIPT_DIR}/fail2ban/jail.local" /etc/fail2ban/jail.local

  log_info "Restarting fail2ban..."
  systemctl enable fail2ban
  systemctl restart fail2ban

  log_success "fail2ban active:"
  fail2ban-client status || log_warning "fail2ban-client status failed - check 'systemctl status fail2ban'"
}

configure_unattended_upgrades() {
  log_info "Enabling unattended-upgrades..."
  echo 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true' | debconf-set-selections
  dpkg-reconfigure -f noninteractive unattended-upgrades
  log_success "unattended-upgrades enabled."
}

set_sshd_option() {
  local key="$1" value="$2" config="$3"
  if grep -qE "^#?${key}\b" "$config"; then
    sed -i "s/^#\?${key}.*/${key} ${value}/" "$config"
  else
    echo "${key} ${value}" >> "$config"
  fi
}

harden_ssh() {
  local sshd_config="/etc/ssh/sshd_config"
  local backup
  backup="${sshd_config}.bak.$(date +%s)"

  log_warning "Hardening SSH: disabling password authentication and root login."
  cp "$sshd_config" "$backup"
  log_info "Backed up ${sshd_config} to ${backup}"

  set_sshd_option "PasswordAuthentication" "no" "$sshd_config"
  set_sshd_option "PermitRootLogin" "no" "$sshd_config"

  if grep -rEl "^\s*(PasswordAuthentication|PermitRootLogin)\s" /etc/ssh/sshd_config.d/ 2>/dev/null; then
    log_warning "PasswordAuthentication/PermitRootLogin is also set under /etc/ssh/sshd_config.d/ - many cloud images ship a drop-in there that loads after (and can override) sshd_config. Review the file(s) above manually."
  fi

  systemctl restart sshd

  log_success "SSH hardened. Verify you can still log in with a key from a NEW terminal before closing this session."
}

main() {
  if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (sudo)."
    exit 1
  fi

  local role="${1:-}"
  local harden_ssh_flag=false
  shift || true
  for arg in "$@"; do
    if [[ "$arg" == "--harden-ssh" ]]; then
      harden_ssh_flag=true
    fi
  done

  case "$role" in
    management|app|agent) ;;
    *)
      log_error "Unknown or missing role: '${role}'"
      usage
      exit 1
      ;;
  esac

  log_info "Hardening host as role '${role}'..."

  apt-get update -y
  apt-get install -y ufw fail2ban unattended-upgrades

  configure_swap "$role"
  configure_ufw "$role"
  configure_nginx_log_dirs "$role"
  configure_fail2ban
  configure_unattended_upgrades

  if [[ "$harden_ssh_flag" == true ]]; then
    harden_ssh
  else
    log_warning "Skipping SSH hardening (password auth / root login still permitted)."
    log_warning "Confirm key-based login works from a SEPARATE terminal, then re-run with --harden-ssh to lock it down. See scripts/README.md."
  fi

  log_success "Host hardening complete for role '${role}'."
}

main "$@"
