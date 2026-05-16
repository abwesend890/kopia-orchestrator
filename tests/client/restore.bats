setup() {
  load ../test_helper/common
  load ../test_helper/mocks
  setup_mocks
  create_kopia_mock
  RESTORE="${PROJECT_ROOT}/client/restore.sh"
}

@test "no args -- exits 1 with usage" {
  run bash "$RESTORE"

  assert_failure
  assert_output --partial "Usage"
}

@test "list -- calls kopia snapshot list" {
  run bash "$RESTORE" list

  assert_success
  assert_mock_called "kopia" "snapshot list"
}

@test "list with path -- passes path to kopia" {
  run bash "$RESTORE" list /data/app

  assert_success
  assert_mock_called "kopia" "snapshot list /data/app"
}

@test "restore with id and target -- calls kopia restore" {
  run bash "$RESTORE" restore abc123 /tmp/restore

  assert_success
  assert_mock_called "kopia" "restore abc123 /tmp/restore"
}

@test "restore missing target -- exits 1" {
  run bash "$RESTORE" restore abc123

  assert_failure
  assert_output --partial "restore requires snapshot ID and target path"
}

@test "unknown subcommand -- exits 1 with usage" {
  run bash "$RESTORE" unknown

  assert_failure
  assert_output --partial "Usage"
}
