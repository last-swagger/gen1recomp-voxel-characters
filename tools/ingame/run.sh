#!/bin/bash
# Gate in-game do Voxel Characters: roda o jogo de verdade, dirige por script e
# fotografa. Complementa o harness offline (tools/render/), que e rapido e mede
# geometria mas carrega o mod com o host MOCKADO, entao nunca mostra o sol real,
# o personagem contra o mundo, a escala de tela real, nem movimento.
#
# Uso:
#   tools/ingame/run.sh <pasta-de-saida> [chave=valor da opcao do mod]
#
# Exemplo de A/B:
#   tools/ingame/run.sh /tmp/ab/off front_shape=off
#   tools/ingame/run.sh /tmp/ab/med front_shape=0.17
#
# Variaveis: VC_VERSION (red|blue|yellow), VC_MAP, VC_X, VC_Y, VC_FOTOS,
#            VC_DRIVER (outro driver), LOVE_BIN.
#
# CADA TRAVA AQUI VEIO DE ERRO PAGO. Nao remova nenhuma sem ler.

set -u
REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
SAVE="$HOME/Library/Application Support/LOVE/pokemon-love2d"
MARCADOR="$SAVE/relaunch_to_launcher.txt"
. "$(cd "$(dirname "$0")/.." && pwd)/tools_bin.sh"
DRIVER="${VC_DRIVER:-$REPO/mods/voxel_characters/tools/ingame/driver.lua}"

SAIDA="${1:?uso: run.sh <pasta-de-saida> [chave=valor]}"
OPCAO="${2:-}"

# ARMADILHA 1: um processo anterior ainda vivo faz o proximo nascer sem
# conseguir nada. Matar NAO e instantaneo; esperar morrer de verdade.
pkill -x love 2>/dev/null
for _ in $(seq 1 20); do
  pgrep -x love >/dev/null 2>&1 || break
  sleep 0.5
done

# ARMADILHA 2, A QUE CUSTOU MAIS CARO: escolher a VERSAO certa.
#
# POKEPORT_GAME e POKEPORT_SLOT (que este script exportava antes) sao letra
# morta sob POKEPORT_DRIVER: eles so sao lidos em LaunchOptions.resolve
# (main.lua:359), depois do `if scripted then ... return end` de main.lua:313.
# A versao que boota vem de POKEPORT_VERSION (main.lua:304), default "red".
#
# E "red" so esta pronto quando a arvore de fontes tem TODOS os arquivos de
# RomImporter.REQUIRED_FILES (RomImporter.lua:52-68, 165-172, 250). Nesta
# maquina faltam dois, entao o boot scriptado caia no importador e ficava
# esperando alguem arrastar um ROM: o driver nem chegava a ser criado, e o
# sintoma era ZERO fotos com log VAZIO, que parece "travou no launcher" e nao
# e. blue/yellow ficam prontos pelo cache no diretorio de save.
#
# Entao: detectar em vez de supor, e dizer em voz alta qual versao vai bootar.
versao_pronta() {
  case "$1" in
    red)
      local faltando=0
      for f in data/generated/constants.lua data/generated/maps.lua \
               data/generated/text.lua data/generated/field.lua \
               data/generated/battle_anims.lua \
               assets/generated/title/pokemon_logo.png \
               assets/generated/fonts/font.png \
               assets/generated/battle/front/pikachu.png \
               assets/generated/battle/anims/move_anim_0.png \
               assets/generated/battle/anims/move_anim_1.png \
               assets/generated/audio/programs.bin \
               assets/generated/trade/game_boy.png; do
        [ -e "$REPO/$f" ] || faltando=1
      done
      [ "$faltando" -eq 0 ]
      ;;
    *) [ -f "$SAVE/$1/rom-cache.complete" ] ;;
  esac
}

if [ -n "${VC_VERSION:-}" ]; then
  VERSAO="$VC_VERSION"
  versao_pronta "$VERSAO" || {
    echo "VC_VERSION=$VERSAO nao esta pronta nesta maquina (sem cache e sem"
    echo "arvore de fontes completa). O jogo cairia no importador e o driver"
    echo "nunca seria criado."
    exit 1
  }
