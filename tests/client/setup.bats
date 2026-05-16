setup() {
  load ../test_helper/common
  load ../test_helper/mocks
  setup_mocks
  create_kopia_mock
  create_mock_with_output "hostname" "test-host"
  create_mock "curl"
  export NOTIFY_SH="${PROJECT_ROOT}/client/notify.sh"
  SETUP="${PROJECT_ROOT}/client/setup.sh"
}

@test "simple path with service retention" {
  write_config "$(cat <<'YAML'
services:
  - name: myapp
    retention:
      keep_daily: 7
      keep_weekly: 4
    paths:
      - /data/myapp
YAML
)"

  run bash "$SETUP"

  assert_success
  assert_mock_called "kopia" "policy set /data/myapp --keep-daily 7 --keep-weekly 4"
  assert_mock_called "kopia" "snapshot create /data/myapp"
}

@test "object path overrides service retention" {
  write_config "$(cat <<'YAML'
services:
  - name: myapp
    retention:
      keep_daily: 7
      keep_weekly: 4
    paths:
      - path: /data/config
        retention:
          keep_daily: 30
YAML
)"

  run bash "$SETUP"

  assert_success
  assert_mock_called "kopia" "policy set /data/config --keep-daily 30 --keep-weekly 4"
}

@test "partial path override -- only keep_daily overridden" {
  write_config "$(cat <<'YAML'
services:
  - name: myapp
    retention:
      keep_daily: 7
      keep_weekly: 4
      keep_monthly: 12
    paths:
      - path: /data/config
        retention:
          keep_daily: 30
YAML
)"

  run bash "$SETUP"

  assert_success
  assert_mock_called "kopia" "policy set /data/config --keep-daily 30 --keep-weekly 4 --keep-monthly 12"
}

@test "global schedule times applied via --snapshot-time" {
  write_config "$(cat <<'YAML'
schedule:
  times:
    - "03:00"
services:
  - name: myapp
    retention:
      keep_daily: 7
    paths:
      - /data/myapp
YAML
)"

  run bash "$SETUP"

  assert_success
  assert_mock_called "kopia" "--snapshot-time 03:00"
}

@test "service schedule overrides global" {
  write_config "$(cat <<'YAML'
schedule:
  times:
    - "03:00"
services:
  - name: myapp
    schedule:
      times:
        - "02:00"
        - "14:00"
    retention:
      keep_daily: 7
    paths:
      - /data/myapp
YAML
)"

  run bash "$SETUP"

  assert_success
  assert_mock_called "kopia" "--snapshot-time 02:00"
  assert_mock_called "kopia" "--snapshot-time 14:00"
  # global time should NOT appear
  run grep -c "03:00" "${BATS_TEST_TMPDIR}/kopia.calls"
  assert_output "0"
}

@test "mode=stop injects before/after actions" {
  write_config "$(cat <<'YAML'
services:
  - name: myapp
    container: myapp-container
    mode: stop
    retention:
      keep_daily: 7
    paths:
      - /data/myapp
YAML
)"

  run bash "$SETUP"

  assert_success
  assert_mock_called "kopia" "--before-snapshot-root-action docker stop myapp-container"
  assert_mock_called "kopia" "--after-snapshot-root-action docker start myapp-container"
}

@test "no container -- mode forced to live, no actions" {
  write_config "$(cat <<'YAML'
services:
  - name: myapp
    mode: stop
    retention:
      keep_daily: 7
    paths:
      - /data/myapp
YAML
)"

  run bash "$SETUP"

  assert_success
  run grep -c "before-snapshot" "${BATS_TEST_TMPDIR}/kopia.calls"
  assert_output "0"
}

@test "policy set failure triggers notification" {
  create_kopia_mock "policy set"
  write_config "$(cat <<'YAML'
notifications:
  email:
    to:
      - admin@test.com
    smtp_host: mail.test.com
    smtp_port: 587
    username_env: SMTP_USER
    password_env: SMTP_PASS
services:
  - name: myapp
    retention:
      keep_daily: 7
    paths:
      - /data/myapp
YAML
)"
  export SMTP_USER="sender@test.com"
  export SMTP_PASS="secret"

  run bash "$SETUP"

  assert_mock_called "curl" "--mail-rcpt admin@test.com"
}

@test "snapshot create failure triggers notification" {
  create_kopia_mock "snapshot create"
  write_config "$(cat <<'YAML'
notifications:
  email:
    to:
      - admin@test.com
    smtp_host: mail.test.com
    smtp_port: 587
    username_env: SMTP_USER
    password_env: SMTP_PASS
services:
  - name: myapp
    retention:
      keep_daily: 7
    paths:
      - /data/myapp
YAML
)"
  export SMTP_USER="sender@test.com"
  export SMTP_PASS="secret"

  run bash "$SETUP"

  assert_mock_called "curl" "--mail-rcpt admin@test.com"
}

@test "multiple services all processed" {
  write_config "$(cat <<'YAML'
services:
  - name: app1
    retention:
      keep_daily: 7
    paths:
      - /data/app1
  - name: app2
    retention:
      keep_daily: 3
    paths:
      - /data/app2
YAML
)"

  run bash "$SETUP"

  assert_success
  assert_mock_called "kopia" "policy set /data/app1"
  assert_mock_called "kopia" "snapshot create /data/app1"
  assert_mock_called "kopia" "policy set /data/app2"
  assert_mock_called "kopia" "snapshot create /data/app2"
  assert_mock_called_times "kopia" 4
}
