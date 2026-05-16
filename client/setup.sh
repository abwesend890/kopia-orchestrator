#!/bin/bash
set -euo pipefail

CONFIG_FILE="/etc/backup/config.yml"

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

global_times=$(yq '.schedule.times // [] | .[]' "$CONFIG_FILE" 2>/dev/null)

service_count=$(yq '.services | length' "$CONFIG_FILE")

for ((s = 0; s < service_count; s++)); do
  name=$(yq ".services[$s].name" "$CONFIG_FILE")
  container=$(yq ".services[$s].container // \"\"" "$CONFIG_FILE")
  mode=$(yq ".services[$s].mode // \"live\"" "$CONFIG_FILE")

  if [ -z "$container" ] || [ "$container" = "null" ]; then
    mode="live"
  fi

  svc_times=$(yq ".services[$s].schedule.times // [] | .[]" "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$svc_times" ]; then
    svc_times="$global_times"
  fi

  svc_keep_daily=$(yq ".services[$s].retention.keep_daily // \"\"" "$CONFIG_FILE")
  svc_keep_weekly=$(yq ".services[$s].retention.keep_weekly // \"\"" "$CONFIG_FILE")
  svc_keep_monthly=$(yq ".services[$s].retention.keep_monthly // \"\"" "$CONFIG_FILE")

  path_count=$(yq ".services[$s].paths | length" "$CONFIG_FILE")

  for ((p = 0; p < path_count; p++)); do
    path_val=$(yq ".services[$s].paths[$p]" "$CONFIG_FILE")

    if echo "$path_val" | grep -q "^/"; then
      snapshot_path="$path_val"
      keep_daily="$svc_keep_daily"
      keep_weekly="$svc_keep_weekly"
      keep_monthly="$svc_keep_monthly"
    else
      snapshot_path=$(yq ".services[$s].paths[$p].path" "$CONFIG_FILE")
      keep_daily=$(yq ".services[$s].paths[$p].retention.keep_daily // \"\"" "$CONFIG_FILE")
      keep_weekly=$(yq ".services[$s].paths[$p].retention.keep_weekly // \"\"" "$CONFIG_FILE")
      keep_monthly=$(yq ".services[$s].paths[$p].retention.keep_monthly // \"\"" "$CONFIG_FILE")

      [ -z "$keep_daily" ] || [ "$keep_daily" = "null" ] && keep_daily="$svc_keep_daily"
      [ -z "$keep_weekly" ] || [ "$keep_weekly" = "null" ] && keep_weekly="$svc_keep_weekly"
      [ -z "$keep_monthly" ] || [ "$keep_monthly" = "null" ] && keep_monthly="$svc_keep_monthly"
    fi

    echo "Configuring path: $snapshot_path (service: $name, mode: $mode)"

    POLICY_ARGS=()
    [ -n "$keep_daily" ] && [ "$keep_daily" != "null" ] && POLICY_ARGS+=("--keep-daily" "$keep_daily")
    [ -n "$keep_weekly" ] && [ "$keep_weekly" != "null" ] && POLICY_ARGS+=("--keep-weekly" "$keep_weekly")
    [ -n "$keep_monthly" ] && [ "$keep_monthly" != "null" ] && POLICY_ARGS+=("--keep-monthly" "$keep_monthly")

    if [ -n "$svc_times" ]; then
      while IFS= read -r t; do
        POLICY_ARGS+=("--snapshot-time" "$t")
      done <<< "$svc_times"
    fi

    if [ "$mode" = "stop" ]; then
      POLICY_ARGS+=("--before-snapshot-root-action" "docker stop $container")
      POLICY_ARGS+=("--after-snapshot-root-action" "docker start $container")
    fi

    kopia policy set "$snapshot_path" "${POLICY_ARGS[@]}" 2>&1 || true

    echo "Creating initial snapshot for $snapshot_path..."
    if ! kopia snapshot create "$snapshot_path" 2>&1; then
      echo "ERROR: snapshot failed for $snapshot_path (service: $name)"
      send_notification \
        "Snapshot failed: $name" \
        "Path: $snapshot_path\nService: $name\nHost: $(hostname)"
    fi
  done
done

echo "Setup complete."
