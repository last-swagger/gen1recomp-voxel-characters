#!/bin/bash
# MEASURES the native-offscreen backend against native (roadmap T0.2, slice 2).
#
#   bash mods/voxel_characters/tools/runner/measure_delta.sh --dry-run
#   bash mods/voxel_characters/tools/runner/measure_delta.sh
#
# NEEDS A DISPLAY AND TAKES THE SCREEN FOR A FEW SECONDS. The native reference
# run opens a real LOVE window by definition: native IS the procedure every
# threshold here was measured under, so there is no version of it that hides.
# Run this on a free machine, or when nobody is using this one.
#
# WHY A FLOOR RUN FIRST, and it is the difference between this and a naive
# comparison. Comparing native against native-offscreen only means something if
# the target is byte-deterministic in the first place. So native runs TWICE and
# those two are compared to each other before anything else happens. If they
# already differ, then a difference against the offscreen run says nothing
# about the backend, and this refuses to draw a conclusion instead of reporting
# whichever answer showed up. That is this project's own rule: a threshold is
# evidence only when a floor was captured by the SAME procedure.
#
# The precedent that makes byte comparison the right instrument here: the ruler
# already asserts that the same card built twice is the same file
# (tools/render/check.sh, "o mesmo card duas vezes da o mesmo arquivo"), so the
# harness is expected to be deterministic and a difference is a finding rather
# than noise.
#
# WHAT IT REFUSES TO DO. It will not write a ZERO into deltas.txt unless every
# run produced an artifact, the floor was established, and the bytes matched.
# A run that rendered nothing is not a match, it is a missing measurement, and
# two absent files comparing equal is the exact defect tools_bin.sh records.
set -u

AQUI="$(cd "$(dirname "$0")" && pwd)"
MOD="$(cd "$AQUI/../.." && pwd)"
RAIZ="$(cd "$MOD/../.." && pwd)"
RUNNER="$AQUI/runner.sh"
DELTAS="$AQUI/deltas.txt"
SAVE_RENDER="$HOME/Library/Application Support/LOVE/render"

DELTAS="${VC_DELTAS:-$AQUI/deltas.txt}"

SECO=0
CHAVE="harness-red-slab"
case "${1:-}" in
  --dry-run) SECO=1; shift ;;
  --selftest) shift; SELFTEST=1 ;;
