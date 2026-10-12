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
# THE MATRIX HAS TWO AXES, host AND game, because a host is not portable
# between them. The Gen 1 lineages do not load on Gold and the Gen 2 lineage
# does not load on Blue, so "did not attach" and "cannot run here at all" are
# different answers and only the first one is a bug. A matrix that scored them
# the same would go red on every single run and stop being read, which is the
# ordinary way a gate dies. Rows that cannot run here print n/a and are not
# counted against the total.
#
# The inverse mistake is the dangerous one, so it is also guarded: a game with
# NO applicable host installed measured nothing at all, and that is a FAILURE
# rather than a quiet pass. Without that rule, deleting a host from HOSTS would
# turn its whole column green by making it empty.
#
# Usage:
#   tools/ingame/hosts.sh              # every host installed here, both games
#   tools/ingame/hosts.sh DRAMALESS_SHAPE potato_voxel
#   VC_VERSION=gold tools/ingame/hosts.sh     # one game only
#
# Prints one row per host per game and exits non-zero if any host that COULD
# have attached did not. Roughly 20s per row that actually boots.
#
# THE SAVE IS RESTORED BYTE FOR BYTE. options.lua is copied before the first
# run and copied back on exit, including on Ctrl-C and on failure, because
# this script has to write the enabled-mod list to do its job and that file is
# the player's. Verified by sha256 at the end; if the compare ever fails the
# script says so loudly rather than leaving it and exiting green.

set -u
AQUI="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$(dirname "$0")")"
MOD="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$AQUI/../..")"
REPO="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${VC_ENGINE_ROOT:-$MOD/../..}")"
SAVE="$HOME/Library/Application Support/LOVE/pokemon-love2d"
OPTIONS="$SAVE/options.lua"
. "$MOD/tools/tools_bin.sh"

DRIVER="$MOD/tools/ingame/probe_hosts.lua"
[ -f "$DRIVER" ] || { echo "driver not found: $DRIVER"; exit 1; }
[ -f "$OPTIONS" ] || { echo "no options.lua at $OPTIONS"; exit 1; }
LUAJIT="$(command -v luajit || true)"
[ -n "$LUAJIT" ] || { echo "luajit not found; cannot verify the imported cache"; exit 1; }

# THE LOVE LOCK, taken before anything else. This script opens with
# `pkill -x love` once per row, so without it a matrix run silently kills a
# ruler or a trailer already in flight and the truncated output of the victim
# reads as a short measurement rather than an interrupted one -- the precise
# failure tools_bin.sh was written for. Reentrant, so the battery calling this
# while already holding the lock is fine.
vc_trava_pega "hosts.sh" || exit 1

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
# BOTH cleanups on one trap, deliberately. vc_trava_pega installs its own
# `trap ... EXIT INT TERM` for the lock, and a second trap on the same signals
# REPLACES the first rather than adding to it -- so setting this one after
# taking the lock is what would otherwise drop the restore on the floor and
# leave the player booting into whichever host the loop happened to be on.
trap 'restaura; vc_trava_solta' EXIT INT TERM

# EVERY HOST THIS MOD CLAIMS, AND THE GAME EACH ONE RUNS ON. One entry per
# host, `id:game`. The game is not decoration: it is what tells the matrix
# which column a host belongs in, and therefore which absences are real.
#
# STADIUM2_OVERWORLD_MODELS is randyadr's Gen 2 lineage and its own manifest
# says games: ["gen2"], so Gold is the only place it can be asked the question.
# The five Gen 1 lineages are the reverse.
HOSTS="potato_voxel:blue
BATTLE_ART_VOXEL_FORK:blue
DRAMALESS_SHAPE:blue
DRAMATIC_SHAPE:blue
TERRARIUM:blue
STADIUM2_OVERWORLD_MODELS:gold"

hosts_ids() { printf '%s\n' "$HOSTS" | cut -d: -f1; }
# the game a host runs on, or empty if this id is not in the table at all
host_jogo() { printf '%s\n' "$HOSTS" | awk -F: -v h="$1" '$1 == h { print $2 }'; }

# Every id the matrix knows about, which is also every id `seleciona` has to
# write out as false. Derived from HOSTS so the two can never drift: a host
# added to the table above is automatically one the selector turns off.
CONHECIDOS="$(hosts_ids | tr '\n' ' ')"

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

# THE SELECTOR LIVES IN tools/ingame/seleciona.py, next to this file. It used
# to be a heredoc right here; it moved out whole -- every comment with it --
# when tools/ingame/gold.sh turned out to need exactly the same writer with a
# wider list of ids to answer for. Two traps are written down in there and both
# cost a red row to find: a mod is only disabled by an explicit `false`, and
# the per-game overlay options.modsByVersion outranks the shared `mods` block.
# A second copy of that code is a second place for either one to be forgotten.
seleciona() {
  python3 "$AQUI/seleciona.py" "$OPTIONS" "$1" "$CONHECIDOS" "$2"
}

