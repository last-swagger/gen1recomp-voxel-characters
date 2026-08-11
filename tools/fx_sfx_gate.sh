#!/bin/bash
# THE FX SOUNDS ARE REAL, checked by regenerating them (roadmap T2.3 slice 2).
#
#   bash mods/voxel_characters/tools/fx_sfx_gate.sh
#
# From the repo root. Needs luajit and ffmpeg, no display and no LOVE.
#
# WHY REGENERATE INSTEAD OF CHECKING A FILE. Two committed WAVs could only ever
# be checked once, by whoever listened to them; after that a gate can confirm
# the bytes are unchanged and nothing else. The sounds are generated here, so
# every run re-derives them and asks the question that matters: is what this
# project produces audible, and is it inside the ceiling that stops a demo
# effect blasting over the game.
#
# FOUR THINGS, and the last two are what stop this being decoration:
#
#   1. each sound passes audio_gate.sh against a silent control: the off path is
#      silent, the on path has signal above that floor, and the peak is under
#      the ceiling;
#   2. the two sounds are DIFFERENT files, or "two effects" is one effect with
#      two names;
#   3. generation is DETERMINISTIC, byte for byte, so a generator that starts
#      drifting is caught rather than absorbed;
#   4. silence really is silent, which is the control the whole measurement
#      leans on.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
MOD="$(cd "$AQUI/.." && pwd)"
RAIZ="$(cd "$MOD/../.." && pwd)"
LUAJIT=$(command -v luajit || echo /usr/local/bin/luajit)

command -v ffmpeg >/dev/null 2>&1 || {
  echo "ffmpeg not found; the audio gate cannot measure anything"
  echo "  NEXT: brew install ffmpeg"
  exit 2
}

TMP="$(mktemp -d -t vcsfx)" || exit 1
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/a" "$TMP/b"

cd "$RAIZ" || exit 1
falhas=0
diga() { printf '%s\n' "$*"; }

"$LUAJIT" "$MOD/tools/fx_sfx.lua" "$TMP/a" >/dev/null || {
  diga "FX SFX FAILED: the generator did not run"; exit 1; }

# 1. each sound against the silent control
for som in fireball bolt; do
  if bash "$MOD/tools/audio_gate.sh" "$TMP/a/silence.wav" "$TMP/a/$som.wav" \
       > "$TMP/$som.log" 2>&1; then
    printf "  %-34s %s\n" "$som" "$(grep '^on ' "$TMP/$som.log" | head -1 | sed 's/^on *//')"
  else
    printf "  %-34s FAILED\n" "$som"
    sed 's/^/      /' "$TMP/$som.log"
    falhas=$((falhas + 1))
  fi
done

# 2. two sounds, not one twice
if cmp -s "$TMP/a/fireball.wav" "$TMP/a/bolt.wav"; then
  diga "  the two effects are the SAME file, so there is one sound with two names"
  falhas=$((falhas + 1))
else
  printf "  %-34s ok\n" "fireball and bolt differ"
fi

# 3. deterministic, or the gate is measuring a different sound each time and
#    cannot tell a change from noise
"$LUAJIT" "$MOD/tools/fx_sfx.lua" "$TMP/b" >/dev/null
for som in fireball bolt silence; do
  if ! cmp -s "$TMP/a/$som.wav" "$TMP/b/$som.wav"; then
    diga "  $som is not reproducible: two runs gave different bytes"
    falhas=$((falhas + 1))
  fi
done
[ "$falhas" -eq 0 ] && printf "  %-34s ok\n" "generation is byte reproducible"

# 4. THE SHIPPED FILES ARE THE GENERATOR'S OUTPUT, byte for byte.
#
# This is what stops sfx/*.wav from being an opaque blob. They are versioned so
# the mod can play them without carrying a synthesiser, and versioned audio is
# exactly the kind of file nobody re-examines: it arrives once, sounds fine to
# whoever added it, and after that a diff can only say the bytes changed. Tying
# them to the generator means the sound in the package is the sound this gate
# measured, and a hand-edited or re-encoded file stops matching.
for som in fireball bolt; do
  if [ ! -f "$MOD/sfx/$som.wav" ]; then
    diga "  sfx/$som.wav is missing from the package"
    falhas=$((falhas + 1))
  elif ! cmp -s "$TMP/a/$som.wav" "$MOD/sfx/$som.wav"; then
    diga "  sfx/$som.wav is NOT what fx_sfx.lua produces; the shipped sound and"
    diga "    the measured sound are different files"
    falhas=$((falhas + 1))
  else
    printf "  %-34s %s\n" "shipped $som matches the generator" \
      "$(shasum -a 256 "$MOD/sfx/$som.wav" | cut -c1-12)"
  fi
done

# The shipped files also have to pass the audio gate in their own right, not
# only as a copy of something that passed.
for som in fireball bolt; do
  if [ -f "$MOD/sfx/$som.wav" ]; then
    bash "$MOD/tools/audio_gate.sh" "$TMP/a/silence.wav" "$MOD/sfx/$som.wav" \
      > "$TMP/ship_$som.log" 2>&1 || {
        diga "  the SHIPPED sfx/$som.wav does not pass the audio gate"
        sed 's/^/      /' "$TMP/ship_$som.log"
        falhas=$((falhas + 1)); }
  fi
done

# 5. the control really is silent. Everything above is measured against it, so
#    a "silent" file with signal in it would quietly raise the floor and let a
#    quiet effect pass as loud.
PICO=$(ffmpeg -hide_banner -nostdin -i "$TMP/a/silence.wav" -af volumedetect \
       -f null - 2>&1 | grep -oE 'max_volume: -?[0-9.]+' | grep -oE '\-?[0-9.]+$')
if [ -z "$PICO" ]; then
  diga "  the control could not be measured at all"
  falhas=$((falhas + 1))
elif ! awk -v p="$PICO" 'BEGIN { exit !(p <= -60) }'; then
  diga "  the silent control peaks at $PICO dBFS, which is not silence"
  falhas=$((falhas + 1))
else
  printf "  %-34s %s dBFS\n" "the silent control is silent" "$PICO"
fi

if [ "$falhas" -eq 0 ]; then
  echo "FX SFX OK: two real sounds, reproducible, inside the ceiling"
  exit 0
fi
echo "FX SFX FAILED: $falhas problem(s)"
exit 1
