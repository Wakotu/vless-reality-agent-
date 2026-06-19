#!/bin/sh
set -eu

REMOVE_ALL=false
SING_BOX_CONFIG="$(pwd)/config.json"

usage() {
    cat <<EOF
Usage:
  $0 [--all] [--config PATH]

Default (no --all):
  Stop service, remove init script, logrotate config, and hourly cron job.
  Preserves log files, sing-box binary, and config.json.

Options:
  --all           Also remove logs, sing-box binary, and config.json.
                  (Does NOT remove the logrotate package itself, as it may
                   be used by other system services.)
  --config PATH   Path to config.json for removal with --all.
                  (default: $(pwd)/config.json)
  -h, --help      Show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --all)  REMOVE_ALL=true ;;
        --config)
            SING_BOX_CONFIG="$2"
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *)  echo "Unknown argument: $1" >&2; usage; exit 1 ;;
    esac
    shift
done

if [ -n "$SING_BOX_CONFIG" ]; then
    case "$SING_BOX_CONFIG" in
        /*) ;;
        *)  SING_BOX_CONFIG="$(pwd)/$SING_BOX_CONFIG" ;;
    esac
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID}"
else
    OS_ID="unknown"
fi

case "$OS_ID" in
    alpine) HOURLY_LOGROTATE="/etc/periodic/hourly/logrotate" ;;
    *)      HOURLY_LOGROTATE="/etc/cron.hourly/logrotate" ;;
esac

case "$OS_ID" in
    alpine)         INIT_SCRIPT="/etc/init.d/sing-box" ;;
    debian|ubuntu)  INIT_SCRIPT="/etc/systemd/system/sing-box.service" ;;
    *)              INIT_SCRIPT="" ;;
esac

LOG_FILE="/var/log/sing-box.log"
LOGROTATE_CONF="/etc/logrotate.d/sing-box"

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

echo "=== Tearing down sing-box service ==="

# 1. Stop and remove service
if [ -n "$INIT_SCRIPT" ] && [ -f "$INIT_SCRIPT" ]; then
    echo "Stopping and removing sing-box service..."
    case "$OS_ID" in
        alpine)
            $SUDO rc-service sing-box stop 2>/dev/null || true
            $SUDO rc-update del sing-box 2>/dev/null || true
            $SUDO rm -f "$INIT_SCRIPT"
            ;;
        debian|ubuntu)
            $SUDO systemctl disable --now sing-box 2>/dev/null || true
            $SUDO rm -f "$INIT_SCRIPT"
            $SUDO systemctl daemon-reload 2>/dev/null || true
            ;;
    esac
else
    echo "sing-box service not found, skipping."
fi

# 2. Remove logrotate config
if [ -f "$LOGROTATE_CONF" ]; then
    echo "Removing logrotate config..."
    $SUDO rm -f "$LOGROTATE_CONF"
else
    echo "logrotate config not found, skipping."
fi

# 3. Remove hourly cron job
if [ -f "$HOURLY_LOGROTATE" ]; then
    echo "Removing hourly logrotate cron job..."
    $SUDO rm -f "$HOURLY_LOGROTATE"
else
    echo "hourly logrotate cron job not found, skipping."
fi

# --all: additional cleanup
if $REMOVE_ALL; then
    echo
    echo "=== Full cleanup (--all) ==="

    echo "Removing log files..."
    $SUDO rm -f "$LOG_FILE"*

    if [ -f "$SING_BOX_CONFIG" ]; then
        echo "Removing config: $SING_BOX_CONFIG"
        $SUDO rm -f "$SING_BOX_CONFIG"
    else
        echo "config.json not found at $SING_BOX_CONFIG, skipping."
    fi

    echo "Removing sing-box binary..."
    case "$OS_ID" in
        alpine)
            $SUDO apk del sing-box 2>/dev/null || true
            ;;
        debian|ubuntu)
            $SUDO rm -f /usr/local/bin/sing-box /usr/bin/sing-box
            ;;
        *)
            $SUDO rm -f /usr/local/bin/sing-box /usr/bin/sing-box
            ;;
    esac
fi

echo
echo "Teardown complete."