# Both games by default, because covering only the one the machine happens to
# boot is the exact hole 1.8.0 shipped through. VC_VERSION still pins a single
# game for a quick run.
JOGOS="${VC_VERSION:-blue gold}"
# An explicit host list means the caller is asking about those hosts, so the
# games narrow to the ones those hosts actually live on -- otherwise
# `hosts.sh potato_voxel` would fail Gold for having nothing to measure there.
if [ -n "${*:-}" ] && [ -z "${VC_VERSION:-}" ]; then
  JOGOS="$(for h in $ALVOS; do host_jogo "$h"; done | sort -u | tr '\n' ' ')"
fi

# A completion marker alone can belong to an older engine and miss outputs
# the current runtime needs. Detect that before LOVE opens the interactive
# importer and the probe silently waits until timeout.
for jogo in $JOGOS; do
  APLICAVEL=0
  for h in $ALVOS; do
    [ "$(host_jogo "$h")" = "$jogo" ] && APLICAVEL=1
  done
  if [ "$APLICAVEL" -eq 1 ]; then
    env -C "$REPO" "$LUAJIT" "$AQUI/cache_ready.lua" "$jogo" "$SAVE" || exit 1
  fi
done

FMT='%-26s %-6s %-10s %-9s %-7s %-7s %s\n'
FALHAS=0
echo
# shellcheck disable=SC2059
printf "$FMT" HOST GAME VERSION ATTACHED DRAW ATLAS NOTE
printf "$FMT" -------------------------- ------ ---------- --------- ------- ------- ----

for jogo in $JOGOS; do
  APLICAVEIS=0
  for h in $ALVOS; do
    HJOGO="$(host_jogo "$h")"
    if [ -z "$HJOGO" ]; then
      printf "$FMT" "$h" "$jogo" "?" FAILED "-" "-" "not in HOSTS: no game declared for it"
      FALHAS=$((FALHAS + 1))
      continue
    fi
    # NOT APPLICABLE IS NOT A FAILURE. This host's lineage does not load on
    # this game at all, so there is no attach to measure and nothing to report
    # against the mod.
    if [ "$HJOGO" != "$jogo" ]; then
      printf "$FMT" "$h" "$jogo" "-" "n/a" "-" "-" "runs on $HJOGO, not this game"
      continue
    fi
    APLICAVEIS=$((APLICAVEIS + 1))

    seleciona "$h" "$jogo" || { echo "could not select $h"; FALHAS=$((FALHAS + 1)); continue; }
    pkill -x love 2>/dev/null
    for _ in $(seq 1 20); do pgrep -x love >/dev/null 2>&1 || break; sleep 0.5; done
    rm -f "$SAVE/vc_hosts.txt"
    LOG="$TMP/$h.$jogo.log"
    POKEPORT_VERSION="$jogo" POKEPORT_DRIVER="$DRIVER" "$LOVE" "$REPO" \
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
      printf "$FMT" "$h" "$jogo" "?" "NO RUN" "-" "-" "the probe wrote nothing; see $LOG"
      FALHAS=$((FALHAS + 1))
      continue
    fi
    LINHA="$(grep '^ATTACH ' "$SAIDA" | head -1)"
    HOSTVER="$(grep "^HOST $h " "$SAIDA" | sed -n 's/.*version=\([^ ]*\).*/\1/p')"
    ATTACHED="$(printf '%s' "$LINHA" | sed -n 's/.*patched=\([^ ]*\).*/\1/p')"
    DRAW="$(printf '%s' "$LINHA" | sed -n 's/.*draw=\([^ ]*\).*/\1/p')"
    ATLAS="$(printf '%s' "$LINHA" | sed -n 's/.*atlas=\([^ ]*\).*/\1/p')"
    NOTA="$(grep '^ATTACH why=' "$SAIDA" | sed 's/^ATTACH why=//' | head -1)"
    # A mod that never survived the loader cannot report a host, and "no
    # attach" would blame the host for it. Say which one it was.
    MODSTATE="$(grep '^MOD  voxel_characters ' "$SAIDA" | sed -n 's/.*state=\([^ ]*\).*/\1/p')"
    if [ -n "$MODSTATE" ] && [ "$MODSTATE" != "loaded" ]; then
      NOTA="voxel_characters state=$MODSTATE"
    fi
    if [ "$ATTACHED" = "true" ]; then
      printf "$FMT" "$h" "$jogo" "${HOSTVER:-?}" OK "${DRAW:--}" "${ATLAS:--}" ""
    else
      printf "$FMT" "$h" "$jogo" "${HOSTVER:-?}" FAILED "${DRAW:--}" "${ATLAS:--}" "${NOTA:-no attach}"
      FALHAS=$((FALHAS + 1))
    fi
  done

  # A GAME WITH NOTHING TO MEASURE IS RED, NOT GREEN. An empty column means
  # this run said nothing about that game, and a gate that reports silence as
  # success is worse than no gate: dropping a host from HOSTS, or uninstalling
  # it, would otherwise turn its column green by emptying it.
  if [ "$APLICAVEIS" -eq 0 ]; then
    printf "$FMT" "(none)" "$jogo" "-" FAILED "-" "-" "no installed host runs on $jogo; nothing was measured"
    FALHAS=$((FALHAS + 1))
  fi
done

echo
if [ "$FALHAS" -gt 0 ]; then
  echo "HOST MATRIX FAILED: $FALHAS row(s) did not attach"
  exit 1
fi
echo "HOST MATRIX OK"
