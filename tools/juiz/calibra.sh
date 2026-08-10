#!/bin/bash
# CALIBRATES A CRITIC against choices Kim already made.
#
#   tools/juiz/calibra.sh prepara [how-many]     renders pairs, hides the answers
#   tools/juiz/calibra.sh conta                  scores a critic's verdicts
#
# WHY THIS IS THE FIRST PIECE OF THE GENERATOR LOOP AND NOT THE LAST.
#
# Roadmap item 20 is a generator that proposes, a critic that judges, and a
# loop that runs without a person. The critique pillar is the one everybody
# copies and the one that usually fails, because a critic with no ground truth
# is a second opinion with more confidence. This project already measured the
# exact failure it produces: an AI redraw here satisfied every numeric
# constraint we own and produced worse art. A visual critic would have approved
# that too, for the same reason.
#
# So before a critic is allowed to drive anything, it answers pairs Kim has
# ALREADY decided, without seeing his answers, and we count. A critic that
# agrees 55% of the time is a coin flip wearing a lab coat. One that agrees 85%
# can pre-filter candidates so Kim only sees the close calls.
#
# THE BASELINE IS PRINTED TOO, and it is the part that makes the number mean
# something. If Kim happened to pick B in 60% of these pairs, a critic that
# always answers B scores 60% while knowing nothing. Agreement is only evidence
# when it beats always-answering-the-commonest-side.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
MOD="$(cd "$AQUI/.." && pwd)"
RAIZ="$(cd "$MOD/../.." && pwd)"
. "$AQUI/../tools_bin.sh"

ESCOLHAS="${VC_ESCOLHAS:-$AQUI/dados/escolhas.txt}"
SAIDA="${VC_CALIBRA_DIR:-/tmp/vc-calibra}"
SAVE_RENDER="$HOME/Library/Application Support/LOVE/render"
SAVE_COMPOSE="$HOME/Library/Application Support/LOVE/compose"
CMD="${1:-prepara}"
QUANTOS="${2:-20}"

cd "$RAIZ" || exit 1

if [ "$CMD" = "conta" ]; then
  GAB="$SAIDA/gabarito.txt"
  VER="$SAIDA/veredito.txt"
  [ -f "$GAB" ] || { echo "no answer key at $GAB. Run 'prepara' first."; exit 1; }
  [ -f "$VER" ] || {
    echo "no verdicts at $VER."
    echo "  The critic writes one line per pair: <n> <A|B>"
    exit 1
  }
  luajit - "$GAB" "$VER" <<'LUA'
local function ler(caminho)
  local m = {}
  for linha in io.lines(caminho) do
    local n, v = linha:match("^%s*(%d+)%s+([ABab])")
    if n then m[tonumber(n)] = v:upper() end
  end
  return m
end
local gab, ver = ler(arg[1]), ler(arg[2])
local total, acertos, respondidas = 0, 0, 0
local contaA, contaB = 0, 0
for n, esperado in pairs(gab) do
  total = total + 1
  if esperado == "A" then contaA = contaA + 1 else contaB = contaB + 1 end
  local dito = ver[n]
  if dito then
    respondidas = respondidas + 1
    if dito == esperado then acertos = acertos + 1 end
  end
end
if respondidas == 0 then
  print("the critic answered nothing")
  os.exit(1)
end
-- The baseline: always answering whichever side Kim picked more often.
local maior = math.max(contaA, contaB)
local base = maior / total
local ac = acertos / respondidas
print(string.format("pairs            %d, answered %d", total, respondidas))
print(string.format("critic agrees    %.1f%%  (%d of %d)",
  ac * 100, acertos, respondidas))
print(string.format("always-%s would  %.1f%%  (Kim picked A %d, B %d)",
  contaA >= contaB and "A" or "B", base * 100, contaA, contaB))
print("")
if ac <= base then
  print("THE CRITIC IS NOT BEATING THE COMMONEST ANSWER. It knows nothing")
  print("about this art yet, whatever its agreement number looks like.")
  os.exit(1)
elseif ac < 0.75 then
  print("The critic beats the baseline but is under 75%. Usable to break ties,")
  print("not to filter: at this rate one in four finalists is wrong.")
else
  print("The critic can pre-filter: show Kim the close calls, not every")
  print("candidate. Re-calibrate whenever the critic's prompt changes.")
end
LUA
  exit $?
fi

# ---------------------------------------------------------------- prepara
# THE LOCK COMES FIRST, BEFORE THE DELETE, and that order is the whole point.
#
# It was the other way round, and a second invocation deleted the output
# directory and THEN discovered the lock was held and refused. So the run that
# was correctly protected by the lock had its output erased underneath it by
# the run the lock had just turned away.
#
# The lock stops two tools sharing LOVE. It cannot stop a tool destroying
# something before it asks. Anything destructive belongs after the lock, and
# nothing belongs before it.
vc_trava_pega "calibra.sh" || exit 1
trap 'vc_trava_solta' EXIT
rm -rf "$SAIDA"; mkdir -p "$SAIDA"

