#!/bin/bash
# Runs LOVE ALWAYS from the repo root, with the binary resolved.
#
# WHY THIS EXISTS. Calling `love mods/voxel_characters/tools/render` from
# inside the mod's directory produces
# `mods/voxel_characters/mods/voxel_characters/tools/render`, which does not
# exist. LOVE then opens a window saying "Cannot load game at path" and WAITS
# for a key: on the script's side, a ten-minute timeout with an empty log.
# Happened twice.
#
# And the `love.errorhandler` this repo installs does NOT cover this case,
# because the error happens during LOVE's boot, before any of our files load.
# In other words: the only possible defence is to never let the wrong path
# leave here.
#
# Usage:  bash mods/voxel_characters/tools/love.sh <target> [args...]
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$AQUI/../../.." && pwd)"
. "$AQUI/tools_bin.sh"
ALVO="${1:?usage: love.sh <path-to-game> [args]}"
shift
[ -d "$REPO/$ALVO" ] || [ -f "$REPO/$ALVO/main.lua" ] || {
  echo "$REPO/$ALVO does not exist"
  echo "  (path is always relative to the repo ROOT, never to your cwd)"
  exit 1
}
cd "$REPO" || exit 1
exec "$LOVE" "$ALVO" "$@"
