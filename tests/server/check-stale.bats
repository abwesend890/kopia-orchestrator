setup() {
  load ../test_helper/common
  load ../test_helper/mocks
  setup_mocks
  create_mock_with_output "hostname" "test-host"
  create_mock "curl"
  export NOTIFY_SUBJECT_PREFIX="Backup Server"
  source "${PROJECT_ROOT}/server/notify.sh"
  source "${PROJECT_ROOT}/server/check-stale.sh"
  SNAPSHOTS_FILE="${BATS_TEST_TMPDIR}/snapshots.json"
  NOW=$(date -d "2026-10-22T12:00:00Z" +%s)
}

# $1: extra YAML appended at top level (e.g. stale_check:)
write_stale_config() {
  write_config "$(cat <<YAML
clients:
  - username: mail
    hostname: ntran
    password_env: CLIENT_MAIL_PASS
  - username: nico
    hostname: laptop
    password_env: CLIENT_LAPTOP_PASS
    max_age_hours: 168
notifications:
  email:
    to:
      - admin@test.com
    smtp_host: mail.test.com
    smtp_port: 465
    username_env: SMTP_USER
    password_env: SMTP_PASS
$1
YAML
)"
}

# Each argument: "user@host|path|startTime|incompleteReason"
# (incompleteReason empty for a complete snapshot).
write_snapshots() {
  local entries=() entry user_host path start_time reason
  for entry in "$@"; do
    IFS='|' read -r user_host path start_time reason <<< "$entry"
    local reason_json="null"
    [ -z "$reason" ] || reason_json="\"${reason}\""
    entries+=("{\"source\":{\"userName\":\"${user_host%@*}\",\"host\":\"${user_host#*@}\",\"path\":\"${path}\"},\"startTime\":\"${start_time}\",\"incompleteReason\":${reason_json}}")
  done
  local IFS=,
  echo "[${entries[*]}]" > "$SNAPSHOTS_FILE"
  echo "fixture: $(cat "$SNAPSHOTS_FILE")"
}

# kopia mock that prints the fixture for `snapshot list` and fails otherwise.
create_kopia_snapshot_mock() {
  cat > "${MOCK_BIN}/kopia" <<SCRIPT
#!/bin/bash
echo "\$*" >> "${BATS_TEST_TMPDIR}/kopia.calls"
[ "\$*" = "snapshot list --all --json" ] || exit 1
cat "${SNAPSHOTS_FILE}"
SCRIPT
  chmod +x "${MOCK_BIN}/kopia"
}

@test "find_stale_sources -- fresh sources print nothing" {
  write_stale_config ""
  write_snapshots \
    "mail@ntran|/data/mail|2026-10-22T02:00:00.68633457Z|" \
    "nico@laptop|/data/docs|2026-10-20T12:00:00Z|"

  run find_stale_sources "$SNAPSHOTS_FILE" "$NOW"

  echo "output: $output"
  assert_success
  assert_output ""
}

@test "find_stale_sources -- path older than the default 26h is reported with its age" {
  write_stale_config ""
  write_snapshots \
    "mail@ntran|/data/mail|2026-10-21T09:00:00Z|" \
    "mail@ntran|/data/config|2026-10-22T02:00:00Z|" \
    "nico@laptop|/data/docs|2026-10-22T02:00:00Z|"

  run find_stale_sources "$SNAPSHOTS_FILE" "$NOW"

  echo "output: $output"
  assert_success
  assert_output "mail@ntran:/data/mail last snapshot 27h ago (limit 26h)"
}

@test "find_stale_sources -- only the newest snapshot of a path counts" {
  write_stale_config ""
  write_snapshots \
    "mail@ntran|/data/mail|2026-10-01T02:00:00Z|" \
    "mail@ntran|/data/mail|2026-10-22T02:00:00Z|" \
    "nico@laptop|/data/docs|2026-10-22T02:00:00Z|"

  run find_stale_sources "$SNAPSHOTS_FILE" "$NOW"

  echo "output: $output"
  assert_success
  assert_output ""
}

