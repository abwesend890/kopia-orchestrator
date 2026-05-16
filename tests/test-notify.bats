setup() {
  load test_helper/common
  load test_helper/mocks
  setup_mocks
  create_mock "curl"
  create_mock_with_output "hostname" "test-host"
  TEST_NOTIFY="${PROJECT_ROOT}/test-notify.sh"
}

@test "--help shows usage" {
  run bash "$TEST_NOTIFY" --help

  assert_success
  assert_output --partial "SMTP notification smoke test"
  assert_output --partial "docker exec"
}

@test "missing config file -- exits 1" {
  export CONFIG_FILE="${BATS_TEST_TMPDIR}/nonexistent.yml"

  run bash "$TEST_NOTIFY"

  assert_failure
  assert_output --partial "FAIL"
  assert_output --partial "config not found"
}

@test "no notifications section -- exits 1" {
  write_config "$(cat <<'YAML'
server:
  url: https://backup.test.com
YAML
)"

  run bash "$TEST_NOTIFY"

  assert_failure
  assert_output --partial "FAIL"
  assert_output --partial "no notifications.email section"
}

@test "missing smtp credentials env var -- exits 1" {
  write_config "$(cat <<'YAML'
notifications:
  email:
    to:
      - admin@test.com
    smtp_host: mail.test.com
    smtp_port: 587
    username_env: SMTP_USER
    password_env: SMTP_PASS
YAML
)"
  unset SMTP_USER 2>/dev/null || true
  unset SMTP_PASS 2>/dev/null || true

  run bash "$TEST_NOTIFY"

  assert_failure
  assert_output --partial "FAIL"
  assert_output --partial "SMTP_USER"
}

@test "empty recipients list -- exits 1" {
  write_config "$(cat <<'YAML'
notifications:
  email:
    to: []
    smtp_host: mail.test.com
    smtp_port: 587
    username_env: SMTP_USER
    password_env: SMTP_PASS
YAML
)"
  export SMTP_USER="sender@test.com"
  export SMTP_PASS="secret"

  run bash "$TEST_NOTIFY"

  assert_failure
  assert_output --partial "FAIL"
  assert_output --partial "no recipients"
}

@test "valid config -- sends test email to first recipient only" {
  write_config "$(cat <<'YAML'
notifications:
  email:
    to:
      - admin@test.com
      - oncall@test.com
    smtp_host: mail.test.com
    smtp_port: 587
    username_env: SMTP_USER
    password_env: SMTP_PASS
YAML
)"
  export SMTP_USER="sender@test.com"
  export SMTP_PASS="secret"

  run bash "$TEST_NOTIFY"

  assert_success
  assert_output --partial "PASS"
  assert_output --partial "first of 2"
  assert_mock_called "curl" "--mail-rcpt admin@test.com"
  # only first recipient, not second
  local calls_file="${BATS_TEST_TMPDIR}/curl.calls"
  run grep -c "oncall" "$calls_file"
  assert_output "0"
}

@test "port 587 -- curl called with smtp protocol and ssl-reqd" {
  write_config "$(cat <<'YAML'
notifications:
  email:
    to:
      - admin@test.com
    smtp_host: mail.test.com
    smtp_port: 587
    username_env: SMTP_USER
    password_env: SMTP_PASS
YAML
)"
  export SMTP_USER="sender@test.com"
  export SMTP_PASS="secret"

  run bash "$TEST_NOTIFY"

  assert_success
  assert_mock_called "curl" "--verbose"
  assert_mock_called "curl" "--ssl-reqd"
  assert_mock_called "curl" "smtp://mail.test.com:587"
}

@test "port 465 -- curl called with smtps protocol, no ssl-reqd" {
  write_config "$(cat <<'YAML'
notifications:
  email:
    to:
      - admin@test.com
    smtp_host: mail.test.com
    smtp_port: 465
    username_env: SMTP_USER
    password_env: SMTP_PASS
YAML
)"
  export SMTP_USER="sender@test.com"
  export SMTP_PASS="secret"

  run bash "$TEST_NOTIFY"

  assert_success
  assert_mock_called "curl" "--verbose"
  assert_mock_called "curl" "smtps://mail.test.com:465"
  local calls_file="${BATS_TEST_TMPDIR}/curl.calls"
  run grep -c "ssl-reqd" "$calls_file"
  assert_output "0"
}

@test "curl failure -- reports FAIL with exit code" {
  create_mock_with_output "curl" "connection refused" 7
  write_config "$(cat <<'YAML'
notifications:
  email:
    to:
      - admin@test.com
    smtp_host: mail.test.com
    smtp_port: 587
    username_env: SMTP_USER
    password_env: SMTP_PASS
YAML
)"
  export SMTP_USER="sender@test.com"
  export SMTP_PASS="secret"

  run bash "$TEST_NOTIFY"

  assert_failure
  assert_output --partial "FAIL"
  assert_output --partial "could not connect"
}
