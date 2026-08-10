#!/bin/bash
# Mede quanta FOLGA sobra contra o teto de 200 locais de chunk do LuaJIT.
#
# POR QUE ISTO E UM GATE E NAO UMA NOTA. Estourar LUAI_MAXVARS e erro de
# COMPILACAO: o mod inteiro deixa de carregar, para todo mundo, e o sintoma nao
# e uma feature quebrada, e o jogo sem o mod. Este arquivo ja chegou a 199 de
# 200 uma vez (ver main.lua:52) e so escapou por uma refatoracao.
#
# A medicao e empirica de proposito: contar `local` no texto erra escopo,
# multi-atribuicao e declaracao dentro de bloco. Aqui a gente ANEXA locais de
# chunk ate o LuaJIT recusar, e a resposta e o numero real.
#
# Uso: bash mods/voxel_characters/tools/folga_locais.sh [piso]
set -u
ALVO="${VC_MAIN:-mods/voxel_characters/main.lua}"
PISO="${1:-15}"
command -v luajit >/dev/null || { echo "luajit nao encontrado"; exit 1; }
[ -f "$ALVO" ] || { echo "nao achei $ALVO (rode da raiz do repo)"; exit 1; }

T=$(mktemp -t vcfolga) || exit 1
trap 'rm -f "$T"' EXIT

cabe() {
  python3 - "$ALVO" "$T" "$1" <<'PY'
import sys
alvo, saida, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
s = open(alvo).read()
open(saida, "w").write(s + "\n" +
  "\n".join("local __folga%d = %d" % (i, i) for i in range(n)) + "\n")
PY
  luajit -bl "$T" /dev/null >/dev/null 2>&1
}

cabe 0 || { echo "FOLGA 0: $ALVO ja NAO COMPILA"; exit 1; }

lo=0; hi=1
while cabe "$hi"; do lo=$hi; hi=$((hi * 2)); [ "$hi" -gt 512 ] && break; done
while [ $((hi - lo)) -gt 1 ]; do
  mid=$(((lo + hi) / 2))
  if cabe "$mid"; then lo=$mid; else hi=$mid; fi
done

echo "folga: $lo locais de chunk (teto do LuaJIT: 200, entao $((200 - lo)) em uso)"
if [ "$lo" -lt "$PISO" ]; then
  echo "ABAIXO DO PISO de $PISO. Nao adicione estado de chunk sem refatorar:"
  echo "  o padrao ja usado aqui e uma TABELA de descricao mais funcoes"
  echo "  genericas, no lugar de um punhado de locais por feature (main.lua:52)."
  exit 1
fi
echo "OK"