@test "find_stale_sources -- incomplete snapshots (checkpoints) do not count as fresh" {
  write_stale_config ""
  write_snapshots \
    "mail@ntran|/data/mail|2026-10-20T12:00:00Z|" \
    "mail@ntran|/data/mail|2026-10-22T11:00:00Z|checkpoint" \
    "nico@laptop|/data/docs|2026-10-22T02:00:00Z|"

  run find_stale_sources "$SNAPSHOTS_FILE" "$NOW"

  echo "output: $output"
  assert_success
  assert_output "mail@ntran:/data/mail last snapshot 48h ago (limit 26h)"
}

@test "find_stale_sources -- per-client max_age_hours overrides the global limit" {
  write_stale_config ""
  write_snapshots \
    "mail@ntran|/data/mail|2026-10-22T02:00:00Z|" \
    "nico@laptop|/data/docs|2026-10-17T12:00:00Z|" \
    "nico@laptop|/data/photos|2026-10-14T12:00:00Z|"

  run find_stale_sources "$SNAPSHOTS_FILE" "$NOW"

  echo "output: $output"
  assert_success
  assert_output "nico@laptop:/data/photos last snapshot 192h ago (limit 168h)"
}

@test "find_stale_sources -- global stale_check.max_age_hours replaces the default" {
  write_stale_config "$(printf 'stale_check:\n  max_age_hours: 6')"
  write_snapshots \
    "mail@ntran|/data/mail|2026-10-22T02:00:00Z|" \
    "nico@laptop|/data/docs|2026-10-22T02:00:00Z|"

  run find_stale_sources "$SNAPSHOTS_FILE" "$NOW"

  echo "output: $output"
  assert_success
  assert_output "mail@ntran:/data/mail last snapshot 10h ago (limit 6h)"
}

@test "find_stale_sources -- limit 0 disables the check" {
  write_stale_config "$(printf 'stale_check:\n  max_age_hours: 0')"
  write_snapshots \
    "mail@ntran|/data/mail|2026-01-01T00:00:00Z|" \
    "nico@laptop|/data/docs|2026-10-22T02:00:00Z|"

  run find_stale_sources "$SNAPSHOTS_FILE" "$NOW"

  echo "output: $output"
  assert_success
  assert_output ""
}

@test "find_stale_sources -- client without any snapshot is reported" {
  write_stale_config ""
  write_snapshots "mail@ntran|/data/mail|2026-10-22T02:00:00Z|"

  run find_stale_sources "$SNAPSHOTS_FILE" "$NOW"

  echo "output: $output"
  assert_success
  assert_output "nico@laptop has no snapshots (limit 168h)"
}

@test "find_stale_sources -- sources of unknown clients are ignored" {
  write_stale_config ""
  write_snapshots \
    "mail@ntran|/data/mail|2026-10-22T02:00:00Z|" \
    "nico@laptop|/data/docs|2026-10-22T02:00:00Z|" \
    "old@retired|/data/x|2025-01-01T00:00:00Z|"

  run find_stale_sources "$SNAPSHOTS_FILE" "$NOW"

  echo "output: $output"
  assert_success
  assert_output ""
}

@test "find_stale_sources -- same username on another host is a different client" {
  write_stale_config ""
  write_snapshots \
    "mail@other-host|/data/mail|2026-10-22T02:00:00Z|" \
    "nico@laptop|/data/docs|2026-10-22T02:00:00Z|"

  run find_stale_sources "$SNAPSHOTS_FILE" "$NOW"

  echo "output: $output"
  assert_success
  assert_output "mail@ntran has no snapshots (limit 26h)"
}

