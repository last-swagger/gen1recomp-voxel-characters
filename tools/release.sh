#!/bin/bash
# Builds, checks and (only when told twice) publishes a release.
#
#   tools/release.sh 1.7.0              REHEARSAL. Builds and checks, publishes nothing.
#   tools/release.sh 1.7.0 --publicar   Actually publishes. Needs GH_TOKEN.
#
# REHEARSAL IS THE DEFAULT AND THAT IS DELIBERATE. Publishing is outward facing
# and irreversible in the ways that matter: a release author cannot be edited
# after creation, and a tag that went out is a tag people fetched. So the
# normal path builds everything, prints exactly what would be published, and
# stops. Somebody has to type `--publicar` on purpose.
#
# WHAT THIS EXISTS TO PREVENT, and it is not hypothetical. Every release from
# 1.0.0 to 1.6.0 was INVISIBLE to the in-game mod updater. `modkit pack`
# produces `<id>-<version>.modpkg`, that file is a zip inside, it validated and
# installed by hand, and everything looked right. But
# `ModUpdate.pickZipAsset` only considers an attachment whose NAME ends in
# `.zip`, and `parseReleases` discards the whole release when it finds none. So
# nine releases shipped that nobody could update to from inside the game, and
# "how do I install this" became the most repeated question in the thread.
#
# The rename is therefore not a nicety, it is the entire point, and this script
# refuses to publish anything whose attachment is not named
# `<id>-<version>.zip`.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
MOD="$(cd "$AQUI/.." && pwd)"
RAIZ="$(cd "$MOD/../.." && pwd)"
. "$AQUI/tools_bin.sh" 2>/dev/null || true

MOD_ID="voxel_characters"
REPO_MOD="${VC_REPO:-last-swagger/gen1recomp-voxel-characters}"
# WHO IS ALLOWED TO PUBLISH, and this changed on 2026-08-13.
#
# It used to be `last-swagger`, the account that OWNS the repository and
# authored 1.0.0 through 1.6.0. Kim has never had that account's token -- those
# releases were published by somebody else -- so the guard was protecting a
# path he could not walk, and 1.7.0 sat finished and unpublished behind it.
#
# His own account has admin on the repo, so this is a change of author, not of
# permission. THE GUARD IS KEPT rather than removed: a release author cannot be
# edited after creation, so publishing from an unexpected account is exactly the
# mistake worth one more line of code. Point it at whoever should be signing
# releases today, and change it deliberately when that changes.
AUTOR_ESPERADO="kimsfigueredo"

VERSAO="${1:?uso: release.sh <versao> [--publicar]}"
MODO="${2:-ensaio}"
TAG="v$VERSAO"
SAIDA="${VC_RELEASE_DIR:-/tmp/vc-release-$VERSAO}"

falha() { echo; echo "PAROU: $*"; exit 1; }
passo() { printf "\n\033[1m== %s\033[0m\n" "$1"; }

# ---------------------------------------------------------------- 1. the tree
passo "1. o repositorio"
SUJO=$(git -C "$MOD" status --porcelain)
[ -z "$SUJO" ] || falha "arvore suja. Uma release tem que sair de um estado que
  alguem consegue voltar a produzir:
$(echo "$SUJO" | sed 's/^/    /')"
RAMO=$(git -C "$MOD" rev-parse --abbrev-ref HEAD)
echo "  ramo $RAMO, em $(git -C "$MOD" rev-parse --short HEAD)"
if git -C "$MOD" rev-parse "$TAG" >/dev/null 2>&1; then
  falha "a tag $TAG ja existe aqui. Uma tag publicada nao se reescreve."
fi

# ------------------------------------------------------------- 2. the battery
passo "2. a bateria"
if ! bash "$AQUI/bateria.sh" > "$SAIDA.bateria.log" 2>&1; then
  tail -20 "$SAIDA.bateria.log"
  falha "a bateria esta vermelha. Log completo em $SAIDA.bateria.log"
fi
# SUMMARISE BY THE SHAPE `verdict` PRINTS, not by a token count. This pattern
# was `^\s+\S+\s+ok$`, which requires the gate's NAME to be a single word, and
# it silently printed 5 of 11: every gate called "option docs" or "reason field"
# or "audio gate selftest" was dropped from the release rehearsal. The
# pre-commit hook had the same defect for a different reason and was fixed; this
# copy was missed, which is the argument for tools/verdict_gate.sh, that found
# it. Same pattern as the hook's on purpose.
# NOT TRUNCATED. This was `head -12`, then `head -14`, and both times the number
# was the gate count on the day somebody wrote it: the battery has grown to 17
# and the rehearsal quietly stopped listing the last three. A release summary
# that shows SOME of what passed is the same defect as one that shows a
# hardcoded list of names, which is what it was before that. There is no reason
# to cap it at all -- the battery is what decides how many lines there are.
grep -E '^   [^[:space:]].*[[:space:]]ok$' "$SAIDA.bateria.log" | sed 's/^/  /'
echo "  BATTERY OK"

