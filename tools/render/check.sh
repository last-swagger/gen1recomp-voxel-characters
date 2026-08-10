#!/bin/bash
# Checks the RULER before trusting any measurement made with it.
#
# Run from the repo root:  bash mods/voxel_characters/tools/render/check.sh
#
# Exists because in a single session ten defects were the harness's own,
# passing themselves off as mod defects, and each one cost a diagnostic
# cycle pointed at the wrong place. A measurement made with a crooked ruler
# is worse than none: it produces confidence.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/tools_bin.sh"
H=mods/voxel_characters/tools/render
FAIL=0

say() { printf "%-52s %s\n" "$1" "$2"; }

# A check that compares TWO measurements passes by comparing empty with empty
# when the render did not even run. That is how the ruler went green on a
# machine without LOVE on the expected path. Every measurement used in an
# equality passes through here first.
medido() {
  [ -n "$1" ] && return 0
  echo "  (no measurement: the render produced no output)" >&2
  return 1
}

# 1. Internal conventions: axes, setVertex forms, frame count.
OUT=$($LOVE $H selftest=1 2>&1 | grep "autoteste")
say "autoteste de convencoes" "$OUT"
# Compares the TWO numbers for real, instead of matching a pattern with a
# backreference. `grep -qE "([0-9]+)/\1$"` accepted "12/2", because the group
# matches the trailing "2" of "12", and accepted "0/0", which is a selftest
# with zero cases. A backreference in ERE is also undefined in POSIX and
# blows up under ugrep.
PASSOU=$(echo "$OUT" | grep -oE "[0-9]+/[0-9]+" | tail -1 | cut -d/ -f1)
DE=$(echo "$OUT" | grep -oE "[0-9]+/[0-9]+" | tail -1 | cut -d/ -f2)
[ -n "${PASSOU:-}" ] && [ -n "${DE:-}" ] && [ "$PASSOU" = "$DE" ] && [ "$DE" -gt 0 ] || FAIL=1

# 2. Conformance: from the front, at pitch zero, the SLAB has to be identical
#    to the original card. This catches an inverted depth sign, a wrong
#    pivot, a swapped Y axis and a mirrored canvas all at once, because any
#    one of them breaks the equality.
for s in red blue snorlax poke_ball nurse; do
  R=$($LOVE $H sprite=$s shapes=flat,slab frames=0 yaws=0 pitch=0 cell=256 \
      metrics=1 out=chk_$s.png 2>&1 | grep slab | grep -o "IoU [0-9.]*" | head -1)
  say "conformidade $s" "$R"
  [ "$R" = "IoU 1.000" ] || FAIL=1
done

# 2b. Conformance on WALKING frames, not just standing. The v1.4.0 blocker
#     existed because the eye table was only validated on frame 0, and on
#     frame 3 the face drops a row. "Sample, not example" applies to the
#     frame axis too, not just the character axis.
for fr in 1 2 3 4 5; do
  R=$($LOVE $H sprite=red shapes=flat,slab frames=$fr yaws=0 pitch=0 cell=256 \
      metrics=1 out=chk_f$fr.png 2>&1 | grep slab | grep -o "IoU [0-9.]*" | head -1)
  say "conformidade red frame $fr" "$R"
  [ "$R" = "IoU 1.000" ] || FAIL=1
done

