setup() {
  load ../test_helper/common
  load ../test_helper/mocks
  setup_mocks
  create_kopia_mock
  create_mock_with_output "hostname" "test-host"
  create_mock "curl"
  create_mock "inotifywait"
  export NOTIFY_SH="${PROJECT_ROOT}/client/notify.sh"
  export SETUP_SH="${MOCK_BIN}/setup_stub"
  create_mock "setup_stub"
  ENTRYPOINT="${PROJECT_ROOT}/client/entrypoint.sh"
}

@test "missing config file -- exits 1" {
  export CONFIG_FILE="${BATS_TEST_TMPDIR}/nonexistent.yml"

  run bash "$ENTRYPOINT"

  assert_failure
  assert_output --partial "config file not found"
}

@test "missing password env -- exits 1" {
  write_config "$(cat <<'YAML'
server:
  url: https://backup.test.com:51515
  username: testuser
  hostname: testhost
  password_env: KOPIA_PASSWORD
YAML
)"
  unset KOPIA_PASSWORD 2>/dev/null || true

  run bash "$ENTRYPOINT"

  assert_failure
  assert_output --partial "not set"
}

@test "connection failure -- notification sent, exits 1" {
  create_kopia_mock "repository connect"
  write_config "$(cat <<'YAML'
server:
  url: https://backup.test.com:51515
  username: testuser
  hostname: testhost
  password_env: KOPIA_PASSWORD
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
  export KOPIA_PASSWORD="secret"
  export SMTP_USER="sender@test.com"
  export SMTP_PASS="secret"

  run bash "$ENTRYPOINT"

  assert_failure
  assert_mock_called "curl" "--mail-rcpt admin@test.com"
}

@test "successful connection -- correct kopia args and setup called" {
  write_config "$(cat <<'YAML'
server:
  url: https://backup.test.com:51515
  username: testuser
  hostname: testhost
  password_env: KOPIA_PASSWORD
YAML
)"
  export KOPIA_PASSWORD="secret"

  run bash "$ENTRYPOINT"

  assert_success
  assert_mock_called "kopia" "repository connect server --url https://backup.test.com:51515 --override-username testuser --override-hostname testhost --password secret --enable-actions"
}
