#!/bin/bash
# Monta a SALA DE TESTE numa segunda maquina: manda daqui tudo que o clone do
# repositorio nao traz, e depois roda a bateria la para provar que montou.
#
#   bash mods/voxel_characters/tools/sala_de_teste.sh mbp
#   bash mods/voxel_characters/tools/sala_de_teste.sh mbp --so-conferir
#
# Existe porque eu ja escrevi na documentacao que os gates visuais so rodavam
# nesta maquina, e que "nao e limitacao que de pra contornar com script". Nao
# era limitacao nenhuma: eram arquivos que ninguem tinha copiado, e o script
# leva vinte minutos. O que o repositorio nao traz esta listado aqui embaixo,
# de forma que da proxima vez a lista seja executavel em vez de descoberta.
#
# Nada aqui faz push. Codigo vai por bundle, que transfere commit sem tocar em
# remoto nenhum.
set -u
DESTINO="${1:?uso: sala_de_teste.sh <host-ssh> [--so-conferir]}"
MODO="${2:-}"
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
SAVE="$HOME/Library/Application Support/LOVE/pokemon-love2d"
MOD="$REPO/mods/voxel_characters"

falta=0
exige() { [ -e "$1" ] || { echo "FALTA nesta maquina: $1"; falta=1; }; }
exige "$REPO/baserom.gb"
exige "$REPO/assets/generated"
exige "$REPO/mods/DramaticShapeVoxelMod"
exige "$SAVE"
[ "$falta" -eq 0 ] || { echo; echo "a sala nao esta montada AQUI; nao da para copiar"; exit 1; }

ssh "$DESTINO" 'echo ok' >/dev/null 2>&1 || { echo "nao alcanco $DESTINO por ssh"; exit 1; }
ALVO=$(ssh "$DESTINO" 'cd ~/Projects/gen1recomp 2>/dev/null && pwd') || {
  echo "$DESTINO nao tem ~/Projects/gen1recomp; clone o gen1recomp la primeiro"; exit 1; }

if [ "$MODO" != "--so-conferir" ]; then
  echo "== LOVE (universal; vai para ~/Applications porque cask precisa de sudo)"
  LOCAL_LOVE=$(ls -d /Applications/love.app "$HOME/Applications/love.app" 2>/dev/null | head -1)
  [ -n "$LOCAL_LOVE" ] || { echo "sem love.app aqui para copiar"; exit 1; }
  ssh "$DESTINO" 'mkdir -p ~/Applications'
  rsync -a "$LOCAL_LOVE/" "$DESTINO:Applications/love.app/"

  echo "== ROM, arte derivada do ROM, e os mods que o clone nao traz"
  rsync -a "$REPO/baserom.gb" "$DESTINO:Projects/gen1recomp/"
  rsync -a "$REPO/assets/generated/" "$DESTINO:Projects/gen1recomp/assets/generated/"
  for m in DramaticShapeVoxelMod gen1_modern_ui; do
    [ -d "$REPO/mods/$m" ] && rsync -a "$REPO/mods/$m" "$DESTINO:Projects/gen1recomp/mods/"
  done

  echo "== save do LOVE (o caminho tem espaco; o rsync da Apple erra, tar nao)"
  ( cd "$(dirname "$SAVE")" && tar czf - --exclude '*-cache' "$(basename "$SAVE")" ) \
    | ssh "$DESTINO" 'mkdir -p ~/Library/Application\ Support/LOVE && tar xzf - -C ~/Library/Application\ Support/LOVE'

  echo "== commits do mod, por bundle (sem push)"
  B=$(mktemp -t vc-bundle)
  ( cd "$MOD" && git bundle create "$B" --all ) >/dev/null 2>&1
  RAMO=$(cd "$MOD" && git branch --show-current)
  scp -q "$B" "$DESTINO:/tmp/vc.bundle" && rm -f "$B"
  ssh "$DESTINO" "cd ~/Projects/gen1recomp/mods/voxel_characters && \
    git fetch -f -q /tmp/vc.bundle 'refs/heads/*:refs/remotes/studio/*' && \
    git reset -q --hard studio/$RAMO && git log --oneline -1"

  echo "== ferramentas de linha de comando"
  ssh "$DESTINO" 'export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH
    for f in luajit ffmpeg gh; do
      command -v $f >/dev/null || { echo "  instalando $f"; NONINTERACTIVE=1 brew install $f >/dev/null 2>&1; }
    done'
fi

echo
echo "== a bateria, la"
ssh "$DESTINO" 'export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH; cd ~/Projects/gen1recomp
  L=mods/voxel_characters
  . $L/tools/tools_bin.sh
  FALHOU=0
  # REPORTAR NAO E GATAR, e a versao anterior so reportava: cada linha era um
  # printf com o resultado de um grep, e o status do script era o do ultimo ssh.
  # Pior, quando uma sonda morre ANTES do resumo o grep sai vazio, e coluna
  # vazia le como "nada a relatar" em vez de "falhou". As duas sondas tem saida
  # antecipada que pula o resumo inteiro.
  linha() {  # $1 rotulo, $2 saida, $3 padrao que significa OK
    local r="$2"
    if [ -z "$r" ]; then
      printf "%-24s SEM SAIDA (a ferramenta morreu antes de concluir)\n" "$1"
      FALHOU=1
      return
    fi
    printf "%-24s %s\n" "$1" "$r"
    case "$r" in *$3*) ;; *) FALHOU=1;; esac
  }

  linha "suite offline" "$(luajit $L/tests/voxel_chars_test.lua 2>&1 | tail -1)" "checks passed"
  linha "linter de assercao" "$(luajit $L/tools/lint_asserts.lua 2>&1 | tail -1)" "nenhuma"
  linha "folga de locais" "$(bash $L/tools/folga_locais.sh 2>&1 | tail -1)" "OK"
  linha "regua" "$(bash $L/tools/render/check.sh 2>&1 | tail -1)" "REGUA OK"
  linha "empacotamento" "$(python3 tools/modkit.py validate $L 2>&1 | tail -1)" "ok"
  linha "pixel da vida" "$(POKEPORT_VERSION=blue POKEPORT_DRIVER=$L/tools/ingame/probe_life.lua "$LOVE" . 2>&1 | grep -E "^\[vida\] VEREDITO" | tail -1)" "CHEGA NA TELA"
  linha "menu" "$(POKEPORT_VERSION=blue POKEPORT_DRIVER=$L/tools/ingame/menu.lua "$LOVE" . 2>&1 | grep -E "^\[menu\] VEREDITO" | tail -1)" "O JOGADOR ESPERA"
  linha "primeira pessoa" "$(POKEPORT_VERSION=blue POKEPORT_DRIVER=$L/tools/ingame/probe_fp.lua "$LOVE" . 2>&1 | grep -E "^\[fp\] VEREDITO" | tail -1)" "SOBREVIVE"
  linha "posicao" "$(POKEPORT_VERSION=blue POKEPORT_DRIVER=$L/tools/ingame/probe_draw.lua "$LOVE" . 2>&1 | grep -E "VEREDITO" | tail -1)" "CHEGA LIMPA"
  linha "fotos" "$(bash $L/tools/ingame/run.sh /tmp/vc-sala 2>&1 | tail -1)" "GATE OK"
  linha "release" "$(bash $L/tools/release_check.sh 2>&1 | grep -E "^RELEASE" | tail -1)" "RELEASE OK"

  echo ""
  if [ "$FALHOU" -eq 0 ]; then echo "SALA OK"; else echo "SALA COM FALHA: ler acima"; fi
  exit $FALHOU'
