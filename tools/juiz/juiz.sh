#!/bin/bash
# THE JUDGE, end to end: reads the choices, measures the variants, and fits.
#
#   tools/juiz/juiz.sh                      uses the laboratory's escolhas.txt
#   tools/juiz/juiz.sh <file>               uses a different choices file
#
# Three steps, and each one lives where it needs to live:
#   1. luajit reads the choices and lists the unique variants
#   2. LOVE measures the features of each variant, because only it has a real
#      sprite and the mod loaded
#   3. luajit fits and prints the accuracy OUT of sample against the best
#      single column, which is the number that decides whether this is a
#      judge or decoration
#
# Before anything, the selftest: if the machinery cannot recover even a
# synthetic rule that exists, there is no point feeding it real choices, and
# Kim's time is the expensive input here.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$AQUI/../../../.." && pwd)"
. "$AQUI/../tools_bin.sh"
SAVE="$HOME/Library/Application Support/LOVE/render"

ESCOLHAS="${1:-$HOME/Library/Application Support/LOVE/render/escolhas.txt}"
[ -f "$ESCOLHAS" ] || {
  echo "no choices at $ESCOLHAS"
  echo "open the laboratory, press t, and choose a few times:"
  echo "  mods/voxel_characters/Laboratorio.command"
  exit 1
}

command -v luajit >/dev/null || { echo "luajit not found"; exit 1; }

echo "== machinery selftest"
luajit "$AQUI/ajusta.lua" --autoteste || exit 1

TMP="$(mktemp -d -t vcjuiz)" || exit 1
trap 'rm -rf "$TMP"' EXIT

echo ""
echo "== variants"
luajit "$AQUI/ajusta.lua" --estados "$ESCOLHAS" > "$TMP/estados.tsv" || exit 1

echo ""
echo "== features"
# Another of our tools running knocks this one down: run.sh, clip.sh and
# trailer.sh start with `pkill -x love`, because a previous LOVE still alive
# makes the next one start without getting anything. Warning beforehand is
# better than measuring half of it.
vc_trava_pega "juiz.sh" || exit 1
cd "$REPO" || exit 1
"$LOVE" mods/voxel_characters/tools/render features="$TMP/estados.tsv" \
  > "$TMP/features.tsv" 2>"$TMP/features.err"
# LOVE returns zero even when the script dies partway through, so counting
# lines is the only way to know it measured: a header plus one line per variant.
N=$(grep -cv '^#' "$TMP/features.tsv" 2>/dev/null || echo 0)
Q=$(wc -l < "$TMP/estados.tsv" | tr -d ' ')
echo "  $N of $Q variants measured"
if [ "$N" -lt "$Q" ]; then
  echo "  FAILED TO MEASURE. First lines of the error:"
  head -5 "$TMP/features.err" | sed 's/^/    /'
  [ "$N" -eq 0 ] && exit 1
fi

echo ""
echo "== fit"
luajit "$AQUI/ajusta.lua" --ajusta "$ESCOLHAS" "$TMP/features.tsv"
