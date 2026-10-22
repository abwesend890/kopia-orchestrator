setup() {
  load test_helper/common
  load test_helper/mocks
  setup_mocks
  create_mock "ssh"
  SSH_CALLS="${BATS_TEST_TMPDIR}/ssh.calls"
}

# Runs from an empty directory so the developer's real .env is never read.
run_make() {
  run make --no-print-directory -C "$BATS_TEST_TMPDIR" -f "${PROJECT_ROOT}/Makefile" "$@"
}

@test "pull-clients -- runs git pull in each clone, in order" {
  run_make pull-clients CLIENT_HOSTS="root@mail.test:/opt/backup other.test:/root/tran-backup"

  echo "output: $output"
  echo "ssh calls:"; cat "$SSH_CALLS"
  assert_success
  run cat "$SSH_CALLS"
  assert_line --index 0 "root@mail.test git -C '/opt/backup' pull --ff-only"
  assert_line --index 1 "other.test git -C '/root/tran-backup' pull --ff-only"
  assert_equal "$(wc -l < "$SSH_CALLS")" 2
}

@test "pull-server -- pulls the clone on BACKUP_HOST only" {
  run_make pull-server BACKUP_HOST="root@backup.test:/opt/backup" CLIENT_HOSTS="client.test:/opt/backup"

  echo "output: $output"
  assert_success
  run cat "$SSH_CALLS"
  assert_output "root@backup.test git -C '/opt/backup' pull --ff-only"
}

@test "pull-all -- pulls server then clients" {
  run_make pull-all BACKUP_HOST="backup.test:/opt/backup" CLIENT_HOSTS="client.test:/srv/backup"

  echo "output: $output"
  assert_success
  run cat "$SSH_CALLS"
  assert_line --index 0 "backup.test git -C '/opt/backup' pull --ff-only"
  assert_line --index 1 "client.test git -C '/srv/backup' pull --ff-only"
}

@test "pull-clients -- stops at the first host that fails" {
  create_mock_with_output "ssh" "fatal: Not possible to fast-forward, aborting." 1

  run_make pull-clients CLIENT_HOSTS="first.test:/opt/backup second.test:/opt/backup"

  echo "output: $output"
  assert_failure
  assert_output --partial "→ first.test:/opt/backup"
  refute_output --partial "→ second.test:/opt/backup"
  run cat "$SSH_CALLS"
  assert_output "first.test git -C '/opt/backup' pull --ff-only"
}

@test "help -- works without a .env file" {
  run_make help

  echo "output: $output"
  assert_success
  assert_output --partial "pull-clients"
  refute_output --partial "push-"
}
