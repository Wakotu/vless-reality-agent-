#!/usr/bin/env bash
set -euo pipefail

# =========================
# Defaults
# =========================
SERVER_ADDRESS="${SERVER_ADDRESS:-}"
LOCAL_PORT="${LOCAL_PORT:-}"
PUBLIC_PORT="${PUBLIC_PORT:-}"
SERVER_NAME="${SERVER_NAME:-tesla.com}"
HANDSHAKE_SERVER="${HANDSHAKE_SERVER:-$SERVER_NAME}"
HANDSHAKE_PORT="${HANDSHAKE_PORT:-443}"
TAG="${TAG:-VLESSReality}"
USER_NAME="${USER_NAME:-VLESSRealityUser}"
FLOW="${FLOW:-xtls-rprx-vision}"
LISTEN_ADDR="${LISTEN_ADDR:-::}"
OUT_FILE="${OUT_FILE:-config.json}"
REMARK="${REMARK:-${USER_NAME}-${SERVER_NAME}}"
SHORT_ID_COUNT="${SHORT_ID_COUNT:-1}"

usage() {
  cat <<EOF
Usage:
  $0 --server-address <ip-or-domain> --local-port <port> --public-port <port> [options]

Required:
  --server-address ADDR      Public address that can access your VPS
  --local-port PORT          Local port on which sing-box listens
  --public-port PORT         NAT public port forwarded to local-port

Optional:
  --server-name NAME         TLS server_name / SNI (default: ${SERVER_NAME})
  --handshake-server NAME    Reality handshake server (default: server-name)
  --handshake-port PORT      Reality handshake port (default: ${HANDSHAKE_PORT})
  --tag TAG                  Inbound tag (default: ${TAG})
  --user-name NAME           User display name (default: ${USER_NAME})
  --flow FLOW                Default: ${FLOW}
  --listen-addr ADDR         Default: ${LISTEN_ADDR}
  --out-file FILE            Output JSON file (default: ${OUT_FILE})
  --remark TEXT              Client URI remark (default: ${REMARK})
  --short-id-count N         Number of extra short_ids to generate (default: ${SHORT_ID_COUNT})

Examples:
  $0 --server-address 1.2.3.4 --local-port 21807 --public-port 443
  $0 --server-address vpn.example.com --local-port 30000 --public-port 443 --server-name tesla.com
EOF
}

# =========================
# Parse args
# =========================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-address|--server-addr)
      SERVER_ADDRESS="$2"
      shift 2
      ;;
    --local-port)
      LOCAL_PORT="$2"
      shift 2
      ;;
    --public-port)
      PUBLIC_PORT="$2"
      shift 2
      ;;
    --server-name)
      SERVER_NAME="$2"
      HANDSHAKE_SERVER="${HANDSHAKE_SERVER:-$SERVER_NAME}"
      shift 2
      ;;
    --handshake-server)
      HANDSHAKE_SERVER="$2"
      shift 2
      ;;
    --handshake-port)
      HANDSHAKE_PORT="$2"
      shift 2
      ;;
    --tag)
      TAG="$2"
      shift 2
      ;;
    --user-name)
      USER_NAME="$2"
      shift 2
      ;;
    --flow)
      FLOW="$2"
      shift 2
      ;;
    --listen-addr)
      LISTEN_ADDR="$2"
      shift 2
      ;;
    --out-file)
      OUT_FILE="$2"
      shift 2
      ;;
    --remark)
      REMARK="$2"
      shift 2
      ;;
    --short-id-count)
      SHORT_ID_COUNT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# If handshake-server was not explicitly set, sync it with final server-name
if [[ -z "${HANDSHAKE_SERVER:-}" ]]; then
  HANDSHAKE_SERVER="$SERVER_NAME"
fi

# =========================
# Required args
# =========================
if [[ -z "$SERVER_ADDRESS" ]]; then
  echo "Error: --server-address is required" >&2
  usage
  exit 1
fi

if [[ -z "$LOCAL_PORT" ]]; then
  echo "Error: --local-port is required" >&2
  usage
  exit 1
fi

if [[ -z "$PUBLIC_PORT" ]]; then
  echo "Error: --public-port is required" >&2
  usage
  exit 1
fi

# =========================
# Checks
# =========================
command -v sing-box >/dev/null 2>&1 || {
  echo "Error: sing-box not found in PATH" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || {
  echo "Error: jq not found in PATH" >&2
  exit 1
}

is_valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 ))
}

if ! is_valid_port "$LOCAL_PORT"; then
  echo "Error: invalid --local-port: $LOCAL_PORT" >&2
  exit 1
fi

if ! is_valid_port "$PUBLIC_PORT"; then
  echo "Error: invalid --public-port: $PUBLIC_PORT" >&2
  exit 1
fi

if ! is_valid_port "$HANDSHAKE_PORT"; then
  echo "Error: invalid --handshake-port: $HANDSHAKE_PORT" >&2
  exit 1
fi

if ! [[ "$SHORT_ID_COUNT" =~ ^[0-9]+$ ]]; then
  echo "Error: invalid --short-id-count" >&2
  exit 1
fi

