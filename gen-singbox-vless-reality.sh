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
NODE_NAME="${NODE_NAME:-${USER_NAME}-${SERVER_NAME}}"
SHORT_ID_COUNT="${SHORT_ID_COUNT:-1}"

# =========================
# Root detection
# =========================
if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

# =========================
# OS detection
# =========================
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="${ID}"
else
  OS_ID="unknown"
fi

# =========================
# Dependency installer
# =========================
install_missing_deps() {
  local need_wget=false
  local need_jq=false
  local need_singbox=false

  command -v wget >/dev/null 2>&1 || need_wget=true
  command -v jq >/dev/null 2>&1 || need_jq=true
  command -v sing-box >/dev/null 2>&1 || need_singbox=true

  if ! $need_wget && ! $need_jq && ! $need_singbox; then
    return 0
  fi

  echo "==> Installing missing dependencies for ${OS_ID}..." >&2

  case "$OS_ID" in
    alpine)
      local pkgs=()
      $need_wget && pkgs+=(wget)
      $need_jq && pkgs+=(jq)
      if [[ ${#pkgs[@]} -gt 0 ]]; then
        $SUDO apk update || true
        $SUDO apk add "${pkgs[@]}" || {
          echo "Error: failed to install: ${pkgs[*]}" >&2
          exit 1
        }
      fi
      hash -r
      $need_wget && { hash -d wget 2>/dev/null; } || true
      $need_jq && { hash -d jq 2>/dev/null; } || true
      $need_wget && { command -v wget >/dev/null 2>&1 || test -x /usr/bin/wget; } || {
        echo "Error: wget still not found after install" >&2
        exit 1
      }
      $need_jq && { command -v jq >/dev/null 2>&1 || test -x /usr/bin/jq; } || {
        echo "Error: jq still not found after install" >&2
        exit 1
      }
      if $need_singbox; then
        $SUDO apk add sing-box --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community || {
          echo "Error: failed to install sing-box" >&2
          exit 1
        }
        hash -r
        hash -d sing-box 2>/dev/null || true
        command -v sing-box >/dev/null 2>&1 || test -x /usr/bin/sing-box || {
          echo "Error: sing-box still not found after install" >&2
          exit 1
        }
      fi
      ;;
    debian|ubuntu)
      if $need_wget || $need_jq; then
        $SUDO apt-get update || true
        local pkgs=()
        $need_wget && pkgs+=(wget)
        $need_jq && pkgs+=(jq)
        $SUDO apt-get install -y "${pkgs[@]}" || {
          echo "Error: failed to install: ${pkgs[*]}" >&2
          exit 1
        }
        hash -r
        $need_wget && command -v wget >/dev/null 2>&1 || {
          echo "Error: wget still not found after install" >&2
          exit 1
        }
        $need_jq && command -v jq >/dev/null 2>&1 || {
          echo "Error: jq still not found after install" >&2
          exit 1
        }
      fi
      if $need_singbox; then
        local arch
        arch="$(uname -m)"
        case "$arch" in
          x86_64)  arch="amd64" ;;
          aarch64) arch="arm64" ;;
          armv7l)  arch="armv7" ;;
          *)       ;;
        esac
        echo "==> Retrieving latest sing-box release info..." >&2
        local latest_tag download_url repo api_url release_json
        repo="SagerNet/sing-box"
        api_url="https://api.github.com/repos/${repo}/releases/latest"

        if ! release_json="$(wget -O- --timeout=15 --tries=2 "$api_url")"; then
          echo "Error: failed to retrieve latest sing-box release info from GitHub" >&2
          echo "Hint: check network connectivity or download sing-box manually:" >&2
          echo "  https://github.com/${repo}/releases" >&2
          exit 1
        fi

        latest_tag="$(jq -r '.tag_name // empty' <<<"$release_json" || true)"

        if [[ -z "$latest_tag" || "$latest_tag" == "null" ]]; then
          echo "Error: failed to parse sing-box release tag from GitHub response:" >&2
          jq . <<<"$release_json" >&2
          exit 1
        fi

        download_url="https://github.com/${repo}/releases/download/${latest_tag}/sing-box-${latest_tag#v}-linux-${arch}.tar.gz"
        local tmpdir
        tmpdir="$(mktemp -d)"
        echo "==> Downloading sing-box ${latest_tag} for linux/${arch}..." >&2
        wget -q --show-progress --timeout=60 --tries=3 -O "${tmpdir}/sing-box.tar.gz" "$download_url" || {
          echo "Error: failed to download sing-box from ${download_url}" >&2
          rm -rf "$tmpdir"
          exit 1
        }
        tar -xzf "${tmpdir}/sing-box.tar.gz" -C "$tmpdir" || {
          echo "Error: failed to extract sing-box archive" >&2
          rm -rf "$tmpdir"
          exit 1
        }
        local bin_path
        bin_path="$(find "${tmpdir}" -type f -name 'sing-box' -executable | head -n1)"
        if [[ -z "$bin_path" ]]; then
          echo "Error: could not find sing-box binary in archive" >&2
          rm -rf "$tmpdir"
          exit 1
        fi
        $SUDO cp "$bin_path" /usr/local/bin/sing-box || {
          echo "Error: failed to copy sing-box to /usr/local/bin" >&2
          rm -rf "$tmpdir"
          exit 1
        }
        $SUDO chmod +x /usr/local/bin/sing-box
        rm -rf "$tmpdir"
        echo "==> sing-box ${latest_tag} installed to /usr/local/bin/sing-box" >&2
        hash -r
        command -v sing-box >/dev/null 2>&1 || {
          echo "Error: sing-box still not found after install" >&2
          exit 1
        }
      fi
      ;;
    *)
      echo "Warning: automatic dependency installation is not supported for ${OS_ID}" >&2
      echo "Please install the following manually:" >&2
      $need_wget && echo "  - wget (https://www.gnu.org/software/wget/)" >&2
      $need_jq && echo "  - jq (https://jqlang.github.io/jq/)" >&2
      $need_singbox && echo "  - sing-box (https://github.com/SagerNet/sing-box/releases)" >&2
      exit 1
      ;;
  esac
}

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
  --node-name NAME           Clash node name (default: ${NODE_NAME})
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
    --node-name)
      NODE_NAME="$2"
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
install_missing_deps

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

[Clash Node]
    - name: "${NODE_NAME}"
      type: vless
      server: ${SERVER_ADDRESS}
      port: ${PUBLIC_PORT}
      uuid: ${UUID}
      udp: true
      tls: true
      flow: ${FLOW}
      servername: ${SERVER_NAME}
      network: tcp
      reality-opts:
        public-key: ${PUBLIC_KEY}
        short-id: ${SELECTED_SHORT_ID}
      client-fingerprint: chrome

EOF