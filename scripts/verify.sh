#!/usr/bin/env bash
set -euo pipefail

step() {
  echo
  echo "==> $1"
}

step "Dart format check"
dart format --output=none --set-exit-if-changed lib test tool

step "Flutter analyze"
flutter analyze

step "Architecture boundary check"
dart run tool/check_boundaries.dart

step "Secret scan"
dart run tool/check_secrets.dart

step "Flutter tests"
flutter test

step "Dependency health advisory"
flutter pub outdated

step "Debug build"
if [[ "${HELIX_VERIFY_BUILD:-0}" == "1" ]]; then
  flutter build windows --debug
else
  echo "Skipped. Set HELIX_VERIFY_BUILD=1 to run flutter build windows --debug."
fi
