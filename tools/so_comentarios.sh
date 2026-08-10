#!/bin/bash
# Checks that the working tree changed only COMMENTS, against a git ref.
#
#   bash tools/so_comentarios.sh [ref] [arquivo...]
#
# With no arguments it checks every modified .lua file against HEAD, which is
# the shape the translation pass (roadmap item 2) needs: a whole file of prose
# rewritten, and a mechanical proof that no line of code moved with it.
#
# Exit 0 only if every file checked is code-identical.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
MOD="$(cd "$AQUI/.." && pwd)"
REF="${1:-HEAD}"
shift 2>/dev/null || true

LUAJIT=$(command -v luajit || echo /usr/local/bin/luajit)
[ -x "$LUAJIT" ] || { echo "luajit nao encontrado"; exit 2; }

if [ $# -eq 0 ]; then
  set -- $(git -C "$MOD" diff --name-only "$REF" -- '*.lua')
fi
[ $# -gt 0 ] || { echo "nenhum .lua modificado contra $REF"; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FALHOU=0
for f in "$@"; do
  rel="${f#"$MOD"/}"
  if ! git -C "$MOD" show "$REF:$rel" > "$TMP/orig.lua" 2>/dev/null; then
    printf "%-40s %s\n" "$rel" "novo no ref, nada a comparar"
    continue
  fi
  SAIDA=$("$LUAJIT" "$AQUI/so_comentarios.lua" "$TMP/orig.lua" "$MOD/$rel" 2>&1)
  if [ $? -eq 0 ]; then
    printf "%-40s %s\n" "$rel" "ok"
  else
    printf "%-40s %s\n" "$rel" "CODIGO MUDOU"
    echo "$SAIDA" | sed 's/^/    /'
    FALHOU=1
  fi
done

echo
[ $FALHOU -eq 0 ] && echo "SO COMENTARIOS OK" \
                  || echo "NAO E SO COMENTARIO: a traducao mexeu em codigo"
exit $FALHOU