else
  VERSAO=""
  for v in blue red yellow; do
    if versao_pronta "$v"; then VERSAO="$v"; break; fi
  done
  [ -n "$VERSAO" ] || {
    echo "nenhuma versao pronta: nem cache em $SAVE nem arvore de fontes completa"
    exit 1
  }
fi
echo "versao: $VERSAO"

# O marcador so afeta o caminho --game / POKEPORT_GAME, que nao e o nosso.
# Apagar continua sendo barato e evita surpresa se alguem rodar sem driver.
rm -f "$MARCADOR" 2>/dev/null

rm -rf "$SAIDA" && mkdir -p "$SAIDA"
find "$SAVE" -maxdepth 1 -name 'vc_*.png' -delete 2>/dev/null
LOG="$SAIDA/run.log"

cd "$REPO" || exit 1
# ARMADILHA 3: o caminho do driver precisa existir. main.lua:233 faz
# assert(loadfile(driverPath)), e um caminho errado derruba o boot em silencio.
[ -f "$DRIVER" ] || { echo "driver nao encontrado: $DRIVER"; exit 1; }

VC_OPT="$OPCAO" POKEPORT_VERSION="$VERSAO" POKEPORT_DRIVER="$DRIVER" \
  "$LOVE" . > "$LOG" 2>&1 &
PID=$!

# ARMADILHA 4: o log costumava sair VAZIO, porque sem TTY o stdout do LOVE fica
# em buffer de BLOCO e um processo que nao sai nunca esvazia. Log vazio nao
# distingue "nao aconteceu nada" de "nao terminou", e eu ja tirei a conclusao
# errada disso. O driver agora chama io.stdout:setvbuf("line"), entao o log e
# confiavel AO VIVO e a espera pode olhar o processo em vez de contar arquivo.
#
# E o numero esperado vem do PROPRIO driver ("fim, N fotos"), nao de uma
# constante aqui: quando eu tirei uma foto do driver, a constante 12 continuou
# la e o gate reprovou um run que tinha ido bem ate o fim.
LIMITE="${VC_TIMEOUT:-180}"
for _ in $(seq 1 "$LIMITE"); do
  pgrep -x love >/dev/null 2>&1 || break
  sleep 1
done

kill -9 "$PID" 2>/dev/null
pkill -x love 2>/dev/null
rm -f "$MARCADOR" 2>/dev/null

ESPERADAS="${VC_FOTOS:-}"
if [ -z "$ESPERADAS" ]; then
  ESPERADAS=$(grep -oE 'fim, [0-9]+ fotos' "$LOG" 2>/dev/null | grep -oE '[0-9]+' | tail -1)
fi
if [ -z "$ESPERADAS" ]; then
  echo "GATE FALHOU: o driver nunca chegou ao fim"
  echo "  log em $LOG ($(wc -l < "$LOG" | tr -d ' ') linhas), versao $VERSAO"
  grep -E 'preso_fora_do_mundo|opcao_sem_efeito|driver error' "$LOG" 2>/dev/null | head -3
  exit 1
fi

N=$(find "$SAVE" -maxdepth 1 -name 'vc_*.png' 2>/dev/null | wc -l | tr -d ' ')
if [ "$N" -ge "$ESPERADAS" ]; then
  find "$SAVE" -maxdepth 1 -name 'vc_*.png' -exec cp {} "$SAIDA"/ \; 2>/dev/null
  find "$SAVE" -maxdepth 1 -name 'vc_*.png' -delete 2>/dev/null
  echo "GATE OK: $N fotos em $SAIDA"
  if [ -n "$OPCAO" ]; then
    # ARMADILHA 5: escrever a opcao no save sem EMITIR o evento nao muda nada,
    # porque a malha ja esta cacheada. Eu produzi um A/B com imagens byte a byte
    # identicas e quase apresentei como comparacao. O driver agora aborta nesse
    # caso; aqui a gente confere que ele nao abortou.
    if grep -q "evento emitido" "$LOG" 2>/dev/null; then
      echo "  opcao aplicada: $OPCAO"
    else
      echo "  AVISO: a opcao $OPCAO NAO foi aplicada; nao use estas fotos para A/B"
      exit 2
    fi
  fi
  exit 0
fi

echo "GATE FALHOU: $N fotos (esperava $ESPERADAS)"
echo "  log em $LOG ($(wc -l < "$LOG" | tr -d ' ') linhas)"
echo "  versao usada: $VERSAO"
exit 1