# 2c. The blink's contract changed in v1.4.2 and the ruler had gone stale: it
#     still claimed "does not blink while walking", which was v1.4.1's
#     behaviour. Now the walking pose blinks IF the eye texel transfers from
#     the standing pose under the step's offset, measured sheet by sheet.
#     Swapping the assertion for a looser one would be rationalising a red
#     gate, so it got TIGHTER instead: it tests both sides of the rule, and
#     both sides come from measurement.
#
#     red transfers in both walking poses (frames 3 and 5). girl does NOT
#     transfer from the front: her head is redrawn between the poses, and in
#     that case the whole sheet has to stay eye-open. If the rule ever breaks
#     towards the permissive side, girl is the one that catches it, and she is
#     the sheet that represents the defect that got v1.4.1 reverted: closing
#     the eye on top of skin.
for fr in 3 5; do
  R=$($LOVE $H sprite=red shapes=slab frames=$fr yaws=0 rungs=75 cell=140 \
      blink=on blinkscan=1 out=chk_b$fr.png 2>&1 | grep BLINKSCAN)
  say "red pisca andando, frame $fr" "$R"
  # ANCHORED AT THE START OF THE MESSAGE, and this `BLINKSCAN ` cost a whole
  # audit: the harness prints "BLINKSCAN fecha em t=..." or "BLINKSCAN nao
  # fecha em 10 s", and the second CONTAINS the first as a substring. A grep
  # for "fecha em" matched both, so deleting the blink entirely left these
  # three checks green, and the two negative ones ("nao fecha") too, because
  # there the absence becomes truth. The five blink checks survived the
  # removal of the feature they exist to measure.
  echo "$R" | grep -q "BLINKSCAN fecha em" || FAIL=1
done

R=$($LOVE $H sprite=girl shapes=slab frames=3 yaws=0 rungs=75 cell=140 \
    blink=on blinkscan=1 out=chk_bgirl.png 2>&1 | grep BLINKSCAN)
say "girl NAO pisca andando, olho nao transfere" "$R"
echo "$R" | grep -q "nao fecha" || FAIL=1

R=$($LOVE $H sprite=red shapes=slab frames=1 yaws=0 rungs=75 cell=140 \
    blink=on blinkscan=1 out=chk_b1.png 2>&1 | grep BLINKSCAN)
say "frame 1 de costas NAO pisca" "$R"
echo "$R" | grep -q "nao fecha" || FAIL=1

# 3. The blink happens. The window is 0.12 s in a period of seconds, so
#    sampling time from far away proves nothing: I already concluded it was
#    not working when it was.
R=$($LOVE $H sprite=red shapes=slab frames=0 yaws=0 rungs=75 cell=140 \
    blink=on blinkscan=1 out=chk_blink.png 2>&1 | grep BLINKSCAN)
say "piscada dispara" "$R"
echo "$R" | grep -q "BLINKSCAN fecha em" || FAIL=1

# 4. The compositor accepts a caption with an equals sign. This bug showed up
#    twice, identical both times, and the symptom is "file not found", which
#    sends whoever reads it looking in the wrong place.
R=$($LOVE $H/compose out=chk_compose.png \
    "t=0.4 uma legenda com igual=$HOME/Library/Application Support/LOVE/render/chk_red.png" \
    2>&1 | grep -cE "WROTE")
say "compositor aceita '=' na legenda" "$([ "$R" = "1" ] && echo ok || echo FALHOU)"
[ "$R" = "1" ] || FAIL=1

# 5. THE RULER MEASURES ITSELF.
#
#    An adversarial review pointed out that the harness's three most recent
#    changes had no coverage at all, and that the official gate
#    (voxel_chars_test.lua) structurally CANNOT cover them: it never loads
#    this file. Green there says nothing about the ruler. So the cases below
#    cover the instrument, not the mod.

# 5a. Leakage between cells. A deep shape used to overflow its own cell and
#     contaminate the neighbouring one, and only at the DEFAULT cell size: at
#     a smaller cell it did not leak, which made the defect disappear whenever
#     someone tried to reproduce it.
A=$($LOVE $H sprite=red shapes=slab frames=0 yaws=0 rungs=35 cell=220 \
    metrics=1 out=chk_iso.png 2>&1 | grep "^  slab" | grep -o "art *[0-9.]*")
B=$($LOVE $H sprite=red shapes=flat,slab,carved frames=0 yaws=0 rungs=35 cell=220 \
    metrics=1 out=chk_juntos.png 2>&1 | grep "^  slab" | grep -o "art *[0-9.]*")
