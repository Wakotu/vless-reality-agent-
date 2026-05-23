#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/ddns-update.env"

# =========================
# Load config
# =========================
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=ddns-update.env disable=SC1091
  . "$ENV_FILE"
  set +a
fi

: "${CF_API_TOKEN:?CF_API_TOKEN is required. Set it in ${ENV_FILE}}"
: "${CF_ZONE_ID:?CF_ZONE_ID is required. Set it in ${ENV_FILE}}"
: "${CF_RECORD_NAME:?CF_RECORD_NAME is required. Set it in ${ENV_FILE}}"

STATE_FILE="${STATE_FILE:-/var/lib/ddns-agent/last_ip}"
CF_API_BASE="https://api.cloudflare.com/client/v4"

# =========================
# Dependency checks
# =========================
command -v curl >/dev/null 2>&1 || {
  echo "Error: curl is required. Install it with: apt-get install curl" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "Error: jq is required. Install it with: apt-get install jq" >&2
  exit 1
}

# =========================
# Helpers
# =========================
ensure_state_dir() {
  if [[ ! -d "$(dirname "$STATE_FILE")" ]]; then
    mkdir -p "$(dirname "$STATE_FILE")" || {
      echo "Error: cannot create state directory $(dirname "$STATE_FILE")" >&2
      exit 1
    }
  fi
}

get_public_ip() {
  local ip
  for src in "https://api.ip.sb/ip" "https://ifconfig.me" "https://api.ipify.org"; do
    ip="$(curl -sf --max-time 5 "$src" 2>/dev/null)" || true
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "$ip"
      return 0
    fi
  done
  return 1
}

cf_api() {
  local method="$1" path="$2" data="${3:-}"
  local args=(-sf -H "Authorization: Bearer ${CF_API_TOKEN}" -H "Content-Type: application/json")
  if [[ -n "$data" ]]; then
    curl "${args[@]}" -X "$method" "${CF_API_BASE}${path}" -d "$data"
  else
    curl "${args[@]}" -X "$method" "${CF_API_BASE}${path}"
  fi
}

# =========================
# Main
# =========================
ensure_state_dir

CURRENT_IP="$(get_public_ip)" || {
  echo "Error: failed to obtain public IP from all sources" >&2
  exit 1
}

LAST_IP=""
if [[ -f "$STATE_FILE" ]]; then
  LAST_IP="$(<"$STATE_FILE")"
fi

if [[ "$CURRENT_IP" == "$LAST_IP" ]]; then
  echo "IP unchanged: ${CURRENT_IP}"
  exit 0
fi

echo "IP changed: ${LAST_IP:-none} -> ${CURRENT_IP}"

RESPONSE="$(cf_api GET "/zones/${CF_ZONE_ID}/dns_records?type=A&name=${CF_RECORD_NAME}")"
RECORD_ID="$(jq -r '.result[0].id // empty' <<<"$RESPONSE")"

if [[ -n "$RECORD_ID" ]]; then
  echo "Updating existing DNS record ${RECORD_ID}..."
  UPDATE_DATA="$(jq -n \
    --arg name "$CF_RECORD_NAME" \
    --arg ip "$CURRENT_IP" \
    '{type:"A", name:$name, content:$ip, ttl:1, proxied:false}')"
  RESPONSE="$(cf_api PATCH "/zones/${CF_ZONE_ID}/dns_records/${RECORD_ID}" "$UPDATE_DATA")"
else
  echo "Creating new A record for ${CF_RECORD_NAME}..."
  CREATE_DATA="$(jq -n \
    --arg name "$CF_RECORD_NAME" \
    --arg ip "$CURRENT_IP" \
    '{type:"A", name:$name, content:$ip, ttl:1, proxied:false}')"
  RESPONSE="$(cf_api POST "/zones/${CF_ZONE_ID}/dns_records" "$CREATE_DATA")"
fi

SUCCESS="$(jq -r '.success' <<<"$RESPONSE")"
if [[ "$SUCCESS" != "true" ]]; then
  echo "Error: Cloudflare API call failed:" >&2
  jq . <<<"$RESPONSE" >&2
  exit 1
fi

echo "$CURRENT_IP" > "$STATE_FILE"
echo "Result: ${CF_RECORD_NAME} -> ${CURRENT_IP}"
