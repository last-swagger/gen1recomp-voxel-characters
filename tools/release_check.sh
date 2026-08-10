#!/bin/bash
# Checks whether a published release is ACCEPTABLE TO THE GAME, using the
# game's own parser instead of our opinion of what it accepts.
#
# WHY THIS EXISTS. v1.6.0 shipped with a package named
# `voxel_characters-1.6.0.modpkg`. `modkit pack` generates that name, and the
# file IS a zip on the inside, so everything looked right: the package
# validated, downloaded and installed by hand. But the mod manager inside the
# game never saw the release.
#
# `ModUpdate.pickZipAsset` (src/mods/ModUpdate.lua:17-45) only looks at an
# attachment whose NAME ends in `.zip`, and `parseReleases` (:155) DISCARDS
# the whole release when it does not find one. A `.modpkg` is invisible to it.
#
# This applies to every one of our releases since 1.0.0: none of them ever
# showed up in the internal updater. Whoever wanted to update had to download
# from GitHub and import by hand, and "how do I install this" is the most
# repeated question in the thread. It was absol who pointed this out, having
# hit the same wall on their own fork.
#
# Usage:
#   tools/release_check.sh [tag]        default: the release marked latest
set -u

REPO_MOD="${VC_REPO:-last-swagger/gen1recomp-voxel-characters}"
RAIZ="$(cd "$(dirname "$0")/../../.." && pwd)"
TAG="${1:-}"

command -v gh >/dev/null || { echo "gh not found"; exit 1; }
command -v luajit >/dev/null || { echo "luajit not found"; exit 1; }

TMP="$(mktemp -t vcrel)" || exit 1
trap 'rm -f "$TMP"' EXIT

if [ -n "$TAG" ]; then
  gh api "repos/$REPO_MOD/releases/tags/$TAG" > "$TMP" 2>/dev/null \
    || { echo "could not read release $TAG"; exit 1; }
else
  gh api "repos/$REPO_MOD/releases/latest" > "$TMP" 2>/dev/null \
    || { echo "could not read the latest release"; exit 1; }
fi

# The mod ID comes from the manifest, not from a constant here: `pickZipAsset`
# prefers exactly `<id>-<version>.zip`, so getting the id wrong here would
# hide a wrong attachment name there.
MOD_ID=$(python3 -c "import json,sys;print(json.load(open('$RAIZ/mods/voxel_characters/manifest.json'))['id'])")

cd "$RAIZ" || exit 1
VC_REL_JSON="$TMP" VC_MOD_ID="$MOD_ID" luajit -e '
package.path = "./?.lua;" .. package.path
local ModUpdate = require("src.mods.ModUpdate")
local f = assert(io.open(os.getenv("VC_REL_JSON")))
local txt = f:read("*a"); f:close()

local lista, err = ModUpdate.parseReleases(txt, os.getenv("VC_MOD_ID"))
if not lista or not lista[1] then
  print("RELEASE REJECTED: the game says \"" .. tostring(err) .. "\"")
  print("")
  print("The mod manager inside the game will NOT see this release.")
  print("It is almost always the attachment name: it needs to end in .zip, and the")
  print("preferred name is " .. tostring(os.getenv("VC_MOD_ID")) .. "-<version>.zip")
  os.exit(1)
end
local r = lista[1]
print(string.format("tag         %s", tostring(r.tag)))
print(string.format("version     %s", tostring(r.version)))
print(string.format("attachment  %s", tostring(r.zip and r.zip.name)))
print(string.format("size        %s bytes", tostring(r.zip and r.zip.size)))
print(string.format("prerelease  %s", tostring(r.prerelease)))
if r.prerelease then
  print("")
  print("WARNING: marked as prerelease; the updater may ignore it.")
end
print("")
print("RELEASE OK: accepted by the parser the game itself runs.")
' 2>&1 || exit 1

echo ""
echo "checked against src/mods/ModUpdate.lua, the code the game actually runs,"
echo "not our assumption about what it accepts."

# ------------------------------------------------------------------
# WHO SIGNS THE RELEASE.
#
# A release's author is the account whose token created it, and GitHub does
# NOT let you change that afterwards: PATCH on releases accepts tag, name,
# body, draft, prerelease and make_latest, and nothing else. The nine
# releases published so far show up signed by kimsfigueredo, which is Kim's
# personal account, because this machine's `gh` is logged into it. The
# COMMITS are correct: all 32 on origin/main are last-swagger.
#
# So this does not fix the past, it prevents the next one. Publishing with
# the wrong account is the kind of mistake that only shows up after
# publishing, which is too late.
# ------------------------------------------------------------------
# THE RELEASE TEXT.
#
# Kim's rule, 2026-08-09: straight to the point, with an image or video, no
# padding. v1.6.0's body had 125 lines and no media. This does not fail it,
# it warns: judging prose by line count would be faking a precision that does
# not exist, but 40 lines is twice what any of our releases needed to say
# what changed, and missing media is binary.
LINHAS=$(python3 -c "import json;print(len(json.load(open('$TMP')).get('body','').splitlines()))" 2>/dev/null || echo 0)
TEM_MIDIA=$(python3 -c "
import json,re
b=json.load(open('$TMP')).get('body','')
print('sim' if re.search(r'!\[|<img|<video|\.png|\.gif|\.mp4', b) else 'nao')
" 2>/dev/null || echo "?")
echo ""
echo "body        $LINHAS lines, media: $TEM_MIDIA"
[ "${LINHAS:-0}" -gt 40 ] && echo "  WARNING: over 40 lines; the agreed format is title, 3 to 5 bullets, media, install, credits"
[ "$TEM_MIDIA" = "nao" ] && echo "  WARNING: no image or video; use the GIF from clip.sh or trailer.sh"

ESPERADO="${VC_RELEASE_AUTHOR:-last-swagger}"
AUTOR=$(python3 -c "import json,sys; print(json.load(open('$TMP')).get('author',{}).get('login',''))" 2>/dev/null)
echo ""
if [ "$AUTOR" = "$ESPERADO" ]; then
  echo "AUTHOR OK: signed by $AUTOR"
else
  echo "WRONG AUTHOR: this release is signed by '$AUTOR', expected '$ESPERADO'."
  echo ""
  echo "  The author is set at CREATION and GitHub does not allow editing it afterwards."
  echo "  For next time: export a token from the $ESPERADO account before publishing"
  echo "    GH_TOKEN=<token from $ESPERADO> gh release create ..."
  echo "  For this one: only deleting and recreating with the right token fixes it,"
  echo "  which resets the download count and drops the link for a few seconds."
  exit 1
fi
