#!/bin/bash
set -euo pipefail

CONFIG_FILE="/etc/backup/config.yml"
REPO_PATH="/repo"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: config file not found at $CONFIG_FILE"
  exit 1
fi

if ! kopia repository status &>/dev/null; then
  echo "Creating new repository at $REPO_PATH..."
  kopia repository create filesystem --path "$REPO_PATH"
else
  echo "Connecting to existing repository at $REPO_PATH..."
  kopia repository connect filesystem --path "$REPO_PATH"
fi

add_clients() {
  local count
  count=$(yq '.clients | length' "$CONFIG_FILE")

  for ((i = 0; i < count; i++)); do
    local name password_env password
    name=$(yq ".clients[$i].name" "$CONFIG_FILE")
    password_env=$(yq ".clients[$i].password_env" "$CONFIG_FILE")
    password="${!password_env}"

    if [ -z "$password" ]; then
      echo "WARNING: $password_env not set, skipping client $name"
      continue
    fi

    echo "Adding client: $name"
    kopia server user add "${name}@${name}" --user-password "$password" 2>/dev/null \
      || kopia server user set "${name}@${name}" --user-password "$password"
  done
}

send_notification() {
  local subject="$1"
  local body="$2"

  local enabled
  enabled=$(yq '.notifications.email // ""' "$CONFIG_FILE")
  if [ -z "$enabled" ] || [ "$enabled" = "null" ]; then
    return
  fi

  local smtp_host smtp_port username_env password_env username password
  smtp_host=$(yq '.notifications.email.smtp_host' "$CONFIG_FILE")
  smtp_port=$(yq '.notifications.email.smtp_port' "$CONFIG_FILE")
  username_env=$(yq '.notifications.email.username_env' "$CONFIG_FILE")
  password_env=$(yq '.notifications.email.password_env' "$CONFIG_FILE")
  username="${!username_env:-}"
  password="${!password_env:-}"

  local recipients
  recipients=$(yq '.notifications.email.to[]' "$CONFIG_FILE")

  for to_addr in $recipients; do
    curl --silent --show-error \
      --url "smtp://${smtp_host}:${smtp_port}" \
      --ssl-reqd \
      --mail-from "$username" \
      --mail-rcpt "$to_addr" \
      --user "${username}:${password}" \
      -T - <<EOF
From: $username
To: $to_addr
Subject: [Backup Server] $subject

$body
EOF
  done
}

export -f send_notification
export CONFIG_FILE

add_clients

SERVER_ARGS=(
  "--address" "0.0.0.0:51515"
  "--insecure"
)

ui_enabled=$(yq '.ui.enabled // false' "$CONFIG_FILE")
if [ "$ui_enabled" != "true" ]; then
  SERVER_ARGS+=("--no-ui")
fi

echo "Starting Kopia server..."
exec kopia server start "${SERVER_ARGS[@]}"
