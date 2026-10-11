#!/bin/bash
# Prepares a local candidate; expensive qualification and publication are explicit.
#
#   tools/release.sh 1.8.2                    focused checks + local package
#   tools/release.sh 1.8.2 --qualificar       offline feature gates + Gen 1 host matrix
#   tools/release.sh 1.8.2 --profundo         full battery + mutation + all host gates
#   tools/release.sh 1.8.2 --publicar         qualifies, then publishes
#
# O padrão não publica nem inicia os testes longos. `--publicar` qualifica
# primeiro e só então cria a tag e a release remota.
#
# O pacote instalável precisa ter nome `<id>-<versão>.zip`; o atualizador ignora
# anexos `.modpkg`, mesmo quando o conteúdo é um ZIP válido.
set -u
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Uso: release.sh <versão> [--qualificar|--profundo|--publicar]" >&2
  exit 2
fi
AQUI="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$(dirname "$0")")"
MOD="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$AQUI/..")"
RAIZ="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${VC_ENGINE_ROOT:-$MOD/../..}")"
. "$AQUI/tools_bin.sh" 2>/dev/null || true

MOD_ID="voxel_characters"
REPO_MOD="${VC_REPO:-last-swagger/gen1recomp-voxel-characters}"
# O GitHub fixa o autor no momento da publicação; confira a conta antes de enviar.
AUTOR_ESPERADO="kimsfigueredo"

VERSAO="${1:?uso: release.sh <versao> [--qualificar|--publicar]}"
MODO="${2:---preparar}"
case "$MODO" in
  --preparar) RIGOROSO=0; PROFUNDO=0; PUBLICAR=0 ;;
  --qualificar) RIGOROSO=1; PROFUNDO=0; PUBLICAR=0 ;;
  --profundo) RIGOROSO=1; PROFUNDO=1; PUBLICAR=0 ;;
  --publicar) RIGOROSO=1; PROFUNDO=0; PUBLICAR=1 ;;
  *) echo "Uso: release.sh <versão> [--qualificar|--profundo|--publicar]" >&2; exit 2 ;;
esac
[[ "$VERSAO" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]] || {
  echo "Invalid version: use semver, for example 1.8.2" >&2
  exit 2
}
VERSAO_MANIFEST=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$MOD/manifest.json") || {
  echo "Could not read the version from manifest.json" >&2
  exit 2
}
[ "$VERSAO_MANIFEST" = "$VERSAO" ] || {
  echo "Requested version ($VERSAO) differs from manifest.json ($VERSAO_MANIFEST)" >&2
  exit 2
}
TAG="v$VERSAO"
SAIDA="${VC_RELEASE_DIR:-/tmp/vc-release-$VERSAO}"
SAIDA_REAL=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$SAIDA")

falha() { echo; echo "PAROU: $*"; exit 1; }
passo() { printf "\n\033[1m== %s\033[0m\n" "$1"; }

