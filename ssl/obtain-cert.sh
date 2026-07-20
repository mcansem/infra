#!/usr/bin/env bash
#
# Obtain (or renew) a TLS certificate for a service, either via Let's Encrypt
# (default) or as a self-signed fallback. Output is always written to the
# same paths regardless of mode, so consumers (nginx.conf, registry config)
# never need to know which mode produced the certificate:
#
#   ssl/<service-name>/fullchain.pem
#   ssl/<service-name>/privkey.pem
#
# Usage:
#   ssl/obtain-cert.sh <service-name> <domain> [--self-signed]
#
# Env vars (Let's Encrypt mode only):
#   LETSENCRYPT_EMAIL   contact email for expiry notices (optional but recommended)
#
# Examples:
#   ssl/obtain-cert.sh registry registry.example.com
#   ssl/obtain-cert.sh jenkins jenkins.example.com --self-signed
#
# Assumes an Nginx server block for <domain> is already serving
# ssl/.webroot at /.well-known/acme-challenge/ (see the relevant
# service's nginx.conf / README for the bootstrap sequence).

set -euo pipefail

log_info()    { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $*"; }
log_error()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

SERVICE_NAME="${1:-}"
DOMAIN="${2:-}"
MODE="letsencrypt"

if [[ "${3:-}" == "--self-signed" ]]; then
  MODE="self-signed"
fi

if [[ -z "${SERVICE_NAME}" || -z "${DOMAIN}" ]]; then
  log_error "Usage: $0 <service-name> <domain> [--self-signed]"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/${SERVICE_NAME}"
WEBROOT_DIR="${SCRIPT_DIR}/.webroot"
CERTBOT_CONF_DIR="${SCRIPT_DIR}/.certbot-conf/${SERVICE_NAME}"

mkdir -p "${OUT_DIR}"

if [[ "${MODE}" == "self-signed" ]]; then
  log_info "Generating self-signed certificate for ${DOMAIN} (${SERVICE_NAME})"
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout "${OUT_DIR}/privkey.pem" \
    -out "${OUT_DIR}/fullchain.pem" \
    -subj "/CN=${DOMAIN}"
  log_success "Self-signed certificate written to ${OUT_DIR}/"
  exit 0
fi

log_info "Requesting Let's Encrypt certificate for ${DOMAIN} (${SERVICE_NAME}) via webroot"

mkdir -p "${WEBROOT_DIR}" "${CERTBOT_CONF_DIR}"

EMAIL_ARGS=(--register-unsafely-without-email)
if [[ -n "${LETSENCRYPT_EMAIL:-}" ]]; then
  EMAIL_ARGS=(--email "${LETSENCRYPT_EMAIL}")
  log_info "Using contact email ${LETSENCRYPT_EMAIL}"
else
  log_info "LETSENCRYPT_EMAIL not set, registering without a contact email"
fi

docker run --rm \
  -v "${WEBROOT_DIR}:/var/www/certbot" \
  -v "${CERTBOT_CONF_DIR}:/etc/letsencrypt" \
  certbot/certbot certonly \
  --webroot --webroot-path=/var/www/certbot \
  --non-interactive --agree-tos "${EMAIL_ARGS[@]}" \
  --cert-name "${SERVICE_NAME}" \
  -d "${DOMAIN}"

cp "${CERTBOT_CONF_DIR}/live/${SERVICE_NAME}/fullchain.pem" "${OUT_DIR}/fullchain.pem"
cp "${CERTBOT_CONF_DIR}/live/${SERVICE_NAME}/privkey.pem" "${OUT_DIR}/privkey.pem"

log_success "Let's Encrypt certificate written to ${OUT_DIR}/"
log_info "Renew later with: $0 ${SERVICE_NAME} ${DOMAIN}  (certbot re-uses ${CERTBOT_CONF_DIR} and only renews if due)"
