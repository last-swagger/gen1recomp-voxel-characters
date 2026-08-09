# Resolve o binario do LOVE, ou morre dizendo por que.
#
# Existe porque tres ferramentas tinham /opt/homebrew/bin/love escrito na mao,
# que e o caminho do Homebrew de UMA maquina. Noutra maquina o caminho nao
# existe, e ai vem o defeito de verdade: `$($LOVE ... | grep ...)` com $LOVE
# ausente devolve string VAZIA, e checagem que compara duas saidas passa
# comparando vazio com vazio. A regua ficava verde sem ter medido nada.
#
# Uso:  . "$(dirname "$0")/../love_bin.sh"   # define $LOVE ou sai 1
#
# Ordem: LOVE_BIN do ambiente, love no PATH, /Applications, ~/Applications.
resolve_love() {
  local c
  for c in \
    "${LOVE_BIN:-}" \
    "$(command -v love 2>/dev/null)" \
    "/Applications/love.app/Contents/MacOS/love" \
    "$HOME/Applications/love.app/Contents/MacOS/love" \
    "/opt/homebrew/bin/love" \
    "/usr/local/bin/love"
  do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

LOVE=$(resolve_love) || {
  echo "ERRO: nao achei o binario do LOVE." >&2
  echo "  procurei em: \$LOVE_BIN, PATH, /Applications/love.app," >&2
  echo "               ~/Applications/love.app, /opt/homebrew, /usr/local" >&2
  echo "  conserto: instale o LOVE 11.5 ou aponte LOVE_BIN=/caminho/para/love" >&2
  exit 1
}
export LOVE
