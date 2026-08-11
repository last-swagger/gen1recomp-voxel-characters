#!/bin/bash
# In-game gate for Voxel Characters: runs the real game, drives it by script
# and photographs it. Complements the offline harness (tools/render/), which
# is fast and measures geometry but loads the mod with the host MOCKED, so it
# never shows the real sun, the character against the world, the real screen
# scale, or movement.
#
# Usage:
#   tools/ingame/run.sh <output-folder> [key=value of the mod option]
#
# A/B example:
#   tools/ingame/run.sh /tmp/ab/off front_shape=off
#   tools/ingame/run.sh /tmp/ab/med front_shape=0.17
#
# Variables: VC_VERSION (red|blue|yellow), VC_MAP, VC_X, VC_Y, VC_FOTOS,
#            VC_DRIVER (another driver), LOVE_BIN.
#
# EVERY LOCK HERE CAME FROM A PAID ERROR. Do not remove any without reading it.

set -u
REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
SAVE="$HOME/Library/Application Support/LOVE/pokemon-love2d"
MARCADOR="$SAVE/relaunch_to_launcher.txt"
. "$(cd "$(dirname "$0")/.." && pwd)/tools_bin.sh"
DRIVER="${VC_DRIVER:-$REPO/mods/voxel_characters/tools/ingame/driver.lua}"

SAIDA="${1:?uso: run.sh <pasta-de-saida> [chave=valor]}"
OPCAO="${2:-}"

# TRAP 1: a previous process still alive makes the next one born unable to
# get anything. Killing is NOT instant; wait for it to actually die.
vc_trava_pega "run.sh" || exit 1
pkill -x love 2>/dev/null
for _ in $(seq 1 20); do
  pgrep -x love >/dev/null 2>&1 || break
  sleep 0.5
done

# TRAP 2, THE ONE THAT COST THE MOST: choosing the right VERSION.
#
# POKEPORT_GAME and POKEPORT_SLOT (which this script used to export) are dead
# letter under POKEPORT_DRIVER: they are only read in LaunchOptions.resolve
# (main.lua:359), after the `if scripted then ... return end` of main.lua:313.
# The version that boots comes from POKEPORT_VERSION (main.lua:304), default
# "red".
#
# And "red" is only ready when the source tree has ALL of
# RomImporter.REQUIRED_FILES (RomImporter.lua:52-68, 165-172, 250). On this
# machine two are missing, so the scripted boot fell into the importer and sat
# waiting for someone to drag in a ROM: the driver never even got created, and
# the symptom was ZERO photos with an EMPTY log, which looks like "stuck at
# the launcher" and is not. blue/yellow are ready via the cache in the save
# directory.
#
# So: detect instead of assume, and say out loud which version is going to boot.
versao_pronta() {
  case "$1" in
    red)
      local faltando=0
      for f in data/generated/constants.lua data/generated/maps.lua \
               data/generated/text.lua data/generated/field.lua \
               data/generated/battle_anims.lua \
               assets/generated/title/pokemon_logo.png \
               assets/generated/fonts/font.png \
               assets/generated/battle/front/pikachu.png \
               assets/generated/battle/anims/move_anim_0.png \
               assets/generated/battle/anims/move_anim_1.png \
               assets/generated/audio/programs.bin \
               assets/generated/trade/game_boy.png; do
        [ -e "$REPO/$f" ] || faltando=1
      done
      [ "$faltando" -eq 0 ]
      ;;
    *) [ -f "$SAVE/$1/rom-cache.complete" ] ;;
  esac
}

if [ -n "${VC_VERSION:-}" ]; then
  VERSAO="$VC_VERSION"
  versao_pronta "$VERSAO" || {
    echo "VC_VERSION=$VERSAO is not ready on this machine (no cache and no"
    echo "complete source tree). The game would fall into the importer and the"
    echo "driver would never be created."
    exit 1
  }
else
  VERSAO=""
  for v in blue red yellow; do
    if versao_pronta "$v"; then VERSAO="$v"; break; fi
  done
  [ -n "$VERSAO" ] || {
    echo "no version ready: neither cache in $SAVE nor complete source tree"
    exit 1
  }
fi
echo "version: $VERSAO"

# The marker only affects the --game / POKEPORT_GAME path, which is not ours.
# Deleting it stays cheap and avoids a surprise if someone runs without a driver.
rm -f "$MARCADOR" 2>/dev/null

rm -rf "$SAIDA" && mkdir -p "$SAIDA"
find "$SAVE" -maxdepth 1 -name 'vc_*.png' -delete 2>/dev/null
LOG="$SAIDA/run.log"

cd "$REPO" || exit 1
# TRAP 3: the driver path needs to exist. main.lua:233 does
# assert(loadfile(driverPath)), and a wrong path silently kills the boot.
[ -f "$DRIVER" ] || { echo "driver not found: $DRIVER"; exit 1; }

