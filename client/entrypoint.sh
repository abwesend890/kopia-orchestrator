#!/bin/bash
set -euo pipefail

CONFIG_FILE="/etc/backup/config.yml"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: config file not found at $CONFIG_FILE"
  exit 1
fi

server_url=$(yq '.server.url' "$CONFIG_FILE")
password_env=$(yq '.server.password_env' "$CONFIG_FILE")
password="${!password_env}"

echo "Connecting to Kopia server at $server_url..."
kopia repository connect server \
  --url "$server_url" \
  --server-cert-fingerprint="" \
  --override-username="$(hostname)" \
  --override-hostname="$(hostname)" \
  --password "$password"

echo "Running initial setup..."
/setup.sh

echo "Watching config file for changes..."
inotifywait -m -e modify,move_self "$CONFIG_FILE" 2>&1 | while read -r event; do
  echo "Config changed: $event — re-running setup..."
  /setup.sh
done &

echo "Kopia client ready. Scheduler active."
exec kopia server start \
  --address 0.0.0.0:51515 \
  --insecure \
  --no-ui \
  --without-password
