#!/usr/bin/env bash
#
# Host-level production hardening: UFW firewall, Fail2ban, unattended
# security upgrades, and (opt-in only) SSH lockdown.
#
# Usage:
#   sudo scripts/harden-host.sh <management|app|agent> [--harden-ssh]
#
# Roles (see scripts/README.md for the full port table):
#   management  - Portainer + Jenkins (+ its nginx) + private Registry host
#   app         - the docker/app/ staging/production stack host
#   agent       - a host running only the Portainer Agent
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
  case "$1" in
    management) echo "9443/tcp 80/tcp 443/tcp 5000/tcp" ;;
    app)        echo "80/tcp 443/tcp" ;;
    agent)      echo "9001/tcp" ;;
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

  configure_ufw "$role"
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
