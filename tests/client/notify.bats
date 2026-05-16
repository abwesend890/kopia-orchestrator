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
