#!/bin/bash
# THE AUDIO GATE (roadmap T1.3), built before there is any audio to measure.
#
#   tools/audio_gate.sh <off-audio> <on-audio>
#   tools/audio_gate.sh --selftest
#
# WHY IT EXISTS BEFORE THE SOUND DOES. Roadmap T2.3 wants character SFX, and
# there is no audio anywhere in this mod today: a sweep for love.audio and
# newSource across main.lua and every tool returns nothing. So SFX is a new
# subsystem, and this project's habit is to build the ruler before trusting the
# measurement.
#
# "It played" is not evidence, in the same way "it changed" was not evidence for
# MOTION LAG when it was shearing the body 45 degrees past 465 offline checks
# and eight in-game checks. Every one of them asked whether something changed
# and none asked by how much or in which direction. This asks how much.
#
# THREE CHECKS, and the OFF path is the one that carries the most weight:
#
#   A1  the off path is SILENT. A negative gate: an effect that plays when it is
#       switched off is the audio version of the defect the clip guard exists
#       for, and nobody would hear it in a busy scene.
#   A2  the on path has SIGNAL, measured against the off path rather than
#       against a guessed constant. Same-procedure floor, the rule this
#       repository keeps re-learning.
#   A3  the on path peaks UNDER A CEILING, so a demo effect cannot blast over
#       the game.
#
# THE NUMBERS ARE A FIRST GUESS AND SAY SO. -60 dBFS for "silent" and -6 dBFS
# for the ceiling are defensible starting points, not measurements: the real
# ceiling should come from comparing against the game's own music and SFX levels
# once there is something to compare with, and that comparison does not exist
# yet. Named here rather than left implied. What is NOT a guess is A2's floor,
# which is captured from the off path in the same run.
set -u

AQUI="$(cd "$(dirname "$0")" && pwd)"
MOD="$AQUI/.."
# shellcheck disable=SC1090
. "$AQUI/tools_bin.sh"

SILENCIO="-60"   # dBFS at or below which the off path counts as silent
TETO="-6"        # dBFS the on path must stay under
MARGEM="20"      # dB the on path must exceed the off path by

SELF=0
OFF=""; ON=""
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) SELF=1; shift ;;
    --ceiling) TETO="${2:?--ceiling needs a value}"; shift 2 ;;
    --silence) SILENCIO="${2:?--silence needs a value}"; shift 2 ;;
    --margin) MARGEM="${2:?--margin needs a value}"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) if [ -z "$OFF" ]; then OFF="$1"; else ON="$1"; fi; shift ;;
  esac
done

[ -n "$FFMPEG" ] || {
  echo "ffmpeg not found (PATH, \$FFMPEG_BIN, /opt/homebrew, /usr/local)" >&2
  echo "  NEXT: brew install ffmpeg" >&2
  exit 2
}

# ------------------------------------------------------------------ measuring
#
# volumedetect reports mean_volume and max_volume in dBFS. Pure digital silence
# comes back as -91.0 on 16-bit material, which is the format's own floor rather
# than a true zero, so "silent" is a threshold and not an equality test.
#
# REFUSES A FILE IT COULD NOT MEASURE. An absent or undecodable file makes
# volumedetect print nothing, and an empty measurement compared against another
# empty measurement is the false green tools_bin.sh records: with $LOVE unset, a
# check compared two empty strings and passed. So a missing number is an error,
# never a zero.
medir() {  # $1 = file; echoes "max mean", or nothing on failure
  local f="$1"
  [ -f "$f" ] || return 1
  [ -s "$f" ] || return 1
  local saida mx mn
  saida=$("$FFMPEG" -hide_banner -nostdin -i "$f" -af volumedetect -f null - 2>&1) || return 1
  mx=$(printf '%s' "$saida" | grep -oE 'max_volume: -?[0-9.]+' | head -1 | grep -oE '\-?[0-9.]+$')
  mn=$(printf '%s' "$saida" | grep -oE 'mean_volume: -?[0-9.]+' | head -1 | grep -oE '\-?[0-9.]+$')
  [ -n "$mx" ] && [ -n "$mn" ] || return 1
  printf '%s %s' "$mx" "$mn"
}

