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
# VC_CLIP_FIXO holds other options identical on BOTH sides, which some options
# need in order to be filmable at all. PART LAG delays what MOTION LAG, SWAY or
# ATTENTION are doing and delays a constant without them; AUTHORED REGIONS only
# changes where PART LAG cuts. Filmed alone, either one produces two identical
# halves and the PSNR guard refuses to publish -- correctly, and for a reason
# nobody could see from the output.
#
#   VC_CLIP_FIXO="part_lag=0.16,lag=1.2" tools/ingame/clip.sh /tmp/c authored_regions=off:on
#
# VC_CLIP_DEGRAU picks the host's camera step:
#   off baixo medio alto empe primeira terceira, or the level number.
# Without it, clip.lua now pins "alto" rather than leaving it at whatever
# step the save has: that used to vary between runs and broke consistent
# framing across time.
#
# The second form is to CHOOSE, not to verify. Against OFF the question is
# "does it do anything?"; between two levels it is "which one?", the only
# question left once the feature exists, and the only one whose answer is
# taste.
#
# Outputs: <option>-off.mp4, <option>-on.mp4, <option>-ab.mp4 and <option>-ab.gif
# In the side-by-side, LEFT is off and RIGHT is on, always.
#
# POSTABLE, which is what roadmap 21.2 asked for. The ab.mp4 now opens on a
# two second TITLE CARD (the option's name and one sentence of what it does,
# drawn by the game in clip.lua) before the comparison, and both sides carry
# a LOWER THIRD naming the option and its level, fading in and out the same
# way trailer.lua's captions do. The camera step defaults to "alto" instead
# of whatever the save had (see clip.lua), so a feature filmed in March
# frames the same as one filmed today. CRF and scale are picked from a real
# measurement, not a guess: see the comment above GIF_FPS below.

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
QUADROS=$(grep -oE 'frames per side: [0-9]+' "$LOG" | grep -oE '[0-9]+' | tail -1)
if [ -z "$QUADROS" ]; then
  echo "FAILED: the driver did not finish"
  # TWELVE, not five. The driver's own refusal for an unrecognised key now
  # prints the two scans it made and what each one found or failed at, which is
  # the whole point of it: the reader has to see WHY the key was not found, not
  # only that it was not. At five lines that diagnosis was cut in half and the
  # only line to survive was the verdict.
  tail -12 "$LOG"
  exit 1
fi

N_OFF=$(find "$SAVE" -maxdepth 1 -name 'vc_clip_off_*.png' | wc -l | tr -d ' ')
N_ON=$(find "$SAVE" -maxdepth 1 -name 'vc_clip_on_*.png' | wc -l | tr -d ' ')
echo "frames recorded: $N_OFF off, $N_ON on"
if [ "$N_OFF" -lt 10 ] || [ "$N_ON" -lt 10 ]; then
  echo "FAILED: too few frames"
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
#
# MEASURED ON THE RAW FRAME, lower third and all, same as before this
# rewrite: clip.lua now keeps the lower third invisible through frame 10
# specifically (see the ATRASO comment in clip.lua), which is the ONE frame
# this gate reads. A first attempt at this tried to fix it here instead, by
# cropping the caption's own band out of frame 10 before measuring. It
# looked right and was not: on `depth=10` the crop needed to hide the
# caption also cut into real, non-caption signal a few dozen pixels above
# it (measured: excluding the last 90px hid a genuine 24 dB difference that
# excluding only the last 30px did not, on the SAME frame, in the pre-lower-
# third code's own middle band). A pixel band is content-dependent and
# fragile; keeping the label off the one frame that gets measured is not.
psnr() {  # $1 $2 = png; prints the average PSNR, or empty
  # Matches "inf" too, not just digits. Without it a truly identical pair
  # (which the "inf comes out when the frames are identical" comment below
  # already anticipated) returned EMPTY instead of the literal word "inf",
  # so it fell into the generic "could not measure the frames" error instead
  # of the specific one below. Found running the negative gate test
  # (`naoexiste=1`) against this rewrite: it correctly refuses either way,
  # but only this fix makes it refuse with the RIGHT reason.
  "$FFMPEG" -hide_banner -i "$1" -i "$2" -lavfi psnr -f null - 2>&1 \
    | grep -oE "average:(inf|[0-9.]+)" | head -1 | cut -d: -f2
}

DENTRO=$(psnr "$TMP/vc_clip_off_0010.png" "$TMP/vc_clip_piso_0010.png")
ENTRE=$(psnr "$TMP/vc_clip_off_0010.png" "$TMP/vc_clip_on_0010.png")
if [ -z "$DENTRO" ] || [ -z "$ENTRE" ]; then
  echo "FAILED: could not measure the frames (ffmpeg without psnr?)"
  exit 1
