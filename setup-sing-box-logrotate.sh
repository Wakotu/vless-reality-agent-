#!/bin/sh
set -eu

LOG_FILE="/var/log/sing-box.log"
LOGROTATE_CONF="/etc/logrotate.d/sing-box"
if [ -n "${1:-}" ]; then
    case "$1" in
        /*) SING_BOX_CONFIG="$1" ;;
        *)  SING_BOX_CONFIG="$(pwd)/$1" ;;
    esac
else
    SING_BOX_CONFIG="$(pwd)/config.json"
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
    alpine) INIT_SCRIPT="/etc/init.d/sing-box" ;;
    debian|ubuntu) INIT_SCRIPT="/etc/systemd/system/sing-box.service" ;;
    *) INIT_SCRIPT="" ;;
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
    dateformat -%Y%m%d%H
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


echo "Installing sing-box system service..."

if pgrep -x sing-box >/dev/null; then
    echo "sing-box is already running, stopping existing instance..."
    $SUDO pkill -x sing-box
fi

case "$OS_ID" in
    alpine)
        cat <<EOF | $SUDO tee "$INIT_SCRIPT" >/dev/null
#!/sbin/openrc-run
supervisor="supervise-daemon"
name="sing-box"
command="/usr/bin/sing-box"
command_args="run -c $SING_BOX_CONFIG"
output_log="$LOG_FILE"
error_log="$LOG_FILE"
respawn_delay=5
respawn_max=0
EOF
        $SUDO chmod +x "$INIT_SCRIPT"
        $SUDO rc-update add sing-box default
        $SUDO rc-service sing-box start
        ;;
    debian|ubuntu)
        cat <<EOF | $SUDO tee "$INIT_SCRIPT" >/dev/null
[Unit]
Description=sing-box
After=network.target

[Service]
ExecStart=/usr/bin/sing-box run -c $SING_BOX_CONFIG
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=0
StartLimitBurst=0

[Install]
WantedBy=multi-user.target
EOF
        $SUDO systemctl daemon-reload
        $SUDO systemctl enable --now sing-box
        ;;
    *)
        echo "Starting sing-box with:"
        echo "nohup sing-box run -c \"$SING_BOX_CONFIG\" >$LOG_FILE 2>&1 &"
        nohup sing-box run -c "$SING_BOX_CONFIG" >"$LOG_FILE" 2>&1 &
        ;;
esac

echo
echo "Setup complete."
echo
echo
echo "Check logs with:"
echo "tail -f $LOG_FILE"
echo
echo "Check rotated logs with:"
echo "ls -lh /var/log/sing-box.log*"