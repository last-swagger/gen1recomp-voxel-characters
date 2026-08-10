#!/bin/bash
# Grava um CLIPE lado a lado de uma opcao do mod: esquerda desligada, direita
# ligada, mesmo lugar, mesma camera, mesmo numero de quadros.
#
# Existe porque foto nao julga movimento. BREATH, SWAY e MOTION LAG so
# significam alguma coisa no tempo, e ate agora a unica forma de mostrar isso
# para alguem era pedir para a pessoa abrir o jogo.
#
# Uso:
#   tools/ingame/clip.sh <pasta-de-saida> <chave=valor>
#   tools/ingame/clip.sh <pasta-de-saida> <chave=valorA:valorB>
#
# Exemplos:
#   tools/ingame/clip.sh /tmp/clipe breath=0.020          OFF contra 0.020
#   tools/ingame/clip.sh /tmp/clipe breath=0.010:0.035    dois niveis, A contra B
#   VC_MAP=VIRIDIAN_CITY tools/ingame/clip.sh /tmp/clipe lag=0.70
#   VC_CLIP_DEGRAU=primeira tools/ingame/clip.sh /tmp/clipe first_person=solid
#
# VC_CLIP_DEGRAU escolhe o degrau de camera do host:
#   off baixo medio alto empe primeira terceira, ou o numero do nivel.
# Sem ele, o clipe sai no degrau que o save tiver, que varia entre corridas.
#
# A segunda forma e para ESCOLHER, nao para verificar. Contra OFF a pergunta e
# "faz alguma coisa?"; entre dois niveis e "qual deles?", que e a unica pergunta
# que sobra depois que a feature existe, e a unica cuja resposta e gosto.
#
# Sai com: <opcao>-off.mp4, <opcao>-on.mp4, <opcao>-ab.mp4 e <opcao>-ab.gif
# No lado a lado, ESQUERDA e desligado e DIREITA e ligado, sempre.

set -u
REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
SAVE="$HOME/Library/Application Support/LOVE/pokemon-love2d"
. "$(cd "$(dirname "$0")/.." && pwd)/tools_bin.sh"
DRIVER="$REPO/mods/voxel_characters/tools/ingame/clip.lua"

SAIDA="${1:?uso: clip.sh <pasta-de-saida> <chave=valor>}"
OPCAO="${2:?uso: clip.sh <pasta-de-saida> <chave=valor>}"
CHAVE="${OPCAO%%=*}"
SUFIXO=$(echo "${OPCAO#*=}" | tr ":" "-" | tr -d " ")

[ -n "$FFMPEG" ] || { echo "ffmpeg nao encontrado (PATH, \$FFMPEG_BIN, /opt/homebrew, /usr/local)"; exit 1; }
[ -f "$DRIVER" ] || { echo "driver nao encontrado: $DRIVER"; exit 1; }

# Mesma deteccao de versao do run.sh, pelo mesmo motivo: POKEPORT_GAME e letra
# morta sob POKEPORT_DRIVER, e red pode nao estar pronto nesta maquina.
versao_pronta() {
  case "$1" in
    red)
      local faltando=0
      for f in data/generated/constants.lua assets/generated/audio/programs.bin \
               assets/generated/trade/game_boy.png; do
        [ -e "$REPO/$f" ] || faltando=1
      done
      [ "$faltando" -eq 0 ]
      ;;
    *) [ -f "$SAVE/$1/rom-cache.complete" ] ;;
  esac
}
VERSAO="${VC_VERSION:-}"
if [ -z "$VERSAO" ]; then
  for v in blue red yellow; do versao_pronta "$v" && { VERSAO="$v"; break; }; done
fi
[ -n "$VERSAO" ] || { echo "nenhuma versao pronta"; exit 1; }

vc_trava_pega "clip.sh" || exit 1
pkill -x love 2>/dev/null
for _ in $(seq 1 20); do pgrep -x love >/dev/null 2>&1 || break; sleep 0.5; done