say "medicao nao vaza entre celulas" "sozinho $A / ao lado do carved $B"
medido "$A" && medido "$B" && [ "$A" = "$B" ] || FAIL=1

# 5b. The generic option pass-through reaches the mod. Without this, a new
#     option would measure with the default and nobody would notice.
A=$($LOVE $H sprite=red shapes=slab frames=0 yaws=0 rungs=35 cell=140 \
    metrics=1 out=chk_o0.png 2>&1 | grep "front  niveis" | grep -o "niveis *[0-9]*")
B=$($LOVE $H sprite=red shapes=slab frames=0 yaws=0 rungs=35 cell=140 \
    opt="front_shape:0.12" metrics=1 out=chk_o1.png 2>&1 | grep "front  niveis" | grep -o "niveis *[0-9]*")
say "opcao generica chega no mod" "sem opcao $A / com opcao $B"
# Guarded on both sides: without it, a run that DIES leaves B empty, "niveis 3"
# differs from "", and the check goes green claiming the option got through.
# And the harness dies on purpose on an unknown key (5c right below), so
# renaming a schema key left 5b and 5c green at the same time.
medido "$A" && medido "$B" && [ "$A" != "$B" ] || FAIL=1

# 5c. An unknown key must not pass silently: a typo turns into "I measured
#     with the option off and did not notice".
R=$($LOVE $H sprite=red shapes=slab frames=0 yaws=0 rungs=35 cell=120 \
    opt="chave_que_nao_existe:1" metrics=1 out=chk_o2.png 2>&1 | grep -c "OPCAO DESCONHECIDA")
say "chave de opcao desconhecida grita" "$([ "$R" -ge 1 ] && echo ok || echo FALHOU)"
[ "$R" -ge 1 ] || FAIL=1

# 5d. The tonal structure needs to DISTINGUISH STRENGTH. The first version
#     counted distinct tones and gave the same number for 0.12 and 0.22, with
#     2382 of 43600 pixels actually different: it said "same" with 5% of the
#     screen changed.
A=$($LOVE $H sprite=red shapes=slab frames=0 yaws=0 rungs=35 cell=140 \
    opt="front_shape:0.12" metrics=1 out=chk_d1.png 2>&1 | grep "front  niveis" | grep -o "desvio [0-9.]*")
B=$($LOVE $H sprite=red shapes=slab frames=0 yaws=0 rungs=35 cell=140 \
    opt="front_shape:0.22" metrics=1 out=chk_d2.png 2>&1 | grep "front  niveis" | grep -o "desvio [0-9.]*")
say "estrutura tonal distingue forca" "0.12 -> $A / 0.22 -> $B"
medido "$A" && medido "$B" && [ "$A" != "$B" ] || FAIL=1

# 6. The LABORATORY opens, and classifies the options on the right side.
#
#    An interactive tool nobody tests breaks silently, so it knows how to open
#    on its own, take a photo and exit (`labshot=`). Beyond opening, what is
#    asserted here is an ARCHITECTURE invariant and not a number: breath,
#    sway, inertia and footfall post-multiply the matrix the host passes to
#    Voxel3D.draw, so they CANNOT change the mesh. The day one of them shows
#    up on this side, either it turned into geometry without anyone saying so,
#    or the classifier broke. Both deserve to stop the queue.
LAB=$($LOVE $H lab=1 labshot=chk_lab.png sprite=red 2>&1)
R=$(echo "$LAB" | grep -c "laboratorio ok")
say "laboratorio abre" "$([ "$R" = "1" ] && echo ok || echo FALHOU)"
[ "$R" = "1" ] || FAIL=1

SEM=$(echo "$LAB" | grep "sem efeito na malha:" | sed 's/.*malha: //')
AQUI=$(echo "$LAB" | grep "^  aqui:" | sed 's/.*aqui: *//')
FALTOU=""
for k in breath sway lag footfall; do
  echo "$SEM" | grep -q "\b$k\b" || FALTOU="$FALTOU -$k"
