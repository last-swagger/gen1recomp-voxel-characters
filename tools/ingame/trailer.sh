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
#
# IT CAN REFUSE. trailer.lua judges every shot from inside the game -- was the
# terrain finished building, did the animation clock run at the video's own
# rate, can the machine draw the scene at the rate the file claims -- and this
# assembles nothing and exits non-zero when any shot failed. A trailer is
# published; a bad one is worse than none.
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

# NOTHING IS ASSEMBLED BEFORE THE SHOTS ARE JUDGED, same order clip.sh uses:
# its PSNR gate runs on the captured frames and exits before ffmpeg is asked
# for a single file, because a bad artifact that exists is an artifact someone
# posts.
#
# THE JUDGEMENT IS NOT MADE OUT HERE ON THE PIXELS, and that was tried first,
# on clip.sh's model. It does not work for a trailer and the measurement says
# why. Pop-in was supposed to show as consecutive frames at the head of a shot
# differing far more than the same shot's settled middle, and it does: 26 dB
# against 42. So does an NPC taking a step. Checked by generating the
# difference image and looking at it, the 20 dB "pop-in" at the head of shot 3
# is a character walking across; frame to frame, the mean luma difference in
# that shot never exceeds 0.8 of 255, and PSNR is dominated by the few pixels
# that change completely. Across the eleven shots the two populations overlap:
# genuine pop-in measured 4.3 dB below the shot's own floor where a healthy
# first-person shot measured 24.7 dB below it. A gate with that much overlap
# would refuse good trailers and pass bad ones, so it does not exist.
#
# What CAN answer the question exactly is inside the game: the host's build
# queue knows when the terrain is finished, to the job. So the driver judges
# and this reads the verdict -- and checks that the verdict was actually
# produced, below, because trusting a log is only safe if a missing log fails.
#
# AND A MISSING VERDICT IS A FAILURE, not a pass. Counting refusals alone
# passes a run whose guards never executed: an older trailer.lua, a driver that
# died between shots, a host without ChunkMesher. So the count of measured
# shots has to match the count of recorded shots, and the summary line has to
# be there. This is the same rule the battery applies to the in-game gates --
# zero FAILED is not enough, there must also be a PASSED.
PLANOS=$(grep -cE '^\[trailer\] plano [0-9]+/[0-9]+ ' "$LOG")
MEDIDOS=$(grep -c 'cost: render' "$LOG")
echo "shots: $PLANOS recorded, $MEDIDOS measured"
if [ "$PLANOS" -eq 0 ] || [ "$MEDIDOS" -ne "$PLANOS" ]; then
  echo "FAILED: $MEDIDOS of $PLANOS shots carry a measurement. A trailer whose"
  echo "  guards did not run is not a trailer that passed them."
  exit 1
fi
if ! grep -q 'TRAILER SHOTS OK\|TRAILER SHOTS REFUSED' "$LOG"; then
  echo "FAILED: the shot list printed no verdict at all"
  exit 1
fi
if grep -q 'REFUSED plano' "$LOG"; then
  echo "REFUSED: this recording should not be published."
  grep 'REFUSED plano' "$LOG" | sed 's/^\[trailer\] /  /'
  echo "  Nothing was assembled. The frames are still in the save directory."
  exit 1
fi

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
