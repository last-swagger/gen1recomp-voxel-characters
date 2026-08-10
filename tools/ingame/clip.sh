#!/bin/bash
# Records a side-by-side CLIP of a mod option: left off, right on, same spot,
# same camera, same number of frames.
#
# Exists because a photo does not judge movement. BREATH, SWAY and MOTION LAG
# only mean something over time, and until now the only way to show that to
# someone was to ask them to open the game.
#
# Usage:
#   tools/ingame/clip.sh <output-folder> <key=value>
#   tools/ingame/clip.sh <output-folder> <key=valueA:valueB>
#
# Examples:
#   tools/ingame/clip.sh /tmp/clip breath=0.020          OFF against 0.020
#   tools/ingame/clip.sh /tmp/clip breath=0.010:0.035    two levels, A against B
#   VC_MAP=VIRIDIAN_CITY tools/ingame/clip.sh /tmp/clip lag=0.70
#   VC_CLIP_DEGRAU=primeira tools/ingame/clip.sh /tmp/clip first_person=solid
#
# VC_CLIP_DEGRAU picks the host's camera step:
#   off baixo medio alto empe primeira terceira, or the level number.
# Without it, the clip comes out at whatever step the save has, which varies
# between runs.
#
# The second form is to CHOOSE, not to verify. Against OFF the question is
# "does it do anything?"; between two levels it is "which one?", the only
# question left once the feature exists, and the only one whose answer is
# taste.
#
# Outputs: <option>-off.mp4, <option>-on.mp4, <option>-ab.mp4 and <option>-ab.gif
# In the side-by-side, LEFT is off and RIGHT is on, always.

set -u
REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
SAVE="$HOME/Library/Application Support/LOVE/pokemon-love2d"
. "$(cd "$(dirname "$0")/.." && pwd)/tools_bin.sh"
DRIVER="$REPO/mods/voxel_characters/tools/ingame/clip.lua"

SAIDA="${1:?uso: clip.sh <pasta-de-saida> <chave=valor>}"
OPCAO="${2:?uso: clip.sh <pasta-de-saida> <chave=valor>}"
CHAVE="${OPCAO%%=*}"
SUFIXO=$(echo "${OPCAO#*=}" | tr ":" "-" | tr -d " ")

[ -n "$FFMPEG" ] || { echo "ffmpeg not found (PATH, \$FFMPEG_BIN, /opt/homebrew, /usr/local)"; exit 1; }
[ -f "$DRIVER" ] || { echo "driver not found: $DRIVER"; exit 1; }

# Same version detection as run.sh, for the same reason: POKEPORT_GAME is dead
# letter under POKEPORT_DRIVER, and red may not be ready on this machine.
versao_pronta() {
  case "$1" in
    red)
      local faltando=0
      for f in data/generated/constants.lua assets/generated/audio/programs.bin \
               assets/generated/trade/game_boy.png; do
        [ -e "$REPO/$f" ] || faltando=1
      done
      [ "$faltando" -eq 0 ]
      ;;
    *) [ -f "$SAVE/$1/rom-cache.complete" ] ;;
  esac
}
VERSAO="${VC_VERSION:-}"
if [ -z "$VERSAO" ]; then
  for v in blue red yellow; do versao_pronta "$v" && { VERSAO="$v"; break; }; done
fi
[ -n "$VERSAO" ] || { echo "no version ready"; exit 1; }

vc_trava_pega "clip.sh" || exit 1
pkill -x love 2>/dev/null
for _ in $(seq 1 20); do pgrep -x love >/dev/null 2>&1 || break; sleep 0.5; done

rm -rf "$SAIDA" && mkdir -p "$SAIDA"
find "$SAVE" -maxdepth 1 -name 'vc_clip_*.png' -delete 2>/dev/null
LOG="$SAIDA/clip.log"

cd "$REPO" || exit 1
echo "version: $VERSAO   option: $OPCAO"
VC_CLIP_OPT="$OPCAO" POKEPORT_VERSION="$VERSAO" POKEPORT_DRIVER="$DRIVER" \
  "$LOVE" . > "$LOG" 2>&1
