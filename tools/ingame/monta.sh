#!/bin/bash
# ASSEMBLES a release montage from a list of features (roadmap item 21.4).
#
#   tools/ingame/monta.sh <output-dir> <option>=<value> [<option>=<value> ...]
#
#   tools/ingame/monta.sh /tmp/v170 front_shape=0.17 top_dome=0.15 part_lag=0.16
#
# Films one clip per feature with `clip.sh`, then joins them into one video
# with the same framing and the same title card style throughout. That is the
# whole point: a release note that carries five separate clips makes a reader
# open five things, and five clips filmed on five different days do not look
# like they belong to the same mod.
#
# NOTHING HERE INVENTS A SHOT. Every clip is produced by clip.sh, which already
# refuses an A/B whose two sides are identical and which validates the option
# key before recording anything. If a feature does not survive that, it does
# not reach the montage, and the montage says which one and why rather than
# quietly assembling four clips and calling it five.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
MOD="$(cd "$AQUI/.." && pwd)"
RAIZ="$(cd "$MOD/../.." && pwd)"
. "$MOD/tools_bin.sh"

SAIDA="${1:?usage: monta.sh <output-dir> <option>=<value> ...}"
shift
[ $# -gt 0 ] || { echo "give at least one option, as key=value"; exit 1; }
[ -n "$FFMPEG" ] || { echo "ffmpeg not found"; exit 1; }

cd "$RAIZ" || exit 1
rm -rf "$SAIDA"; mkdir -p "$SAIDA"

# THE LOCK IS TAKEN ONCE, HERE, and inherited by every clip.sh below. Taking
# it per clip would let another tool slip in between two of them and film half
# the montage against a different scene. The lock is reentrant across a process
# tree, so the children take nothing and release nothing.
vc_trava_pega "monta.sh" || exit 1
trap 'vc_trava_solta' EXIT

# WHAT AN OPTION NEEDS BEFORE IT CAN BE FILMED AT ALL, and this is not
# tuning. Two of the options in this mod are not filmable with clip.sh's
# defaults, and in both cases the reason is in the OPTION, not in the montage:
#
#   part_lag      delays whatever MOTION LAG, SWAY or ATTENTION are doing, and
#                 with all three off it delays a CONSTANT. Both halves then
#                 come out the same and clip.sh's PSNR guard refuses to
#                 publish -- correctly, and for a reason nobody can see from
#                 the output, because it reads as "the option does nothing".
#                 So one of the three is held on BOTH sides with VC_CLIP_FIXO.
#                 SWAY is the one picked, and MOTION LAG was tried first and
#                 MEASURED as the wrong choice: MOTION LAG only exists while
#                 the character moves, and asking for the walk to get it
#                 (VC_CLIP_ANDAR=1) made the walk itself the dominant signal.
#                 Within one side 25.95 against between the sides 27.21, so
#                 the guard refused -- correctly again, because at that point
#                 the clip was showing a walk and not a delay. SWAY animates
#                 STANDING STILL, which keeps the within-side variation down
#                 where the delay can be seen above it: 25.36 within against
#                 24.59 between, and that margin is thin enough to be worth
#                 knowing before anyone widens this clip's scope.
#   footfall      and
#   step_weight   are both driven by the WALK, and the guard reads exactly one
#                 frame, number 10. At the default VC_CLIP_STEP=2 that frame
#                 lands on tick 20 of the recording, which is before a
#                 velocity-driven effect has any amplitude at all: footfall's
#                 amplitude comes from smoothed velocity and step_weight's
#                 lean comes from the art's own step, and at tick 20 there is
#                 barely a step yet. Measured, and NOT a threshold that got
#                 lowered -- the guard's rule is untouched. step_weight walking
#                 at STEP=2: within 27.17, between 29.88, refused. The SAME
#                 option, the SAME walk, sampled at STEP=6 so frame 10 lands on
#                 tick 60: within 29.60, between 27.36, published. One variable
#                 between those two runs. footfall at STEP=6: within 27.76,
#                 between 26.06.
#
#                 WHAT THIS COSTS, because it is worth saying out loud: at the
#                 default sampling these two published about half the time, on
#                 luck. The first montage run passed both; the second refused
#                 both with the option and the scene unchanged. step_weight's
#                 refusal was the honest one to read: within and between came
#                 out at 27.669099 and 27.669099, the same number to six
#                 decimals, which is the on side landing byte for byte on the
#                 floor pass. The option had done nothing by frame 10, and the
#                 27.67 was the scene's own run-to-run noise being read as if
#                 it were the option. A clip that publishes on that is worth
#                 less than no clip.
#   first_person  only does anything at the host's first person camera step,
#                 and pointing the camera there is NOT enough on its own.
#                 clip.lua pins "alto" by default, where FirstPerson.cardBlend
#                 is zero and CARD against SOLID is a guaranteed no-op. At
#                 "primeira" the blend settles at FULL, and there the host
#                 hides the player's own card (FirstPerson.hidePlayer above
#                 0.9), so the default landing spot came out with nobody in
#                 frame at all: within AND between both measured `inf`, three
#                 passes byte for byte identical. probe_fp solves the same
#                 problem by measuring at the MIDDLE of the blend, which this
#                 tool has no way to hold, so the clip solves it the other
#                 way, by facing somebody: Oak's lab has stationary NPCs, and
#                 the option changes how THEY are drawn up close.
#
# Anything not listed here is filmed with clip.sh's own defaults. That is the
# rule and not an accident: this table is for options that cannot be filmed AT
# ALL without help, never for making a clip look better. An option that fails
# its own guard for any other reason stays failed and gets reported.
ambiente_de() {
  case "$1" in
    footfall)     printf '%s\n' 'VC_CLIP_STEP=6' ;;
    step_weight)  printf '%s\n' 'VC_CLIP_ANDAR=1' 'VC_CLIP_STEP=6' ;;
    part_lag)     printf '%s\n' 'VC_CLIP_FIXO=sway=0.45' ;;
    first_person) printf '%s\n' 'VC_CLIP_DEGRAU=primeira' 'VC_FACING=up' ;;
  esac
}

