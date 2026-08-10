#!/bin/bash
# GENERATES candidates, ranks them with the judge, and shows the finalists.
#
#   tools/juiz/gera.sh [how-many-finalists]
#
# This is the generator half of roadmap item 20. `calibra.sh` is the other
# half, and it is the one that decides whether any of this is trustworthy.
#
# WHAT IT GENERATES, and this is the part worth being explicit about: it
# proposes COMBINATIONS OF EXISTING OPTIONS, not new art. This project measured
# that an AI redraw satisfies every numeric constraint we own and produces
# worse art, so the generator that makes sense here is one that searches the
# space the mod already exposes, where every point in the space is something a
# player could have set by hand and nothing is invented.
#
# WHY THAT SPACE IS NOT THE ONE THE JUDGE WAS TRAINED ON. `rodada.sh` builds
# candidates by varying ONE option at a time from a fixed base, because pairs
# that differ in one thing are what make a choice interpretable. That is right
# for collecting preferences and wrong for finding the best setting: it never
# once asks what FRONT SHAPE and TOP DOME do TOGETHER, and the two of them are
# the pair the judge currently ranks highest on its own.
#
# So this samples combinations. The judge scores them, and the top few go to a
# person or to a critic, never straight into a default.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
MOD="$(cd "$AQUI/.." && pwd)"
RAIZ="$(cd "$MOD/../.." && pwd)"
. "$AQUI/../tools_bin.sh"

MODELO="${VC_MODELO:-$AQUI/dados/modelo.txt}"
QUANTOS="${1:-6}"
TMP="$(mktemp -d -t vcgera)" || exit 1
trap 'rm -rf "$TMP"; vc_trava_solta' EXIT

cd "$RAIZ" || exit 1
[ -f "$MODELO" ] || { echo "no model at $MODELO. Run a round of the judge first."; exit 1; }
vc_trava_pega "gera.sh" || exit 1

echo "== building the combination space"
luajit - "$TMP/cand.tsv" <<'LUA'
local saida = assert(io.open(arg[1], "w"))
local folhas = {}
local p = io.popen("ls assets/generated/sprites 2>/dev/null")
if p then
  for l in p:lines() do
    local n = l:match("^(.+)%.png$")
    if n then folhas[#folhas + 1] = n end
  end
  p:close()
end
table.sort(folhas)

-- The options that touch the MESH, with the levels the menu actually offers.
-- Only mesh options: the life channel post-multiplies a matrix and does not
-- change a single vertex, so it is invisible to a feature extractor that reads
-- the mesh, and including it would generate candidates that measure identical.
local OPCOES = {
  { "shape",        { "slab", "carved", "carved_plus" } },
  { "depth",        { 1, 3, 5 } },
  { "front_shape",  { "off", 0.12, 0.17, 0.22 } },
  { "top_dome",     { "off", 0.15, 0.30 } },
  { "top_edge",     { "off", "on" } },
  { "ground_shade", { "off", "on" } },
  { "side_color",   { "body", "outline" } },
}
local BASE = "blink:on,breath:0.01,first_person:card,footfall:off,lag:off,sway:off,step_weight:off"

-- FULL CROSS PRODUCT would be 3*3*4*3*2*2*2 = 864 per sheet, and measuring one
-- variant needs a render. Over even ten sheets that is a coffee break for a
-- search whose answer is decided by the top handful. So: a deterministic
-- sample, spread evenly through the product rather than taken from its start,
-- which would fix `shape` at slab for the entire run.
local total = 1
for _, o in ipairs(OPCOES) do total = total * #o[2] end
local ALVO = 90                      -- variants per sheet
local passo = math.max(1, math.floor(total / ALVO))

local n = 0
for i = 1, #folhas, 9 do            -- one sheet in nine: the criterion ranks, not the count
  for k = 0, total - 1, passo do
    local partes, resto = { BASE }, k
    for _, o in ipairs(OPCOES) do
      local idx = (resto % #o[2]) + 1
      resto = math.floor(resto / #o[2])
      partes[#partes + 1] = o[1] .. ":" .. tostring(o[2][idx])
    end
    saida:write(folhas[i] .. "\t0\t0\t" .. table.concat(partes, ",") .. "\n")
    n = n + 1
  end
end
saida:close()
io.stderr:write(string.format("%d combinations, from a space of %d per sheet\n",
  n, total))
LUA

echo "== measuring"
"$LOVE" mods/voxel_characters/tools/render features="$TMP/cand.tsv" \
  > "$TMP/feat.tsv" 2>"$TMP/feat.err"
MEDIDOS=$(grep -cv '^#' "$TMP/feat.tsv" 2>/dev/null || echo 0)
echo "  $MEDIDOS measured"
[ "$MEDIDOS" -gt 10 ] || { echo "measurement failed"; tail -3 "$TMP/feat.err"; exit 1; }

echo "== ranking"
luajit "$AQUI/ajusta.lua" --ranking "$TMP/feat.tsv" "$MODELO" "$QUANTOS" \
  > "$TMP/rank.tsv" 2>&1
cat "$TMP/rank.tsv"

# The finalists get RENDERED, because a ranking is a list of strings and a
# preference is about what something looks like. Nobody should approve a
# setting they have not seen.
SAVE_RENDER="$HOME/Library/Application Support/LOVE/render"
SAIDA="${VC_GERA_DIR:-/tmp/vc-gera}"
rm -rf "$SAIDA"; mkdir -p "$SAIDA"
echo ""
echo "== rendering the finalists"
i=0
while IFS=$'\t' read -r folha frame clock estado z; do
  case "$folha" in ''|'='*|'#'*) continue ;; esac
  i=$((i + 1)); [ "$i" -gt "$QUANTOS" ] && break
  # The builder comes from the state, anchored. `shape:` is a substring of
  # `front_shape:`, so an unanchored match returns the wrong word and the
  # harness is handed a builder that does not exist, which it hangs on.
  forma=$(printf '%s' "$estado" | grep -oE '(^|,)shape:[a-z_]+' | head -1 | cut -d: -f2)
  case "$forma" in slab|carved|carved_plus) ;; *) forma=slab ;; esac
  "$LOVE" mods/voxel_characters/tools/render sprite="$folha" shapes="$forma" \
    frames="$frame" yaws=0 rungs=35 cell=320 label=0 \
    out="gera_$i.png" opt="$estado" > /dev/null 2>&1 < /dev/null
  [ -f "$SAVE_RENDER/gera_$i.png" ] && cp "$SAVE_RENDER/gera_$i.png" "$SAIDA/finalista_$i.png"
  printf "  %d  %-16s %s\n" "$i" "$folha" \
    "$(printf '%s' "$estado" | sed 's/blink:on,breath:0.01,first_person:card,footfall:off,lag:off,sway:off,step_weight:off,//')"
done < <(grep -vE '^(==|$)' "$TMP/rank.tsv")

echo ""
echo "finalists in $SAIDA"
echo "NOTHING HERE CHANGES A DEFAULT. A new visual option ships off until the"
echo "community has seen it; this is a shortlist, not a decision."