done
# BOTH SIDES. Checking only the "no effect" list let through the mutation
# that breaks the entire classifier: if buildGeometry fails, labAssinatura
# returns "no mesh" for EVERY level, no option changes, all of them fall into
# the "no effect" list, the laboratory ends up with no controls at all, and
# this gate stays green. Comparing empty with empty again, now in list form.
for k in depth shape front_shape top_dome step_weight; do
  echo "$AQUI" | grep -q "\b$k\b" || FALTOU="$FALTOU +$k"
done
say "classificador poe cada opcao do lado certo" \
    "$([ -z "$FALTOU" ] && echo ok || echo "FALHOU:$FALTOU")"
[ -z "$FALTOU" ] || FAIL=1

# 7. CHOICE MODE proposes a visible pair and records the choice.
#
#    A pair whose two sides are identical on screen does not collect
#    preference, it collects a coin flip, and a coin flip enters the judge's
#    fit with the same face of a die as a real choice. So the roll only
#    delivers a pair after FINDING a condition (pose, instant) where the two
#    differ, and this check proves that it delivers.
#
#    Records to a separate file on purpose: the gate must not write a
#    made-up choice where the judge is going to learn from it.
rm -f "$HOME/Library/Application Support/LOVE/render/chk_escolhas.txt"
AB=$($LOVE $H lab=1 labab=1 labpick=A labfile=chk_escolhas.txt \
     labshot=chk_lab_ab.png 2>&1)
R=$(echo "$AB" | grep "modo escolha:" | grep -vc "NENHUM PAR")
say "modo escolha propoe par visivel" \
    "$(echo "$AB" | grep -o 'modo escolha: .*' | head -1)"
[ "$R" = "1" ] || FAIL=1

LINHAS=$(wc -l < "$HOME/Library/Application Support/LOVE/render/chk_escolhas.txt" 2>/dev/null | tr -d ' ')
say "a escolha vira linha de arquivo" \
    "$([ "${LINHAS:-0}" -ge 1 ] && echo "ok, $LINHAS linha" || echo FALHOU)"
[ "${LINHAS:-0}" -ge 1 ] || FAIL=1

# 8. THE JUDGE LOOP closes: model goes out to a file, pairs come out of the
#    model, and the laboratory consumes the pairs. Each piece already has its
#    own proof; what this check covers is the JOIN, which is where file
#    format tends to diverge without anyone noticing until it is time to use it.
rm -f "$HOME/Library/Application Support/LOVE/render/chk_pares.txt"
$LOVE $H features=/dev/stdin > /tmp/vc_chk_feat.tsv 2>/dev/null <<'ENTRADA'
red	0	0	depth:3,shape:slab,side_color:body
red	0	0	depth:3,shape:slab,side_color:outline
red	0	0	depth:10,shape:slab,side_color:body
ENTRADA
luajit mods/voxel_characters/tools/juiz/ajusta.lua --pares /tmp/vc_chk_feat.tsv   "" 3 > /tmp/vc_chk_pares.txt 2>/dev/null
NPARES=$(wc -l < /tmp/vc_chk_pares.txt | tr -d " ")
say "o juiz propoe par a partir de features"     "$([ "${NPARES:-0}" -ge 1 ] && echo "ok, $NPARES" || echo FALHOU)"
[ "${NPARES:-0}" -ge 1 ] || FAIL=1

LAB2=$($LOVE $H lab=1 labab=1 labpares=/tmp/vc_chk_pares.txt labpick=A        labfile=chk_pares.txt labshot=chk_lab_pares.png 2>&1)
R=$(echo "$LAB2" | grep -c "pares pedidos pelo juiz")
say "o laboratorio consome os pares do juiz"     "$([ "$R" = "1" ] && echo ok || echo FALHOU)"
[ "$R" = "1" ] || FAIL=1

