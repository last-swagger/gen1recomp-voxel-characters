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
  echo "ERROR: $MOD is not a git repository."
  echo "  Remember this mod is a NESTED repo, with its own remote: its .git"
  echo "  lives here, not at the gen1recomp root."
  exit 1
fi
mkdir -p "$DESTINO"

if [ "${1:-}" = "--remove" ]; then
  for h in "$AQUI/hooks"/*; do
    n=$(basename "$h")
    [ -f "$DESTINO/$n" ] && rm -f "$DESTINO/$n" && echo "removed: $n"
  done
  exit 0
fi

for h in "$AQUI/hooks"/*; do
  n=$(basename "$h")
  cp "$h" "$DESTINO/$n"
  chmod +x "$DESTINO/$n"
  echo "installed: $n"
done

echo
echo "quick hook test:"
if bash "$DESTINO/pre-commit" > /dev/null 2>&1; then
  echo "  the hook runs and approves the current tree"
else
  echo "  the hook runs and REJECTS the current tree (the quick battery is red)"
fi
echo "escape hatch: git commit --no-verify"
