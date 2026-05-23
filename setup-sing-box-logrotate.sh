#!/bin/sh
set -eu

LOG_FILE="/var/log/sing-box.log"
LOGROTATE_CONF="/etc/logrotate.d/sing-box"
HOURLY_LOGROTATE="/etc/periodic/hourly/logrotate"
SING_BOX_CONFIG="${1:-config.json}"

echo "Installing logrotate..."
apk update
apk add logrotate

echo "Ensuring crond is running..."
if command -v rc-service >/dev/null 2>&1; then
    rc-service crond start || true
    rc-update add crond || true
else
    crond || true
fi

echo "Creating sing-box log file..."
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

echo "Writing logrotate config..."
cat > "$LOGROTATE_CONF" <<EOF
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
cat > "$HOURLY_LOGROTATE" <<'EOF'
#!/bin/sh
/usr/sbin/logrotate /etc/logrotate.conf
EOF

chmod +x "$HOURLY_LOGROTATE"

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