@test "find_stale_sources -- path with spaces is reported intact" {
  write_stale_config ""
  write_snapshots \
    "mail@ntran|/data/my mail|2026-10-20T12:00:00Z|" \
    "nico@laptop|/data/docs|2026-10-22T02:00:00Z|"

  run find_stale_sources "$SNAPSHOTS_FILE" "$NOW"

  echo "output: $output"
  assert_success
  assert_output "mail@ntran:/data/my mail last snapshot 48h ago (limit 26h)"
}

@test "check_stale_backups -- stale source sends one mail listing it" {
  write_stale_config ""
  write_snapshots \
    "mail@ntran|/data/mail|2026-01-01T00:00:00Z|" \
    "nico@laptop|/data/docs|$(date -u +%Y-%m-%dT%H:%M:%SZ)|"
  create_kopia_snapshot_mock
  export SMTP_USER="sender@test.com" SMTP_PASS="secret"

  run check_stale_backups

  echo "output: $output"
  echo "curl calls:"; cat "${BATS_TEST_TMPDIR}/curl.calls" 2>/dev/null || true
  assert_success
  assert_output --partial "Stale check: stale sources found:"
  assert_output --partial "mail@ntran:/data/mail last snapshot"
  assert_mock_called_times "curl" 1
  assert_mock_called "curl" "--mail-rcpt admin@test.com"
}

@test "check_stale_backups -- all fresh sends no mail" {
  write_stale_config ""
  local now_iso
  now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  write_snapshots "mail@ntran|/data/mail|${now_iso}|" "nico@laptop|/data/docs|${now_iso}|"
  create_kopia_snapshot_mock

  run check_stale_backups

  echo "output: $output"
  assert_success
  assert_output "Stale check: all sources within their limit"
  assert_mock_not_called "curl"
}

@test "check_stale_backups -- kopia failure sends a mail and returns 1" {
  write_stale_config ""
  create_kopia_mock "snapshot list"
  export SMTP_USER="sender@test.com" SMTP_PASS="secret"

  run check_stale_backups

  echo "output: $output"
  assert_failure
  assert_output --partial "ERROR: stale check could not list snapshots"
  assert_mock_called "curl" "--mail-rcpt admin@test.com"
}

@test "run_stale_checks -- waits the startup delay, then checks daily" {
  write_stale_config ""
  local now_iso
  now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  write_snapshots "mail@ntran|/data/mail|${now_iso}|" "nico@laptop|/data/docs|${now_iso}|"
  create_kopia_snapshot_mock
  # sleep succeeds twice, then fails to end the loop.
  cat > "${MOCK_BIN}/sleep" <<SCRIPT
#!/bin/bash
echo "\$*" >> "${BATS_TEST_TMPDIR}/sleep.calls"
[ "\$(wc -l < "${BATS_TEST_TMPDIR}/sleep.calls")" -le 2 ]
SCRIPT
  chmod +x "${MOCK_BIN}/sleep"

  run run_stale_checks

  echo "output: $output"
  echo "sleep calls:"; cat "${BATS_TEST_TMPDIR}/sleep.calls"
  assert_success
  run cat "${BATS_TEST_TMPDIR}/sleep.calls"
  assert_line --index 0 "$STALE_CHECK_STARTUP_DELAY_SECONDS"
  assert_line --index 1 "$STALE_CHECK_INTERVAL_SECONDS"
  assert_line --index 2 "$STALE_CHECK_INTERVAL_SECONDS"
  assert_mock_called_times "kopia" 2
}

@test "run_stale_checks -- a failing check does not stop the loop" {
  write_stale_config ""
  create_kopia_mock "snapshot list"
  cat > "${MOCK_BIN}/sleep" <<SCRIPT
#!/bin/bash
echo "\$*" >> "${BATS_TEST_TMPDIR}/sleep.calls"
[ "\$(wc -l < "${BATS_TEST_TMPDIR}/sleep.calls")" -le 2 ]
SCRIPT
  chmod +x "${MOCK_BIN}/sleep"

  run run_stale_checks

  echo "output: $output"
  assert_success
  assert_mock_called_times "kopia" 2
}
