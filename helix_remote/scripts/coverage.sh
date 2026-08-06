#!/usr/bin/env bash
# Collects line coverage for Helix Remote and prints a single percentage.
#
# The initial ratchet is deliberately conservative. It is a release gate, not
# a report: raise it as new suites land, but never lower it to accommodate a
# regression.
#
# Scope is helix_remote only. helix_local is a separate product with its own
# arrangements and is deliberately untouched here.
set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR="coverage"
MIN_LINE_COVERAGE="${MIN_LINE_COVERAGE:-20}"
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
  (cd "$dir" && flutter test --no-pub --coverage)

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
coverage="$(awk -F: '
  /^LF:/ { found += $2 }
  /^LH:/ { hit   += $2 }
  END {
    if (found == 0) { exit 2 }
    printf "%.2f", (hit/found)*100
  }
')" || { echo "No lines instrumented."; exit 1; }

echo
echo "Helix Remote line coverage: ${coverage}% (minimum: ${MIN_LINE_COVERAGE}%)"
awk -v actual="$coverage" -v minimum="$MIN_LINE_COVERAGE" 'BEGIN {
  if (actual + 0 < minimum + 0) {
    printf "Coverage gate failed: %.2f%% is below %.2f%%\n", actual, minimum
    exit 1
  }
}'

echo
echo "Note: the backend is covered by 'dart test' in verify.sh, which does not"
echo "emit lcov; its ~411 tests are not represented in the number above."
