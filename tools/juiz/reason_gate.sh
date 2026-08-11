#!/bin/bash
# A REASON ON A CHOICE CHANGES NOTHING DOWNSTREAM (roadmap T1.4).
#
#   bash mods/voxel_characters/tools/juiz/reason_gate.sh
#
# From the repo root. Needs luajit, no display and no LOVE.
#
# `reason_gate.lua` next to this file checks the encoding against a COPY of the
# patterns the judge uses. A copy can go stale, and a stale copy is a gate that
# passes while the real tool breaks. So this runs the real ones:
#
#   1. the lua gate, for the encoding contract itself;
#   2. `ajusta.lua --estados` over the recorded choices, then over the same
#      choices with a reason on every line, and the two must be byte-identical
#      because the state list is what every later stage is keyed on;
#   3. the pair selector LIFTED OUT OF calibra.sh, run the same way, so the
#      pairs and the answer key come out identical too.
#
# The third one extracts the heredoc from calibra.sh instead of restating it.
# Restating it is how the copy in the lua gate can drift; lifting it means this
# check breaks loudly if calibra.sh is restructured, which is the correct
# reaction rather than a silent pass.
#
# WHAT THIS CATCHES AND WHAT IT DOES NOT, measured rather than assumed. Breaking
# the encoder so the reason is written plainly does trip the state list here.
# Leaking one character does not, and it is worth being precise about why:
# hijacking the A/B split needs `|`, a space and `:` literal all at once, and
# even then `estadoCanonico` only harvests `key=value` tokens, so the junk is
# ignored and the canonical state comes out the same. The single-character
# leaks are caught by the structural checks in the lua gate instead. The two
# halves are not redundant; each one covers what the other cannot see.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
MOD="$(cd "$AQUI/../.." && pwd)"
RAIZ="$(cd "$MOD/../.." && pwd)"
LUAJIT=$(command -v luajit || echo /usr/local/bin/luajit)
ESCOLHAS="$AQUI/dados/escolhas.txt"

cd "$RAIZ" || exit 1
falhas=0
TMP="$(mktemp -d -t vcreason)" || exit 1
trap 'rm -rf "$TMP"' EXIT

[ -f "$ESCOLHAS" ] || { echo "REASON FAILED: no choices at $ESCOLHAS"; exit 1; }

# 1. the encoding contract
if "$LUAJIT" "$AQUI/reason_gate.lua" > "$TMP/lua.log" 2>&1; then
  printf "  %-38s %s\n" "encoding contract" "$(tail -1 "$TMP/lua.log")"
else
  sed 's/^/      /' "$TMP/lua.log"
  falhas=$((falhas + 1))
fi

# A copy of every recorded choice, each carrying the WORST reason someone could
# write, not merely an awkward one.
#
# The first version of this used a reason containing a bare pipe, and the drift
# checks below stayed green when the encoder was deliberately broken to let
# pipes through. A bare pipe is harmless: the split looks for `|` followed by
# `A:`, and a lone pipe just makes it backtrack onto the real one. What actually
# breaks the split is a reason that contains `| A:` and `| B:` itself, because
# then the earlier, fake pair wins. So that is what goes in, plus the quotes,
# spaces and equals sign for the other three parsers.
"$LUAJIT" - "$ESCOLHAS" "$TMP/com_reason.txt" "$MOD/tools/render/reason.lua" <<'LUA'
local R = dofile(arg[3])
local campo = R.field('kim said "flat" | B: FAKE | A: FAKE opcao=x folha=fake')
local saida = assert(io.open(arg[2], "w"))
local n = 0
for linha in io.lines(arg[1]) do
  if linha:match("escolha=%S+") then
    n = n + 1
    linha = linha:gsub("escolha=%S+", function(m) return m .. campo end, 1)
  end
  saida:write(linha, "\n")
end
saida:close()
if n == 0 then io.stderr:write("no choices were given a reason\n"); os.exit(1) end
LUA
[ -s "$TMP/com_reason.txt" ] || {
  echo "  the reason-carrying copy came out empty, so nothing below is a test"
  echo "REASON FAILED: 1 problem(s)"; exit 1; }

# 2. the real state list, both ways
"$LUAJIT" "$AQUI/ajusta.lua" --estados "$ESCOLHAS" > "$TMP/estados_sem.txt" 2>"$TMP/e1" \
  || { echo "  ajusta.lua --estados failed on the recorded choices"; sed 's/^/      /' "$TMP/e1"; falhas=$((falhas + 1)); }
"$LUAJIT" "$AQUI/ajusta.lua" --estados "$TMP/com_reason.txt" > "$TMP/estados_com.txt" 2>"$TMP/e2" \
  || { echo "  ajusta.lua --estados failed once a reason was present"; sed 's/^/      /' "$TMP/e2"; falhas=$((falhas + 1)); }
linhas=$(wc -l < "$TMP/estados_sem.txt" | tr -d ' ')
if [ "${linhas:-0}" -lt 100 ]; then
  echo "  the state list is only $linhas lines, so comparing it proves nothing"
  falhas=$((falhas + 1))
elif cmp -s "$TMP/estados_sem.txt" "$TMP/estados_com.txt"; then
  printf "  %-38s %s states, identical\n" "ajusta.lua --estados" "$linhas"
else
  echo "  THE STATE LIST DRIFTED once a reason was added:"
  diff "$TMP/estados_sem.txt" "$TMP/estados_com.txt" | head -6 | sed 's/^/      /'
  falhas=$((falhas + 1))
fi

# 3. the real pair selector, lifted out of calibra.sh rather than restated
awk '/^luajit - "\$ESCOLHAS"/ { dentro = 1; next } dentro && /^LUA$/ { exit } dentro' \
  "$AQUI/calibra.sh" > "$TMP/seletor.lua"
if [ ! -s "$TMP/seletor.lua" ] || ! grep -q 'escolha=' "$TMP/seletor.lua"; then
  echo "  the pair selector could not be lifted out of calibra.sh; it has been"
  echo "    restructured, and this check is no longer reading the real code"
  falhas=$((falhas + 1))
else
  ok=1
  for etiqueta in sem com; do
    entrada="$ESCOLHAS"; [ "$etiqueta" = "com" ] && entrada="$TMP/com_reason.txt"
    "$LUAJIT" "$TMP/seletor.lua" "$entrada" 30 \
      "$TMP/pares_$etiqueta.tsv" "$TMP/gab_$etiqueta.txt" 2>/dev/null || ok=0
  done
  if [ "$ok" -ne 1 ] || [ ! -s "$TMP/pares_sem.tsv" ]; then
    echo "  the lifted pair selector did not run, so the pairs were not compared"
    falhas=$((falhas + 1))
  else
    for saida in pares gab; do
      ext=tsv; [ "$saida" = gab ] && ext=txt
      if cmp -s "$TMP/${saida}_sem.$ext" "$TMP/${saida}_com.$ext"; then
        printf "  %-38s %s lines, identical\n" "calibra.sh $saida" \
          "$(wc -l < "$TMP/${saida}_sem.$ext" | tr -d ' ')"
      else
        echo "  THE $saida DRIFTED once a reason was added:"
        diff "$TMP/${saida}_sem.$ext" "$TMP/${saida}_com.$ext" | head -6 | sed 's/^/      /'
        falhas=$((falhas + 1))
      fi
    done
  fi
fi

if [ "$falhas" -eq 0 ]; then
  echo "REASON OK: the recorded choices read the same with and without a reason"
  exit 0
fi
echo "REASON FAILED: $falhas problem(s)"
exit 1
