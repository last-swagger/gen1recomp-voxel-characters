#!/bin/bash
# THE GEN 2 WALK GATE: can this harness put the player somewhere in Gold and
# make it walk, with the mod attached while it does?
#
#   bash mods/voxel_characters/tools/ingame/gold.sh
#
# The same pinning, pointed at the other generation, which is how the adapter's
# Gen 1 half gets proved by the same instrument rather than by a second one:
#
#   VC_VERSION=blue VC_HOST=DRAMATIC_SHAPE \
#     VC_MAP=REDS_HOUSE_2F VC_X=4 VC_Y=4 \
#     bash mods/voxel_characters/tools/ingame/gold.sh
#
# WHY THIS EXISTS. tools/ingame/hosts.sh proves the mod ATTACHES on Gold. That
# is the first sentence and not the paragraph: every other probe in this
# directory measures pixels, and every one of them takes for granted a landing
# layer that only Gen 1 has. Until the player can be put on a named cell and
# driven, nothing else can be pointed at Gen 2 at all -- and worse, pointing
# them there would not fail loudly. Measured 2026-08-17 with the old path:
# `U.teleport` returns success on Gold having pushed a Gen 1 state onto Gold's
# stack, the world then reads a non-empty stack as "a menu is open", and the
# player freezes. A pixel probe would have photographed that and measured it.
#
# WHAT IT PINS, AND WHY EVERY ONE OF THEM.
#
#   * THE MOD SET. Only voxel_characters and the Gen 2 voxel host are left
#     enabled; every other mod installed on the machine is written out as
#     false. This is not tidiness. The first Gold run of this gate was made
#     with the machine's ordinary set and the walk came out at TWO cells per
#     step in 17 frames, with the walk back overshooting by one: another mod
#     installed here wraps Gold's World.step and the world was stepping more
#     than once per frame. The gate was measuring the neighbours;
#   * THE GAME. POKEPORT_VERSION=gold, which is the only variable the scripted
#     boot reads (main.lua:304); POKEPORT_GAME is a dead letter under
#     POKEPORT_DRIVER;
#   * THE LANDING. Handed to the driver as VC_MAP/VC_X/VC_Y, because the driver
#     refuses to invent one. PLAYERS_HOUSE_2F 3,3 is where a New Game starts
#     (engine/menus/intro_menu.asm NewGame, SPAWN_HOME) and it is the one Gold
#     room this side of the front door with nobody in it, which is the same
#     reason tools/ingame/probe_walk.lua stands in REDS_HOUSE_2F on Gen 1.
#
# THE SAVE IS RESTORED BYTE FOR BYTE, the way tools/ingame/hosts.sh does it and
# for the same reason: options.lua is the player's file and this script has to
# write the enabled-mod list to do its job. The restore runs on every exit path
# including Ctrl-C, and it is verified by sha256; a compare that fails says so
# loudly instead of exiting green.
#
# THE MOD IS FORCED ONTO GEN 2 RATHER THAN CLAIMING IT. Our manifest still says
# games: ["gen1"], so the loader gates the mod out of a Gen 2 boot. The
# player's own TRY HERE ANYWAY override (options.modsGen2) forces it on for one
# boot and marks it "not verified by its author", which is exactly what is true
# today. Widening the manifest instead would make this gate pass by assertion:
# the claim that the mod runs on Gold is the thing being measured, so it cannot
# also be the input.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$AQUI/../../../.." && pwd)"
SAVE="$HOME/Library/Application Support/LOVE/pokemon-love2d"
OPTIONS="$SAVE/options.lua"
. "$(cd "$AQUI/.." && pwd)/tools_bin.sh"

DRIVER="${VC_DRIVER:-$AQUI/probe_world.lua}"
HOST="${VC_HOST:-STADIUM2_OVERWORLD_MODELS}"
JOGO="${VC_VERSION:-gold}"
MAPA="${VC_MAP:-PLAYERS_HOUSE_2F}"
CX="${VC_X:-3}"
CY="${VC_Y:-3}"

[ -f "$DRIVER" ] || { echo "driver not found: $DRIVER"; exit 1; }
[ -f "$OPTIONS" ] || { echo "no options.lua at $OPTIONS"; exit 1; }
[ -f "$SAVE/$JOGO/rom-cache.complete" ] || {
  echo "$JOGO is not imported on this machine (no $SAVE/$JOGO/rom-cache.complete)."
  echo "  The scripted boot would fall into the ROM importer and the driver"
  echo "  would never be created: an empty log that reads like a hang."
  exit 1
}