QUADROS=$(grep -oE 'quadros por lado: [0-9]+' "$LOG" | grep -oE '[0-9]+' | tail -1)
if [ -z "$QUADROS" ]; then
  echo "FALHOU: the driver did not finish"
  tail -5 "$LOG"
  exit 1
fi

N_OFF=$(find "$SAVE" -maxdepth 1 -name 'vc_clip_off_*.png' | wc -l | tr -d ' ')
N_ON=$(find "$SAVE" -maxdepth 1 -name 'vc_clip_on_*.png' | wc -l | tr -d ' ')
echo "frames recorded: $N_OFF off, $N_ON on"
if [ "$N_OFF" -lt 10 ] || [ "$N_ON" -lt 10 ]; then
  echo "FALHOU: too few frames"
  exit 1
fi

TMP="$SAIDA/.quadros"
mkdir -p "$TMP"
find "$SAVE" -maxdepth 1 -name 'vc_clip_*.png' -exec mv {} "$TMP"/ \;

# BOTH SIDES MUST DIFFER, and this check exists because the same failure
# already happened: an A/B came out with both sides IDENTICAL BYTE FOR BYTE
# and I nearly presented it as a comparison. The cause was writing the option
# to the save without emitting the event, so the cached mesh never rebuilt.
#
# driver.lua aborts in that case; clip.lua only warned in the log and nobody
# read it. And "event emitted" does not close the hole: `pcall(emit)` returns
# true when the bus accepted the message, including when there is no listener
# at all. The only proof that does not depend on introspecting the mod is the
# SCREEN.
#
# WHAT THIS GUARD CATCHES AND WHAT IT DOES NOT CATCH, measured and not
# assumed. I filmed an A/B with the SAME value on both sides (breath=0.010:0.010)
# and it did NOT trigger: with animation on, both sides are recorded in
# sequence, the motion phase advances, and the frames differ on their own. So:
#
#   CATCHES: a MESH option that did not arrive. Without rebuild and without
#            animation both sides come out byte for byte equal, which is
#            exactly the historical defect that motivated this guard.
#   DOES NOT CATCH: an option that arrived and had no effect, with animation on.
#
# Closing the second case requires comparing the difference BETWEEN the sides
# against the variation WITHIN one side, which is a measurement and not a
# byte comparison. It is on the list, and until then this guard only promises
# what it delivers.
# THE MEASUREMENT, not the byte comparison.
#
# The previous version only asked whether the two sides were identical. That
# catches the historical defect (a mesh option that did not arrive, cache
# never rebuilt, both sides byte for byte equal) and does not catch the case
# that matters now: an option that arrived and did nothing. With animation on
# the sides are recorded in sequence, the phase advances, and they ALWAYS
# differ. Measured: filming with the same value on both sides did not trigger
# the guard.
#
# So the right question is not "do they differ?", it is "do they differ MORE
# than one side differs from itself?". The variation within one side is the
# animation; what exceeds that is the option. Same shape as the floor the
# life probe measures with its own procedure, and as the judge's blind
# features report: comparison only becomes evidence once something else
# establishes the scale.
#
# PSNR because it already ships with ffmpeg and is monotonic in what we want:
# the LOWER, the more different. So the option only counts if the pair
# between sides is more different (lower PSNR) than the pair within one side.
psnr() {  # $1 $2 = png; prints the average PSNR, or empty
  "$FFMPEG" -hide_banner -i "$1" -i "$2" -lavfi psnr -f null - 2>&1 \
    | grep -oE "average:[0-9.]+" | head -1 | cut -d: -f2
}

DENTRO=$(psnr "$TMP/vc_clip_off_0010.png" "$TMP/vc_clip_piso_0010.png")
ENTRE=$(psnr "$TMP/vc_clip_off_0010.png" "$TMP/vc_clip_on_0010.png")
if [ -z "$DENTRO" ] || [ -z "$ENTRE" ]; then
  echo "FALHOU: could not measure the frames (ffmpeg without psnr?)"
  exit 1
