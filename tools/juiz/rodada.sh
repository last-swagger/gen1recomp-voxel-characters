#!/bin/bash
# UMA RODADA DO LOOP: ajusta o juiz com o que ja foi escolhido, pede a ele os
# pares mais informativos, e abre o laboratorio com eles.
#
#   tools/juiz/rodada.sh [quantos-pares]
#
# POR QUE NAO SORTEAR. Trinta escolhas do Kim sao o insumo caro deste projeto.
# Sorteadas, boa parte cai em par que o modelo ja acerta de olhos fechados, e
# uma escolha dessas nao move peso nenhum. Perguntar justamente onde o modelo
# esta em cima do muro faz cada escolha valer varias.
#
# Na PRIMEIRA rodada nao ha modelo, e ai o criterio e maior distancia de
# feature: pares obviamente diferentes primeiro, que e o que separa as colunas
# para o primeiro ajuste ter o que morder.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$AQUI/../../../.." && pwd)"
. "$AQUI/../tools_bin.sh"
SAVE="$HOME/Library/Application Support/LOVE/render"
ESCOLHAS="${VC_ESCOLHAS:-$SAVE/escolhas.txt}"
QUANTOS="${1:-30}"

cd "$REPO" || exit 1
command -v luajit >/dev/null || { echo "luajit nao encontrado"; exit 1; }
vc_trava_pega "rodada.sh" || exit 1

TMP="$(mktemp -d -t vcrodada)" || exit 1
trap 'rm -rf "$TMP"; vc_trava_solta' EXIT

MODELO=""
if [ -f "$ESCOLHAS" ]; then
  echo "== ajustando com o que ja existe"
  luajit "$AQUI/ajusta.lua" --estados "$ESCOLHAS" > "$TMP/est.tsv" 2>/dev/null
  "$LOVE" mods/voxel_characters/tools/render features="$TMP/est.tsv" \
    > "$TMP/feat_antigo.tsv" 2>/dev/null
  if luajit "$AQUI/ajusta.lua" --pesos "$ESCOLHAS" "$TMP/feat_antigo.tsv" \
       "$TMP/modelo.txt" 2>/dev/null; then
    MODELO="$TMP/modelo.txt"
  else
    echo "  ainda nao da para ajustar; os pares vao sair por distancia"
  fi
else
  echo "== primeira rodada: nao ha escolhas ainda"
fi

# O ESPACO DE CANDIDATOS. Uma folha por linha, com cada nivel de cada opcao que
# mexe na malha. Sai grande de proposito: quem escolhe o que perguntar e o
# criterio, nao o tamanho da lista.
echo "== montando o espaco de candidatos"
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
-- Amostra de folhas: todas seria caro e nao mais informativo, porque o
-- criterio ja ordena. Uma a cada seis cobre os tres tamanhos de sheet.
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

echo "== medindo os candidatos"
"$LOVE" mods/voxel_characters/tools/render features="$TMP/cand.tsv" \
  > "$TMP/feat.tsv" 2>"$TMP/feat.err"
MEDIDOS=$(grep -cv '^#' "$TMP/feat.tsv" 2>/dev/null || echo 0)
echo "  $MEDIDOS variantes medidas"
[ "$MEDIDOS" -gt 10 ] || { echo "medicao falhou"; tail -3 "$TMP/feat.err"; exit 1; }

echo "== escolhendo os pares"
luajit "$AQUI/ajusta.lua" --pares "$TMP/feat.tsv" "$MODELO" "$QUANTOS" \
  > "$SAVE/pares.txt" 2>&1 | tail -1
CRIT=$(luajit "$AQUI/ajusta.lua" --pares "$TMP/feat.tsv" "$MODELO" "$QUANTOS" 2>&1 >/dev/null | tail -1)
echo "  $CRIT"
echo "  pares em $SAVE/pares.txt"

vc_trava_solta
echo ""
echo "Abra o laboratorio e aperte t:"
echo "  bash $REPO/mods/voxel_characters/Laboratorio.command labpares=$SAVE/pares.txt"
