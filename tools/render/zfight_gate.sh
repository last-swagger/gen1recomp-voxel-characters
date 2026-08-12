#!/bin/bash
# NO Z-FIGHTING AROUND A FULL TURN, measured rather than watched.
#
#   bash mods/voxel_characters/tools/render/zfight_gate.sh
#
# From the repo root. Needs LOVE and a display.
#
# WHERE THIS CAME FROM. The "Kanto HD-Voxel Engine Pipeline v2.0" specification
# asked for a validation step: "rotate the camera 360 degrees around the extruded
# tiles to check whether the Z axis renders without flicker or geometry
# interpenetration". The ruler measured four camera rungs and never a full turn,
# so the item was worth taking even though most of that document was not.
#
# HOW A FLICKER BECOMES A NUMBER. Two coplanar surfaces competing for the depth
# buffer do not produce a clean wrong answer, they produce an ALTERNATING one:
# neighbouring pixels resolve to different faces, sprayed across a region that
# should belong to one. The provenance pass already labels every pixel with the
# face it came from, so the harness now reports, per cell, how often two adjacent
# drawn pixels disagree about their face. Clean geometry puts those
# disagreements only along real edges.
#
# THE THRESHOLD IS THE SWEEP'S OWN MEDIAN, not a constant. The honest value
# depends on the shape, the cell size and how much of the silhouette is edge: a
# character seen edge-on is mostly edge and legitimately scores three times what
# it does face-on. Measured on `red` at rung 35 over eight yaws: 2.70% face-on
# against 9.65% edge-on, and the values mirror across 180 degrees to within a
# fifth of a percentage point. That mirroring is the real signal, and a spike is
# what breaks it.
#
# TWO CHECKS, and the second is the one that stops an empty green:
#
#   1. no yaw exceeds twice the sweep's median. A coplanar collision spikes,
#      it does not drift;
#   2. the sweep VARIES. If every yaw reports the same number the camera is
#      probably not turning at all, and a gate measuring a still image would
#      pass forever.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
MOD="$(cd "$AQUI/../.." && pwd)"
RAIZ="$(cd "$MOD/../.." && pwd)"
. "$MOD/tools/tools_bin.sh"
H=mods/voxel_characters/tools/render
cd "$RAIZ" || exit 1

vc_trava_pega "zfight_gate.sh" || exit 1
trap 'vc_trava_solta' EXIT

# Twenty-four steps of fifteen degrees. Fifteen is the laboratory's own yaw step
# (`q`/`e` in lab.lua), so a spike found here is one somebody can navigate to by
# hand rather than a value only a script can produce.
YAWS="0,15,30,45,60,75,90,105,120,135,150,165,180,195,210,225,240,255,270,285,300,315,330,345"
FALHAS=0

for forma in slab carved; do
  SAIDA=$($LOVE $H sprite=red shapes=$forma frames=0 rungs=35 cell=140 \
    metrics=1 out=zf_$forma.png yaws="$YAWS" 2>&1 | grep '^  ZFIGHT')
  N=$(printf '%s\n' "$SAIDA" | grep -c ZFIGHT)
  if [ "${N:-0}" -lt 24 ]; then
    echo "  $forma: only $N of 24 yaws reported a measurement, so the sweep is"
    echo "    incomplete and anything below would be reading a partial turn"
    FALHAS=$((FALHAS + 1))
    continue
  fi
  VEREDITO=$(printf '%s\n' "$SAIDA" | awk '
    { gsub("%","",$7); yaw[NR]=$6; v[NR]=$7+0; n=NR }
    END {
      # median, by sorting a copy
      for (i = 1; i <= n; i++) s[i] = v[i]
      for (i = 1; i < n; i++) for (j = i+1; j <= n; j++)
        if (s[j] < s[i]) { t = s[i]; s[i] = s[j]; s[j] = t }
      med = (n % 2) ? s[(n+1)/2] : (s[n/2] + s[n/2+1]) / 2
      pior = 0; piorYaw = -1; menor = 1e9
      for (i = 1; i <= n; i++) {
        if (v[i] > pior) { pior = v[i]; piorYaw = yaw[i] }
        if (v[i] < menor) menor = v[i]
      }
      printf "%.2f %.2f %.2f %s", med, pior, menor, piorYaw
    }')
  MED=$(echo "$VEREDITO" | cut -d' ' -f1)
  PIOR=$(echo "$VEREDITO" | cut -d' ' -f2)
  MENOR=$(echo "$VEREDITO" | cut -d' ' -f3)
  PIORYAW=$(echo "$VEREDITO" | cut -d' ' -f4)

  if awk -v p="$PIOR" -v m="$MED" 'BEGIN { exit !(p > 2 * m) }'; then
    echo "  $forma: yaw $PIORYAW spikes to $PIOR%, more than twice the sweep's"
    echo "    median of $MED%. That is what two coplanar faces competing for the"
    echo "    depth buffer looks like when nobody is watching the screen."
    FALHAS=$((FALHAS + 1))
  elif awk -v a="$PIOR" -v b="$MENOR" 'BEGIN { exit !(a - b < 0.5) }'; then
    echo "  $forma: every yaw reports between $MENOR% and $PIOR%, a spread of"
    echo "    under half a point across a full turn. The camera is probably not"
    echo "    turning, and a gate measuring a still image passes forever."
    FALHAS=$((FALHAS + 1))
  else
    printf "  %-8s %d yaws  median %5s%%  worst %5s%% at yaw %-4s  floor %5s%%\n" \
      "$forma" "$N" "$MED" "$PIOR" "$PIORYAW" "$MENOR"
  fi
done

if [ "$FALHAS" -eq 0 ]; then
  echo "ZFIGHT OK: no yaw spikes against its own sweep, and the sweep varies"
  exit 0
fi
echo "ZFIGHT FAILED: $FALHAS problem(s)"
exit 1
