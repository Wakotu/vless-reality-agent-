#!/bin/sh
set -eu

LOG_FILE="/var/log/sing-box.log"
LOGROTATE_CONF="/etc/logrotate.d/sing-box"
SING_BOX_CONFIG="${1:-config.json}"

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

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

echo "Installing logrotate..."
case "$OS_ID" in
    alpine)
        $SUDO apk update
        $SUDO apk add logrotate
        ;;
    debian|ubuntu)
        $SUDO apt-get update
        $SUDO apt-get install -y logrotate cron
        ;;
    *)
        echo "Warning: unknown OS, cannot install logrotate automatically"
        ;;
esac

echo "Ensuring cron is running..."
case "$OS_ID" in
    alpine)
        $SUDO rc-service crond start 2>/dev/null || true
        $SUDO rc-update add crond 2>/dev/null || true
        ;;
    debian|ubuntu)
        $SUDO systemctl enable --now cron 2>/dev/null || true
        ;;
    *)
        echo "Warning: cannot ensure cron is running, skipping"
        ;;
esac

echo "Creating sing-box log file..."
$SUDO touch "$LOG_FILE"
$SUDO chmod 644 "$LOG_FILE"

echo "Writing logrotate config..."
cat <<EOF | $SUDO tee "$LOGROTATE_CONF" >/dev/null
$LOG_FILE {
    size 1M
    rotate 2
    compress
    missingok
    notifempty
    copytruncate
}
EOF

echo "Creating hourly logrotate job..."
cat <<'EOF' | $SUDO tee "$HOURLY_LOGROTATE" >/dev/null
#!/bin/sh
/usr/sbin/logrotate /etc/logrotate.conf
EOF

$SUDO chmod +x "$HOURLY_LOGROTATE"

echo "Testing logrotate config..."
logrotate -d /etc/logrotate.conf >/dev/null


echo "Starting sing-box with:"
echo "nohup sing-box run -c \"$SING_BOX_CONFIG\" >$LOG_FILE 2>&1 &"
nohup sing-box run -c "$SING_BOX_CONFIG" >"$LOG_FILE" 2>&1 &

echo
echo "Setup complete."
echo
echo
echo "Check logs with:"
echo "tail -f $LOG_FILE"
echo
echo "Check rotated logs with:"
echo "ls -lh /var/log/sing-box.log*"