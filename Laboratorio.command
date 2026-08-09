#!/bin/bash
# Clique duas vezes no Finder para abrir o LABORATORIO.
#
# Uma janela com um personagem grande, todas as opcoes do mod que mexem na
# malha, e as 67 folhas do jogo para navegar. Serve para olhar uma opcao mudar
# na hora, e para olhar em quem NAO e o red, que e onde as regressoes moram.
#
# O nome do arquivo segue Play-Mac.command, que e como este repositorio ja
# entrega coisa clicavel no Mac.
cd "$(dirname "$0")/../.." || exit 1
. mods/voxel_characters/tools/tools_bin.sh
exec "$LOVE" mods/voxel_characters/tools/render lab=1 "$@"
