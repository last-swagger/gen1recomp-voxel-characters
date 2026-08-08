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
#   tools/ingame/run.sh /tmp/ab/low front_shape=0.12
#
# CADA TRAVA AQUI VEIO DE ERRO PAGO NESTA SESSAO. Nao remova nenhuma sem ler.

set -u
REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
SAVE="$HOME/Library/Application Support/LOVE/pokemon-love2d"
MARCADOR="$SAVE/relaunch_to_launcher.txt"
LOVE="${LOVE_BIN:-/opt/homebrew/bin/love}"
DRIVER="$REPO/mods/voxel_characters/tools/ingame/driver.lua"

SAIDA="${1:?uso: run.sh <pasta-de-saida> [chave=valor]}"
OPCAO="${2:-}"

# ARMADILHA 1: um processo anterior ainda vivo faz o proximo nascer sem
# conseguir nada. Matar NAO e instantaneo; esperar morrer de verdade.
pkill -x love 2>/dev/null
for _ in $(seq 1 20); do
  pgrep -x love >/dev/null 2>&1 || break
  sleep 0.5
done

# ARMADILHA 2: o jogo escreve um marcador AO SAIR que faz o boot seguinte
# ignorar --game exatamente uma vez e parar no launcher (main.lua:352-357, o
# marcador e consumido na leitura). Sem apagar isto, uma sequencia de runs
# alterna entre funcionar e ficar preso, o que parece flakiness e nao e.
rm -f "$MARCADOR" 2>/dev/null

rm -rf "$SAIDA" && mkdir -p "$SAIDA"
rm -f "$SAVE"/vc_*.png 2>/dev/null
LOG="$SAIDA/run.log"

cd "$REPO" || exit 1
# ARMADILHA 3: POKEPORT_GAME sozinho nao basta; sem POKEPORT_SLOT o jogo pode
# parar antes do mundo. E o caminho do driver precisa existir: um caminho errado
# faz o assert do loadfile derrubar o boot em silencio.
[ -f "$DRIVER" ] || { echo "driver nao encontrado: $DRIVER"; exit 1; }

VC_OPT="$OPCAO" POKEPORT_GAME="${VC_GAME:-blue}" POKEPORT_SLOT="${VC_SLOT:-1}" \
  POKEPORT_DRIVER="$DRIVER" "$LOVE" . > "$LOG" 2>&1 &
PID=$!

# ARMADILHA 4: quando o processo NAO sai, o stdout fica em buffer de bloco e o
# log sai VAZIO. Log vazio nao distingue "nao aconteceu nada" de "nao terminou",
# e eu ja tirei a conclusao errada disso. Entao a espera olha as FOTOS, que sao
# escritas na hora, e nao o log.
ESPERADAS="${VC_FOTOS:-12}"
for _ in $(seq 1 90); do
  N=$(ls "$SAVE" 2>/dev/null | grep -c '^vc_.*png$')
  [ "$N" -ge "$ESPERADAS" ] && break
  pgrep -x love >/dev/null 2>&1 || break
  sleep 1
done

kill -9 "$PID" 2>/dev/null
pkill -x love 2>/dev/null
rm -f "$MARCADOR" 2>/dev/null

N=$(ls "$SAVE" 2>/dev/null | grep -c '^vc_.*png$')
if [ "$N" -ge "$ESPERADAS" ]; then
  cp "$SAVE"/vc_*.png "$SAIDA"/ 2>/dev/null
  rm -f "$SAVE"/vc_*.png 2>/dev/null
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
echo "  log vazio quase sempre quer dizer que o jogo ficou preso no launcher"
echo "  e nao que nada aconteceu: sem sair, o stdout nunca esvazia."
exit 1
