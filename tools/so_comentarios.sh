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
  # The sweep's list comes from git itself, so a path in it that is not in the
  # ref really is a new file, and saying so is correct.
  export VC_SOC_SWEEP=1
  set -- $(git -C "$MOD" diff --name-only "$REF" -- '*.lua')
fi
[ $# -gt 0 ] || { echo "nenhum .lua modificado contra $REF"; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FALHOU=0

# PATHS ARE NORMALISED TO THE MOD REPO, AND A MISS IS A FAILURE.
#
# Two defects lived here and both were false PASSES, which is the only
# direction this tool must never fail in.
#
# The mod is a NESTED git repo: inside it, this file is `main.lua`, but from
# the gen1recomp root the natural way to name it is
# `mods/voxel_characters/main.lua`. Stripping `$MOD/` only handled the
# absolute form, so the documented invocation left `rel` as the root-relative
# path, `git show HEAD:mods/voxel_characters/main.lua` found nothing, and...
#
# ...the old code treated "not in the ref" as "a new file, nothing to compare"
# and CONTINUED, exiting 0. So the gate reported success without diffing a
# single byte. That was found by an agent following the documented command
# literally, which is the best possible way to find it and the worst possible
# way to have shipped it.
#
# Now: every accepted spelling is normalised, and a file named explicitly that
# cannot be resolved in the ref is an ERROR. "New file" is only a legitimate
# answer during the automatic sweep, where the list came from git itself.
normaliza_caminho() {
  local p="$1"
  case "$p" in
    "$MOD"/*) printf '%s' "${p#"$MOD"/}" ;;            # absolute, inside the mod
    /*)       printf '%s' "$p" ;;                       # absolute, elsewhere
    mods/voxel_characters/*) printf '%s' "${p#mods/voxel_characters/}" ;;
    *)        printf '%s' "$p" ;;                       # already mod-relative
  esac
}

EXPLICITOS=1
[ "${VC_SOC_SWEEP:-0}" = "1" ] && EXPLICITOS=0

for f in "$@"; do
  rel=$(normaliza_caminho "$f")
  if [ ! -f "$MOD/$rel" ]; then
    printf "%-40s %s\n" "$rel" "NAO EXISTE em $MOD"
    FALHOU=1
    continue
  fi
  if ! git -C "$MOD" show "$REF:$rel" > "$TMP/orig.lua" 2>/dev/null; then
    if [ "$EXPLICITOS" = "1" ]; then
      printf "%-40s %s\n" "$rel" "NAO ESTA EM $REF"
      echo "    Pedido explicitamente, entao nao ha com o que comparar e isso"
      echo "    e uma falha, nao um 'ok'. Confira o caminho e o ref."
      FALHOU=1
    else
      printf "%-40s %s\n" "$rel" "novo no ref, nada a comparar"
    fi
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
