#!/usr/bin/env bash
set -euo pipefail

step() {
  echo
  echo "==> $1"
}

HELIX_VERIFY_BUILD="${HELIX_VERIFY_BUILD:-0}"
HELIX_DEPENDENCY_ADVISORY="${HELIX_DEPENDENCY_ADVISORY:-}"
CI="${CI:-}"

dependency_advisory_enabled() {
  case "${HELIX_DEPENDENCY_ADVISORY}" in
    1|true|TRUE|yes|YES) return 0 ;;
  esac

  case "${CI}" in
    1|true|TRUE|yes|YES) return 0 ;;
  esac

  return 1
}

flutter_pub_args=()
if ! dependency_advisory_enabled; then
  flutter_pub_args=(--no-pub)
fi

step "Dart format check"
dart format --output=none --set-exit-if-changed apps packages tool

step "Flutter analyze"
flutter analyze "${flutter_pub_args[@]}"

step "Architecture boundary check"
dart run tool/check_boundaries.dart

step "Forbidden import tests + cycle detection (P4-010/P4-015)"
dart test tool/boundary_test.dart

step "Dependency graph (P4-014)"
dart run tool/dep_graph.dart

step "Secret scan"
dart run tool/check_secrets.dart

step "Release hardening checks (P7)"
dart run tool/check_release_hardening.dart

step "SBOM/license inventory check (P7)"
dart run tool/generate_local_sbom.dart --check-only

step "Flutter tests (helix_local)"
(cd apps/helix_local && flutter test "${flutter_pub_args[@]}")

step "Flutter tests (helix_remote)"
(cd apps/helix_remote && flutter test "${flutter_pub_args[@]}")

for pkg in packages/local/*/ packages/shared/*/ packages/remote/*/; do
  [ -d "$pkg" ] || continue
  if [ -d "${pkg}test" ]; then
    step "Tests: ${pkg%/}"
    if grep -q 'flutter:$\|sdk: flutter' "${pkg}pubspec.yaml" 2>/dev/null; then
      (cd "$pkg" && flutter test "${flutter_pub_args[@]}")
    else
      (cd "$pkg" && dart test)
    fi
  fi
done

step "Tests: services/helix_remote_backend"
(cd services/helix_remote_backend && dart test)

step "Dependency health advisory"
if dependency_advisory_enabled; then
  flutter pub outdated
else
  echo "Skipped for local verification. Set HELIX_DEPENDENCY_ADVISORY=1 to run flutter pub outdated."
fi

if [[ "${HELIX_VERIFY_BUILD}" == "1" ]]; then
  step "Debug build: helix_local (Windows)"
  (cd apps/helix_local && flutter build windows --debug "${flutter_pub_args[@]}")

  step "Debug build: helix_local (Android APK)"
  (cd apps/helix_local && flutter build apk --debug "${flutter_pub_args[@]}")

  step "Debug build: helix_remote (Windows)"
  (cd apps/helix_remote && flutter build windows --debug "${flutter_pub_args[@]}")

  step "Debug build: helix_remote (Android APK)"
  (cd apps/helix_remote && flutter build apk --debug "${flutter_pub_args[@]}")

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
