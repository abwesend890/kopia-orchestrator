#!/bin/bash

CONFIG_FILE="${CONFIG_FILE:-/etc/backup/config.yml}"

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
Subject: [Backup Client] $subject

$body
EOF
  done
}