# =========================
# Helpers
# =========================
extract_reality_keys() {
  local output="$1"
  local private_key public_key

  private_key="$(printf '%s\n' "$output" | sed -nE 's/^[Pp]rivate[Kk]ey:[[:space:]]*//p; s/^[Pp]rivate key:[[:space:]]*//p' | head -n1)"
  public_key="$(printf '%s\n' "$output" | sed -nE 's/^[Pp]ublic[Kk]ey:[[:space:]]*//p; s/^[Pp]ublic key:[[:space:]]*//p' | head -n1)"

  if [[ -z "$private_key" || -z "$public_key" ]]; then
    echo "Error: failed to parse reality keypair from sing-box output:" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi

  printf '%s\n%s\n' "$private_key" "$public_key"
}

rawurlencode() {
  local string="${1}"
  local strlen=${#string}
  local encoded=""
  local pos c o

  for (( pos=0; pos<strlen; pos++ )); do
    c=${string:$pos:1}
    case "$c" in
      [a-zA-Z0-9.~_-]) o="$c" ;;
      *) printf -v o '%%%02X' "'$c" ;;
    esac
    encoded+="$o"
  done
  echo "$encoded"
}

# =========================
# Generate values
# =========================
UUID="$(sing-box generate uuid)"

KEYPAIR_OUTPUT="$(sing-box generate reality-keypair)"
mapfile -t REALITY_KEYS < <(extract_reality_keys "$KEYPAIR_OUTPUT")
PRIVATE_KEY="${REALITY_KEYS[0]}"
PUBLIC_KEY="${REALITY_KEYS[1]}"

SHORT_IDS_JSON='[""]'
SELECTED_SHORT_ID=""

for ((i=0; i<SHORT_ID_COUNT; i++)); do
  SID="$(sing-box generate rand --hex 8)"
  SHORT_IDS_JSON="$(jq -c --arg sid "$SID" '. + [$sid]' <<<"$SHORT_IDS_JSON")"
  if [[ -z "$SELECTED_SHORT_ID" ]]; then
    SELECTED_SHORT_ID="$SID"
  fi
done

if [[ "$SHORT_ID_COUNT" -eq 0 ]]; then
  SELECTED_SHORT_ID=""
fi

# =========================
# Generate server config
# local-port is used here
# =========================
jq -n \
  --arg tag "$TAG" \
  --arg listen_addr "$LISTEN_ADDR" \
  --argjson local_port "$LOCAL_PORT" \
  --arg user_name "$USER_NAME" \
  --arg uuid "$UUID" \
  --arg flow "$FLOW" \
  --arg server_name "$SERVER_NAME" \
  --arg handshake_server "$HANDSHAKE_SERVER" \
  --argjson handshake_port "$HANDSHAKE_PORT" \
  --arg private_key "$PRIVATE_KEY" \
  --argjson short_ids "$SHORT_IDS_JSON" \
'
{
  log: {
    level: "info",
    timestamp: true
  },
  inbounds: [
    {
      type: "vless",
      tag: $tag,
      listen: $listen_addr,
      listen_port: $local_port,
      users: [
        {
          name: $user_name,
          uuid: $uuid,
          flow: $flow
        }
      ],
      tls: {
        enabled: true,
        server_name: $server_name,
        reality: {
          enabled: true,
          handshake: {
            server: $handshake_server,
            server_port: $handshake_port
          },
          private_key: $private_key,
          short_id: $short_ids
        }
      }
    }
  ],
  outbounds: [
    {
      type: "direct",
      tag: "direct"
    }
  ]
}
' > "$OUT_FILE"

ENCODED_REMARK="$(rawurlencode "$REMARK")"

# =========================
# Generate client URI
# public-port is used here
# =========================
CLIENT_URI="vless://${UUID}@${SERVER_ADDRESS}:${PUBLIC_PORT}?security=reality&encryption=none&flow=${FLOW}&type=tcp&sni=${SERVER_NAME}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SELECTED_SHORT_ID}#${ENCODED_REMARK}"

# =========================
# Output summary
# =========================
cat <<EOF

==============================
sing-box VLESS Reality Vision
==============================

[Server config]
Saved to: ${OUT_FILE}

[Server inbound]
Tag:              ${TAG}
Listen:           ${LISTEN_ADDR}
Local Port:       ${LOCAL_PORT}

[NAT mapping]
Server Address:   ${SERVER_ADDRESS}
Public Port:      ${PUBLIC_PORT}
Forward To:       ${LISTEN_ADDR}:${LOCAL_PORT}

[Reality]
Server Name/SNI:  ${SERVER_NAME}
Handshake Server: ${HANDSHAKE_SERVER}
Handshake Port:   ${HANDSHAKE_PORT}
Private Key:      ${PRIVATE_KEY}
Public Key:       ${PUBLIC_KEY}

[User]
Name:             ${USER_NAME}
UUID:             ${UUID}
Flow:             ${FLOW}

[Short IDs]
$(jq -r '.[]' <<<"$SHORT_IDS_JSON" | nl -w2 -s'. ')

[Client connection params]
Address:          ${SERVER_ADDRESS}
Port:             ${PUBLIC_PORT}
UUID:             ${UUID}
Flow:             ${FLOW}
TLS:              reality
SNI:              ${SERVER_NAME}
Public Key:       ${PUBLIC_KEY}
Short ID:         ${SELECTED_SHORT_ID}
Fingerprint:      chrome

[Client URI]
${CLIENT_URI}

EOF