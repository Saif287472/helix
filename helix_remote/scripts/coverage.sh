#!/usr/bin/env bash
# Collects line coverage for Helix Remote and prints a single percentage.
#
# Advisory by design: it reports, it does not gate. The point of Phase 0 is to
# establish a real baseline number so a threshold can be chosen from evidence
# rather than invented. Make it blocking once that number is known and stable.
#
# Scope is helix_remote only. helix_local is a separate product with its own
# arrangements and is deliberately untouched here.
set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR="coverage"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# Each suite writes its own lcov file, which are concatenated at the end.
# `flutter test --coverage` always writes to <package>/coverage/lcov.info, so
# the files are collected per package rather than redirected.
collect() {
  local dir="$1"
  local label="$2"
  [ -d "$dir" ] || return 0

  echo "==> coverage: ${label}"
  # A suite that fails must not abort the whole run - coverage is advisory,
  # and the test gate in verify.sh has already reported the real pass/fail.
  if ! (cd "$dir" && flutter test --no-pub --coverage) ; then
    echo "    (${label} tests failed; coverage for it is skipped)"
    return 0
  fi

  if [ -f "${dir}/coverage/lcov.info" ]; then
    cat "${dir}/coverage/lcov.info" >> "${OUT_DIR}/lcov.info"
  fi
}

collect app app
collect admin admin
for pkg in packages/*/; do
  [ -d "${pkg}test" ] || continue
  collect "${pkg%/}" "${pkg%/}"
done

if [ ! -f "${OUT_DIR}/lcov.info" ]; then
  echo "No coverage data produced."
  exit 0
fi

# LF = lines found, LH = lines hit. Summing the per-record totals across the
# concatenated files gives overall line coverage without needing lcov(1)
# installed on the runner.
awk -F: '
  /^LF:/ { found += $2 }
  /^LH:/ { hit   += $2 }
  END {
    if (found == 0) { print "No lines instrumented."; exit }
    printf "\nHelix Remote line coverage: %.2f%% (%d/%d lines)\n", (hit/found)*100, hit, found
  }
' "${OUT_DIR}/lcov.info"

echo
echo "Note: the backend is covered by 'dart test' in verify.sh, which does not"
echo "emit lcov; its ~411 tests are not represented in the number above."
