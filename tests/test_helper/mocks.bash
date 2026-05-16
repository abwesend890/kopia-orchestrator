create_mock() {
  local name="$1"
  cat > "${MOCK_BIN}/${name}" <<'SCRIPT'
#!/bin/bash
echo "$@" >> "${BATS_TEST_TMPDIR}/MOCK_NAME.calls"
SCRIPT
  sed -i "s/MOCK_NAME/${name}/g" "${MOCK_BIN}/${name}"
  chmod +x "${MOCK_BIN}/${name}"
}

create_mock_with_output() {
  local name="$1"
  local output="$2"
  local exit_code="${3:-0}"
  cat > "${MOCK_BIN}/${name}" <<SCRIPT
#!/bin/bash
echo "\$@" >> "${BATS_TEST_TMPDIR}/${name}.calls"
echo "${output}"
exit ${exit_code}
SCRIPT
  chmod +x "${MOCK_BIN}/${name}"
}

create_kopia_mock() {
  local fail_on="${1:-}"
  cat > "${MOCK_BIN}/kopia" <<SCRIPT
#!/bin/bash
echo "\$*" >> "${BATS_TEST_TMPDIR}/kopia.calls"
if [ -n "${fail_on}" ] && echo "\$*" | grep -qF "${fail_on}"; then
  exit 1
fi
exit 0
SCRIPT
  chmod +x "${MOCK_BIN}/kopia"
}

create_kopia_mock_multi() {
  cat > "${MOCK_BIN}/kopia" <<'SCRIPT'
#!/bin/bash
echo "$*" >> "${BATS_TEST_TMPDIR}/kopia.calls"
if [ -f "${BATS_TEST_TMPDIR}/kopia.fail_patterns" ]; then
  while IFS= read -r pattern; do
    if echo "$*" | grep -qF "$pattern"; then
      exit 1
    fi
  done < "${BATS_TEST_TMPDIR}/kopia.fail_patterns"
fi
exit 0
SCRIPT
  chmod +x "${MOCK_BIN}/kopia"
}

kopia_fail_on() {
  echo "$1" >> "${BATS_TEST_TMPDIR}/kopia.fail_patterns"
}

assert_mock_called() {
  local name="$1"
  local pattern="$2"
  local calls_file="${BATS_TEST_TMPDIR}/${name}.calls"
  [ -f "$calls_file" ] || fail "${name} was never called"
  grep -qF -- "$pattern" "$calls_file" || fail "${name} was not called with '${pattern}'. Calls:\n$(cat "$calls_file")"
}

assert_mock_not_called() {
  local name="$1"
  local calls_file="${BATS_TEST_TMPDIR}/${name}.calls"
  [ ! -f "$calls_file" ] || [ ! -s "$calls_file" ] || fail "${name} was called but should not have been. Calls:\n$(cat "$calls_file")"
}

assert_mock_called_times() {
  local name="$1"
  local expected="$2"
  local calls_file="${BATS_TEST_TMPDIR}/${name}.calls"
  if [ ! -f "$calls_file" ]; then
    [ "$expected" -eq 0 ] || fail "${name} was never called (expected ${expected} times)"
    return
  fi
  local actual
  actual=$(wc -l < "$calls_file")
  [ "$actual" -eq "$expected" ] || fail "${name} called ${actual} times, expected ${expected}. Calls:\n$(cat "$calls_file")"
}
