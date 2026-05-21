setup() {
  load ../test_helper/common
  load ../test_helper/mocks
  setup_mocks
  create_mock "curl"
  create_mock_with_output "hostname" "test-host"
  export NOTIFY_SH="${PROJECT_ROOT}/client/notify.sh"
  source "$NOTIFY_SH"
}

@test "no notification section -- curl not called" {
  write_config "services: []"

  send_notification "test" "body"

  assert_mock_not_called "curl"
}

@test "email section is null -- curl not called" {
  write_config "$(cat <<'YAML'
notifications:
  email: null
YAML
)"

  send_notification "test" "body"

  assert_mock_not_called "curl"
}

@test "single recipient -- curl called once" {
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

  send_notification "Alert" "Something broke"

  assert_mock_called_times "curl" 1
  assert_mock_called "curl" "--mail-rcpt admin@test.com"
  assert_mock_called "curl" "smtp://mail.test.com:587"
  assert_mock_called "curl" "--user sender@test.com:secret"
}

@test "port 465 -- uses smtps protocol without ssl-reqd" {
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

  send_notification "Alert" "Something broke"

  assert_mock_called "curl" "smtps://mail.test.com:465"
  local calls_file="${BATS_TEST_TMPDIR}/curl.calls"
  run grep -c "ssl-reqd" "$calls_file"
  assert_output "0"
}

@test "port 587 -- uses smtp protocol with ssl-reqd" {
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

  send_notification "Alert" "Something broke"

  assert_mock_called "curl" "smtp://mail.test.com:587"
  assert_mock_called "curl" "--ssl-reqd"
}

@test "multiple recipients -- curl called per recipient" {
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

  send_notification "Alert" "Something broke"

  assert_mock_called_times "curl" 2
  assert_mock_called "curl" "--mail-rcpt admin@test.com"
  assert_mock_called "curl" "--mail-rcpt oncall@test.com"
}

# --- contact form POST fallback ---

@test "no email config + CONTACT_FORM_URL set -- uses POST" {
  write_config "services: []"
  export CONTACT_FORM_URL="https://example.com/contact"
  export CONTACT_FORM_EMAIL="backup@test.com"
  export CONTACT_FORM_NAME="Backup Agent"

  send_notification "Alert" "Something broke"

  assert_mock_called_times "curl" 1
  assert_mock_called "curl" "--data-urlencode email=backup@test.com"
  assert_mock_called "curl" "--data-urlencode name=Backup Agent"
  assert_mock_called "curl" "--data-urlencode message=Something broke"
  assert_mock_called "curl" "https://example.com/contact"
}

@test "contact form -- subject includes prefix" {
  write_config "services: []"
  export CONTACT_FORM_URL="https://example.com/contact"
  export CONTACT_FORM_EMAIL="backup@test.com"
  export CONTACT_FORM_NAME="Backup Agent"

  send_notification "Disk Full" "Something broke"

  assert_mock_called "curl" "--data-urlencode subject=[Backup] Disk Full"
}

@test "contact form -- missing CONTACT_FORM_EMAIL -- warns and skips" {
  write_config "services: []"
  export CONTACT_FORM_URL="https://example.com/contact"
  unset CONTACT_FORM_EMAIL 2>/dev/null || true
  export CONTACT_FORM_NAME="Backup Agent"

  run bash -c "source '$NOTIFY_SH' && send_notification 'Alert' 'body'"

  assert_mock_not_called "curl"
  assert_output --partial "WARNING"
  assert_output --partial "CONTACT_FORM_EMAIL"
}

@test "contact form -- CONTACT_FORM_URL not set -- curl not called" {
  write_config "services: []"
  unset CONTACT_FORM_URL 2>/dev/null || true
  unset CONTACT_FORM_EMAIL 2>/dev/null || true
  unset CONTACT_FORM_NAME 2>/dev/null || true

  send_notification "Alert" "body"

  assert_mock_not_called "curl"
}

@test "email config present -- contact form not used" {
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

  send_notification "Alert" "Something broke"

  assert_mock_called "curl" "smtp://mail.test.com:587"
  local calls_file="${BATS_TEST_TMPDIR}/curl.calls"
  run grep -c "data-urlencode" "$calls_file"
  assert_output "0"
}
