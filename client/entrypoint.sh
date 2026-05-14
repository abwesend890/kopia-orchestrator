#!/bin/bash
set -euo pipefail

CONFIG_FILE="/etc/backup/config.yml"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: config file not found at $CONFIG_FILE"
  exit 1
fi

server_url=$(yq '.server.url' "$CONFIG_FILE")
password_env=$(yq '.server.password_env' "$CONFIG_FILE")
password="${!password_env:-}"
client_user=$(yq '.server.username' "$CONFIG_FILE")
client_host=$(yq '.server.hostname' "$CONFIG_FILE")

if [ -z "$password" ]; then
  echo "ERROR: $password_env not set"
  exit 1
fi

echo "Connecting to Kopia server at $server_url as ${client_user}@${client_host}..."
kopia repository connect server \
  --url "$server_url" \
  --override-username "$client_user" \
  --override-hostname "$client_host" \
  --password "$password" \
  --enable-actions

echo "Running initial setup..."
/setup.sh

echo "Watching config file for changes..."
inotifywait -m -q -e modify,move_self "$CONFIG_FILE" | while read -r event; do
  echo "Config changed — re-running setup..."
  /setup.sh
done &

echo "Kopia client ready. Scheduler active."
exec kopia server start \
  --address 127.0.0.1:51515 \
  --insecure \
  --no-ui \
  --without-password
