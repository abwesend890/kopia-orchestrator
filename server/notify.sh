#!/bin/bash

CONFIG_FILE="${CONFIG_FILE:-/etc/backup/config.yml}"
NOTIFY_SUBJECT_PREFIX="${NOTIFY_SUBJECT_PREFIX:-Backup}"

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

  local curl_args=("--silent" "--show-error")
  if [ "$smtp_port" = "465" ]; then
    curl_args+=("--url" "smtps://${smtp_host}:${smtp_port}")
  else
    curl_args+=("--url" "smtp://${smtp_host}:${smtp_port}" "--ssl-reqd")
  fi

  yq '.notifications.email.to[]' "$CONFIG_FILE" | while IFS= read -r to_addr; do
    if ! curl "${curl_args[@]}" \
      --mail-from "$username" \
      --mail-rcpt "$to_addr" \
      --user "${username}:${password}" \
      -T - <<EOF
From: $username
To: $to_addr
Subject: [${NOTIFY_SUBJECT_PREFIX}] $subject

$body
EOF
    then
      echo "WARNING: notification delivery failed for $to_addr" >&2
    fi
  done
}