rm -rf "$SAIDA" && mkdir -p "$SAIDA"
find "$SAVE" -maxdepth 1 -name 'vc_clip_*.png' -delete 2>/dev/null
LOG="$SAIDA/clip.log"

cd "$REPO" || exit 1
echo "versao: $VERSAO   opcao: $OPCAO"
VC_CLIP_OPT="$OPCAO" POKEPORT_VERSION="$VERSAO" POKEPORT_DRIVER="$DRIVER" \
  "$LOVE" . > "$LOG" 2>&1
QUADROS=$(grep -oE 'quadros por lado: [0-9]+' "$LOG" | grep -oE '[0-9]+' | tail -1)
if [ -z "$QUADROS" ]; then
  echo "FALHOU: o driver nao terminou"
  tail -5 "$LOG"
  exit 1
fi

N_OFF=$(find "$SAVE" -maxdepth 1 -name 'vc_clip_off_*.png' | wc -l | tr -d ' ')
N_ON=$(find "$SAVE" -maxdepth 1 -name 'vc_clip_on_*.png' | wc -l | tr -d ' ')
echo "quadros gravados: $N_OFF desligado, $N_ON ligado"
if [ "$N_OFF" -lt 10 ] || [ "$N_ON" -lt 10 ]; then
  echo "FALHOU: quadros de menos"
  exit 1
fi

TMP="$SAIDA/.quadros"
mkdir -p "$TMP"
find "$SAVE" -maxdepth 1 -name 'vc_clip_*.png' -exec mv {} "$TMP"/ \;

# OS DOIS LADOS PRECISAM DIFERIR, e este check existe porque a mesma falha ja
# aconteceu: um A/B saiu com os dois lados BYTE A BYTE IDENTICOS e eu quase
# apresentei como comparacao. A causa foi escrever a opcao no save sem emitir o
# evento, entao a malha cacheada nunca reconstruia.
#
# O driver.lua aborta nesse caso; o clip.lua so avisava no log e ninguem lia. E
# "evento emitido" nao fecha o buraco: `pcall(emit)` devolve verdadeiro quando o
# barramento aceitou a mensagem, inclusive quando nao ha ouvinte nenhum. A unica
# prova que nao depende de introspeccao do mod e a TELA.
#
# O QUE ESTA GUARDA PEGA E O QUE ELA NAO PEGA, medido e nao suposto. Filmei um
# A/B com o MESMO valor dos dois lados (breath=0.010:0.010) e ela NAO disparou:
# com animacao ligada os dois lados sao gravados em sequencia, a fase do
# movimento avanca, e os quadros diferem por conta propria. Entao:
#
#   PEGA: opcao de MALHA que nao chegou. Sem reconstrucao e sem animacao os
#         dois lados saem byte a byte iguais, que e exatamente o defeito
#         historico que motivou esta guarda.
#   NAO PEGA: opcao que chegou e nao teve efeito, com animacao ligada.
#
# Fechar o segundo caso exige comparar a diferenca ENTRE os lados contra a
# variacao DENTRO de um lado, que e medida e nao comparacao de bytes. Esta na
# lista, e ate la esta guarda promete so o que cumpre.
IGUAIS=0; COMPARADOS=0
for i in 0010 0030 0050 0070; do
  A="$TMP/vc_clip_off_$i.png"; B="$TMP/vc_clip_on_$i.png"
  if [ -f "$A" ] && [ -f "$B" ]; then
    COMPARADOS=$((COMPARADOS + 1))
    cmp -s "$A" "$B" && IGUAIS=$((IGUAIS + 1))
  fi
done
if [ "$COMPARADOS" -eq 0 ]; then
  echo "FALHOU: nao consegui comparar quadro nenhum entre os dois lados"
  exit 1
fi
if [ "$IGUAIS" -eq "$COMPARADOS" ]; then
  echo "FALHOU: os dois lados sao IDENTICOS nos $COMPARADOS quadros amostrados."
  echo "  A opcao nao chegou na tela, e um clipe assim parece uma comparacao"
  echo "  sem ser uma. Ver o AVISO em $LOG."
  exit 1