# The LOVE lock before anything else, for the reason tools_bin.sh gives: this
# script opens with pkill, so without it a run here silently kills a ruler or a
# matrix already in flight and the victim's truncated output reads as a short
# measurement rather than an interrupted one. Reentrant, so the battery calling
# this while already holding the lock is fine.
vc_trava_pega "gold.sh" || exit 1

TMP="$(mktemp -d)"
BACKUP="$TMP/options.lua.original"
cp "$OPTIONS" "$BACKUP"
ANTES="$(shasum -a 256 < "$BACKUP" | cut -d' ' -f1)"

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
# BOTH cleanups on one trap, deliberately: vc_trava_pega installs its own
# `trap ... EXIT INT TERM` for the lock, and a second trap on the same signals
# REPLACES the first rather than adding to it.
trap 'restaura; vc_trava_solta' EXIT INT TERM

# EVERY MOD INSTALLED HERE, from its own manifest rather than from a list in
# this file: a list would go stale the first time somebody installs something,
# and a mod this script does not know about is a mod it cannot switch off. Only
# `false` disables a mod (src/mods/Loader.lua:156), so an id nobody wrote out
# is an id that is ENABLED.
CONHECIDOS="$(python3 - "$REPO" "$SAVE" <<'PY'
import glob, json, os, sys
ids = set()
for base in sys.argv[1:3]:
    for f in glob.glob(os.path.join(base, "mods", "*", "manifest.json")):
        try:
            mid = json.load(open(f, encoding="utf-8")).get("id")
        except Exception:
            mid = None
        if mid:
            ids.add(mid)
print(" ".join(sorted(ids)))
PY
)"
[ -n "${CONHECIDOS// /}" ] || { echo "no installed mod manifest found"; exit 1; }
echo "mods answered for: $CONHECIDOS"
echo "left enabled:      voxel_characters $HOST"

python3 "$AQUI/seleciona.py" "$OPTIONS" "voxel_characters $HOST" \
  "$CONHECIDOS" "$JOGO" || { echo "could not write the selection"; exit 1; }

pkill -x love 2>/dev/null
for _ in $(seq 1 20); do pgrep -x love >/dev/null 2>&1 || break; sleep 0.5; done

LOG="$TMP/gold.log"
cd "$REPO" || exit 1
VC_MAP="$MAPA" VC_X="$CX" VC_Y="$CY" \
  POKEPORT_VERSION="$JOGO" POKEPORT_DRIVER="$DRIVER" "$LOVE" "$REPO" \
  > "$LOG" 2>&1 &
PID=$!
for _ in $(seq 1 "${VC_TIMEOUT:-180}"); do
  pgrep -x love >/dev/null 2>&1 || break
  sleep 1
done
kill -9 "$PID" 2>/dev/null
pkill -x love 2>/dev/null

echo
grep -E '^\[world\]|^LOVE ERROR' "$LOG" || true
echo

# THE VERDICT IS COUNTED FROM BOTH SIDES, the way the battery counts the Gen 1
# probes. Zero FAILED is not enough: a boot that never reached the driver
# prints nothing at all, and "no FAILED" would read that as a pass. There has
# to be at least one PASSED as well, or the honest answer is "no measurement".
NFAILED=$(grep -cE '\bFAILED\b' "$LOG")
NPASSED=$(grep -cE '\bPASSED\b' "$LOG")
if [ "$NPASSED" -eq 0 ]; then
  echo "WALK GATE on $JOGO: NO VERDICT (the driver measured nothing)"
  # Copied OUT of $TMP before saying where it is: the restore trap deletes
  # $TMP on the way out, so a message pointing into it sends the reader to a
  # path that no longer exists by the time they read it.
  cp "$LOG" "${VC_LOG:-/tmp/vc_gold.log}" 2>/dev/null
  echo "  full log at ${VC_LOG:-/tmp/vc_gold.log}"
  exit 1
fi
if [ "$NFAILED" -gt 0 ]; then
  echo "WALK GATE on $JOGO FAILED: $NFAILED check(s) of $((NPASSED + NFAILED))"
  cp "$LOG" "${VC_LOG:-/tmp/vc_gold.log}" 2>/dev/null
  echo "  full log at ${VC_LOG:-/tmp/vc_gold.log}"
  exit 1
fi
echo "WALK GATE on $JOGO OK: $NPASSED check(s), $MAPA $CX,$CY"