# ------------------------------------------------------------- 2b. mutants
# The battery says the checks pass. This says the checks are checking. It is
# not in bateria.sh because it needs a clean tree and it rewrites files while
# it runs, so it belongs at a moment when nothing else is happening: this one.
#
# Its first run found that flipping the sign of the MOTION LAG term changed
# nothing any of 603 checks looked at. A release is exactly the wrong moment to
# discover the suite has a blind spot.
passo "2b. os mutantes: a suite esta mesmo checando?"
if ! bash "$AQUI/mutantes.sh" > "$SAIDA.mutantes.log" 2>&1; then
  tail -12 "$SAIDA.mutantes.log"
  falha "um mutante sobreviveu: a suite passa por cima dessa linha.
  Log completo em $SAIDA.mutantes.log"
fi
tail -1 "$SAIDA.mutantes.log" | sed 's/^/  /'

# ------------------------------------------------------------- 2c. the Gen 2 gates
# THE PUBLIC PROMISE, MADE ENFORCEABLE. 1.8.1's notes say every release is
# booted against each voxel host before it ships. Until this step existed that
# sentence was kept by somebody remembering: both Gen 2 gates sit outside
# bateria.sh on purpose (its in-game step is the slow one and only one LOVE runs
# at a time, so a Gold boot is added wall-clock rather than overlapped), and the
# battery was this script's only gate. Outside the battery therefore meant
# outside the release, which is how 1.8.0 shipped listing PotatoVoxel as
# supported having never once attached to it.
#
# Here is where that cost is affordable: once per release instead of every run.
#
#   hosts.sh   every installed voxel host, on both games: does the mod attach?
#   gold.sh    Gen 2 specifically: can the harness land the player and drive it
#              with the mod attached, which is what makes any Gen 2 claim
#              measurable rather than hoped.
#
# ONLY GOLD FOR THE WALK GATE, not both games. gold.sh runs on Blue too and that
# is how its Gen 1 half was proved, but probe_walk.lua already drives the same
# adapter on Blue on every battery run. Repeating it here would buy a second
# copy of a green check and charge a game boot for it.
#
# EXIT CODE IS ENOUGH HERE, unlike the battery's step 9, which has to count
# PASSED as well because it reads drivers directly. Both of these scripts
# already do that counting themselves and refuse a silent run: gold.sh answers
# NO VERDICT when nothing printed, and hosts.sh fails a game with zero
# applicable hosts. Re-counting their output here would be a second, weaker copy
# of a check they already make.
passo "2c. os gates de Gen 2"
for g in hosts gold; do
  if ! bash "$AQUI/ingame/$g.sh" > "$SAIDA.$g.log" 2>&1; then
    tail -15 "$SAIDA.$g.log"
    falha "o gate $g.sh reprovou. Log completo em $SAIDA.$g.log"
  fi
  # THE VERDICT IS NOT THE LAST LINE, which is what this was first written as.
  # Both scripts restore the player's options.lua on the way out and print the
  # sha they verified it against, so `tail -1` reports the restore and never the
  # verdict. That is the same defect step 2 above already carries a comment
  # about: a summary that reads plausibly while showing the wrong thing.
  #
  # And an empty match is a failure, not a blank line. A gate that exits 0
  # having printed no verdict has not passed, it has not answered -- the
  # distinction this project keeps relearning.
  VEREDITO=$(grep -E '^(HOST MATRIX|WALK GATE) .*\bOK\b' "$SAIDA.$g.log" | tail -1)
  [ -n "$VEREDITO" ] || falha "$g.sh saiu verde sem imprimir veredito, o que
  nao e um pass e sim uma falta de resposta. Log completo em $SAIDA.$g.log"
  echo "  $VEREDITO"
done

# ----------------------------------------------------------- 3. the changelog
# The body comes from CHANGELOG.md and nowhere else. Writing release notes by
# hand at publish time is how a release ends up saying something the changelog
# does not, and the changelog is the version people read six months later.
passo "3. a secao do changelog"
NOTAS="$SAIDA.notas.md"
mkdir -p "$(dirname "$NOTAS")"
awk -v v="$VERSAO" '
  $0 ~ "^## \\[" v "\\]" { dentro=1; next }
  dentro && /^## \[/     { exit }
  dentro                 { print }
' "$MOD/CHANGELOG.md" > "$NOTAS"
if [ ! -s "$NOTAS" ]; then
  falha "CHANGELOG.md has no [$VERSAO] section.
  Write the entry before packaging: it IS the release text."
fi
LINHAS=$(grep -c . "$NOTAS")
echo "  $LINHAS lines of notes"
[ "$LINHAS" -le 40 ] || echo "  WARNING: over 40 lines. A release page is read in" \
  "fifteen seconds; the rest belongs in the changelog."

