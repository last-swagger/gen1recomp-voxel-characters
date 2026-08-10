#!/bin/bash
# Builds a before-and-after explainer card from a recipe file.
#
#   tools/render/card.sh cards/shading.card [saida.png]
#
# The recipe is DATA and this file only executes it, the same split the trailer
# uses: whoever edits a card edits a text file, not shell. It also means a card
# published in a release note is reproducible from something in the repository,
# rather than from a command somebody typed once.
#
# The recipe renders the two halves with the harness and composes them. The
# "before" half can come from a released tag instead of from options, which is
# the difference between measuring what a version changed and illustrating it
# from memory:
#
#   before_tag=v1.5.0        renders the before with THAT version's main.lua
#
# Recipe keys, all optional except the ones marked:
#   title=            heading across the top
#   sprite=  frame=  rung=  yaw=  cell=      what to render (defaults below)
#   before_label=  before_sub=  before_opt=  before_tag=
#   after_label=   after_sub=   after_opt=
#   point=x,y|TITLE|sentence                 repeatable, x/y are fractions of
#                                            the CROPPED character, 0..1
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$AQUI/../../.." && pwd)"
. "$(cd "$AQUI/.." && pwd)/tools_bin.sh"

RECEITA="${1:?uso: card.sh <receita.card> [saida.png]}"
[ -f "$RECEITA" ] || { echo "receita nao encontrada: $RECEITA"; exit 1; }
SAIDA="${2:-card.png}"

SAVE_RENDER="$HOME/Library/Application Support/LOVE/render"
SAVE_COMPOSE="$HOME/Library/Application Support/LOVE/compose"

title="" ; sprite="red" ; frame="0" ; rung="35" ; yaw="0" ; cell="320"
before_label="BEFORE" ; before_sub="" ; before_opt="" ; before_tag=""
after_label="AFTER"   ; after_sub=""  ; after_opt=""
PONTOS=()

# Read the recipe. Cut at the FIRST `=`, because a callout sentence is prose
# and prose has equals signs in it; the key is always a bare word.
while IFS= read -r linha || [ -n "$linha" ]; do
  case "$linha" in ''|'#'*) continue ;; esac
  chave="${linha%%=*}"
  valor="${linha#*=}"
  case "$chave" in
    title|sprite|frame|rung|yaw|cell) printf -v "$chave" '%s' "$valor" ;;
    before_label|before_sub|before_opt|before_tag) printf -v "$chave" '%s' "$valor" ;;
    after_label|after_sub|after_opt) printf -v "$chave" '%s' "$valor" ;;
    point) PONTOS+=("point=$valor") ;;
    *) echo "AVISO: chave desconhecida na receita: $chave" ;;
  esac
done < "$RECEITA"

vc_trava_pega "card.sh" || exit 1

render() {  # $1 = arquivo de saida, $2 = opt=, $3 = VOXEL_CHARS_MAIN ou vazio
  local out="$1" opt="$2" main="${3:-}"
  local args=(sprite="$sprite" shapes=slab frames="$frame" yaws="$yaw"
              rungs="$rung" cell="$cell" label=0 out="$out")
  [ -n "$opt" ] && args+=(opt="$opt")
  if [ -n "$main" ]; then
    VOXEL_CHARS_MAIN="$main" bash "$AQUI/../love.sh" \
      mods/voxel_characters/tools/render "${args[@]}" > /dev/null || return 1
  else
    bash "$AQUI/../love.sh" mods/voxel_characters/tools/render "${args[@]}" \
      > /dev/null || return 1
  fi
  [ -f "$SAVE_RENDER/$out" ] || { echo "FALHOU: o harness nao escreveu $out"; return 1; }
}

ANTES_MAIN=""
if [ -n "$before_tag" ]; then
  ANTES_MAIN="$(mktemp -t vc_before).lua"
  git -C "$REPO/mods/voxel_characters" show "$before_tag:main.lua" > "$ANTES_MAIN" \
    || { echo "FALHOU: nao consegui ler main.lua de $before_tag"; exit 1; }
  echo "antes: main.lua da tag $before_tag"
fi

echo "renderizando $sprite frame $frame, rung $rung, yaw $yaw"
render card_antes.png "$before_opt" "$ANTES_MAIN" || exit 1
render card_depois.png "$after_opt" "" || exit 1

ARGS=(mode=card "out=$SAIDA" "title=$title"
      "before=$before_label|$before_sub|$SAVE_RENDER/card_antes.png"
      "after=$after_label|$after_sub|$SAVE_RENDER/card_depois.png")
# `"${PONTOS[@]}"` on an EMPTY array is an unbound variable under `set -u` in
# bash 3.2, which is what /bin/bash is on macOS. A recipe with no `point=`
# lines is a legitimate use of the format (a plain before and after), and it
# died here with "unbound variable" AFTER both halves had already rendered.
# Found by review, reproduced. The guard is one line and the alternative is a
# tool that breaks on its own documented input.
[ ${#PONTOS[@]} -gt 0 ] && ARGS+=("${PONTOS[@]}")

bash "$AQUI/../love.sh" mods/voxel_characters/tools/render/compose "${ARGS[@]}" || exit 1

echo "CARD OK  ->  $SAVE_COMPOSE/$SAIDA"