FEITOS=()
FALHOS=()
for spec in "$@"; do
  nome=$(printf '%s' "$spec" | cut -d= -f1)
  echo ""
  echo "== $spec"
  # bash 3.2 is what macOS ships, and there `"${A[@]}"` on an EMPTY array is an
  # unbound-variable error under `set -u`. The `+` form is the portable way to
  # expand an array that may be empty, so an option with nothing special to
  # declare still runs through exactly the same line as one that does.
  AMBIENTE=()
  while IFS= read -r par; do
    [ -n "$par" ] && AMBIENTE+=("$par")
  done <<EOF
$(ambiente_de "$nome")
EOF
  [ ${#AMBIENTE[@]} -eq 0 ] || echo "   env: ${AMBIENTE[*]}"
  if env ${AMBIENTE[@]+"${AMBIENTE[@]}"} \
       bash "$AQUI/clip.sh" "$SAIDA/$nome" "$spec" > "$SAIDA/$nome.log" 2>&1; then
    ab=$(find "$SAIDA/$nome" -name '*-ab.mp4' 2>/dev/null | head -1)
    if [ -n "$ab" ] && [ -f "$ab" ]; then
      FEITOS+=("$ab")
      echo "   ok  $(basename "$ab")"
    else
      FALHOS+=("$spec (published nothing)")
      echo "   FAILED: clip.sh succeeded but produced no side-by-side"
    fi
  else
    # Both languages, because the drivers are being converted one at a time.
    # A counter that knows only one of them reads a converted driver as silent.
    motivo=$(grep -oE 'FAILED.*|unknown option.*' \
             "$SAIDA/$nome.log" | head -1)
    FALHOS+=("$spec ${motivo:-unknown}")
    echo "   FAILED: ${motivo:-see $SAIDA/$nome.log}"
  fi
done

echo ""
if [ ${#FEITOS[@]} -eq 0 ]; then
  echo "NOTHING TO ASSEMBLE: every feature failed its own clip gate."
  printf '  %s\n' "${FALHOS[@]}"
  exit 1
fi

# Concat by re-encoding rather than by stream copy. The clips come from the
# same tool with the same preset, so a stream copy would usually work, and
# "usually" is how a montage ends up with one segment that stutters on
# somebody's player. Re-encoding once costs seconds and is the same CRF.
LISTA="$SAIDA/lista.txt"
: > "$LISTA"
for f in "${FEITOS[@]}"; do
  printf "file '%s'\n" "$(cd "$(dirname "$f")" && pwd)/$(basename "$f")" >> "$LISTA"
done

"$FFMPEG" -y -loglevel error -f concat -safe 0 -i "$LISTA" \
  -c:v libx264 -pix_fmt yuv420p -crf "${VC_CLIP_CRF:-18}" -preset slow \
  "$SAIDA/montagem.mp4" || { echo "ffmpeg concat failed"; exit 1; }

TAM=$(du -h "$SAIDA/montagem.mp4" | cut -f1 | tr -d ' ')
echo "MONTAGEM OK  ->  $SAIDA/montagem.mp4  ($TAM, ${#FEITOS[@]} features)"

# SAYING WHAT WAS DROPPED IS PART OF THE OUTPUT. A montage that quietly
# contains four of the five features somebody asked for is worse than one that
# fails, because it will be published as if it showed all five.
if [ ${#FALHOS[@]} -gt 0 ]; then
  echo ""
  echo "NOT IN THE MONTAGE, ${#FALHOS[@]} of $(( ${#FEITOS[@]} + ${#FALHOS[@]} )):"
  printf '  %s\n' "${FALHOS[@]}"
  exit 1
fi
