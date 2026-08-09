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
