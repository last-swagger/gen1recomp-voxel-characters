#!/bin/bash
# O JUIZ, de ponta a ponta: le as escolhas, mede as variantes e ajusta.
#
#   tools/juiz/juiz.sh                      usa o escolhas.txt do laboratorio
#   tools/juiz/juiz.sh <arquivo>            usa outro arquivo de escolhas
#
# Tres passos, e cada um mora onde precisa morar:
#   1. luajit le as escolhas e lista as variantes unicas
#   2. LOVE mede as features de cada variante, porque so ele tem sprite de
#      verdade e o mod carregado
#   3. luajit ajusta e imprime a acuracia FORA da amostra contra a melhor
#      coluna sozinha, que e o numero que decide se isto e juiz ou enfeite
#
# Antes de tudo, o autoteste: se a maquinaria nao recupera nem uma regra
# sintetica que existe, nao adianta alimenta-la com escolha de verdade, e o
# tempo do Kim e o insumo caro aqui.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$AQUI/../../.." && pwd)"
. "$AQUI/../tools_bin.sh"
SAVE="$HOME/Library/Application Support/LOVE/render"

ESCOLHAS="${1:-$HOME/Library/Application Support/LOVE/render/escolhas.txt}"
[ -f "$ESCOLHAS" ] || {
  echo "sem escolhas em $ESCOLHAS"
  echo "abra o laboratorio, aperte t e escolha algumas vezes:"
  echo "  mods/voxel_characters/Laboratorio.command"
  exit 1
}

command -v luajit >/dev/null || { echo "luajit nao encontrado"; exit 1; }

echo "== autoteste da maquinaria"
luajit "$AQUI/ajusta.lua" --autoteste || exit 1

TMP="$(mktemp -d -t vcjuiz)" || exit 1
trap 'rm -rf "$TMP"' EXIT

echo ""
echo "== variantes"
luajit "$AQUI/ajusta.lua" --estados "$ESCOLHAS" > "$TMP/estados.tsv" || exit 1

echo ""
echo "== features"
# Outra ferramenta nossa rodando derruba esta: run.sh, clip.sh e trailer.sh
# comecam com `pkill -x love`, porque um LOVE anterior vivo faz o proximo
# nascer sem conseguir nada. Avisar antes e melhor que medir pela metade.
if pgrep -x love >/dev/null 2>&1; then
  echo "  JA TEM UM LOVE RODANDO. Espere ele acabar: as ferramentas deste"
  echo "  repo se matam entre si e a medicao sairia truncada."
  exit 1
fi
cd "$REPO" || exit 1
"$LOVE" mods/voxel_characters/tools/render features="$TMP/estados.tsv" \
  > "$TMP/features.tsv" 2>"$TMP/features.err"
# LOVE devolve zero mesmo quando o script morre no meio, entao contar linha e
# a unica forma de saber que mediu: cabecalho mais uma linha por variante.
N=$(grep -cv '^#' "$TMP/features.tsv" 2>/dev/null || echo 0)
Q=$(wc -l < "$TMP/estados.tsv" | tr -d ' ')
echo "  $N de $Q variantes medidas"
if [ "$N" -lt "$Q" ]; then
  echo "  FALTOU MEDIR. Primeiras linhas do erro:"
  head -5 "$TMP/features.err" | sed 's/^/    /'
  [ "$N" -eq 0 ] && exit 1
fi

echo ""
echo "== ajuste"
luajit "$AQUI/ajusta.lua" --ajusta "$ESCOLHAS" "$TMP/features.tsv"
