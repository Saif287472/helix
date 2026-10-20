#!/usr/bin/env bash
# compare.sh key1 key2 ...: Part B's pixel check (orbit/HANDOFF.md).
#
# Shoots each key from this checkout's preview build and scores it against
# the prototype's shot: the share of pixels off by more than 16 levels. A
# port batch must leave every compared key at its Review 4 score
# (review4_scores.txt) unless the change is deliberate and in DEVIATIONS.md.
#
# Needs Windows (the preview's shoot mode is a Windows build), Python 3, and
# the prototype's shots in tools/compare/shots/reduce-motion (make them with
# ../shoot_html.py, see ../README.md; they are not committed).
#
#   NOBUILD=1   skip `flutter build windows --debug`
#   DEV=window-l or window-m   the wide window instead of the phone
#   SHOTS=dir   prototype shots somewhere else
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
FL="$(cd "$HERE/../../.." && pwd)" # orbit/flutter
H="${SHOTS:-$FL/tools/compare/shots/reduce-motion}"
DEV="${DEV:-phone}"
OUT="$FL/tools/compare/flutter"
mkdir -p "$OUT"
[ -n "${NOBUILD:-}" ] ||
  (cd "$FL/apps/orbit_preview" && flutter build windows --debug 2>&1 | grep -E "error|Error" | head -20)
exe="$FL/apps/orbit_preview/build/windows/x64/runner/Debug/orbit_preview.exe"
# The preview finds prototype/screens.json from here.
cd "$FL/tools/compare" || exit 1
keys=$(IFS=,; echo "$*")
dev=()
[ "$DEV" = phone ] || dev=(--device "$DEV")
"$exe" --shoot "$keys" --theme orbit "${dev[@]}" --reduce-motion --html "$H" \
  --out "$OUT" --report "$FL/tools/compare/report-orbit" 2>&1 |
  grep -E "threw|not shot|Exception|overflowed" || true
for k in "$@"; do
  score=$(python "$HERE/prof.py" "$H/$k.$DEV.orbit.png" "$OUT/$k.$DEV.orbit.png" 2>&1 | tail -1)
  ref=""
  [ "$DEV" = phone ] && ref=$(grep -E "^$k total" "$HERE/review4_scores.txt" | head -1 | sed 's/^[^ ]* //')
  echo "$k $score   (Review 4: ${ref:-none})"
done