# 9. The explanatory CARD: the before/after figure that goes into the release
#    note and Discord. A published figure is a public claim, so it is checked
#    like a measurement, not like decoration.
COMPOSE="$HOME/Library/Application Support/LOVE/compose"
CARDS=mods/voxel_characters/tools/render/cards
rm -f "$COMPOSE/chk_card1.png" "$COMPOSE/chk_card2.png" "$COMPOSE/chk_sem.png"

bash $H/card.sh $CARDS/shading.card chk_card1.png > /dev/null 2>&1
say "o card sai da receita" \
    "$([ -f "$COMPOSE/chk_card1.png" ] && echo ok || echo FALHOU)"
[ -f "$COMPOSE/chk_card1.png" ] || FAIL=1

# 9b. FLOOR. Building the same card twice has to produce the same file.
#     Without this, any comparison between cards measures the drawing's noise
#     instead of what changed, and the two checks below mean nothing.
bash $H/card.sh $CARDS/shading.card chk_card2.png > /dev/null 2>&1
if [ -f "$COMPOSE/chk_card1.png" ] && [ -f "$COMPOSE/chk_card2.png" ]; then
  cmp -s "$COMPOSE/chk_card1.png" "$COMPOSE/chk_card2.png" && IGUAL=ok || IGUAL=FALHOU
else
  IGUAL=FALHOU
fi
say "o mesmo card duas vezes da o mesmo arquivo" "$IGUAL"
[ "$IGUAL" = "ok" ] || FAIL=1

# 9c. The annotation's COORDINATE reaches the drawing.
#
#     The first version of this check compared a card with four points
#     against a card with none, and passed with the callout drawing ENTIRELY
#     disabled: without points the card has a different height, so it was
#     comparing canvas size and never the annotation. Caught by mutation,
#     which is how this kind of hollow check has been caught in this project.
#
#     Now both cards have the SAME text and the SAME number of points, and
#     only the coordinate changes. Layout identical by construction, so the
#     only thing that can differ is the line and the target. If the tether
#     stops being drawn, the two files come out equal and this check falls.
SAVE_R="$HOME/Library/Application Support/LOVE/render"
for par in "0.20,0.20 chk_p1.png" "0.80,0.80 chk_p2.png"; do
  set -- $par
  $LOVE $H/compose mode=card out=$2 \
    "before=A||$SAVE_R/card_antes.png" "after=B||$SAVE_R/card_depois.png" \
    "point=$1|SAME TITLE|Same sentence, so the block height is identical." \
    > /dev/null 2>&1
done
if [ -f "$COMPOSE/chk_p1.png" ] && [ -f "$COMPOSE/chk_p2.png" ]; then
  cmp -s "$COMPOSE/chk_p1.png" "$COMPOSE/chk_p2.png" && ANOT=FALHOU || ANOT=ok
else
  ANOT=FALHOU
fi
say "a coordenada da anotacao chega ao desenho" "$ANOT"
[ "$ANOT" = "ok" ] || FAIL=1

# 9d. The REFUSAL fires. Two identical halves announce in writing a change
#     that did not happen, which is the defect the clip already had. Checks
#     the exit code: the first version of this refusal printed the message
#     and exited with ZERO, and whoever read the exit code saw success.
$LOVE $H/compose mode=card out=chk_recusa.png \
  "before=A||$SAVE_R/card_antes.png" "after=B||$SAVE_R/card_antes.png" \
  > /dev/null 2>&1
RC=$?
say "card recusa metades identicas" \
    "$([ "$RC" -ne 0 ] && echo "ok, saiu $RC" || echo "FALHOU, saiu 0")"
[ "$RC" -ne 0 ] || FAIL=1

echo
[ $FAIL -eq 0 ] && echo "REGUA OK" || echo "REGUA TORTA: do not trust measurement until it's fixed"
exit $FAIL
