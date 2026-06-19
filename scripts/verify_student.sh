#!/usr/bin/env bash
set -euo pipefail

step() { echo "==> $*"; "$@"; }

step dart format --output=none --set-exit-if-changed apps packages tool
step flutter analyze --no-pub
step dart run tool/check_boundaries.dart
step dart test tool/boundary_test.dart
step dart run tool/check_secrets.dart
step flutter test --no-pub apps/helix_remote/test/
step flutter test --no-pub packages/remote/helix_remote_crypto/test/
step flutter test --no-pub packages/remote/helix_remote_calls/test/
step flutter test --no-pub packages/remote/helix_remote_groups/test/
step flutter test --no-pub packages/remote/helix_remote_storage/test/
step flutter test --no-pub packages/remote/helix_remote_sync/test/
step flutter test --no-pub packages/remote/helix_remote_api/test/
step dart test services/helix_remote_backend/test/
step flutter test --no-pub apps/helix_local/test/

echo "All student validation checks passed."
