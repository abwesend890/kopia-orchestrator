setup() {
  load ../test_helper/common
  load ../test_helper/mocks
  setup_mocks
  create_kopia_mock
  create_mock_with_output "hostname" "test-host"
  create_mock "curl"
  create_mock "inotifywait"
  export REPO_PATH="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$REPO_PATH"
  export KOPIA_VIRTUAL_HOST="backup.test.com"
  export NOTIFY_SH="${PROJECT_ROOT}/server/notify.sh"
  ENTRYPOINT="${PROJECT_ROOT}/server/entrypoint.sh"
}

write_server_config() {
  write_config "$(cat <<YAML
ui:
  enabled: false
clients:
  - username: testuser
    hostname: testhost
    password_env: CLIENT_PASS
$1
YAML
)"
}

@test "new repo -- repository create called" {
  write_server_config ""
  export CLIENT_PASS="secret"

  run bash "$ENTRYPOINT"

  assert_success
  assert_mock_called "kopia" "repository create filesystem --path ${REPO_PATH}"
}

@test "existing repo -- repository connect called" {
  touch "${REPO_PATH}/kopia.repository.f"
  write_server_config ""
  export CLIENT_PASS="secret"

  run bash "$ENTRYPOINT"

  assert_success
  assert_mock_called "kopia" "repository connect filesystem --path ${REPO_PATH}"
}

@test "repo create failure -- notification sent, exits 1" {
  create_kopia_mock "repository create"
  write_config "$(cat <<'YAML'
ui:
  enabled: false
clients: []
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

  run bash "$ENTRYPOINT"

  assert_failure
  assert_mock_called "curl" "--mail-rcpt admin@test.com"
}

@test "client add succeeds -- user set not called" {
  write_server_config ""
  export CLIENT_PASS="secret"

  run bash "$ENTRYPOINT"

  assert_success
  assert_mock_called "kopia" "server user add testuser@testhost --user-password secret"
}

@test "client add and set both fail -- notification sent" {
  create_kopia_mock_multi
  kopia_fail_on "server user add"
  kopia_fail_on "server user set"
  write_config "$(cat <<'YAML'
ui:
  enabled: false
clients:
  - username: testuser
    hostname: testhost
    password_env: CLIENT_PASS
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
  export CLIENT_PASS="secret"
  export SMTP_USER="sender@test.com"
  export SMTP_PASS="secret"

  run bash "$ENTRYPOINT"

  assert_mock_called "curl" "--mail-rcpt admin@test.com"
}

@test "missing client password -- skipped with warning" {
  write_server_config ""
  unset CLIENT_PASS 2>/dev/null || true

  run bash "$ENTRYPOINT"

  assert_success
  assert_output --partial "WARNING"
  assert_output --partial "skipping"
}

@test "TLS certs present -- tls flags in server args" {
  write_server_config ""
  export CLIENT_PASS="secret"
  export CERT_DIR="${BATS_TEST_TMPDIR}/certs"
  mkdir -p "${CERT_DIR}/backup.test.com"
  touch "${CERT_DIR}/backup.test.com/fullchain.pem"
  touch "${CERT_DIR}/backup.test.com/key.pem"

  run bash "$ENTRYPOINT"

  assert_success
  assert_mock_called "kopia" "--tls-cert-file"
  assert_mock_called "kopia" "--tls-key-file"
}

@test "no TLS certs -- falls back to insecure" {
  write_server_config ""
  export CLIENT_PASS="secret"

  run bash "$ENTRYPOINT"

  assert_success
  assert_mock_called "kopia" "--insecure"
}

@test "UI disabled -- no-ui flag" {
  write_server_config ""
  export CLIENT_PASS="secret"

  run bash "$ENTRYPOINT"

  assert_success
  assert_mock_called "kopia" "--no-ui"
}

@test "UI enabled with password" {
  write_config "$(cat <<'YAML'
ui:
  enabled: true
  username: admin
  password_env: UI_PASS
clients:
  - username: testuser
    hostname: testhost
    password_env: CLIENT_PASS
YAML
)"
  export CLIENT_PASS="secret"
  export UI_PASS="uisecret"

  run bash "$ENTRYPOINT"

  assert_success
  assert_mock_called "kopia" "--server-control-username admin --server-control-password uisecret"
}
