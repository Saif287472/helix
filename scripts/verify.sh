#!/usr/bin/env bash
set -euo pipefail

step() {
  echo
  echo "==> $1"
}

HELIX_VERIFY_BUILD="${HELIX_VERIFY_BUILD:-0}"

step "Dart format check"
dart format --output=none --set-exit-if-changed apps packages tool

step "Flutter analyze"
flutter analyze

step "Architecture boundary check"
dart run tool/check_boundaries.dart

step "Secret scan"
dart run tool/check_secrets.dart

step "Flutter tests (helix_local)"
(cd apps/helix_local && flutter test)

step "Flutter tests (helix_remote)"
(cd apps/helix_remote && flutter test)

for pkg in packages/*/; do
  if [ -d "${pkg}test" ]; then
    step "Tests: ${pkg}"
    # Run as flutter test if the package has a flutter dependency, otherwise dart test.
    if grep -q 'flutter:$\|sdk: flutter' "${pkg}pubspec.yaml" 2>/dev/null; then
      (cd "$pkg" && flutter test)
    else
      (cd "$pkg" && dart test)
    fi
  fi
done

step "Dependency health advisory"
flutter pub outdated

if [[ "${HELIX_VERIFY_BUILD}" == "1" ]]; then
  step "Debug build: helix_local (Windows)"
  (cd apps/helix_local && flutter build windows --debug)

  step "Debug build: helix_local (Android APK)"
  (cd apps/helix_local && flutter build apk --debug)

  step "Debug build: helix_remote (Windows)"
  (cd apps/helix_remote && flutter build windows --debug)

  step "Debug build: helix_remote (Android APK)"
  (cd apps/helix_remote && flutter build apk --debug)

  # Signing safety: each product must use product-scoped env vars
  step "Signing credential isolation check"
  local_pass="${HELIX_LOCAL_STORE_PASSWORD:-}"
  remote_pass="${HELIX_REMOTE_STORE_PASSWORD:-}"
  if [[ -n "${local_pass}" && "${local_pass}" == "${remote_pass}" ]]; then
    echo "ERROR: HELIX_LOCAL_STORE_PASSWORD and HELIX_REMOTE_STORE_PASSWORD must differ."
    exit 1
  fi
  echo "Signing env var check passed (passwords differ or not set)."
else
  echo ""
  echo "==> Debug builds"
  echo "Skipped. Set HELIX_VERIFY_BUILD=1 to run all four platform debug builds."
fi
