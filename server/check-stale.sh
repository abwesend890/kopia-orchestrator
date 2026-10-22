#!/bin/bash
# Alerts when a configured client's newest complete snapshot of a path is
# older than its limit (stale_check.max_age_hours, overridable per client).
# Sourced by entrypoint.sh; needs send_notification from notify.sh.

CONFIG_FILE="${CONFIG_FILE:-/etc/backup/config.yml}"

DEFAULT_MAX_AGE_HOURS=26
SECONDS_PER_HOUR=3600
STALE_CHECK_STARTUP_DELAY_SECONDS=300
STALE_CHECK_INTERVAL_SECONDS=86400

# Prints one line per stale path of a configured client, and one line per
# client that has no complete snapshot at all. Clients with a limit of 0 are
# skipped. Sources of clients not in config.yml are ignored.
# $1: file with `kopia snapshot list --all --json` output
# $2: current time as epoch seconds
find_stale_sources() {
  local snapshots_file="$1"
  local now="$2"

  local newest_per_source
  newest_per_source=$(yq -p json -oy '
    [.[] | select(.incompleteReason == null)]
    | group_by(.source.userName + "@" + .source.host + ":" + .source.path)
    | .[] | sort_by(.startTime) | .[-1]
    | [.source.userName + "@" + .source.host, .source.path, .startTime] | @tsv
  ' "$snapshots_file")

  local global_limit client_count
  global_limit=$(yq ".stale_check.max_age_hours // ${DEFAULT_MAX_AGE_HOURS}" "$CONFIG_FILE")
  client_count=$(yq '.clients | length' "$CONFIG_FILE")

  local i
  for ((i = 0; i < client_count; i++)); do
    local client limit
    client=$(yq ".clients[$i].username + \"@\" + .clients[$i].hostname" "$CONFIG_FILE")
    limit=$(yq ".clients[$i].max_age_hours // ${global_limit}" "$CONFIG_FILE")
    [ "$limit" -gt 0 ] || continue

    local has_snapshot=false
    local source_client path start_time
    while IFS=$'\t' read -r source_client path start_time; do
      [ "$source_client" = "$client" ] || continue
      has_snapshot=true
      local age_seconds
      age_seconds=$(( now - $(date -d "$start_time" +%s) ))
      if [ "$age_seconds" -gt $(( limit * SECONDS_PER_HOUR )) ]; then
        echo "${client}:${path} last snapshot $(( age_seconds / SECONDS_PER_HOUR ))h ago (limit ${limit}h)"
      fi
    done <<< "$newest_per_source"

    if [ "$has_snapshot" = false ]; then
      echo "${client} has no snapshots (limit ${limit}h)"
    fi
  done
}

# Returns 1 if snapshots could not be listed, 0 otherwise (stale or not).
check_stale_backups() {
  local snapshots_file
  snapshots_file=$(mktemp)

  if ! kopia snapshot list --all --json > "$snapshots_file"; then
    rm -f "$snapshots_file"
    echo "ERROR: stale check could not list snapshots" >&2
    send_notification "Stale check failed" "$(printf 'Could not list snapshots.\nHost: %s' "$(hostname)")"
    return 1
  fi

  local stale
  stale=$(find_stale_sources "$snapshots_file" "$(date +%s)")
  rm -f "$snapshots_file"

  if [ -z "$stale" ]; then
    echo "Stale check: all sources within their limit"
    return 0
  fi

  echo "Stale check: stale sources found:"
  echo "$stale"
  send_notification "Stale backups" "$(printf '%s\n\nHost: %s' "$stale" "$(hostname)")"
}

# Runs the check shortly after startup, then daily. Loops on sleep's exit
# status rather than `while true`, so it stops if sleep is interrupted.
run_stale_checks() {
  local delay="$STALE_CHECK_STARTUP_DELAY_SECONDS"
  while sleep "$delay"; do
    check_stale_backups || true
    delay="$STALE_CHECK_INTERVAL_SECONDS"
  done
}
