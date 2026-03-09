#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
DOMAIN="${1:?Usage: $0 <domain> [threshold_days] [email]}"
THRESHOLD_DAYS="${2:-30}"
EMAIL="${3:-}"
LOG_FILE="/var/log/ssl-check-renew.log"
CERTBOT_BIN="$(command -v certbot 2>/dev/null || true)"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

# --- Get cert expiry date via openssl ---
get_cert_expiry() {
  local expiry
  expiry=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null \
    | sed 's/notAfter=//')

  if [[ -z "$expiry" ]]; then
    log "ERROR: Could not retrieve certificate for $DOMAIN"
    return 1
  fi
  echo "$expiry"
}

# --- Convert date string to epoch (cross-platform) ---
to_epoch() {
  local datestr="$1"
  if date --version &>/dev/null; then
    # GNU/Linux
    date -d "$datestr" +%s
  else
    # macOS/BSD
    date -j -f "%b %d %H:%M:%S %Y %Z" "$datestr" +%s
  fi
}

# --- Renew certificate ---
renew_cert() {
  if [[ -z "$CERTBOT_BIN" ]]; then
    log "ERROR: certbot not found. Install it or renew manually."
    log "  apt install certbot  OR  brew install certbot"
    return 1
  fi

  log "Attempting certificate renewal for $DOMAIN..."

  local email_flag=""
  [[ -n "$EMAIL" ]] && email_flag="--email $EMAIL" || email_flag="--register-unsafely-without-email"

  if $CERTBOT_BIN certonly \
    --non-interactive \
    --agree-tos \
    $email_flag \
    --preferred-challenges http \
    -d "$DOMAIN" \
    --keep-until-expiring \
    --renew-with-new-domains; then
    log "SUCCESS: Certificate renewed for $DOMAIN"
  else
    log "ERROR: Certificate renewal failed for $DOMAIN"
    return 1
  fi
}

# --- Main ---
main() {
  log "Checking SSL certificate for $DOMAIN (threshold: ${THRESHOLD_DAYS} days)..."

  local expiry_str
  if ! expiry_str=$(get_cert_expiry); then
    log "No valid cert found — attempting to obtain a new one."
    renew_cert
    return $?
  fi

  local expiry_epoch now_epoch days_left
  expiry_epoch=$(to_epoch "$expiry_str")
  now_epoch=$(date +%s)
  days_left=$(( (expiry_epoch - now_epoch) / 86400 ))

  log "Certificate expires: $expiry_str ($days_left days remaining)"

  if (( days_left <= 0 )); then
    log "EXPIRED — renewing now."
    renew_cert
  elif (( days_left <= THRESHOLD_DAYS )); then
    log "EXPIRING SOON — renewing now."
    renew_cert
  else
    log "OK — no action needed."
  fi
}

main