fi
printf "psnr within one side %s, between the sides %s\n" "$DENTRO" "$ENTRE"
# `inf` comes out when the frames are identical. On the DENTRO (within) side
# that means a still scene, and then the comparison loses its reference; on
# the ENTRE (between) side it means the option changed nothing, which is a
# direct fail.
case "$ENTRE" in inf|"") echo "FALHOU: both sides are identical at frame 10"; exit 1;; esac
case "$DENTRO" in
  inf) echo "  (still scene: no animation, any difference between sides is the option)";;
  *)
    MAIOR=$(awk -v a="$ENTRE" -v b="$DENTRO" 'BEGIN{print (a < b) ? 1 : 0}')
    if [ "$MAIOR" != "1" ]; then
      echo "FALHOU: the sides differ LESS from each other ($ENTRE) than one side"
      echo "  differs from itself ($DENTRO). That is the animation, not the option."
      echo "  A clip like this looks like a comparison without being one."
      exit 1
    fi;;
esac

# The floor frames come out before assembly: they exist to measure, not to
# appear.
rm -f "$TMP"/vc_clip_piso_*.png

FPS="${VC_CLIP_FPS:-30}"
ESCALA="${VC_CLIP_ESCALA:-640}"
# CROP instead of zooming the game camera. Forcing zoom in the game pulls the
# camera to a low angle and fills half the frame with ground; cropping
# afterward does not touch anything the game drew and frames exactly the
# character, who always stays near the center because the camera follows them
# (Camera.lua:14-18). The crop is a bit above center: the feet stay in the
# middle, the body rises.
RECORTE="${VC_CLIP_RECORTE:-560:420:232:200}"

monta() {  # $1 = side, $2 = output file
  "$FFMPEG" -y -loglevel error -framerate "$FPS" -start_number 1 \
    -i "$TMP/vc_clip_$1_%04d.png" \
    -vf "crop=$RECORTE,scale=$ESCALA:-2:flags=neighbor" \
    -c:v libx264 -pix_fmt yuv420p -crf 18 "$2"
}
monta off "$SAIDA/$CHAVE-$SUFIXO-a.mp4" || { echo "ffmpeg failed on the off side"; exit 1; }
monta on  "$SAIDA/$CHAVE-$SUFIXO-b.mp4"  || { echo "ffmpeg failed on the on side"; exit 1; }

# Side by side. LEFT off, RIGHT on, with a strip between the two so there is
# no doubt where one ends. No caption over the video on purpose: this ffmpeg
# has no drawtext (no libfreetype), and a pipeline that depends on a
# third-party build breaks on the first user who does not have it.
"$FFMPEG" -y -loglevel error \
  -i "$SAIDA/$CHAVE-$SUFIXO-a.mp4" -i "$SAIDA/$CHAVE-$SUFIXO-b.mp4" \
  -filter_complex "[0:v]pad=iw+4:ih:0:0:color=white[e];[e][1:v]hstack=inputs=2" \
  -c:v libx264 -pix_fmt yuv420p -crf 18 "$SAIDA/$CHAVE-$SUFIXO-ab.mp4" \
  || { echo "ffmpeg failed on the side-by-side"; exit 1; }

# GIF in two passes: own palette, otherwise the sky gradient turns into banding.
"$FFMPEG" -y -loglevel error -i "$SAIDA/$CHAVE-$SUFIXO-ab.mp4" \
  -vf "fps=$FPS,scale=720:-2:flags=neighbor,palettegen=stats_mode=diff" \
  "$TMP/paleta.png" || { echo "ffmpeg failed on the palette"; exit 1; }
"$FFMPEG" -y -loglevel error -i "$SAIDA/$CHAVE-$SUFIXO-ab.mp4" -i "$TMP/paleta.png" \
  -lavfi "fps=$FPS,scale=720:-2:flags=neighbor[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
  "$SAIDA/$CHAVE-$SUFIXO-ab.gif" || { echo "ffmpeg failed on the gif"; exit 1; }

rm -rf "$TMP"
echo "CLIPE OK"
for f in "$SAIDA"/*.mp4 "$SAIDA"/*.gif; do
  [ -e "$f" ] && printf "  %-40s %s\n" "$(basename "$f")" \
    "$(du -h "$f" | cut -f1 | tr -d ' ')"
done
ESQ="${OPCAO#*=}"; DIR="$ESQ"
case "$ESQ" in *:*) DIR="${ESQ#*:}"; ESQ="${ESQ%%:*}";; *) ESQ="off";; esac
echo "  in the side-by-side: left $CHAVE=$ESQ, right $CHAVE=$DIR"
