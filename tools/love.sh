#!/bin/bash
# Roda o LOVE SEMPRE da raiz do repo, com o binario resolvido.
#
# POR QUE ISTO EXISTE. Chamar `love mods/voxel_characters/tools/render` de
# dentro do diretorio do mod produz
# `mods/voxel_characters/mods/voxel_characters/tools/render`, que nao existe. O
# LOVE entao abre uma janela dizendo "Cannot load game at path" e ESPERA tecla:
# do lado do script, dez minutos de timeout com log vazio. Aconteceu duas vezes.
#
# E o `love.errorhandler` que este repo instala NAO cobre este caso, porque o
# erro acontece no boot do LOVE, antes de qualquer arquivo nosso carregar. Ou
# seja: a unica defesa possivel e nao deixar o caminho errado sair daqui.
#
# Uso:  bash mods/voxel_characters/tools/love.sh <alvo> [args...]
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$AQUI/../../.." && pwd)"
. "$AQUI/tools_bin.sh"
ALVO="${1:?uso: love.sh <caminho-do-jogo> [args]}"
shift
[ -d "$REPO/$ALVO" ] || [ -f "$REPO/$ALVO/main.lua" ] || {
  echo "nao existe $REPO/$ALVO"
  echo "  (caminho e sempre relativo a RAIZ do repo, nunca ao seu cwd)"
  exit 1
}
cd "$REPO" || exit 1
exec "$LOVE" "$ALVO" "$@"
