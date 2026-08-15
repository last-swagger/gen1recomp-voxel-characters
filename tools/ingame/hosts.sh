#!/bin/bash
# THE HOST MATRIX GATE: does this mod attach to every voxel host installed on
# this machine, one at a time?
#
# WHY THIS EXISTS, AND IT IS THE WHOLE POINT.
#
# 1.8.0 shipped with 669 green checks and was broken for a large part of the
# people who installed it. Every gate this project owns -- the offline suite,
# the render harness, the in-game probes -- runs against the ONE voxel host
# that happens to be enabled on the machine doing the measuring, which here is
# always DRAMATIC_SHAPE. The mod attached to it perfectly. It also:
#
#   * refused DRAMALESS_SHAPE 2.0.x, which had just removed lib/ImageCache.lua
#     in its 2026-08-13 cleanup (Pikon, BYRAX);
#   * refused potato_voxel, which never had one -- while listing it in HOSTS
#     as a supported host, added in that same release (setogabes).
#
# Neither shows up in a suite that mocks the host, because a mock has whatever
# the mod asks for. The only thing that could have caught it is booting the
# real game against the real hosts, which is what this does.
#
# Usage:
#   tools/ingame/hosts.sh              # every host installed here
#   tools/ingame/hosts.sh DRAMALESS_SHAPE potato_voxel
#
# Prints one row per host and exits non-zero if any installed host fails to
# attach. Roughly 20s per host.
#
# THE SAVE IS RESTORED BYTE FOR BYTE. options.lua is copied before the first
# run and copied back on exit, including on Ctrl-C and on failure, because
# this script has to write the enabled-mod list to do its job and that file is
# the player's. Verified by sha256 at the end; if the compare ever fails the
# script says so loudly rather than leaving it and exiting green.

set -u
REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
SAVE="$HOME/Library/Application Support/LOVE/pokemon-love2d"
OPTIONS="$SAVE/options.lua"
. "$(cd "$(dirname "$0")/.." && pwd)/tools_bin.sh"

DRIVER="$REPO/mods/voxel_characters/tools/ingame/probe_hosts.lua"
[ -f "$DRIVER" ] || { echo "driver not found: $DRIVER"; exit 1; }
[ -f "$OPTIONS" ] || { echo "no options.lua at $OPTIONS"; exit 1; }

TMP="$(mktemp -d)"
BACKUP="$TMP/options.lua.original"
cp "$OPTIONS" "$BACKUP"
ANTES="$(shasum -a 256 < "$BACKUP" | cut -d' ' -f1)"

# THE RESTORE RUNS ON EVERY EXIT PATH, including the interrupt. Without the
# trap a Ctrl-C in the middle of the matrix leaves the player booting into
# whichever host the loop happened to be on.
restaura() {
  cp "$BACKUP" "$OPTIONS"
  local depois
  depois="$(shasum -a 256 < "$OPTIONS" | cut -d' ' -f1)"
  if [ "$ANTES" != "$depois" ]; then
    echo "!! options.lua was NOT restored cleanly; the original is at $BACKUP" >&2
    return 1
  fi
  echo "options.lua restored (sha256 $ANTES)"
  rm -rf "$TMP"
}
trap 'restaura' EXIT INT TERM

# Which hosts exist here at all: every manifest under the repo's mods/ and the
# save's mods/ whose id is one this mod knows how to attach to.
CONHECIDOS="potato_voxel BATTLE_ART_VOXEL_FORK DRAMALESS_SHAPE DRAMATIC_SHAPE"
instalado() {
  local id="$1" f
  for f in "$REPO"/mods/*/manifest.json "$SAVE"/mods/*/manifest.json; do
    [ -f "$f" ] || continue
    grep -q "\"id\"[[:space:]]*:[[:space:]]*\"$id\"" "$f" && return 0
  done
  return 1
}

ALVOS="${*:-}"
if [ -z "$ALVOS" ]; then
  for h in $CONHECIDOS; do instalado "$h" && ALVOS="$ALVOS $h"; done
fi
[ -n "${ALVOS// /}" ] || { echo "no known voxel host installed"; exit 1; }