menor_ou_igual() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a <= b) }'; }
maior_ou_igual() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a >= b) }'; }
soma() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", a + b }'; }

avalia() {  # $1 = off file, $2 = on file; prints verdicts, returns nonzero on failure
  local off="$1" on="$2" falhas=0
  local m_off m_on off_max off_mean on_max on_mean

  m_off=$(medir "$off") || {
    echo "A0 FAILED    could not measure the OFF file: $off"
    echo "             A file that cannot be measured is not a silent file."
    return 1
  }
  m_on=$(medir "$on") || {
    echo "A0 FAILED    could not measure the ON file: $on"
    echo "             A tool that wrote no audio did not play anything."
    return 1
  }
  off_max=${m_off%% *}; off_mean=${m_off##* }
  on_max=${m_on%% *};   on_mean=${m_on##* }

  echo "off          max ${off_max} dBFS   mean ${off_mean} dBFS"
  echo "on           max ${on_max} dBFS   mean ${on_mean} dBFS"
  echo "thresholds   silent <= ${SILENCIO}, ceiling <= ${TETO}, margin >= ${MARGEM} dB"

  if menor_ou_igual "$off_max" "$SILENCIO"; then
    echo "A1 PASSED    the off path is silent (${off_max} <= ${SILENCIO})"
  else
    echo "A1 FAILED    the off path is NOT silent (${off_max} > ${SILENCIO})"
    echo "             Something plays when the option is off."
    falhas=$((falhas + 1))
  fi

  local minimo
  minimo=$(soma "$off_max" "$MARGEM")
  if maior_ou_igual "$on_max" "$minimo"; then
    echo "A2 PASSED    the on path has signal (${on_max} >= ${minimo}, floor from this run)"
  else
    echo "A2 FAILED    the on path has no signal above its own floor"
    echo "             ${on_max} is not ${MARGEM} dB above the off path's ${off_max}."
    falhas=$((falhas + 1))
  fi

  if menor_ou_igual "$on_max" "$TETO"; then
    echo "A3 PASSED    the on path stays under the ceiling (${on_max} <= ${TETO})"
  else
    echo "A3 FAILED    the on path is too loud (${on_max} > ${TETO})"
    echo "             A demo effect must not blast over the game."
    falhas=$((falhas + 1))
  fi

  [ "$falhas" -eq 0 ] && { echo "AUDIO GATE OK"; return 0; }
  echo "AUDIO GATE FAILED: $falhas of 3"
  return 1
}

# ------------------------------------------------------------------ selftest
#
# Fixtures are generated with ffmpeg, so this needs no audio assets, no LOVE and
# no display. The amplitudes below were MEASURED rather than assumed: lavfi's
# `sine` peaks at -18.1 dBFS at its default amplitude, not at 0, so a test built
# on the theoretical number would have been calibrated against nothing.
#
#   silence            -91.0   (the 16-bit floor)
#   sine, default      -18.1   a reasonable effect
#   sine, volume=+15   ~ -3.1  too loud
#   sine, volume=-20   -38.1   audible, so not silent
if [ "$SELF" = "1" ]; then
  TMPA="$(mktemp -d -t vcaudio)" || exit 1
  trap 'rm -rf "$TMPA"' EXIT
  gera() {  # $1 = file, $2 = lavfi source, $3 = extra filter or empty
    local f="$1" src="$2" filtro="${3:-}"
    if [ -n "$filtro" ]; then
      "$FFMPEG" -hide_banner -loglevel error -y -f lavfi -i "$src" -t 0.5 \
        -af "$filtro" "$f" || return 1
    else
      "$FFMPEG" -hide_banner -loglevel error -y -f lavfi -i "$src" -t 0.5 "$f" || return 1
    fi
  }
  gera "$TMPA/silencio.wav" "anullsrc=r=44100:cl=mono" || { echo "fixture failed"; exit 1; }
  gera "$TMPA/efeito.wav"   "sine=frequency=440:sample_rate=44100" || { echo "fixture failed"; exit 1; }
  gera "$TMPA/alto.wav"     "sine=frequency=440:sample_rate=44100" "volume=+15dB" || { echo "fixture failed"; exit 1; }
  gera "$TMPA/vazando.wav"  "sine=frequency=440:sample_rate=44100" "volume=-20dB" || { echo "fixture failed"; exit 1; }
  : > "$TMPA/vazio.wav"

  falhas=0; casos=0
  espera() {  # $1 = wanted (0 ok / 1 fail), $2 = name, $3 = off, $4 = on
    local quero="$1" nome="$2" off="$3" on="$4" saida rc got
    casos=$((casos + 1))
    saida=$(avalia "$off" "$on" 2>&1); rc=$?
    got=0; [ "$rc" -ne 0 ] && got=1
    if [ "$got" = "$quero" ]; then
      printf "  %-48s ok\n" "$nome"
    else
      printf "  %-48s WRONG (rc=%s, wanted %s)\n" "$nome" "$rc" "$quero"
      printf '%s\n' "$saida" | sed 's/^/       /'
      falhas=$((falhas + 1))
    fi
  }

  echo "audio gate selftest: does it fail when it should?"
  echo "  (fixtures generated with ffmpeg; no LOVE, no display, no assets)"
  espera 0 "silent off plus a reasonable effect passes" "$TMPA/silencio.wav" "$TMPA/efeito.wav"
  espera 1 "an off path that plays something fails A1"  "$TMPA/vazando.wav"  "$TMPA/efeito.wav"
  espera 1 "an on path with no signal fails A2"         "$TMPA/silencio.wav" "$TMPA/silencio.wav"
  espera 1 "an on path over the ceiling fails A3"       "$TMPA/silencio.wav" "$TMPA/alto.wav"
  espera 1 "a missing file is refused, not passed"      "$TMPA/silencio.wav" "$TMPA/nope.wav"
  espera 1 "an empty file is refused, not passed"       "$TMPA/silencio.wav" "$TMPA/vazio.wav"

  # The measurement itself has to be right, not only its verdicts: if medir
  # silently returned the same number for everything, every case above would
  # still land where it is expected to.
  casos=$((casos + 1))
  s_max=$(medir "$TMPA/silencio.wav" | cut -d' ' -f1)
  e_max=$(medir "$TMPA/efeito.wav" | cut -d' ' -f1)
  a_max=$(medir "$TMPA/alto.wav" | cut -d' ' -f1)
  if menor_ou_igual "$s_max" "-90" && maior_ou_igual "$e_max" "-25" \
     && menor_ou_igual "$e_max" "-10" && maior_ou_igual "$a_max" "-6"; then
    printf "  %-48s ok\n" "the measurement tells the fixtures apart"
    echo "       silence $s_max, effect $e_max, loud $a_max dBFS"
  else
    printf "  %-48s WRONG\n" "the measurement tells the fixtures apart"
    echo "       silence $s_max, effect $e_max, loud $a_max dBFS"
    falhas=$((falhas + 1))
  fi

  echo ""
  if [ "$falhas" -eq 0 ]; then
    echo "AUDIO GATE SELFTEST OK: $casos cases, every failing state failed"
    exit 0
  fi
  echo "AUDIO GATE SELFTEST FAILED: $falhas of $casos"
  exit 1
fi

# --------------------------------------------------------------------- normal
[ -n "$OFF" ] && [ -n "$ON" ] || {
  echo "usage: audio_gate.sh <off-audio> <on-audio>" >&2
  echo "       audio_gate.sh --selftest" >&2
  echo "" >&2
  echo "  --ceiling <dBFS>  peak the on path must stay under (default $TETO)" >&2
  echo "  --silence <dBFS>  at or below which the off path is silent (default $SILENCIO)" >&2
  echo "  --margin <dB>     how far the on path must exceed the off path (default $MARGEM)" >&2
  exit 2
}
avalia "$OFF" "$ON"
