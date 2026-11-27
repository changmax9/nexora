#!/usr/bin/env bash
set -euo pipefail

# Exercise the real installer in a disposable repository. The only curl on its
# PATH copies a local fixture, so these tests cannot download or replace a core
# in the checkout running this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_SOURCE="$SCRIPT_DIR/install_mihomo_core.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/nexora-installer-tests.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
FIXTURE_DIR="$TEST_ROOT/fixtures"
FAKE_BIN="$TEST_ROOT/bin"
TEST_VERSION="v0.0.9"
mkdir -p "$FIXTURE_DIR" "$FAKE_BIN"

fail() {
  echo "FAIL: $*" >&2
  if [[ -f "${CASE_ROOT:-}/installer.log" ]]; then
    cat "$CASE_ROOT/installer.log" >&2
  fi
  exit 1
}

cat >"$FAKE_BIN/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
destination=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)
      destination="$2"
      shift 2
      ;;
    *) shift ;;
  esac
done
[[ -n "$destination" && -f "$MIHOMO_INSTALLER_TEST_DOWNLOAD_FIXTURE" ]]
/bin/cp "$MIHOMO_INSTALLER_TEST_DOWNLOAD_FIXTURE" "$destination"
SH
chmod +x "$FAKE_BIN/curl"

cat >"$FIXTURE_DIR/valid-core" <<'SH'
#!/usr/bin/env bash
[[ "${1:-}" == -v ]] || exit 9
printf '%s\n' 'Mihomo Meta v0.0.9 darwin fixture'
SH
cat >"$FIXTURE_DIR/wrong-version-core" <<'SH'
#!/usr/bin/env bash
[[ "${1:-}" == -v ]] || exit 9
printf '%s\n' 'Mihomo Meta v0.0.8 darwin fixture'
SH
gzip -c "$FIXTURE_DIR/valid-core" >"$FIXTURE_DIR/valid.gz"
gzip -c "$FIXTURE_DIR/wrong-version-core" >"$FIXTURE_DIR/wrong-version.gz"
printf '%s\n' 'This has a matching checksum but is not a gzip stream.' >"$FIXTURE_DIR/corrupt.gz"

fixture_digest() {
  shasum -a 256 "$1" | awk '{print $1}'
}

prepare_case() {
  CASE_ROOT="$TEST_ROOT/$1"
  mkdir -p "$CASE_ROOT/script" "$CASE_ROOT/core"
  cp "$INSTALLER_SOURCE" "$CASE_ROOT/script/install_mihomo_core.sh"
  printf '%s\n' 'original core sentinel' >"$CASE_ROOT/core/mihomo"
  chmod +x "$CASE_ROOT/core/mihomo"
  cp "$CASE_ROOT/core/mihomo" "$CASE_ROOT/expected-original"
  # Retain the previous inode as well as its expected bytes. Successful installs
  # must rename a new inode into place instead of truncating the existing one.
  ln "$CASE_ROOT/core/mihomo" "$CASE_ROOT/previous-core"
}

run_installer() {
  PATH="$FAKE_BIN:$PATH" \
  MIHOMO_VERSION="$TEST_VERSION" \
  MIHOMO_SHA256="$2" \
  MIHOMO_INSTALLER_TEST_DOWNLOAD_FIXTURE="$1" \
    /bin/bash "$CASE_ROOT/script/install_mihomo_core.sh" >"$CASE_ROOT/installer.log" 2>&1
}

assert_output_contains() {
  [[ "$(cat "$CASE_ROOT/installer.log")" == *"$1"* ]] \
    || fail "installer output did not contain: $1"
}

assert_staging_removed() {
  local leftover
  for leftover in "$CASE_ROOT/core"/.mihomo-install.*; do
    [[ ! -e "$leftover" ]] || fail "staging directory was not cleaned up"
  done
}

assert_original_preserved() {
  cmp -s "$CASE_ROOT/expected-original" "$CASE_ROOT/core/mihomo" \
    || fail "failed installation changed the original core"
  [[ "$CASE_ROOT/core/mihomo" -ef "$CASE_ROOT/previous-core" ]] \
    || fail "failed installation replaced the original inode"
  [[ -x "$CASE_ROOT/core/mihomo" ]] \
    || fail "failed installation removed the original executable permission"
  assert_staging_removed
}

prepare_case checksum-mismatch
if run_installer "$FIXTURE_DIR/valid.gz" "0000000000000000000000000000000000000000000000000000000000000000"; then
  fail "checksum mismatch was accepted"
fi
assert_output_contains ': FAILED'
assert_original_preserved
echo 'PASS: checksum mismatch preserves the original core'

prepare_case corrupt-gzip
if run_installer "$FIXTURE_DIR/corrupt.gz" "$(fixture_digest "$FIXTURE_DIR/corrupt.gz")"; then
  fail "matching-hash corrupt gzip was accepted"
fi
assert_output_contains ': OK'
assert_original_preserved
echo 'PASS: matching-hash corrupt gzip preserves the original core'

prepare_case wrong-version
if run_installer "$FIXTURE_DIR/wrong-version.gz" "$(fixture_digest "$FIXTURE_DIR/wrong-version.gz")"; then
  fail "wrong core version was accepted"
fi
assert_output_contains ': OK'
assert_output_contains "did not report the requested version $TEST_VERSION"
assert_original_preserved
echo 'PASS: matching-hash wrong version preserves the original core'

prepare_case valid-install
run_installer "$FIXTURE_DIR/valid.gz" "$(fixture_digest "$FIXTURE_DIR/valid.gz")" \
  || fail "valid core was rejected"
cmp -s "$FIXTURE_DIR/valid-core" "$CASE_ROOT/core/mihomo" \
  || fail "valid core was not installed"
cmp -s "$CASE_ROOT/expected-original" "$CASE_ROOT/previous-core" \
  || fail "successful installation modified the original inode"
[[ ! "$CASE_ROOT/core/mihomo" -ef "$CASE_ROOT/previous-core" ]] \
  || fail "successful installation overwrote the original core in place"
[[ -x "$CASE_ROOT/core/mihomo" ]] || fail "installed core is not executable"
assert_output_contains "Mihomo Meta $TEST_VERSION "
assert_staging_removed
echo 'PASS: valid core atomically replaces the original core'
echo 'Mihomo installer: all 4 offline regression cases passed.'
