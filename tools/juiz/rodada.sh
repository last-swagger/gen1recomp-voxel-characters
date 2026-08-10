#!/bin/bash
# ONE ROUND OF THE LOOP: fits the judge with what has already been chosen,
# asks it for the most informative pairs, and opens the laboratory with them.
#
#   tools/juiz/rodada.sh [how-many-pairs]
#
# WHY NOT ROLL. Thirty of Kim's choices are this project's expensive input.
# Rolled, a good share land on a pair the model already gets right with its
# eyes closed, and a choice like that moves no weight at all. Asking
# specifically where the model is on the fence makes each choice worth several.
#
# On the FIRST round there is no model, and then the criterion is greatest
# feature distance: obviously different pairs first, which is what separates
# the columns so the first fit has something to bite into.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$AQUI/../../../.." && pwd)"
. "$AQUI/../tools_bin.sh"
SAVE="$HOME/Library/Application Support/LOVE/render"
ESCOLHAS="${VC_ESCOLHAS:-$SAVE/escolhas.txt}"
QUANTOS="${1:-30}"

cd "$REPO" || exit 1
command -v luajit >/dev/null || { echo "luajit not found"; exit 1; }
vc_trava_pega "rodada.sh" || exit 1

TMP="$(mktemp -d -t vcrodada)" || exit 1
trap 'rm -rf "$TMP"; vc_trava_solta' EXIT

MODELO=""
if [ -f "$ESCOLHAS" ]; then
  echo "== fitting with what already exists"
  luajit "$AQUI/ajusta.lua" --estados "$ESCOLHAS" > "$TMP/est.tsv" 2>/dev/null
  "$LOVE" mods/voxel_characters/tools/render features="$TMP/est.tsv" \
    > "$TMP/feat_antigo.tsv" 2>/dev/null
  if luajit "$AQUI/ajusta.lua" --pesos "$ESCOLHAS" "$TMP/feat_antigo.tsv" \
       "$TMP/modelo.txt" 2>/dev/null; then
    MODELO="$TMP/modelo.txt"
  else
    echo "  cannot fit yet; pairs will come out by distance"
  fi
else
  echo "== first round: no choices yet"
fi

# THE CANDIDATE SPACE. One sheet per line, with every level of every option
# that touches the mesh. Deliberately large: what decides what to ask is the
# criterion, not the size of the list.
echo "== building the candidate space"
luajit - "$TMP/cand.tsv" <<'LUA'
local saida = assert(io.open(arg[1], "w"))
local folhas = {}
local p = io.popen("ls assets/generated/sprites 2>/dev/null")
if p then
  for l in p:lines() do
    local n = l:match("^(.+)%.png$")
    if n then folhas[#folhas + 1] = n end
  end
  p:close()
end
table.sort(folhas)
-- Sample of sheets: all of them would be expensive and no more informative,
-- because the criterion already ranks. One every six covers the three sheet sizes.
local OPCOES = {
  { "depth", { 1, 3, 5, 10 } },
  { "shape", { "slab", "carved", "carved_plus" } },
  { "side_color", { "body", "outline" } },
  { "ground_shade", { "off", "on" } },
  { "top_edge", { "off", "on" } },
  { "front_shape", { "off", 0.12, 0.17, 0.22 } },
  { "top_dome", { "off", 0.15, 0.30 } },
  { "step_weight", { "off", 0.25, 0.5 } },
}
local BASE = "blink:on,breath:0.01,first_person:card,footfall:off,lag:off,sway:off"
local n = 0
for i = 1, #folhas, 6 do
  for _, o in ipairs(OPCOES) do
    for _, nivel in ipairs(o[2]) do
      local partes = { BASE }
      for _, oo in ipairs(OPCOES) do
        partes[#partes + 1] = oo[1] .. ":" ..
          tostring(oo[1] == o[1] and nivel or oo[2][1])
      end
      saida:write(folhas[i] .. "\t0\t0\t" .. table.concat(partes, ",") .. "\n")
      n = n + 1
    end
  end
end
saida:close()
io.stderr:write(n .. " candidatos\n")
LUA

echo "== measuring the candidates"
"$LOVE" mods/voxel_characters/tools/render features="$TMP/cand.tsv" \
  > "$TMP/feat.tsv" 2>"$TMP/feat.err"
MEDIDOS=$(grep -cv '^#' "$TMP/feat.tsv" 2>/dev/null || echo 0)
echo "  $MEDIDOS variants measured"
[ "$MEDIDOS" -gt 10 ] || { echo "measurement failed"; tail -3 "$TMP/feat.err"; exit 1; }

echo "== choosing the pairs"
luajit "$AQUI/ajusta.lua" --pares "$TMP/feat.tsv" "$MODELO" "$QUANTOS" \
  > "$SAVE/pares.txt" 2>&1 | tail -1
CRIT=$(luajit "$AQUI/ajusta.lua" --pares "$TMP/feat.tsv" "$MODELO" "$QUANTOS" 2>&1 >/dev/null | tail -1)
echo "  $CRIT"
echo "  pairs in $SAVE/pares.txt"

vc_trava_solta

# IT OPENS THE LABORATORY ITSELF. The header of this file has always said it
# does, and it did not: it printed a command and stopped, so the round ended
# with a few LOVE windows flashing past during the measurement and nothing
# visibly happening. That reads exactly like a tool that ran and failed.
#
# The printed command was also missing `labab=1`, so following it opened the
# laboratory in browse mode and the person had to know to press `t` first.
#
# `--so-preparar` keeps the old behaviour for anything automated.
if [ "${2:-}" = "--so-preparar" ] || [ "${VC_SO_PREPARAR:-0}" = "1" ]; then
  echo ""
  echo "pairs ready. To choose:"
  echo "  bash $AQUI/rodada.sh --abrir"
  exit 0
fi

ANTES=0
[ -f "$ESCOLHAS" ] && ANTES=$(grep -c . "$ESCOLHAS" 2>/dev/null || echo 0)

cat <<'AJUDA'

== THE LABORATORY IS OPENING. Keys:

     left arrow    pick the LEFT one
     right arrow   pick the RIGHT one
     space         skip this pair, when neither is better
     f             turn the character (front, back, side)
     1 2 3 4       camera rung
     q  e          rotate 15 degrees
     esc           stop, keeping everything chosen so far

   There is no wrong answer and no need to explain one. Pick the one you would
   rather see in the game. Nothing here is committed and nothing is published.

AJUDA

"$LOVE" mods/voxel_characters/tools/render lab=1 labab=1 \
  labpares="$SAVE/pares.txt" 2>/dev/null

DEPOIS=0
[ -f "$ESCOLHAS" ] && DEPOIS=$(grep -c . "$ESCOLHAS" 2>/dev/null || echo 0)
FEITAS=$((DEPOIS - ANTES))
echo ""
echo "== $FEITAS choices this round, $DEPOIS in total, in $ESCOLHAS"
if [ "$DEPOIS" -ge 30 ]; then
  echo "   Enough to fit the judge. Next: luajit $AQUI/ajusta.lua --ajusta"
else
  echo "   The judge wants about 30. Run this again to continue where it left off."
fi