# Named credit is a house rule, so the absence of any name is worth a word.
grep -qiE 'thanks|reported by|@|found by' "$NOTAS" \
  || echo "  WARNING: no named credit in the section. Whoever reported it goes in by name."

# --------------------------------------------------------------- 4. packaging
passo "4. o pacote"
rm -rf "$SAIDA"; mkdir -p "$SAIDA"
python3 "$RAIZ/tools/modkit.py" pack "$MOD" > "$SAIDA/pack.log" 2>&1 \
  || { tail -5 "$SAIDA/pack.log"; falha "modkit pack falhou"; }
PKG=$(grep -oE '[^ ]+\.modpkg' "$SAIDA/pack.log" | tail -1)
[ -n "${PKG:-}" ] && [ -f "$PKG" ] || {
  PKG=$(find "$RAIZ" "$MOD" -maxdepth 2 -name "*${VERSAO}.modpkg" -newer "$SAIDA/pack.log" 2>/dev/null | head -1)
}
[ -n "${PKG:-}" ] && [ -f "$PKG" ] || falha "nao achei o .modpkg que o pack gerou.
  Veja $SAIDA/pack.log"

# THE RENAME. See the header. The in-game updater cannot see a .modpkg.
ZIP="$SAIDA/${MOD_ID}-${VERSAO}.zip"
cp "$PKG" "$ZIP"
echo "  $(basename "$PKG")  ->  $(basename "$ZIP")  ($(du -h "$ZIP" | cut -f1 | tr -d ' '))"

case "$(basename "$ZIP")" in
  "${MOD_ID}-${VERSAO}.zip") ;;
  *) falha "o anexo tem que se chamar ${MOD_ID}-${VERSAO}.zip" ;;
esac
unzip -tq "$ZIP" >/dev/null 2>&1 || falha "o .zip nao abre como zip"

# ------------------------------------------------------------------ 5. media
# House rule since 1.6.0: every release carries images and video. The tools
# that make them already exist, so this looks for their output rather than
# asking the person to remember.
passo "5. midia"
MIDIA=()
for f in "$HOME/Library/Application Support/LOVE/compose/shading.png" \
         "$SAIDA/trailer.mp4" "$SAIDA/trailer.gif"; do
  [ -f "$f" ] && MIDIA+=("$f") && echo "  $(basename "$f")"
done
if [ ${#MIDIA[@]} -eq 0 ]; then
  echo "  none. Generate them first:"
  echo "    tools/render/card.sh tools/render/cards/<x>.card <x>.png"
  echo "    tools/ingame/trailer.sh $SAIDA"
  echo "    tools/ingame/clip.sh $SAIDA <option>=<value>"
fi

# ------------------------------------------------------------- 6. the verdict
passo "6. o que seria publicado"
cat <<FIM
  repositorio  $REPO_MOD
  tag          $TAG
  autor        precisa ser $AUTOR_ESPERADO
  anexo        $(basename "$ZIP")
  midia        ${#MIDIA[@]} arquivo(s)
  notas        $NOTAS
FIM
echo "  ---8<--- notas ---"
sed 's/^/  /' "$NOTAS"
echo "  ---8<---"

if [ "$MODO" != "--publicar" ]; then
  echo
  echo "REHEARSAL OK. Nothing was published."
  echo "  To publish for real:  tools/release.sh $VERSAO --publicar"
  echo "  Before that: GH_TOKEN must be a token from the $AUTOR_ESPERADO account."
  echo "  A release author CANNOT be edited after creation."
  exit 0
fi

# ---------------------------------------------------------------- 7. publish
passo "7. publicando"
command -v gh >/dev/null || falha "gh nao encontrado"
[ -n "${GH_TOKEN:-}" ] || falha "sem GH_TOKEN.
  As nove releases anteriores sairam assinadas pela conta pessoal e isso nao
  tem conserto depois. Exporte um token da conta $AUTOR_ESPERADO."

QUEM=$(gh api user --jq .login 2>/dev/null || echo "?")
[ "$QUEM" = "$AUTOR_ESPERADO" ] || falha "o token e de '$QUEM', nao de '$AUTOR_ESPERADO'."

git -C "$MOD" tag -a "$TAG" -m "$MOD_ID $VERSAO" || falha "nao consegui criar a tag"
git -C "$MOD" push origin "$TAG" || falha "nao consegui enviar a tag"

gh release create "$TAG" --repo "$REPO_MOD" \
  --title "$MOD_ID $VERSAO" --notes-file "$NOTAS" \
  "$ZIP" "${MIDIA[@]}" || falha "gh release create falhou"

passo "8. o jogo aceita?"
bash "$AQUI/release_check.sh" "$TAG" || falha "a release saiu mas o jogo nao a
  enxerga. Conserte o anexo antes de anunciar."
echo
echo "RELEASE OK: $TAG"
