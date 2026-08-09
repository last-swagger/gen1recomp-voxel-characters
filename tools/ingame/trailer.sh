#!/bin/bash
# Monta o TRAILER: roda o jogo dirigido pelo roteiro de trailer.lua, grava a
# sequencia inteira e junta num mp4 com transicao entre os planos.
#
#   tools/ingame/trailer.sh <pasta-de-saida>
#   VC_TRAILER_SEGUNDOS=12 tools/ingame/trailer.sh /tmp/t    versao curta
#
# O roteiro (mapas, degraus de camera, opcoes, legendas) mora em trailer.lua.
# Este arquivo so executa e monta, de proposito: quem edita o trailer edita
# dado, nao shell.
set -u
REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
SAVE="$HOME/Library/Application Support/LOVE/pokemon-love2d"
. "$(cd "$(dirname "$0")/.." && pwd)/tools_bin.sh"
DRIVER="$REPO/mods/voxel_characters/tools/ingame/trailer.lua"

SAIDA="${1:?uso: trailer.sh <pasta-de-saida>}"
[ -n "$FFMPEG" ] || { echo "ffmpeg nao encontrado"; exit 1; }
[ -f "$DRIVER" ] || { echo "roteiro nao encontrado: $DRIVER"; exit 1; }

versao_pronta() {
  case "$1" in
    red) [ -e "$REPO/data/generated/constants.lua" ] \
      && [ -e "$REPO/assets/generated/audio/programs.bin" ] ;;
    *) [ -f "$SAVE/$1/rom-cache.complete" ] ;;
  esac
}
VERSAO="${VC_VERSION:-}"
if [ -z "$VERSAO" ]; then
  for v in blue red yellow; do versao_pronta "$v" && { VERSAO="$v"; break; }; done
fi
[ -n "$VERSAO" ] || { echo "nenhuma versao pronta"; exit 1; }

pkill -x love 2>/dev/null
for _ in $(seq 1 20); do pgrep -x love >/dev/null 2>&1 || break; sleep 0.5; done

rm -rf "$SAIDA" && mkdir -p "$SAIDA"
find "$SAVE" -maxdepth 1 -name 'vc_trailer_*.png' -delete 2>/dev/null
LOG="$SAIDA/trailer.log"

cd "$REPO" || exit 1
echo "versao: $VERSAO   roteiro: $(basename "$DRIVER")"
POKEPORT_VERSION="$VERSAO" POKEPORT_DRIVER="$DRIVER" "$LOVE" . > "$LOG" 2>&1

# O driver diz quantos quadros gravou. Contar arquivo em vez de acreditar no
# log ja pegou um run que morreu no meio parecendo completo.
ESPERADOS=$(grep -oE 'fim, [0-9]+ quadros' "$LOG" | grep -oE '[0-9]+' | tail -1)
N=$(find "$SAVE" -maxdepth 1 -name 'vc_trailer_*.png' | wc -l | tr -d ' ')
if [ -z "$ESPERADOS" ]; then
  echo "FALHOU: o roteiro nao chegou ao fim"
  tail -5 "$LOG"
  exit 1
fi
echo "quadros: $N gravados, $ESPERADOS esperados"
[ "$N" -ge "$ESPERADOS" ] || { echo "FALHOU: faltaram quadros"; exit 1; }

TMP="$SAIDA/.quadros"
mkdir -p "$TMP"
find "$SAVE" -maxdepth 1 -name 'vc_trailer_*.png' -exec mv {} "$TMP"/ \;

FPS="${VC_TRAILER_FPS:-30}"
# Sem recorte: um trailer mostra o enquadramento do jogo, ao contrario do clipe
# de feature, que recorta no personagem porque a pergunta ali e outra.
"$FFMPEG" -y -loglevel error -framerate "$FPS" -start_number 1 \
  -i "$TMP/vc_trailer_%05d.png" \
  -c:v libx264 -pix_fmt yuv420p -crf 18 -preset slow \
  "$SAIDA/trailer.mp4" || { echo "ffmpeg falhou"; exit 1; }

# Um GIF curto do comeco, para colar em thread onde video nao toca sozinho.
"$FFMPEG" -y -loglevel error -t 6 -i "$SAIDA/trailer.mp4" \
  -vf "fps=15,scale=640:-2:flags=neighbor,palettegen=stats_mode=diff" \
  "$TMP/paleta.png" >/dev/null 2>&1
"$FFMPEG" -y -loglevel error -t 6 -i "$SAIDA/trailer.mp4" -i "$TMP/paleta.png" \
  -lavfi "fps=15,scale=640:-2:flags=neighbor[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3" \
  "$SAIDA/trailer.gif" >/dev/null 2>&1

rm -rf "$TMP"
echo "TRAILER OK"
for f in "$SAIDA"/trailer.mp4 "$SAIDA"/trailer.gif; do
  [ -e "$f" ] && printf "  %-20s %s\n" "$(basename "$f")" \
    "$(du -h "$f" | cut -f1 | tr -d ' ')"
done
grep -E '^\[trailer\] plano' "$LOG" | sed 's/^\[trailer\] /  /'