esac
[ $# -gt 0 ] && CHAVE="$1"

# ------------------------------------------------------- recording a verdict
#
# ONE LINE PER backend+target, enforced by replacing rather than appending.
#
# This was append-only, and the two halves disagreed: runner.sh read the FIRST
# matching line while this wrote new ones at the END, so re-measuring a key
# left the runner reporting the SUPERSEDED verdict forever. A stale ZERO is the
# worst possible version of that bug, because it is the one that would let a
# threshold be trusted on a backend that had since been shown to differ.
#
# Everything that is not this exact backend+target survives byte for byte:
# comments, blank lines, other backends, other targets.
registra_delta() {  # $1 backend, $2 key, $3 verdict, $4 evidence; echoes n replaced
  local backend="$1" chave="$2" veredito="$3" evid="$4"
  local novo="${TMP:-/tmp}/deltas.novo" antigas=0
  if [ -f "$DELTAS" ]; then
    antigas=$(awk -v b="$backend" -v k="$chave" '
      /^[[:space:]]*#/ { next }
      /^[[:space:]]*$/ { next }
      ($1 == b && $2 == k) { n++ }
      END { print n + 0 }
    ' "$DELTAS")
    awk -v b="$backend" -v k="$chave" '
      /^[[:space:]]*#/ { print; next }
      /^[[:space:]]*$/ { print; next }
      ($1 == b && $2 == k) { next }
      { print }
    ' "$DELTAS" > "$novo" || return 1
  else
    : > "$novo" || return 1
  fi
  printf '%-18s %-14s %-9s %s\n' "$backend" "$chave" "$veredito" "$evid" >> "$novo" || return 1
  mv "$novo" "$DELTAS" || return 1
  printf '%s' "$antigas"
}

# THE TARGET. One canvas-based harness render with every parameter pinned:
# sprite, builder, frame, yaw, camera rung and cell size all fixed, label off.
# Nothing here reads the clock or a save file, which is what makes a byte
# comparison a fair question to ask.
#
# Deliberately NOT check.sh for this first measurement. The ruler runs the
# harness many times and calls card.sh, so it is a visual batch: the right
# thing to escalate to once one target has answered the question, and the wrong
# size for the first answer.
render_cmd() {  # $1 = output filename
  printf '%s' "bash mods/voxel_characters/tools/love.sh mods/voxel_characters/tools/render \
sprite=red shapes=slab frames=0 yaws=0 rungs=35 cell=320 label=0 metrics=1 out=$1"
}
PROBE_CMD="bash mods/voxel_characters/tools/love.sh mods/voxel_characters/tools/runner/window_probe"

diga() { printf '%s\n' "$*"; }
cabeca() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- selftest
#
# Text only: no display, no LOVE launched, and the real deltas.txt is never
# touched (VC_DELTAS points both this and runner.sh at a temp file). It exists
# because the bug it covers was invisible: the writer appended, the reader took
# the first match, and everything looked fine until a key was measured twice.
if [ "${SELFTEST:-0}" = "1" ]; then
  TMP="$(mktemp -d -t vcdeltaself)" || exit 1
  trap 'rm -rf "$TMP"' EXIT
  DELTAS="$TMP/deltas.txt"
  falhas=0
  ok() { printf "  %-52s ok\n" "$1"; }
  nao() { printf "  %-52s WRONG (%s)\n" "$1" "$2"; falhas=$((falhas + 1)); }

  diga "measure_delta selftest: one line per backend+target"

  cat > "$DELTAS" <<'SEED'
# a comment that must survive
native-offscreen   other-target   DIFFERS   an earlier measurement of something else
native-offscreen   harness-x      DIFFERS   the stale verdict for OUR key
SEED

  n=$(registra_delta "native-offscreen" "harness-x" "ZERO" "fresh evidence")
  [ "$n" = "1" ] && ok "replacing reports how many lines it replaced" \
    || nao "replacing reports how many lines it replaced" "got '$n'"

  linhas=$(awk '$1=="native-offscreen" && $2=="harness-x"' "$DELTAS" | wc -l | tr -d ' ')
  [ "$linhas" = "1" ] && ok "exactly one line survives for the key" \
    || nao "exactly one line survives for the key" "$linhas lines"

  v=$(awk '$1=="native-offscreen" && $2=="harness-x" {print $3}' "$DELTAS")
  [ "$v" = "ZERO" ] && ok "the surviving line carries the NEW verdict" \
    || nao "the surviving line carries the NEW verdict" "got '$v'"

  grep -q "^# a comment that must survive" "$DELTAS" \
    && ok "comments survive a rewrite" || nao "comments survive a rewrite" "comment lost"

  grep -qE "^native-offscreen[[:space:]]+other-target[[:space:]]+DIFFERS" "$DELTAS" \
    && ok "another target's measurement is untouched" \
    || nao "another target's measurement is untouched" "other-target lost or changed"

  # The reader has to agree with the writer about which line is current. This
  # runs the runner with no LOVE launched: the command is an echo.
  saida=$(VC_DELTAS="$DELTAS" VC_RUNS="$TMP/runs" bash "$AQUI/runner.sh" \
          run native-offscreen --label harness-x --verdict PASSOU \
          -- "echo PASSOU" 2>&1)
  printf '%s' "$saida" | grep -q "delta=ZERO" \
    && ok "runner.sh reports the fresh verdict" \
    || nao "runner.sh reports the fresh verdict" "$(printf '%s' "$saida" | head -1)"

  # And the belt: a duplicate added by hand, as an older append-only writer
  # would have left behind. The reader must take the LAST one, not the first.
  printf '%-18s %-14s %-9s %s\n' "native-offscreen" "harness-x" "DIFFERS" \
    "a later hand-added line" >> "$DELTAS"
  saida=$(VC_DELTAS="$DELTAS" VC_RUNS="$TMP/runs" bash "$AQUI/runner.sh" \
          run native-offscreen --label harness-x --verdict PASSOU \
          -- "echo PASSOU" 2>&1)
  printf '%s' "$saida" | grep -q "delta=DIFFERS" \
    && ok "with a duplicate present, the LAST line wins" \
    || nao "with a duplicate present, the LAST line wins" "$(printf '%s' "$saida" | head -1)"

  # An unmeasured key must still read UNMEASURED, or the whole scheme is moot.
  saida=$(VC_DELTAS="$DELTAS" VC_RUNS="$TMP/runs" bash "$AQUI/runner.sh" \
          run native-offscreen --label never-measured --verdict PASSOU \
          -- "echo PASSOU" 2>&1)
  printf '%s' "$saida" | grep -q "delta=UNMEASURED" \
    && ok "a key with no line reads UNMEASURED" \
    || nao "a key with no line reads UNMEASURED" "$(printf '%s' "$saida" | head -1)"

  diga ""
  if [ "$falhas" -eq 0 ]; then
    diga "MEASURE_DELTA SELFTEST OK"
    exit 0
  fi
  diga "MEASURE_DELTA SELFTEST FAILED: $falhas"
  exit 1
fi

# --------------------------------------------------------------- preflight
cabeca "preflight"
for b in native native-offscreen; do
  if bash "$RUNNER" probe "$b" >/dev/null 2>&1; then
    diga "  backend $b usable"
  else
    diga "  BACKEND UNUSABLE: $b"
    bash "$RUNNER" probe "$b" 2>&1 | sed 's/^/    /'
    exit 2
  fi
done
command -v shasum >/dev/null || { diga "shasum not found"; exit 2; }

if [ "$SECO" = "1" ]; then
  cabeca "dry run: what would happen, in order"
  diga "  key           $CHAVE"
  diga "  save dir      $SAVE_RENDER"
  diga "  deltas file   $DELTAS"
  diga ""
  diga "  1. native            $(render_cmd vcdelta_n1.png)"
  diga "  2. native            $(render_cmd vcdelta_n2.png)   <- the FLOOR"
  diga "  3. native-offscreen  $(render_cmd vcdelta_o1.png)"
  diga "  4. native-offscreen  $PROBE_CMD"
  diga "  5. native            $PROBE_CMD   <- the control for step 4"
  diga ""
  diga "  then: shasum n1 vs n2 (floor), n1 vs o1 (delta),"
  diga "        compose mode=conta for a pixel count if the bytes differ,"
  diga "        and ONE line per backend+target written to deltas.txt, replacing"
  diga "        any earlier line for this key, ONLY with full evidence."
  diga ""
  diga "  key already recorded for this target: $(awk -v k="$CHAVE" '
        /^[[:space:]]*#/ { next } ($1=="native-offscreen" && $2==k) { v=$3 }
        END { print (v == "" ? "none" : v) }' "$DELTAS" 2>/dev/null)"
  diga ""
  diga "  NOTHING WAS RUN. Steps 1 to 5 each open a LOVE window; steps 1, 2"
  diga "  and 5 are visible by definition. Drop --dry-run on a free machine."
  exit 0
fi

# ------------------------------------------------------------------- lock
# Taken ONCE for the whole measurement, not per run. Three renders that are
# going to be compared byte for byte must not have another tool starting a
# LOVE between them. runner.sh sees the inherited VC_TRAVA_DONO and proceeds
# without taking anything.
# shellcheck disable=SC1090
. "$MOD/tools/tools_bin.sh"
vc_trava_pega "measure_delta.sh" || exit 2

# REENTRANCY IS NOT UNIVERSAL, and assuming it cost a whole run on the MBP.
#
# This takes the lock once for the measurement so nothing interleaves between
# three renders that are about to be compared byte for byte. That only works if
# the host's tools_bin.sh is the version where the lock is REENTRANT across a
# process tree: whoever takes it exports VC_TRAVA_DONO, and a child that sees an
# inherited value proceeds without taking anything.
#
# An older checkout does not export it. There, the parent taking the lock LOCKS
# OUT ITS OWN CHILDREN, every render refuses, and the log blames "another tool
# is using LOVE" while naming this script's own pid. That is a misleading error,
# which this project treats as worse than a missing one: it sends you looking
# for a stray process that does not exist.
#
# So: detect it, say so, and degrade to per-run locking instead of failing.
# Each render still takes the lock, just not all three under one hold.
REENTRANT=1
if [ -z "${VC_TRAVA_DONO:-}" ]; then
  REENTRANT=0
  vc_trava_solta
  diga "NOTE: this host's tools_bin.sh predates the reentrant lock, so the"
  diga "  measurement cannot hold LOVE for all three renders at once. Each"
  diga "  render will take the lock on its own, which is safe but leaves a"
  diga "  gap another tool could start in. Nothing else should run meanwhile."
  diga "  NEXT, to close the gap: bring this host's tools/tools_bin.sh up to"
  diga "  the version that exports VC_TRAVA_DONO."
  diga ""
fi

TMP="$(mktemp -d -t vcdelta)" || exit 2
trap 'rm -rf "$TMP"; vc_trava_solta' EXIT INT TERM

rm -f "$SAVE_RENDER"/vcdelta_n1.png "$SAVE_RENDER"/vcdelta_n2.png \
      "$SAVE_RENDER"/vcdelta_o1.png

corre() {  # $1 = backend, $2 = label, $3 = out png, $4 = command
  local backend="$1" label="$2" png="$3" cmd="$4"
  # The verdict is the OUTPUT FILENAME, which the harness prints when it
  # writes. Tighter than looking for the word "IoU": it proves the tool
  # reported writing the file this step asked for, and --expect-artifacts then
  # proves the file is really there. Two different claims, both needed.
  bash "$RUNNER" run "$backend" --label "$label" \
    --verdict "$png" \
    --collect "$SAVE_RENDER/$png" --expect-artifacts 1 \
    -- "$cmd" 2>&1 | sed 's/^/    /'
  return "${PIPESTATUS[0]}"
}

# A failing run does not stop the measurement, it just will not have produced a
# file. The artifact check below is the real gate, and letting all three run
# first means one report covers everything instead of one failure at a time.
cabeca "1. native, first pass"
corre native delta-n1 vcdelta_n1.png "$(render_cmd vcdelta_n1.png)" || true
cabeca "2. native, second pass (the floor)"
corre native delta-n2 vcdelta_n2.png "$(render_cmd vcdelta_n2.png)" || true
cabeca "3. native-offscreen"
corre native-offscreen delta-o1 vcdelta_o1.png "$(render_cmd vcdelta_o1.png)" || true

N1="$SAVE_RENDER/vcdelta_n1.png"
N2="$SAVE_RENDER/vcdelta_n2.png"
O1="$SAVE_RENDER/vcdelta_o1.png"

# EVERY FILE HAS TO EXIST BEFORE ANY COMPARISON. Two missing files compare
# equal, and that is precisely the false green this whole runner exists for.
cabeca "artifacts"
faltando=0
for f in "$N1" "$N2" "$O1"; do
  if [ -s "$f" ]; then
    diga "  $(basename "$f")   $(wc -c < "$f" | tr -d ' ') bytes"
  else
    diga "  $(basename "$f")   MISSING OR EMPTY"
    faltando=$((faltando + 1))
  fi
done
if [ "$faltando" -gt 0 ]; then
  diga ""
  diga "NO MEASUREMENT: $faltando of 3 renders produced nothing."
  diga "  Nothing is written to deltas.txt. Absent files are not a match."
  exit 1
fi

sha() { shasum -a 256 "$1" | awk '{print $1}'; }
S_N1=$(sha "$N1"); S_N2=$(sha "$N2"); S_O1=$(sha "$O1")

conta() {  # pixel difference between two PNGs, via the harness's own tool
  bash "$MOD/tools/love.sh" mods/voxel_characters/tools/render/compose \
    mode=conta "$1" "$2" 2>/dev/null | grep -oE 'diferenca [0-9]+' | grep -oE '[0-9]+'
}

cabeca "floor: native against native, same procedure twice"
diga "  n1  $S_N1"
diga "  n2  $S_N2"
if [ "$S_N1" = "$S_N2" ]; then
  PISO="identical"
  diga "  the target is byte deterministic, so a byte comparison is meaningful"
else
  PISO="differs"
  PISO_PIX=$(conta "$N1" "$N2"); PISO_PIX=${PISO_PIX:-unknown}
  diga "  NOT identical. Floor pixel difference: $PISO_PIX"
  diga "  A byte comparison against the offscreen run cannot mean anything now."
fi

cabeca "delta: native against native-offscreen"
diga "  n1  $S_N1"
diga "  o1  $S_O1"
IGUAL=0
[ "$S_N1" = "$S_O1" ] && IGUAL=1

cabeca "4. where the window went"
bash "$RUNNER" run native-offscreen --label delta-window-off \
  --verdict 'W1 (PASSOU|FALHOU)' -- "$PROBE_CMD" 2>&1 | sed 's/^/    /'
JANELA_NA_TELA=$(grep -h "^on screen" "${VC_RUNS:-/tmp/vc-runs}"/*delta-window-off/stdout.log 2>/dev/null | tail -1 | awk '{print $3}')
cabeca "5. the control: where the window goes normally"
bash "$RUNNER" run native --label delta-window-on \
  --verdict 'W1 (PASSOU|FALHOU)' -- "$PROBE_CMD" 2>&1 | sed 's/^/    /'
CONTROLE_NA_TELA=$(grep -h "^on screen" "${VC_RUNS:-/tmp/vc-runs}"/*delta-window-on/stdout.log 2>/dev/null | tail -1 | awk '{print $3}')

diga ""
diga "  offscreen mode on screen: ${JANELA_NA_TELA:-unknown}   <- false is what the mode is FOR"
diga "  normal    mode on screen: ${CONTROLE_NA_TELA:-unknown}   <- the control, true is expected"

# ------------------------------------------------------------------ verdict
cabeca "verdict"
DATA=$(date +%Y-%m-%d)

if [ "$PISO" != "identical" ]; then
  diga "  INCONCLUSIVE. The floor is not stable, so this instrument cannot"
  diga "  answer the question. Nothing written to deltas.txt."
  diga "  NEXT: find out why the same render twice is not the same file"
  diga "  before comparing anything across backends."
  exit 1
fi

if [ "$IGUAL" = "1" ]; then
  VEREDITO="ZERO"
  EVID="$DATA sha256 identical across native x2 and native-offscreen, floor identical, offscreen-mode window ON SCREEN=${JANELA_NA_TELA:-unknown}"
else
  VEREDITO="DIFFERS"
  PIX=$(conta "$N1" "$O1"); PIX=${PIX:-unknown}
  EVID="$DATA sha256 differs, ${PIX} pixels, floor identical so the difference is the backend, offscreen-mode window ON SCREEN=${JANELA_NA_TELA:-unknown}"
fi

SUBSTITUIDAS=$(registra_delta "native-offscreen" "$CHAVE" "$VEREDITO" "$EVID") || {
  diga "  FAILED to write $DELTAS. The measurement stands, the record does not."
  exit 1
}
diga "  $VEREDITO"
if [ "${SUBSTITUIDAS:-0}" -gt 0 ]; then
  diga "  written to $DELTAS, replacing $SUBSTITUIDAS earlier line(s) for this key"
else
  diga "  written to $DELTAS"
fi

if [ "$VEREDITO" = "ZERO" ] && [ "${JANELA_NA_TELA:-}" != "false" ]; then
  diga ""
  diga "  WARNING: the output matches, but the window was NOT confirmed off"
  diga "  screen. The delta is genuinely zero and the mode still buys nothing"
  diga "  until the window stops appearing. Try a separate macOS user session,"
  diga "  Space or display before relying on this."
fi

diga ""
diga "  Re-run the ruler and the in-game gates before trusting anything else:"
diga "    bash mods/voxel_characters/tools/bateria.sh"
[ "$VEREDITO" = "ZERO" ] && exit 0
exit 0
