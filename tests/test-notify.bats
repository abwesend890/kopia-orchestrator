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
  assert_output --partial "Notification smoke test"
  assert_output --partial "docker exec"
}

@test "no config + no contact form -- exits 1" {
  export CONFIG_FILE="${BATS_TEST_TMPDIR}/nonexistent.yml"
  unset CONTACT_FORM_URL 2>/dev/null || true

  run bash "$TEST_NOTIFY"

  assert_failure
  assert_output --partial "FAIL"
  assert_output --partial "no notification method configured"
}

@test "no email section + no contact form -- exits 1" {
  write_config "$(cat <<'YAML'
server:
  url: https://backup.test.com
YAML
)"
  unset CONTACT_FORM_URL 2>/dev/null || true

  run bash "$TEST_NOTIFY"

  assert_failure
  assert_output --partial "FAIL"
  assert_output --partial "no notification method configured"
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

# --- contact form fallback in test-notify.sh ---

@test "no email config + CONTACT_FORM_URL -- sends test POST" {
  write_config "services: []"
  export CONTACT_FORM_URL="https://example.com/contact"
  export CONTACT_FORM_EMAIL="backup@test.com"
  export CONTACT_FORM_NAME="Backup Agent"

  run bash "$TEST_NOTIFY"

  assert_success
  assert_output --partial "PASS"
  assert_output --partial "contact form POST sent"
  assert_mock_called_times "curl" 1
  assert_mock_called "curl" "--data-urlencode email=backup@test.com"
  assert_mock_called "curl" "--data-urlencode name=Backup Agent"
  assert_mock_called "curl" "https://example.com/contact"
}

@test "contact form -- shows config in output" {
  write_config "services: []"
  export CONTACT_FORM_URL="https://example.com/contact"
  export CONTACT_FORM_EMAIL="backup@test.com"
  export CONTACT_FORM_NAME="Backup Agent"

  run bash "$TEST_NOTIFY"

  assert_success
  assert_output --partial "url:   https://example.com/contact"
  assert_output --partial "email: backup@test.com"
  assert_output --partial "name:  Backup Agent"
}

@test "contact form -- missing CONTACT_FORM_EMAIL -- exits 1" {
  write_config "services: []"
  export CONTACT_FORM_URL="https://example.com/contact"
  unset CONTACT_FORM_EMAIL 2>/dev/null || true
  export CONTACT_FORM_NAME="Backup Agent"

  run bash "$TEST_NOTIFY"

  assert_failure
  assert_output --partial "FAIL"
  assert_output --partial "CONTACT_FORM_EMAIL"
}

@test "contact form curl failure -- reports FAIL" {
  create_mock_with_output "curl" "connection refused" 7
  write_config "services: []"
  export CONTACT_FORM_URL="https://example.com/contact"
  export CONTACT_FORM_EMAIL="backup@test.com"
  export CONTACT_FORM_NAME="Backup Agent"

  run bash "$TEST_NOTIFY"

  assert_failure
  assert_output --partial "FAIL"
  assert_output --partial "could not connect"
}

@test "email config present + CONTACT_FORM_URL -- SMTP wins" {
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
  export CONTACT_FORM_URL="https://example.com/contact"
  export CONTACT_FORM_EMAIL="backup@test.com"
  export CONTACT_FORM_NAME="Backup Agent"

  run bash "$TEST_NOTIFY"

  assert_success
  assert_output --partial "PASS"
  assert_output --partial "test email sent"
  assert_mock_called "curl" "smtp://mail.test.com:587"
  local calls_file="${BATS_TEST_TMPDIR}/curl.calls"
  run grep -c "data-urlencode" "$calls_file"
  assert_output "0"
}