echo "== reading the choices"
luajit - "$ESCOLHAS" "$QUANTOS" "$SAIDA/pares.tsv" "$SAIDA/gabarito.txt" <<'LUA'
local caminho, quantos, saidaPares, saidaGab = arg[1], tonumber(arg[2]), arg[3], arg[4]
local function canonico(texto)
  local pares = {}
  for k, v in tostring(texto):gmatch("([%w_]+)=([^%s]+)") do
    pares[#pares + 1] = { k = k, v = v }
  end
  table.sort(pares, function(a, b) return a.k < b.k end)
  local partes = {}
  for _, p in ipairs(pares) do partes[#partes + 1] = p.k .. ":" .. p.v end
  return table.concat(partes, ",")
end
local linhas = {}
for linha in io.lines(caminho) do
  local folha = linha:match("folha=(%S+)")
  local escolha = linha:match("escolha=(%S+)")
  local a, b = linha:match("|%s*A:%s*(.-)%s*|%s*B:%s*(.*)$")
  if folha and (escolha == "A" or escolha == "B") and a and b then
    linhas[#linhas + 1] = { folha = folha, escolha = escolha,
      frame = linha:match("frame=(%d+)") or "0",
      a = canonico(a), b = canonico(b) }
  end
end
-- Spread the sample across the file instead of taking the first N: the early
-- choices are the ones made while still learning what the question was.
local passo = math.max(1, math.floor(#linhas / quantos))
local p = assert(io.open(saidaPares, "w"))
local g = assert(io.open(saidaGab, "w"))
local n = 0
for i = 1, #linhas, passo do
  if n >= quantos then break end
  n = n + 1
  local l = linhas[i]
  p:write(string.format("%d\t%s\t%s\t%s\t%s\n", n, l.folha, l.frame, l.a, l.b))
  g:write(string.format("%d %s\n", n, l.escolha))
end
p:close(); g:close()
io.stderr:write(n .. " pairs selected out of " .. #linhas .. "\n")
LUA

echo "== rendering each side"
# NO `while read` LOOP HERE, and that is deliberate rather than stylistic.
#
# With the pair list piped into a `while read`, LOVE inherited the loop's
# stdin, which IS the file being read, and hung: the trace showed the command
# built correctly and then simply never returning, while the identical command
# typed by hand finished in under a second. Redirecting each child from
# /dev/null did not fix it either.
#
# Reading the whole list into an array first removes the interaction rather
# than negotiating with it. The list is a few dozen lines; there is nothing to
# stream.
LINHAS=()
while IFS= read -r l; do LINHAS+=("$l"); done < "$SAIDA/pares.tsv"

for linha in "${LINHAS[@]}"; do
  idx=$(printf '%s' "$linha" | cut -f1)
  folha=$(printf '%s' "$linha" | cut -f2)
  frame=$(printf '%s' "$linha" | cut -f3)
  ea=$(printf '%s' "$linha" | cut -f4)
  eb=$(printf '%s' "$linha" | cut -f5)
  for lado in A B; do
    [ "$lado" = "A" ] && est="$ea" || est="$eb"
    # ANCHORED. `shape:` is a SUBSTRING of `front_shape:`, and the option list
    # is sorted alphabetically, so `front_shape:off` comes first and an
    # unanchored grep returned "off". The harness was then handed `shapes=off`,
    # which it neither rendered nor refused: it hung, and from outside that
    # looked like LOVE being slow rather than like a bad argument.
    forma=$(printf '%s' "$est" | grep -oE '(^|,)shape:[a-z_]+' | head -1 | cut -d: -f2)
    case "$forma" in
      slab|carved|carved_plus) ;;
      *) echo "  pair $idx: could not read the builder from the state"; forma=slab ;;
    esac
    # THROUGH love.sh, not through $LOVE directly, and the difference is
    # empirical rather than principled. Calling the binary in a loop hung on
    # the SECOND call, every time, with the first one finishing in under a
    # second. card.sh makes three calls in a row and has never hung, and the
    # only thing it does differently is go through this wrapper, which cds to
    # the repo root and execs. So: copy what works.
    bash "$AQUI/../love.sh" mods/voxel_characters/tools/render \
      sprite="$folha" shapes="$forma" frames="$frame" yaws=0 rungs=35 \
      cell=320 label=0 out="cal_${idx}_${lado}.png" opt="$est" \
      > /dev/null 2>&1 < /dev/null
  done
  # TWO FILES, NOT ONE COMPOSITE, and this is a decision that was reversed.
  #
  # The first version composed each pair into a single side-by-side image,
  # reasoning that a critic shown two separate files judges them separately and
  # then compares its own two judgements, which is a weaker question than the
  # one Kim answered. That reasoning is probably right and it was never
  # measured, which is the point: the composite step hung inside this loop for
  # reasons that took longer to chase than the whole rest of the tool, and a
  # theoretical improvement is not worth a tool that does not run.
  #
  # If calibration numbers ever look suspiciously low, this is the first thing
  # to re-test: compose the pairs and see whether agreement moves.
  if [ -f "$SAVE_RENDER/cal_${idx}_A.png" ] && [ -f "$SAVE_RENDER/cal_${idx}_B.png" ]; then
    cp "$SAVE_RENDER/cal_${idx}_A.png" "$SAIDA/par_${idx}_A.png"
    cp "$SAVE_RENDER/cal_${idx}_B.png" "$SAIDA/par_${idx}_B.png"
    # IS THIS PAIR EVEN A QUESTION? `cmp` only catches two byte-identical
    # files, and the first calibration run proved that is nowhere near enough.
    # A critic graded on that set scored below always-answering-B, and its
    # written notes said why: one side had rendered BLANK, two pairs had the
    # character cropped out of frame, and one differed by under 5% brightness.
    # Four of seven pairs were not about taste at all. The agreement number
    # said the critic knew nothing; the set was broken.
    #
    # So the harness measures what the critic had to notice by eye.
    CONTA=$(bash "$AQUI/../love.sh" mods/voxel_characters/tools/render/compose \
      mode=conta "$SAIDA/par_${idx}_A.png" "$SAIDA/par_${idx}_B.png" 2>/dev/null)
    CA=$(printf '%s' "$CONTA" | grep -oE 'conteudo_a [0-9]+' | grep -oE '[0-9]+')
    CB=$(printf '%s' "$CONTA" | grep -oE 'conteudo_b [0-9]+' | grep -oE '[0-9]+')
    DIF=$(printf '%s' "$CONTA" | grep -oE 'diferenca [0-9]+' | grep -oE '[0-9]+')
    CA=${CA:-0}; CB=${CB:-0}; DIF=${DIF:-0}
    MENOR=$(( CA < CB ? CA : CB ))
    # A side with almost nothing on it is a failed render, not a setting.
    # A difference under a few percent of the character is below what anyone
    # can see, so asking about it collects a coin flip and calls it data.
    # These two thresholds are a first guess and are worth revisiting the day
    # the calibration numbers stop making sense.
    PISO=$(( MENOR / 20 ))
    if [ "$MENOR" -lt 2000 ]; then
      echo "  pair $idx dropped: a side rendered almost empty ($CA / $CB)"
      rm -f "$SAIDA/par_${idx}_A.png" "$SAIDA/par_${idx}_B.png"
      grep -v "^${idx} " "$SAIDA/gabarito.txt" > "$SAIDA/gab.tmp" 2>/dev/null \
        && mv "$SAIDA/gab.tmp" "$SAIDA/gabarito.txt"
    elif [ "$DIF" -lt "$PISO" ]; then
      echo "  pair $idx dropped: differ by $DIF, under the $PISO floor"
      rm -f "$SAIDA/par_${idx}_A.png" "$SAIDA/par_${idx}_B.png"
      grep -v "^${idx} " "$SAIDA/gabarito.txt" > "$SAIDA/gab.tmp" 2>/dev/null \
        && mv "$SAIDA/gab.tmp" "$SAIDA/gabarito.txt"
    elif cmp -s "$SAIDA/par_${idx}_A.png" "$SAIDA/par_${idx}_B.png"; then
      # A pair whose two sides are the same image is not a choice, so grading a
      # critic on it grades it on a question with no answer. Out of the key too.
      echo "  pair $idx dropped: the two sides render identically"
      rm -f "$SAIDA/par_${idx}_A.png" "$SAIDA/par_${idx}_B.png"
      grep -v "^${idx} " "$SAIDA/gabarito.txt" > "$SAIDA/gab.tmp" 2>/dev/null \
        && mv "$SAIDA/gab.tmp" "$SAIDA/gabarito.txt"
    else
      echo "  pair $idx ready"
    fi
  else
    echo "  pair $idx dropped: a side failed to render"
    grep -v "^${idx} " "$SAIDA/gabarito.txt" > "$SAIDA/gab.tmp" 2>/dev/null \
      && mv "$SAIDA/gab.tmp" "$SAIDA/gabarito.txt"
  fi
done

USAVEIS=$(ls "$SAIDA"/par_*_A.png 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "$USAVEIS pairs ready in $SAIDA"
echo "  images     $SAIDA/par_<n>_A.png and par_<n>_B.png"
echo "  answer key $SAIDA/gabarito.txt   <- the critic must NOT read this"
echo ""
echo "The critic writes $SAIDA/veredito.txt, one line per pair: <n> <A|B>"
echo "Then: bash $AQUI/calibra.sh conta"
