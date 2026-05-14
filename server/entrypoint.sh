#!/bin/bash
set -euo pipefail

CONFIG_FILE="/etc/backup/config.yml"
REPO_PATH="/repo"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: config file not found at $CONFIG_FILE"
  exit 1
fi

if [ -f "$REPO_PATH/kopia.repository.f" ]; then
  echo "Connecting to existing repository at $REPO_PATH..."
  kopia repository connect filesystem --path "$REPO_PATH"
else
  echo "Creating new repository at $REPO_PATH..."
  kopia repository create filesystem --path "$REPO_PATH"
fi

add_clients() {
  local count
  count=$(yq '.clients | length' "$CONFIG_FILE")

  for ((i = 0; i < count; i++)); do
    local username hostname password_env password
    username=$(yq ".clients[$i].username" "$CONFIG_FILE")
    hostname=$(yq ".clients[$i].hostname" "$CONFIG_FILE")
    password_env=$(yq ".clients[$i].password_env" "$CONFIG_FILE")
    password="${!password_env:-}"

    if [ -z "$password" ]; then
      echo "WARNING: $password_env not set, skipping client ${username}@${hostname}"
      continue
    fi

    echo "Adding client: ${username}@${hostname}"
    kopia server user add "${username}@${hostname}" --user-password "$password" 2>/dev/null \
      || kopia server user set "${username}@${hostname}" --user-password "$password"
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

DOMAIN="${KOPIA_VIRTUAL_HOST}"
TLS_CERT="/certs/${DOMAIN}/fullchain.pem"
TLS_KEY="/certs/${DOMAIN}/key.pem"

SERVER_ARGS=(
  "--address" "0.0.0.0:51515"
)

if [ -f "$TLS_CERT" ] && [ -f "$TLS_KEY" ]; then
  echo "Using TLS certs for $DOMAIN"
  SERVER_ARGS+=("--tls-cert-file" "$TLS_CERT" "--tls-key-file" "$TLS_KEY")
else
  echo "WARNING: TLS certs not found at $TLS_CERT — falling back to --insecure"
  SERVER_ARGS+=("--insecure")
fi

ui_enabled=$(yq '.ui.enabled // false' "$CONFIG_FILE")
if [ "$ui_enabled" != "true" ]; then
  SERVER_ARGS+=("--no-ui")
else
  ui_user=$(yq '.ui.username' "$CONFIG_FILE")
  ui_pass_env=$(yq '.ui.password_env' "$CONFIG_FILE")
  : "${ui_user:=admin}"
  if [ -n "$ui_pass_env" ] && [ "$ui_pass_env" != "null" ] && [ -n "${!ui_pass_env:-}" ]; then
    SERVER_ARGS+=("--server-control-username" "$ui_user")
    SERVER_ARGS+=("--server-control-password" "${!ui_pass_env}")
  else
    echo "WARNING: UI enabled but no password set — UI will use Kopia defaults"
  fi
fi

if [ -f "$TLS_CERT" ]; then
  (inotifywait -m -e modify,create "$TLS_CERT" 2>/dev/null | while read -r _; do
    echo "TLS cert renewed — restarting kopia..."
    kill 1
  done) &
fi

echo "Starting Kopia server..."
exec kopia server start "${SERVER_ARGS[@]}"
