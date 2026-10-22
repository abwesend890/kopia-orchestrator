#!/bin/bash
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/etc/backup/config.yml}"
REPO_PATH="${REPO_PATH:-/repo}"
export NOTIFY_SUBJECT_PREFIX="Backup Server"
source "${NOTIFY_SH:-/notify.sh}"
source "${CHECK_STALE_SH:-/check-stale.sh}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: config file not found at $CONFIG_FILE"
  exit 1
fi

export -f send_notification
export CONFIG_FILE

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
    if ! kopia server user add "${username}@${hostname}" --user-password "$password" 2>/dev/null \
      && ! kopia server user set "${username}@${hostname}" --user-password "$password"; then
      echo "ERROR: failed to add client ${username}@${hostname}"
      send_notification \
        "Client add failed" \
        "Could not add client ${username}@${hostname}\nHost: $(hostname)"
    fi
  done
}

if [ -f "$REPO_PATH/kopia.repository.f" ]; then
  echo "Connecting to existing repository at $REPO_PATH..."
  if ! kopia repository connect filesystem --path "$REPO_PATH"; then
    send_notification "Repository connect failed" "Could not connect to repo at $REPO_PATH\nHost: $(hostname)"
    exit 1
  fi
else
  echo "Creating new repository at $REPO_PATH..."
  if ! kopia repository create filesystem --path "$REPO_PATH"; then
    send_notification "Repository create failed" "Could not create repo at $REPO_PATH\nHost: $(hostname)"
    exit 1
  fi
fi

add_clients

DOMAIN="${KOPIA_VIRTUAL_HOST}"
CERT_DIR="${CERT_DIR:-/certs}"
TLS_CERT="${CERT_DIR}/${DOMAIN}/fullchain.pem"
TLS_KEY="${CERT_DIR}/${DOMAIN}/key.pem"

SERVER_ARGS=(
  "--address" "0.0.0.0:51515"
)

cert_fingerprint() {
  [ -f "$TLS_CERT" ] && [ -f "$TLS_KEY" ] || return 0
  md5sum "$TLS_CERT" "$TLS_KEY"
}

# Watches the whole cert volume rather than the cert file: on first boot the
# domain directory does not exist yet, and acme-companion replaces the cert
# files on renewal instead of writing them in place, so a watch on the file
# itself would either fail to start or follow a stale inode. Events for other
# domains are ignored because the fingerprint does not change.
restart_on_cert_change() {
  local known_fingerprint
  known_fingerprint=$(cert_fingerprint)

  inotifywait -m -r -e close_write,create,moved_to "$CERT_DIR" | while read -r _; do
    local current_fingerprint
    current_fingerprint=$(cert_fingerprint)
    [ -n "$current_fingerprint" ] || continue
    [ "$current_fingerprint" != "$known_fingerprint" ] || continue

    echo "TLS cert for ${DOMAIN} changed, restarting kopia to load it..."
    kill 1
    return
  done
}

if [ -f "$TLS_CERT" ] && [ -f "$TLS_KEY" ]; then
  echo "Using TLS certs for $DOMAIN"
  SERVER_ARGS+=("--tls-cert-file" "$TLS_CERT" "--tls-key-file" "$TLS_KEY")
else
  echo "WARNING: TLS certs not found at $TLS_CERT, falling back to --insecure"
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

if [ -d "$CERT_DIR" ]; then
  restart_on_cert_change &
else
  echo "WARNING: cert directory ${CERT_DIR} is not mounted, cert renewals will not be picked up"
fi

run_stale_checks &

echo "Starting Kopia server..."
exec kopia server start "${SERVER_ARGS[@]}"