fi
printf "psnr within one side %s, between the sides %s\n" "$DENTRO" "$ENTRE"
# `inf` comes out when the frames are identical. On the DENTRO (within) side
# that means a still scene, and then the comparison loses its reference; on
# the ENTRE (between) side it means the option changed nothing, which is a
# direct fail.
case "$ENTRE" in inf|"") echo "FAILED: both sides are identical at frame 10"; exit 1;; esac
case "$DENTRO" in
  inf) echo "  (still scene: no animation, any difference between sides is the option)";;
  *)
    MAIOR=$(awk -v a="$ENTRE" -v b="$DENTRO" 'BEGIN{print (a < b) ? 1 : 0}')
    if [ "$MAIOR" != "1" ]; then
      echo "FAILED: the sides differ LESS from each other ($ENTRE) than one side"
      echo "  differs from itself ($DENTRO). That is the animation, not the option."
      echo "  A clip like this looks like a comparison without being one."
      exit 1
    fi;;
esac

# The floor frames come out before assembly: they exist to measure, not to
# appear.
rm -f "$TMP"/vc_clip_piso_*.png

FPS="${VC_CLIP_FPS:-30}"
# THREE TIMES, EXACTLY, AND NOT 640.
#
# This was 640 against a 560 pixel crop: a scale of 1.14, which is not an
# integer, so `flags=neighbor` cannot help and every art pixel lands across a
# fractional boundary. Then `-pix_fmt yuv444p` throws away colour in 2x2 blocks,
# and at that scale a 2x2 block IS an art pixel.
#
# Measured, after Kim reported that a piece of a character seemed to disappear:
# the character band of one frame held 831 distinct colours in art that has
# FOUR. Refilming at CRF 0 still gave 483, which is how it was established that
# the loss is the subsampling and not the bitrate. The palette GIF beside it
# gave 98.
#
# So the clip was destroying exactly the single-pixel detail these options
# change, in the one artifact Kim uses to judge them. An integer 3x means each
# art pixel is a 3x3 block and a chroma pair no longer straddles two of them.
ESCALA="${VC_CLIP_ESCALA:-1680}"
# CRF 18 MEASURED, not guessed. A 15 second WORST CASE clip (VC_CLIP_FRAMES=450,
# VC_CLIP_ANDAR=1 so the character walks the whole time instead of standing
# still, the highest-motion content this tool makes) at CRF 18 / scale 640
# came out to a.mp4 1.24 MB, b.mp4 1.28 MB, ab.mp4 2.4 MB: comfortably under
# Discord's 10 MB free limit with room to spare, and CRF 18 is already the
# point x264 is usually called visually transparent, so there is no quality
# to buy by spending more of that margin. Kept as a named knob rather than a
# bare number so the next measurement does not have to hunt for it.
CRF="${VC_CLIP_CRF:-18}"
# GIF FPS AND WIDTH ARE THEIR OWN KNOB, lower than the video's, because a gif
# has no CRF: the only way to control its size is fewer, smaller frames. Same
# worst case measured above, at the OLD 30 fps / 720 px this tool used to
# hardcode: 10.46 MB, already OVER the 10 MB limit before Discord even saw
# the mp4. At 20 fps and this side's own width (640, so the gif is not
# secretly the sharpest output) it measured 5.87 MB: comfortably under, and
# 20 fps still reads breathing and walking fine, it only drops what a gif
# palette could not keep clean anyway.
GIF_FPS="${VC_CLIP_GIF_FPS:-20}"
# CROP instead of zooming the game camera. Forcing zoom in the game pulls the
# camera to a low angle and fills half the frame with ground; cropping
# afterward does not touch anything the game drew and frames exactly the
# character, who always stays near the center because the camera follows them
# (Camera.lua:14-18). The crop is a bit above center: the feet stay in the
# middle, the body rises.
#
# DETERMINISTIC AND IDENTICAL BETWEEN THE TWO SIDES by construction: this one
# $RECORTE value feeds both monta() calls below, and the desktop window opens
# at a fixed, non-resizable 1024x768 (conf.lua), so the same box always means
# the same patch of screen, on this machine or another, in March or today.
RECORTE="${VC_CLIP_RECORTE:-560:420:232:200}"

monta() {  # $1 = side, $2 = output file
  "$FFMPEG" -y -loglevel error -framerate "$FPS" -start_number 1 \
    -i "$TMP/vc_clip_$1_%04d.png" \
    -vf "crop=$RECORTE,scale=$ESCALA:-2:flags=neighbor" \
    -c:v libx264 -pix_fmt yuv444p -crf "$CRF" "$2"
}
monta off "$SAIDA/$CHAVE-$SUFIXO-a.mp4" || { echo "ffmpeg failed on the off side"; exit 1; }
monta on  "$SAIDA/$CHAVE-$SUFIXO-b.mp4"  || { echo "ffmpeg failed on the on side"; exit 1; }