fi
echo "lados diferem em $((COMPARADOS - IGUAIS)) de $COMPARADOS quadros amostrados"

FPS="${VC_CLIP_FPS:-30}"
ESCALA="${VC_CLIP_ESCALA:-640}"
# RECORTE em vez de zoom da camera do jogo. Forcar zoom no jogo puxa a camera
# para um angulo baixo e enche metade do quadro de chao; recortar depois nao
# mexe em nada do que o jogo desenhou e enquadra exatamente o personagem, que
# fica sempre perto do centro porque a camera o segue (Camera.lua:14-18). O
# recorte e um pouco acima do centro: os pes ficam no meio, o corpo sobe.
RECORTE="${VC_CLIP_RECORTE:-560:420:232:200}"

monta() {  # $1 = lado, $2 = arquivo de saida
  "$FFMPEG" -y -loglevel error -framerate "$FPS" -start_number 1 \
    -i "$TMP/vc_clip_$1_%04d.png" \
    -vf "crop=$RECORTE,scale=$ESCALA:-2:flags=neighbor" \
    -c:v libx264 -pix_fmt yuv420p -crf 18 "$2"
}
monta off "$SAIDA/$CHAVE-$SUFIXO-a.mp4" || { echo "ffmpeg falhou no lado off"; exit 1; }
monta on  "$SAIDA/$CHAVE-$SUFIXO-b.mp4"  || { echo "ffmpeg falhou no lado on"; exit 1; }

# Lado a lado. ESQUERDA desligado, DIREITA ligado, com uma faixa entre os dois
# para nao restar duvida de onde um acaba. Sem legenda em cima do video de
# proposito: este ffmpeg nao tem drawtext (sem libfreetype), e um pipeline que
# depende de build de terceiro quebra no primeiro usuario que nao tem.
"$FFMPEG" -y -loglevel error \
  -i "$SAIDA/$CHAVE-$SUFIXO-a.mp4" -i "$SAIDA/$CHAVE-$SUFIXO-b.mp4" \
  -filter_complex "[0:v]pad=iw+4:ih:0:0:color=white[e];[e][1:v]hstack=inputs=2" \
  -c:v libx264 -pix_fmt yuv420p -crf 18 "$SAIDA/$CHAVE-$SUFIXO-ab.mp4" \
  || { echo "ffmpeg falhou no lado a lado"; exit 1; }

# GIF em duas passadas: paleta propria, senao o degrade do ceu vira faixa.
"$FFMPEG" -y -loglevel error -i "$SAIDA/$CHAVE-$SUFIXO-ab.mp4" \
  -vf "fps=$FPS,scale=720:-2:flags=neighbor,palettegen=stats_mode=diff" \
  "$TMP/paleta.png" || { echo "ffmpeg falhou na paleta"; exit 1; }
"$FFMPEG" -y -loglevel error -i "$SAIDA/$CHAVE-$SUFIXO-ab.mp4" -i "$TMP/paleta.png" \
  -lavfi "fps=$FPS,scale=720:-2:flags=neighbor[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
  "$SAIDA/$CHAVE-$SUFIXO-ab.gif" || { echo "ffmpeg falhou no gif"; exit 1; }

rm -rf "$TMP"
echo "CLIPE OK"
for f in "$SAIDA"/*.mp4 "$SAIDA"/*.gif; do
  [ -e "$f" ] && printf "  %-40s %s\n" "$(basename "$f")" \
    "$(du -h "$f" | cut -f1 | tr -d ' ')"
done
ESQ="${OPCAO#*=}"; DIR="$ESQ"
case "$ESQ" in *:*) DIR="${ESQ#*:}"; ESQ="${ESQ%%:*}";; *) ESQ="off";; esac
echo "  no lado a lado: esquerda $CHAVE=$ESQ, direita $CHAVE=$DIR"
