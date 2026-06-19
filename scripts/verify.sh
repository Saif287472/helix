#!/usr/bin/env bash
set -euo pipefail

step() {
  echo
  echo "==> $1"
}

run_step() {
  local name="$1"
  shift
  step "$name"
  local start
  start=$(date +%s)
  "$@"
  local end
  end=$(date +%s)
  echo "<== ${name} completed in $((end - start))s"
}

HELIX_VERIFY_BUILD="${HELIX_VERIFY_BUILD:-0}"
HELIX_VERIFY_BUILD_ONLY="${HELIX_VERIFY_BUILD_ONLY:-0}"
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

build_only_enabled() {
  case "${HELIX_VERIFY_BUILD_ONLY}" in
    1|true|TRUE|yes|YES) return 0 ;;
  esac
  return 1
}

if ! build_only_enabled; then
run_step "Dart format check" dart format --output=none --set-exit-if-changed apps packages services tool

run_step "Flutter analyze" flutter analyze "${flutter_pub_args[@]}"

run_step "Dart analyze (backend and tooling)" dart analyze services/helix_remote_backend tool

run_step "Architecture boundary check" dart run tool/check_boundaries.dart

run_step "Forbidden import tests + cycle detection (P4-010/P4-015)" dart test tool/boundary_test.dart

run_step "Phase 0 guardrail tests" dart test tool/secret_scan_test.dart tool/dependency_policy_test.dart tool/documentation_consistency_test.dart tool/risk_coverage_test.dart

run_step "Phase 20 release/governance audit" dart test tool/phase20_release_governance_test.dart

run_step "Dependency graph (P4-014)" dart run tool/dep_graph.dart

run_step "Secret scan" dart run tool/check_secrets.dart

run_step "Release hardening checks (P7)" dart run tool/check_release_hardening.dart

run_step "SBOM/license inventory check (P7)" dart run tool/generate_local_sbom.dart --check-only

run_step "Flutter tests (helix_local)" bash -c 'cd apps/helix_local && flutter test "$@"' _ "${flutter_pub_args[@]}"

run_step "Flutter tests (helix_remote)" bash -c 'cd apps/helix_remote && flutter test "$@"' _ "${flutter_pub_args[@]}"

for pkg in packages/local/*/ packages/shared/*/ packages/remote/*/; do
  [ -d "$pkg" ] || continue
  if [ -d "${pkg}test" ]; then
    if grep -q 'flutter:$\|sdk: flutter' "${pkg}pubspec.yaml" 2>/dev/null; then
      run_step "Tests: ${pkg%/}" bash -c 'cd "$1" && flutter test "${@:2}"' _ "$pkg" "${flutter_pub_args[@]}"
    else
      run_step "Tests: ${pkg%/}" bash -c 'cd "$1" && dart test' _ "$pkg"
    fi
  fi
done

run_step "Tests: services/helix_remote_backend" bash -c 'cd services/helix_remote_backend && dart test'

step "Dependency health advisory"
if dependency_advisory_enabled; then
  flutter pub outdated
else
  echo "Skipped for local verification. Set HELIX_DEPENDENCY_ADVISORY=1 to run flutter pub outdated."
fi
else
  echo ""
  echo "==> Build-only verification"
  echo "Skipping format, analyze, dependency, and test gates because HELIX_VERIFY_BUILD_ONLY=1."
fi

if [[ "${HELIX_VERIFY_BUILD}" == "1" ]]; then
  run_step "Debug build: helix_local (Windows)" bash -c 'cd apps/helix_local && flutter build windows --debug "$@"' _ "${flutter_pub_args[@]}"

  run_step "Debug build: helix_local (Android APK)" bash -c 'cd apps/helix_local && flutter build apk --debug "$@"' _ "${flutter_pub_args[@]}"

  run_step "Debug build: helix_remote (Windows)" bash -c 'cd apps/helix_remote && flutter build windows --debug "$@"' _ "${flutter_pub_args[@]}"

  run_step "Debug build: helix_remote (Android APK)" bash -c 'cd apps/helix_remote && flutter build apk --debug "$@"' _ "${flutter_pub_args[@]}"

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