# Side by side, CORE comparison only: the title card gets attached after, once
# this file exists, so the two segments are guaranteed to share the exact
# same width and height instead of two independent guesses at it.
# LEFT off, RIGHT on, with a strip between the two so there is no doubt where
# one ends. No caption over the video on purpose: this ffmpeg has no drawtext
# (no libfreetype), and a pipeline that depends on a third-party build breaks
# on the first user who does not have it.
"$FFMPEG" -y -loglevel error \
  -i "$SAIDA/$CHAVE-$SUFIXO-a.mp4" -i "$SAIDA/$CHAVE-$SUFIXO-b.mp4" \
  -filter_complex "[0:v]pad=iw+4:ih:0:0:color=white[e];[e][1:v]hstack=inputs=2" \
  -c:v libx264 -pix_fmt yuv444p -crf "$CRF" "$TMP/nucleo-ab.mp4" \
  || { echo "ffmpeg failed on the side-by-side"; exit 1; }

# TITLE CARD: two seconds at the head with the option's name and one sentence
# of what it does. clip.lua already drew that into ONE frame
# (vc_clip_title_0001.png), captured through the same crop as the sides so it
# lines up with them; here it only gets scaled the same way, padded to the
# comparison's full width, and held for two seconds with -loop. Same division
# of labor as everywhere else in this pipeline: the GAME draws pixels, ffmpeg
# only holds and stitches them, so nothing here depends on a drawtext build.
LARGURA_AB=$((ESCALA * 2 + 4))
if [ -f "$TMP/vc_clip_title_0001.png" ]; then
  "$FFMPEG" -y -loglevel error -loop 1 -i "$TMP/vc_clip_title_0001.png" \
    -t 2 -r "$FPS" \
    -vf "crop=$RECORTE,scale=$ESCALA:-2:flags=neighbor,pad=$LARGURA_AB:ih:($LARGURA_AB-iw)/2:0:color=black" \
    -c:v libx264 -pix_fmt yuv444p -crf "$CRF" "$TMP/titulo.mp4" \
    || { echo "ffmpeg failed on the title card"; exit 1; }
  "$FFMPEG" -y -loglevel error -i "$TMP/titulo.mp4" -i "$TMP/nucleo-ab.mp4" \
    -filter_complex "[0:v][1:v]concat=n=2:v=1:a=0[v]" -map "[v]" \
    -c:v libx264 -pix_fmt yuv444p -crf "$CRF" "$SAIDA/$CHAVE-$SUFIXO-ab.mp4" \
    || { echo "ffmpeg failed attaching the title card"; exit 1; }
else
  echo "WARNING: no title card frame from clip.lua, shipping without one"
  cp "$TMP/nucleo-ab.mp4" "$SAIDA/$CHAVE-$SUFIXO-ab.mp4"
fi

# GIF in two passes: own palette, otherwise the sky gradient turns into
# banding. Reads from the FINISHED ab.mp4, so the title card rides along for
# free: whatever ended up in the mp4 is what becomes the gif, no separate step.
# NO DITHER, and stats_mode=full rather than diff.
# 
# This GIF is the artifact to trust for pixel detail, so it must not invent
# pixels. `dither=bayer` was scattering them on purpose: measured at 9% of
# 3x3 blocks perfectly uniform, against 65% for the mp4 beside it, on art
# where a faithful 3x upscale should be 100%. Dithering exists to fake shades
# a palette lacks, and this palette lacks nothing -- the art has four tones.
# 
# stats_mode=diff builds the palette from what CHANGES between frames, which
# for a two-panel comparison is the moving character and not the scene. full
# sees everything, and at four source tones there is no pressure on the 256
# slots anyway.
"$FFMPEG" -y -loglevel error -i "$SAIDA/$CHAVE-$SUFIXO-ab.mp4" \
  -vf "fps=$GIF_FPS,scale=$ESCALA:-2:flags=neighbor,palettegen=stats_mode=full" \
  "$TMP/paleta.png" || { echo "ffmpeg failed on the palette"; exit 1; }
"$FFMPEG" -y -loglevel error -i "$SAIDA/$CHAVE-$SUFIXO-ab.mp4" -i "$TMP/paleta.png" \
  -lavfi "fps=$GIF_FPS,scale=$ESCALA:-2:flags=neighbor[x];[x][1:v]paletteuse=dither=none:diff_mode=rectangle" \
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
