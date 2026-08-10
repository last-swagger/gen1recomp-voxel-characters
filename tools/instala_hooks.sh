#!/bin/bash
# Installs the repo's hooks into .git/hooks.
#
#   bash mods/voxel_characters/tools/instala_hooks.sh
#   bash mods/voxel_characters/tools/instala_hooks.sh --remove
#
# Hooks are not versioned by git, so the hook itself lives in tools/hooks/ and
# this copies it. That way the hook is reviewable, travels with the repository,
# and the same one runs on both machines.
#
# Installing is a per-clone action on purpose: it changes what happens when
# somebody types `git commit`, and doing that silently on checkout is how a
# tool earns distrust.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
MOD="$(cd "$AQUI/.." && pwd)"
DESTINO="$MOD/.git/hooks"

if [ ! -d "$MOD/.git" ]; then
  echo "ERRO: $MOD nao e um repositorio git."
  echo "  Lembre que este mod e um repo ANINHADO, com remote proprio: o .git"
  echo "  dele fica aqui, nao na raiz do gen1recomp."
  exit 1
fi
mkdir -p "$DESTINO"

if [ "${1:-}" = "--remove" ]; then
  for h in "$AQUI/hooks"/*; do
    n=$(basename "$h")
    [ -f "$DESTINO/$n" ] && rm -f "$DESTINO/$n" && echo "removido: $n"
  done
  exit 0
fi

for h in "$AQUI/hooks"/*; do
  n=$(basename "$h")
  cp "$h" "$DESTINO/$n"
  chmod +x "$DESTINO/$n"
  echo "instalado: $n"
done

echo
echo "teste rapido do hook:"
if bash "$DESTINO/pre-commit" > /dev/null 2>&1; then
  echo "  o hook roda e aprova a arvore atual"
else
  echo "  o hook roda e REPROVA a arvore atual (a bateria rapida esta vermelha)"
fi
echo "escape: git commit --no-verify"
