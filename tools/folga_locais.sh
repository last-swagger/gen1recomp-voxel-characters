#!/bin/bash
# Measures how much SLACK is left against LuaJIT's ceiling of 200 chunk locals.
#
# WHY THIS IS A GATE AND NOT A NOTE. Blowing LUAI_MAXVARS is a COMPILATION
# error: the whole mod stops loading, for everyone, and the symptom is not a
# broken feature, it is the game without the mod. This file already reached
# 199 of 200 once (see main.lua:52) and only escaped it through a refactor.
#
# The measurement is empirical on purpose: counting `local` in the text gets
# scope, multi-assignment and in-block declaration wrong. Here we APPEND chunk
# locals until LuaJIT refuses, and the answer is the real number.
#
# Usage: bash mods/voxel_characters/tools/folga_locais.sh [floor]
set -u
ALVO="${VC_MAIN:-mods/voxel_characters/main.lua}"
PISO="${1:-15}"
command -v luajit >/dev/null || { echo "luajit not found"; exit 1; }
[ -f "$ALVO" ] || { echo "could not find $ALVO (run from the repo root)"; exit 1; }

T=$(mktemp -t vcfolga) || exit 1
trap 'rm -f "$T"' EXIT

cabe() {
  python3 - "$ALVO" "$T" "$1" <<'PY'
import sys
alvo, saida, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
s = open(alvo).read()
open(saida, "w").write(s + "\n" +
  "\n".join("local __folga%d = %d" % (i, i) for i in range(n)) + "\n")
PY
  luajit -bl "$T" /dev/null >/dev/null 2>&1
}

cabe 0 || { echo "SLACK 0: $ALVO already DOES NOT COMPILE"; exit 1; }

lo=0; hi=1
while cabe "$hi"; do lo=$hi; hi=$((hi * 2)); [ "$hi" -gt 512 ] && break; done
while [ $((hi - lo)) -gt 1 ]; do
  mid=$(((lo + hi) / 2))
  if cabe "$mid"; then lo=$mid; else hi=$mid; fi
done

echo "slack: $lo chunk locals (LuaJIT ceiling: 200, so $((200 - lo)) in use)"
if [ "$lo" -lt "$PISO" ]; then
  echo "BELOW THE FLOOR of $PISO. Do not add chunk state without refactoring:"
  echo "  the pattern already used here is a description TABLE plus generic"
  echo "  functions, instead of a handful of locals per feature (main.lua:52)."
  exit 1
fi
echo "OK"
