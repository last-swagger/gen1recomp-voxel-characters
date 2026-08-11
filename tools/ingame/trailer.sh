#!/bin/bash
# Builds the TRAILER: runs the game driven by trailer.lua's shot list, records
# the whole sequence and joins it into an mp4.
#
#   tools/ingame/trailer.sh <pasta-de-saida>
#   VC_TRAILER_SEGUNDOS=12 tools/ingame/trailer.sh /tmp/t    short version
#   VC_TRAILER_HORA=night  tools/ingame/trailer.sh /tmp/t    force one hour
#
# The shot list (maps, camera rungs, options, captions, hour) lives in
# trailer.lua. This file only runs and assembles, deliberately: whoever edits
# the trailer edits data, not shell.
set -u
REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
SAVE="$HOME/Library/Application Support/LOVE/pokemon-love2d"
. "$(cd "$(dirname "$0")/.." && pwd)/tools_bin.sh"
DRIVER="$REPO/mods/voxel_characters/tools/ingame/trailer.lua"

SAIDA="${1:?uso: trailer.sh <pasta-de-saida>}"
[ -n "$FFMPEG" ] || { echo "ffmpeg not found"; exit 1; }
[ -f "$DRIVER" ] || { echo "shot list not found: $DRIVER"; exit 1; }

versao_pronta() {
  case "$1" in
    red) [ -e "$REPO/data/generated/constants.lua" ] \
      && [ -e "$REPO/assets/generated/audio/programs.bin" ] ;;
    *) [ -f "$SAVE/$1/rom-cache.complete" ] ;;
  esac
}
VERSAO="${VC_VERSION:-}"
if [ -z "$VERSAO" ]; then
  for v in blue red yellow; do versao_pronta "$v" && { VERSAO="$v"; break; }; done
fi
[ -n "$VERSAO" ] || { echo "no version ready"; exit 1; }

vc_trava_pega "trailer.sh" || exit 1
pkill -x love 2>/dev/null
for _ in $(seq 1 20); do pgrep -x love >/dev/null 2>&1 || break; sleep 0.5; done

rm -rf "$SAIDA" && mkdir -p "$SAIDA"
find "$SAVE" -maxdepth 1 -name 'vc_trailer_*.png' -delete 2>/dev/null
LOG="$SAIDA/trailer.log"

cd "$REPO" || exit 1
echo "version: $VERSAO   shot list: $(basename "$DRIVER")"
POKEPORT_VERSION="$VERSAO" POKEPORT_DRIVER="$DRIVER" "$LOVE" . > "$LOG" 2>&1

# The driver says how many frames it recorded. Counting files instead of
# believing the log already caught a run that died halfway and looked complete.
ESPERADOS=$(grep -oE 'end, [0-9]+ frames' "$LOG" | grep -oE '[0-9]+' | tail -1)
N=$(find "$SAVE" -maxdepth 1 -name 'vc_trailer_*.png' | wc -l | tr -d ' ')
if [ -z "$ESPERADOS" ]; then
  echo "FAILED: the shot list did not reach the end"
  tail -5 "$LOG"
  exit 1
fi
echo "frames: $N recorded, $ESPERADOS expected"
[ "$N" -ge "$ESPERADOS" ] || { echo "FAILED: frames are missing"; exit 1; }

TMP="$SAIDA/.quadros"
mkdir -p "$TMP"
find "$SAVE" -maxdepth 1 -name 'vc_trailer_*.png' -exec mv {} "$TMP"/ \;

FPS="${VC_TRAILER_FPS:-30}"
# No crop: a trailer shows the game's own framing, unlike the feature clip,
# which crops to the character because the question there is a different one.
"$FFMPEG" -y -loglevel error -framerate "$FPS" -start_number 1 \
  -i "$TMP/vc_trailer_%05d.png" \
  -c:v libx264 -pix_fmt yuv420p -crf 18 -preset slow \
  "$SAIDA/trailer.mp4" || { echo "ffmpeg failed"; exit 1; }

# A short GIF of the opening, for threads where video does not autoplay.
"$FFMPEG" -y -loglevel error -t 6 -i "$SAIDA/trailer.mp4" \
  -vf "fps=15,scale=640:-2:flags=neighbor,palettegen=stats_mode=diff" \
  "$TMP/paleta.png" >/dev/null 2>&1
"$FFMPEG" -y -loglevel error -t 6 -i "$SAIDA/trailer.mp4" -i "$TMP/paleta.png" \
  -lavfi "fps=15,scale=640:-2:flags=neighbor[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3" \
  "$SAIDA/trailer.gif" >/dev/null 2>&1

rm -rf "$TMP"
echo "TRAILER OK"
for f in "$SAIDA"/trailer.mp4 "$SAIDA"/trailer.gif; do
  [ -e "$f" ] && printf "  %-20s %s\n" "$(basename "$f")" \
    "$(du -h "$f" | cut -f1 | tr -d ' ')"
done
grep -E '^\[trailer\] plano' "$LOG" | sed 's/^\[trailer\] /  /'
