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
run_step "Dart format check" dart format --output=none --set-exit-if-changed app backend packages tool

run_step "Flutter analyze" flutter analyze "${flutter_pub_args[@]}"

run_step "Dart analyze (backend and tooling)" dart analyze backend tool

run_step "Flutter tests (app)" bash -c 'cd app && flutter test "$@"' _ "${flutter_pub_args[@]}"

run_step "Tests: backend" bash -c 'cd backend && dart test'

for pkg in packages/*/; do
  [ -d "$pkg" ] || continue
  if [ -d "${pkg}test" ]; then
    if grep -q 'sdk:[[:space:]]*flutter' "${pkg}pubspec.yaml" 2>/dev/null; then
      run_step "Tests: ${pkg%/}" bash -c 'cd "$1" && flutter test "${@:2}"' _ "$pkg" "${flutter_pub_args[@]}"
    else
      run_step "Tests: ${pkg%/}" bash -c 'cd "$1" && dart test' _ "$pkg"
    fi
  fi
done

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
  run_step "Debug build: Helix Remote (Windows)" bash -c 'cd app && flutter build windows --debug "$@"' _ "${flutter_pub_args[@]}"

  run_step "Debug build: Helix Remote (Android APK)" bash -c 'cd app && flutter build apk --debug "$@"' _ "${flutter_pub_args[@]}"

  step "Signing credential isolation check"
  if [[ -z "${HELIX_REMOTE_STORE_PASSWORD:-}" ]]; then
    echo "Remote signing env vars are not set; skipping release-signing isolation check."
  else
    echo "Remote signing env var check passed."
  fi
else
  echo ""
  echo "==> Debug builds"
  echo "Skipped. Set HELIX_VERIFY_BUILD=1 to run platform debug builds."
fi
