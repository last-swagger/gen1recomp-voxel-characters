# Resolve os binarios externos das ferramentas, ou morre dizendo por que.
#
# Existe porque tres ferramentas tinham /opt/homebrew/bin/love escrito na mao,
# que e o caminho do Homebrew de UMA maquina. Noutra maquina o caminho nao
# existe, e ai vem o defeito de verdade: `$($LOVE ... | grep ...)` com $LOVE
# ausente devolve string VAZIA, e checagem que compara duas saidas passa
# comparando vazio com vazio. A regua ficava verde sem ter medido nada.
#
# Vale para qualquer maquina: shell nao interativo do ssh nao carrega o perfil,
# entao /opt/homebrew/bin e /usr/local/bin costumam estar fora do PATH mesmo
# quando o binario esta instalado.
#
# Uso:  . "$(cd "$(dirname "$0")/.." && pwd)/tools_bin.sh"
#       $LOVE     sempre definido, ou o script ja saiu com erro
#       $FFMPEG   definido se existir, VAZIO se nao (quem precisa e que cobra)

acha() {  # $1 = nome no PATH, resto = caminhos absolutos candidatos
  local nome="$1"; shift
  local c
  for c in "$(command -v "$nome" 2>/dev/null)" "$@"; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

LOVE=$(acha love \
        "${LOVE_BIN:-}" \
        "/Applications/love.app/Contents/MacOS/love" \
        "$HOME/Applications/love.app/Contents/MacOS/love" \
        "/opt/homebrew/bin/love" \
        "/usr/local/bin/love") || {
  echo "ERRO: nao achei o binario do LOVE." >&2
  echo "  procurei em: PATH, \$LOVE_BIN, /Applications/love.app," >&2
  echo "               ~/Applications/love.app, /opt/homebrew, /usr/local" >&2
  echo "  conserto: instale o LOVE 11.5 ou aponte LOVE_BIN=/caminho/para/love" >&2
  exit 1
}
export LOVE

FFMPEG=$(acha ffmpeg "${FFMPEG_BIN:-}" "/opt/homebrew/bin/ffmpeg" "/usr/local/bin/ffmpeg") || FFMPEG=""
export FFMPEG

# TRAVA DO LOVE. Uma ferramenta de cada vez.
#
# run.sh, clip.sh e trailer.sh comecam com `pkill -x love`, porque um LOVE
# anterior vivo faz o proximo nascer sem conseguir nada. O efeito colateral e
# que iniciar uma ferramenta MATA qualquer medicao em andamento, e a saida
# truncada le como medicao curta em vez de medicao interrompida. Aconteceu: o
# trailer matou uma extracao de features no meio e o arquivo parcial parecia
# resultado.
#
# A trava e um diretorio, porque mkdir e atomico em qualquer sistema de
# arquivos. Guarda o PID para poder detectar dono morto: sem isso, uma
# ferramenta que caiu deixa a trava para sempre e o proximo tem que apagar na
# mao, o que ensina a pessoa a apagar a trava por reflexo.
VC_TRAVA="${VC_TRAVA:-/tmp/vc-love.lock}"

vc_trava_pega() {
  local quem="${1:-ferramenta}"
  if mkdir "$VC_TRAVA" 2>/dev/null; then
    echo "$$ $quem" > "$VC_TRAVA/dono"
    trap 'vc_trava_solta' EXIT INT TERM
    return 0
  fi
  local dono pid
  dono=$(cat "$VC_TRAVA/dono" 2>/dev/null || echo "?")
  pid=${dono%% *}
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    echo "trava orfa de $dono, recuperando"
    rm -rf "$VC_TRAVA"
    vc_trava_pega "$quem"
    return $?
  fi
  echo "OUTRA FERRAMENTA ESTA USANDO O LOVE: $dono"
  echo "  Espere ela acabar. Iniciar agora mataria a medicao dela e a saida"
  echo "  truncada pareceria um resultado curto."
  return 1
}

vc_trava_solta() {
  [ -d "$VC_TRAVA" ] || return 0
  local dono
  dono=$(cat "$VC_TRAVA/dono" 2>/dev/null || echo "")
  case "$dono" in "$$ "*) rm -rf "$VC_TRAVA" ;; esac
}
