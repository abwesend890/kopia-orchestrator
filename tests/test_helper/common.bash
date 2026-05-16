PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

load "${PROJECT_ROOT}/tests/libs/bats-support/load"
load "${PROJECT_ROOT}/tests/libs/bats-assert/load"

MOCK_BIN="${BATS_TEST_TMPDIR}/bin"

setup_mocks() {
  mkdir -p "$MOCK_BIN"
  export PATH="${MOCK_BIN}:${PATH}"
}

write_config() {
  local config_path="${BATS_TEST_TMPDIR}/config.yml"
  printf '%s\n' "$1" > "$config_path"
  export CONFIG_FILE="$config_path"
}
