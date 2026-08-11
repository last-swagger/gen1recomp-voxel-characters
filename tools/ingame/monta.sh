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

FEITOS=()
FALHOS=()
for spec in "$@"; do
  nome=$(printf '%s' "$spec" | cut -d= -f1)
  echo ""
  echo "== $spec"
  if bash "$AQUI/clip.sh" "$SAIDA/$nome" "$spec" > "$SAIDA/$nome.log" 2>&1; then
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
