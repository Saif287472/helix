#!/usr/bin/env bash
# Shoot one key on both sides in several themes and compare them.
#   orbit/flutter/tools/compare/compare_kit.sh <key> [theme ...]
# Needs the prototype serving on 5317 and the preview app built
# (flutter build windows --debug in apps/orbit_preview). Writes
# shots/reduce-motion/, flutter/ and report-<theme>/ beside this script.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
flutter_dir="$(cd "$here/../.." && pwd)"
key="$1"; shift
themes=("$@"); [ ${#themes[@]} -eq 0 ] && themes=(orbit night arcade papyrus)
exe="$flutter_dir/apps/orbit_preview/build/windows/x64/runner/Debug/orbit_preview.exe"
for t in "${themes[@]}"; do
  python "$here/shoot_html.py" --reduce-motion --theme "$t" ${SCROLL:+--scroll $SCROLL} --out "$here/shots/reduce-motion" "$key" | grep -E "\] (ok|FAIL)" || true
  "$exe" --shoot "$key" --theme "$t" --reduce-motion --html "$here/shots/reduce-motion" \
    ${SCROLL:+--scroll $SCROLL} --out "$here/flutter" --report "$here/report-$t" 2>&1 | grep -E "differ|failed|threw|not shot" || true
done