VC_OPT="$OPCAO" POKEPORT_VERSION="$VERSAO" POKEPORT_DRIVER="$DRIVER" \
  "$LOVE" . > "$LOG" 2>&1 &
PID=$!

# TRAP 4: the log used to come out EMPTY, because without a TTY the LOVE
# stdout goes into BLOCK buffering and a process that never exits never
# flushes. An empty log does not distinguish "nothing happened" from "did not
# finish", and I already drew the wrong conclusion from that. The driver now
# calls io.stdout:setvbuf("line"), so the log is reliable LIVE and the wait
# can watch the process instead of counting files.
#
# And the expected number comes from the driver ITSELF ("fim, N fotos"), not
# from a constant here: when I removed a photo from the driver, the constant
# 12 stayed put and the gate failed a run that had gone fine all the way to
# the end.
LIMITE="${VC_TIMEOUT:-180}"
for _ in $(seq 1 "$LIMITE"); do
  pgrep -x love >/dev/null 2>&1 || break
  sleep 1
done

kill -9 "$PID" 2>/dev/null
pkill -x love 2>/dev/null
rm -f "$MARCADOR" 2>/dev/null

ESPERADAS="${VC_FOTOS:-}"
if [ -z "$ESPERADAS" ]; then
  ESPERADAS=$(grep -oE 'end, [0-9]+ photos' "$LOG" 2>/dev/null | grep -oE '[0-9]+' | tail -1)
fi
if [ -z "$ESPERADAS" ]; then
  echo "GATE FAILED: the driver never reached the end"
  echo "  log at $LOG ($(wc -l < "$LOG" | tr -d ' ') lines), version $VERSAO"
  grep -E 'preso_fora_do_mundo|opcao_sem_efeito|driver error' "$LOG" 2>/dev/null | head -3
  exit 1
fi

N=$(find "$SAVE" -maxdepth 1 -name 'vc_*.png' 2>/dev/null | wc -l | tr -d ' ')
if [ "$N" -ge "$ESPERADAS" ]; then
  find "$SAVE" -maxdepth 1 -name 'vc_*.png' -exec cp {} "$SAIDA"/ \; 2>/dev/null
  find "$SAVE" -maxdepth 1 -name 'vc_*.png' -delete 2>/dev/null
  # THE CONTROL, and without it "GATE OK" only said the game opened. Counting
  # files does not measure anything about the mod: turning off the whole mod
  # produced the same number of photos and the same green.
  #
  # The threshold comes from the FLOOR measured in the same run, not from a
  # chosen fraction. With the mod deliberately neutralized, the difference
  # came out 175 of 87552 against a fixed threshold of 175: it passed by a
  # hair, by chance.
  CTRL=$(grep -oE 'control floor [0-9-]+, mod on against off [0-9-]+, of [0-9]+' "$LOG" | tail -1)
  PISO=$(echo "$CTRL" | sed -nE 's/.*floor (-?[0-9]+).*/\1/p')
  DIF=$(echo "$CTRL" | sed -nE 's/.*against (-?[0-9]+).*/\1/p')
  TOT=$(echo "$CTRL" | sed -nE 's/.*of ([0-9]+)$/\1/p')
  if [ -z "${DIF:-}" ] || [ -z "${TOT:-}" ] || [ -z "${PISO:-}" ]; then
    echo "GATE FAILED: the driver did not measure the control"
    exit 1
  fi
  if [ "$PISO" -lt 0 ] || [ "$DIF" -lt 0 ]; then
    echo "GATE FAILED: some capture of the control did not come out"
    exit 1
  fi
  MIN=$((PISO * 3 + 200))
  if [ "$DIF" -lt "$MIN" ]; then
    echo "GATE FAILED: with the mod on, the screen does not differ enough from"
    echo "  it off: $DIF against floor $PISO (minimum $MIN, of $TOT samples)."
    echo "  Either there is no character of ours in this scene, or the mod does nothing."
    exit 1
  fi
  echo "GATE OK: $N photos in $SAIDA, control $DIF against floor $PISO"
  if [ -n "$OPCAO" ]; then
    # TRAP 5: writing the option to the save without EMITTING the event
    # changes nothing, because the mesh is already cached. I produced an A/B
    # with images identical byte for byte and nearly presented it as a
    # comparison. The driver now aborts in that case; here we check that it
    # did not abort.
    if grep -q "evento emitido" "$LOG" 2>/dev/null; then
      echo "  option applied: $OPCAO"
    else
      echo "  WARNING: option $OPCAO was NOT applied; do not use these photos for A/B"
      exit 2
    fi
  fi
  exit 0
fi

echo "GATE FAILED: $N photos (expected $ESPERADAS)"
echo "  log at $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
echo "  version used: $VERSAO"
exit 1