# ---------------------------------------------------------------- 1. the tree
passo "1. o repositorio"
case "$SAIDA_REAL" in
  "$MOD"|"$MOD"/*) falha "a pasta de saída precisa ficar fora do repositório: $SAIDA_REAL" ;;
esac
RAMO=$(git -C "$MOD" rev-parse --abbrev-ref HEAD)
echo "  ramo $RAMO, em $(git -C "$MOD" rev-parse --short HEAD)"
if [ "$RIGOROSO" -eq 1 ]; then
  SUJO=$(git -C "$MOD" status --porcelain)
  [ -z "$SUJO" ] || falha "qualificação exige árvore limpa; finalize ou mova as alterações antes.
$(echo "$SUJO" | sed 's/^/    /')"
else
  ALTERACOES=$(git -C "$MOD" status --porcelain | wc -l | tr -d ' ')
  [ "$ALTERACOES" -eq 0 ] || echo "  preparando a partir da cópia de trabalho ($ALTERACOES entradas alteradas)"
fi
if [ "$RIGOROSO" -eq 1 ] && git -C "$MOD" rev-parse "$TAG" >/dev/null 2>&1; then
  falha "a tag $TAG ja existe aqui. Uma tag publicada nao se reescreve."
fi

# ---------------------------------------------------------- 2. selected gates
mkdir -p "$SAIDA" || falha "nao consegui criar a pasta de saida $SAIDA"
if [ "$RIGOROSO" -eq 1 ]; then
  if [ "$PROFUNDO" -eq 1 ]; then PERFIL="--tudo"; else PERFIL="--sem-jogo"; fi
  passo "2. gates offline $PERFIL"
  if ! bash "$AQUI/bateria.sh" "$PERFIL" > "$SAIDA.bateria.log" 2>&1; then
    tail -20 "$SAIDA.bateria.log"
    falha "a bateria completa reprovou. Log: $SAIDA.bateria.log"
  fi
else
  passo "2. verificacoes focadas"
  if ! bash "$AQUI/bateria.sh" --foco > "$SAIDA.bateria.log" 2>&1; then
    tail -20 "$SAIDA.bateria.log"
    falha "as verificacoes focadas reprovaram. Log: $SAIDA.bateria.log"
  fi
fi
# O resumo usa o formato produzido por verdict(); verdict_gate.sh protege esse
# contrato para o release e o hook continuarem mostrando todas as aprovações.
grep -E '^   [^[:space:]].*[[:space:]]ok$' "$SAIDA.bateria.log" | sed 's/^/  /' || true
if [ "$PROFUNDO" -eq 1 ]; then
  echo "  DEEP BATTERY OK"
elif [ "$RIGOROSO" -eq 1 ]; then
  echo "  OFFLINE AND RENDER GATES OK"
else
  echo "  FOCUSED BATTERY OK"
fi

# ----------------------------------------------------------- 2b. runtime gates
if [ "$RIGOROSO" -eq 1 ] && [ "$PROFUNDO" -eq 1 ]; then
  passo "2b. testes de mutação"
  if ! bash "$AQUI/mutantes.sh" > "$SAIDA.mutantes.log" 2>&1; then
    tail -12 "$SAIDA.mutantes.log"
    falha "mutação reprovou. Log: $SAIDA.mutantes.log"
  fi
  tail -1 "$SAIDA.mutantes.log" | sed 's/^/  /'
fi

if [ "$RIGOROSO" -eq 1 ]; then
  if [ "$PROFUNDO" -eq 1 ]; then
    passo "2c. matriz completa de hosts e Gold"
    for g in hosts gold; do
      if ! bash "$AQUI/ingame/$g.sh" > "$SAIDA.$g.log" 2>&1; then
        tail -15 "$SAIDA.$g.log"
        falha "o gate $g.sh reprovou. Log: $SAIDA.$g.log"
      fi
      VEREDITO=$(grep -E '^(HOST MATRIX|WALK GATE) .*OK' "$SAIDA.$g.log" | tail -1)
      [ -n "$VEREDITO" ] || falha "$g.sh terminou sem um veredito. Log: $SAIDA.$g.log"
      echo "  $VEREDITO"
    done
  else
    passo "2b. hosts Gen 1 em Blue"
    if ! VC_VERSION=blue bash "$AQUI/ingame/hosts.sh" > "$SAIDA.hosts.log" 2>&1; then
      tail -15 "$SAIDA.hosts.log"
      falha "a matriz Gen 1 reprovou. Log: $SAIDA.hosts.log"
    fi
    VEREDITO=$(grep -E '^HOST MATRIX .*OK' "$SAIDA.hosts.log" | tail -1)
    [ -n "$VEREDITO" ] || falha "hosts.sh terminou sem um veredito. Log: $SAIDA.hosts.log"
    echo "  $VEREDITO"
  fi
fi

# ----------------------------------------------------------- 3. the changelog
# A release page gets the short introduction from the changelog. The detailed
# history stays in CHANGELOG.md without being copied wholesale into the release.
passo "3. a secao do changelog"
NOTAS="$SAIDA.notas.md"
mkdir -p "$(dirname "$NOTAS")"
awk -v v="$VERSAO" '
  $0 ~ "^## \\[" v "\\]" { dentro=1; next }
  dentro && /^## \[/     { exit }
  dentro && /^### /      { exit }
  dentro                 { print }
' "$MOD/CHANGELOG.md" > "$NOTAS"
if [ ! -s "$NOTAS" ]; then
  falha "CHANGELOG.md has no [$VERSAO] section.
  Add a short introduction before the detailed sections."
fi
LINHAS=$(grep -c . "$NOTAS")
echo "  $LINHAS lines of notes"
[ "$LINHAS" -le 40 ] || echo "  WARNING: over 40 lines. A release page is read in" \
  "fifteen seconds; the rest belongs in the changelog."

# --------------------------------------------------------------- 4. packaging
passo "4. o pacote"
PKG="$SAIDA/${MOD_ID}-${VERSAO}.modpkg"
python3 "$RAIZ/tools/modkit.py" pack "$MOD" --repo "$RAIZ" --output "$PKG" > "$SAIDA/pack.log" 2>&1 \
  || { tail -5 "$SAIDA/pack.log"; falha "modkit pack falhou"; }
[ -f "$PKG" ] || falha "o pack terminou sem criar $PKG. Veja $SAIDA/pack.log"

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

if [ "$PUBLICAR" -ne 1 ]; then
  echo
  if [ "$RIGOROSO" -eq 1 ]; then
    echo "QUALIFICAÇÃO OK. Nada foi publicado."
    echo "  Para publicar: tools/release.sh $VERSAO --publicar"
  else
    echo "CANDIDATE OK. Local package ready; game and mutation tests did not run."
    echo "  Para qualificar: tools/release.sh $VERSAO --qualificar"
  fi
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
