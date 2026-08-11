#!/bin/bash
# Assembles the TEST ROOM on a second machine: sends over everything the
# repository clone does not bring, then runs the battery there to prove it
# assembled.
#
#   bash mods/voxel_characters/tools/sala_de_teste.sh mbp
#   bash mods/voxel_characters/tools/sala_de_teste.sh mbp --so-conferir
#
# Exists because I already wrote in the documentation that the visual gates
# only ran on this machine, and that "this is not a limitation a script can
# work around". It was not a limitation at all: it was files nobody had
# copied, and the script takes twenty minutes. What the repository does not
# bring is listed below, so that next time the list is executable instead of
# something to rediscover.
#
# Nothing here pushes. Code goes by bundle, which transfers commits without
# touching any remote.
set -u
DESTINO="${1:?usage: sala_de_teste.sh <ssh-host> [--so-conferir]}"
MODO="${2:-}"
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
SAVE="$HOME/Library/Application Support/LOVE/pokemon-love2d"
MOD="$REPO/mods/voxel_characters"

falta=0
exige() { [ -e "$1" ] || { echo "MISSING on this machine: $1"; falta=1; }; }
exige "$REPO/baserom.gb"
exige "$REPO/assets/generated"
exige "$REPO/mods/DramaticShapeVoxelMod"
exige "$SAVE"
[ "$falta" -eq 0 ] || { echo; echo "the room is not assembled HERE; cannot copy"; exit 1; }

ssh "$DESTINO" 'echo ok' >/dev/null 2>&1 || { echo "cannot reach $DESTINO by ssh"; exit 1; }
ALVO=$(ssh "$DESTINO" 'cd ~/Projects/gen1recomp 2>/dev/null && pwd') || {
  echo "$DESTINO has no ~/Projects/gen1recomp; clone gen1recomp there first"; exit 1; }

if [ "$MODO" != "--so-conferir" ]; then
  echo "== LOVE (universal; goes to ~/Applications because the cask needs sudo)"
  LOCAL_LOVE=$(ls -d /Applications/love.app "$HOME/Applications/love.app" 2>/dev/null | head -1)
  [ -n "$LOCAL_LOVE" ] || { echo "no love.app here to copy"; exit 1; }
  ssh "$DESTINO" 'mkdir -p ~/Applications'
  rsync -a "$LOCAL_LOVE/" "$DESTINO:Applications/love.app/"

  echo "== ROM, art derived from the ROM, and the mods the clone does not bring"
  rsync -a "$REPO/baserom.gb" "$DESTINO:Projects/gen1recomp/"
  rsync -a "$REPO/assets/generated/" "$DESTINO:Projects/gen1recomp/assets/generated/"
  for m in DramaticShapeVoxelMod gen1_modern_ui; do
    [ -d "$REPO/mods/$m" ] && rsync -a "$REPO/mods/$m" "$DESTINO:Projects/gen1recomp/mods/"
  done

  echo "== LOVE save (the path has a space; Apple's rsync gets it wrong, tar does not)"
  ( cd "$(dirname "$SAVE")" && tar czf - --exclude '*-cache' "$(basename "$SAVE")" ) \
    | ssh "$DESTINO" 'mkdir -p ~/Library/Application\ Support/LOVE && tar xzf - -C ~/Library/Application\ Support/LOVE'

  echo "== mod commits, by bundle (no push)"
  B=$(mktemp -t vc-bundle)
  ( cd "$MOD" && git bundle create "$B" --all ) >/dev/null 2>&1
  RAMO=$(cd "$MOD" && git branch --show-current)
  scp -q "$B" "$DESTINO:/tmp/vc.bundle" && rm -f "$B"
  ssh "$DESTINO" "cd ~/Projects/gen1recomp/mods/voxel_characters && \
    git fetch -f -q /tmp/vc.bundle 'refs/heads/*:refs/remotes/studio/*' && \
    git reset -q --hard studio/$RAMO && git log --oneline -1"

  echo "== command-line tools"
  ssh "$DESTINO" 'export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH
    for f in luajit ffmpeg gh; do
      command -v $f >/dev/null || { echo "  installing $f"; NONINTERACTIVE=1 brew install $f >/dev/null 2>&1; }
    done'
fi

echo
echo "== the battery, over there"
ssh "$DESTINO" 'export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH; cd ~/Projects/gen1recomp
  L=mods/voxel_characters
  . $L/tools/tools_bin.sh
  FALHOU=0
  # REPORTING IS NOT GATING, and the previous version only reported: each line
  # was a printf with the result of a grep, and the script status was that of
  # the last ssh. Worse, when a probe dies BEFORE the summary the grep comes
  # out empty, and an empty column reads as "nothing to report" instead of
  # "failed". Both probes have an early exit that skips the whole summary.
  linha() {  # $1 label, $2 output, $3 pattern that means OK
    local r="$2"
    if [ -z "$r" ]; then
      printf "%-24s NO OUTPUT (the tool died before finishing)\n" "$1"
      FALHOU=1
      return
    fi
    printf "%-24s %s\n" "$1" "$r"
    case "$r" in *$3*) ;; *) FALHOU=1;; esac
  }

  linha "offline suite" "$(luajit $L/tests/voxel_chars_test.lua 2>&1 | tail -1)" "checks passed"
  linha "assertion linter" "$(luajit $L/tools/lint_asserts.lua 2>&1 | tail -1)" "nenhuma"
  linha "local slack" "$(bash $L/tools/folga_locais.sh 2>&1 | tail -1)" "OK"
  linha "ruler" "$(bash $L/tools/render/check.sh 2>&1 | tail -1)" "RULER OK"
  linha "packaging" "$(python3 tools/modkit.py validate $L 2>&1 | tail -1)" "ok"
  linha "life pixel" "$(POKEPORT_VERSION=blue POKEPORT_DRIVER=$L/tools/ingame/probe_life.lua "$LOVE" . 2>&1 | grep -E "^\[vida\] VEREDITO" | tail -1)" "CHEGA NA TELA"
  linha "menu" "$(POKEPORT_VERSION=blue POKEPORT_DRIVER=$L/tools/ingame/menu.lua "$LOVE" . 2>&1 | grep -E "^\[menu\] VEREDITO" | tail -1)" "O JOGADOR ESPERA"
  linha "first person" "$(POKEPORT_VERSION=blue POKEPORT_DRIVER=$L/tools/ingame/probe_fp.lua "$LOVE" . 2>&1 | grep -E "^\[fp\] VEREDITO" | tail -1)" "SOBREVIVE"
  linha "position" "$(POKEPORT_VERSION=blue POKEPORT_DRIVER=$L/tools/ingame/probe_draw.lua "$LOVE" . 2>&1 | grep -E "VEREDITO" | tail -1)" "CHEGA LIMPA"
  linha "photos" "$(bash $L/tools/ingame/run.sh /tmp/vc-sala 2>&1 | tail -1)" "GATE OK"
  linha "release" "$(bash $L/tools/release_check.sh 2>&1 | grep -E "^RELEASE" | tail -1)" "RELEASE OK"

  echo ""
  if [ "$FALHOU" -eq 0 ]; then echo "ROOM OK"; else echo "ROOM FAILED: read above"; fi
  exit $FALHOU'