# Only `false` disables a mod (src/mods/Loader.lua:156): a host merely left out
# of the list counts as ENABLED, so every host we are not testing has to be
# written out as false explicitly. Getting this wrong makes the matrix measure
# the wrong host and still look like it worked.
seleciona() {
  python3 - "$OPTIONS" "$1" "$CONHECIDOS" <<'PY'
import re, sys
path, want, known = sys.argv[1], sys.argv[2], sys.argv[3].split()
src = open(path, encoding="utf-8").read()
m = re.search(r"\n  mods = \{\n(.*?)\n  \},\n", src, re.S)
if not m:
    sys.exit("could not find the mods block in options.lua")
entries = {}
for line in m.group(1).split("\n"):
    em = re.match(r"\s*([\w_]+) = (true|false),\s*$", line)
    if em:
        entries[em.group(1)] = em.group(2)
for h in known:
    entries[h] = "false"
entries[want] = "true"
body = "\n".join("    %s = %s," % (k, v) for k, v in sorted(entries.items()))
open(path, "w", encoding="utf-8").write(
    src[:m.start()] + "\n  mods = {\n" + body + "\n  },\n" + src[m.end():])
PY
}

VERSAO="${VC_VERSION:-blue}"
FALHAS=0
echo
printf '%-24s %-10s %-9s %-7s %-7s %s\n' HOST VERSION ATTACHED DRAW ATLAS NOTE
printf '%-24s %-10s %-9s %-7s %-7s %s\n' ------------------------ ---------- --------- ------- ------- ----

for h in $ALVOS; do
  seleciona "$h" || { echo "could not select $h"; FALHAS=$((FALHAS + 1)); continue; }
  pkill -x love 2>/dev/null
  for _ in $(seq 1 20); do pgrep -x love >/dev/null 2>&1 || break; sleep 0.5; done
  rm -f "$SAVE/vc_hosts.txt"
  LOG="$TMP/$h.log"
  POKEPORT_VERSION="$VERSAO" POKEPORT_DRIVER="$DRIVER" "$LOVE" "$REPO" \
    > "$LOG" 2>&1 &
  PID=$!
  for _ in $(seq 1 "${VC_TIMEOUT:-90}"); do
    pgrep -x love >/dev/null 2>&1 || break
    sleep 1
  done
  kill -9 "$PID" 2>/dev/null
  pkill -x love 2>/dev/null

  SAIDA="$SAVE/vc_hosts.txt"
  if [ ! -f "$SAIDA" ]; then
    printf '%-24s %-10s %-9s %-7s %-7s %s\n' "$h" "?" "NO RUN" "-" "-" "the probe wrote nothing; see $LOG"
    FALHAS=$((FALHAS + 1))
    continue
  fi
  LINHA="$(grep '^ATTACH ' "$SAIDA" | head -1)"
  HOSTVER="$(grep "^HOST $h " "$SAIDA" | sed -n 's/.*version=\([^ ]*\).*/\1/p')"
  ATTACHED="$(printf '%s' "$LINHA" | sed -n 's/.*patched=\([^ ]*\).*/\1/p')"
  DRAW="$(printf '%s' "$LINHA" | sed -n 's/.*draw=\([^ ]*\).*/\1/p')"
  ATLAS="$(printf '%s' "$LINHA" | sed -n 's/.*atlas=\([^ ]*\).*/\1/p')"
  NOTA="$(grep '^ATTACH why=' "$SAIDA" | sed 's/^ATTACH why=//' | head -1)"
  if [ "$ATTACHED" = "true" ]; then
    printf '%-24s %-10s %-9s %-7s %-7s %s\n' "$h" "${HOSTVER:-?}" OK "${DRAW:--}" "${ATLAS:--}" ""
  else
    printf '%-24s %-10s %-9s %-7s %-7s %s\n' "$h" "${HOSTVER:-?}" FAILED "${DRAW:--}" "${ATLAS:--}" "${NOTA:-no attach}"
    FALHAS=$((FALHAS + 1))
  fi
done

echo
if [ "$FALHAS" -gt 0 ]; then
  echo "HOST MATRIX FAILED: $FALHAS host(s) did not attach"
  exit 1
fi
echo "HOST MATRIX OK"
