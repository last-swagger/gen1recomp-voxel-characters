#!/bin/bash
# THE THREE-PANEL PRESET CARD: original, authored, randomised (roadmap T2.2).
#
#   bash mods/voxel_characters/tools/render/preset_card.sh [out.png] [seed]
#
# From the repo root. Needs LOVE and ffmpeg.
#
# The roadmap's last gate condition for the character creator is "one card shows
# original Ash, one authored preset and one randomised preset side by side".
#
# WHY NOT `card.sh`. That tool and the compositor's card mode are built around
# exactly two panels, before and after, with the callout layout computed from
# that. Making them N-panel is a refactor of layout maths whose only beneficiary
# is this one picture, and the risk lands on `shading.card`, which is a
# published figure. ffmpeg is already a dependency of the clip and audio paths
# and stacks three images without touching any of that.
#
# THE RANDOMISED PANEL COMES FROM THE SEED, not from a roll at build time, so
# the card is reproducible: the same seed gives the same third panel forever,
# and a card that changed every time it was built could not be compared with
# the one somebody looked at last week.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
MOD="$(cd "$AQUI/../.." && pwd)"
RAIZ="$(cd "$MOD/../.." && pwd)"
. "$MOD/tools/tools_bin.sh"
H=mods/voxel_characters/tools/render
SAIDA="${1:-preset_card.png}"
SEED="${2:-42}"
SAVE_RENDER="$HOME/Library/Application Support/LOVE/render"

cd "$RAIZ" || exit 1
command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg not found"; exit 2; }

vc_trava_pega "preset_card.sh" || exit 1
trap 'vc_trava_solta' EXIT

# The authored panel is a HAND-CHOSEN preset and the randomised one comes from
# the generator, because the card's whole point is showing that those are two
# different kinds of proposal.
AUTORAL='preset1 sheet=red hair=3 body=1 feet=2'
ALEATORIO=$(luajit -e '
  local R = dofile("mods/voxel_characters/tools/randomiza.lua")
  local P = dofile("mods/voxel_characters/authored/preset.lua")
  local c = R.candidatos("red", 1, '"$SEED"')
  io.write(P.serialise(c[1]))')
[ -n "$ALEATORIO" ] || { echo "FAILED: the randomiser produced no candidate"; exit 1; }

render() {  # $1 = out, $2 = preset text or empty
  # `set -u` and an empty array do not get along in bash 3.2, which is what
  # macOS ships: "${extra[@]}" on an empty array is an unbound variable there,
  # not an empty expansion. Branching is shorter than the workarounds.
  if [ -n "$2" ]; then
    $LOVE $H sprite=red shapes=slab frames=0 yaws=0 rungs=35 cell=256 \
      out="$1" preset="$2" > /dev/null 2>&1
  else
    $LOVE $H sprite=red shapes=slab frames=0 yaws=0 rungs=35 cell=256 \
      out="$1" > /dev/null 2>&1
  fi
  [ -f "$SAVE_RENDER/$1" ] || { echo "FAILED: no render at $1"; return 1; }
}

rm -f "$SAVE_RENDER/pc_orig.png" "$SAVE_RENDER/pc_auth.png" "$SAVE_RENDER/pc_rand.png"
render pc_orig.png "" || exit 1
render pc_auth.png "$AUTORAL" || exit 1
render pc_rand.png "$ALEATORIO" || exit 1

# THE THREE PANELS MUST DIFFER FROM EACH OTHER, and this is the check that stops
# the card being a picture of the same character three times. It has a real
# failure mode: if the preset path silently stopped applying, every panel would
# render identically and the card would look deliberate.
for par in "pc_orig.png pc_auth.png" "pc_orig.png pc_rand.png" "pc_auth.png pc_rand.png"; do
  set -- $par
  if cmp -s "$SAVE_RENDER/$1" "$SAVE_RENDER/$2"; then
    echo "FAILED: $1 and $2 are byte identical, so the card would show the"
    echo "  same character three times and call them different proposals"
    exit 1
  fi
done

ffmpeg -hide_banner -loglevel error -y \
  -i "$SAVE_RENDER/pc_orig.png" -i "$SAVE_RENDER/pc_auth.png" \
  -i "$SAVE_RENDER/pc_rand.png" \
  -filter_complex "[0:v][1:v][2:v]hstack=inputs=3[v]" -map "[v]" \
  "$SAVE_RENDER/$SAIDA" || { echo "FAILED: ffmpeg could not stack the panels"; exit 1; }

echo "PRESET CARD $SAVE_RENDER/$SAIDA"
echo "  original"
echo "  authored   $AUTORAL"
echo "  randomised $ALEATORIO   (seed $SEED)"
