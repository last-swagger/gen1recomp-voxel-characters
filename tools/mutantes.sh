#!/bin/bash
# Runs the declared mutants and reports which ones the suite failed to kill.
#
#   bash mods/voxel_characters/tools/mutantes.sh          all of tools/mutantes.txt
#   bash mods/voxel_characters/tools/mutantes.sh 3        only mutant number 3
#
# WHY THIS IS A COMMAND AND NOT A HABIT. Mutation testing found something both
# times it was run by hand in this project, and both times it was nearly not
# run, because the suite had just gone green and green feels like verification.
# A habit that only fires when someone remembers is not a habit.
#
# A surviving mutant is the finding: the suite executes that line and asserts
# nothing about it.
#
# SAFETY, and it is the reason for every absolute path below. A previous
# hand-run of this idea destroyed its own backup: the first command did `cd`,
# the second command's backup then captured the ALREADY MUTATED file, and the
# restore wrote the mutation back in permanently. Nothing here is relative, and
# the restore runs from a trap so it also happens when the suite crashes or the
# run is interrupted.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
MOD="$(cd "$AQUI/.." && pwd)"
RAIZ="$(cd "$MOD/../.." && pwd)"
LISTA="$AQUI/mutantes.txt"
SO="${1:-}"

LUAJIT=$(command -v luajit || echo /usr/local/bin/luajit)
[ -x "$LUAJIT" ] || { echo "luajit nao encontrado"; exit 2; }
[ -f "$LISTA" ] || { echo "sem lista de mutantes: $LISTA"; exit 2; }

# THE SUITE ONLY RUNS FROM THE REPO ROOT. Its second line is
# `require("tests.love_stub")`, resolved against the CURRENT DIRECTORY, so from
# anywhere else it dies with "module not found" and never counts a check.
#
# That matters more here than anywhere else in the repository: this script
# decides whether a mutant lived or died by reading the suite's output, and a
# suite that cannot start produces no count at all. Run from the wrong
# directory, every single mutant would be reported as killed, which is the
# report saying "your tests are perfect" precisely when it measured nothing.
#
# The baseline check below would catch it, but only by accident, and the error
# it prints would blame the suite. So: cd first, explicitly.
cd "$RAIZ" || { echo "nao consegui entrar em $RAIZ"; exit 2; }

# The working tree has to be clean for the RESULT to mean anything: a mutant
# that "survives" because an unrelated edit was already breaking the suite is a
# false report, and the report is the whole product here.
SUJO=$(git -C "$MOD" status --porcelain -- '*.lua' | head -5)
if [ -n "$SUJO" ]; then
  echo "ARVORE SUJA. Mutacao precisa de base limpa, senao o resultado mistura"
  echo "a mutacao com o que ja estava modificado:"
  echo "$SUJO" | sed 's/^/  /'
  exit 2
fi

BACKUP=$(mktemp -d)
RESTAURA=""
limpa() {
  if [ -n "$RESTAURA" ] && [ -f "$BACKUP/orig" ]; then
    cp "$BACKUP/orig" "$RESTAURA"
  fi
  rm -rf "$BACKUP"
}
trap limpa EXIT INT TERM

# The baseline. Everything is measured against this number, from this run, on
# this machine: a count copied from a document goes stale and then every mutant
# looks dead.
BASE=$("$LUAJIT" "$MOD/tests/voxel_chars_test.lua" 2>&1 | grep -oE '[0-9]+/[0-9]+ checks passed' | head -1)
BASE_OK=$(echo "$BASE" | cut -d/ -f1)
BASE_DE=$(echo "$BASE" | cut -d/ -f2 | grep -oE '^[0-9]+')
if [ -z "${BASE_OK:-}" ] || [ "$BASE_OK" != "$BASE_DE" ]; then
  echo "A SUITE JA ESTA VERMELHA sem mutante nenhum: $BASE"
  echo "  Conserte antes. Mutacao contra base vermelha nao mede nada."
  exit 2
fi
echo "base limpa: $BASE_OK checagens"
echo

N=0
SOBREVIVERAM=0
RODARAM=0
while IFS= read -r linha || [ -n "$linha" ]; do
  case "$linha" in ''|'#'*) continue ;; esac
  N=$((N + 1))
  [ -n "$SO" ] && [ "$SO" != "$N" ] && continue

  ARQ=$(printf '%s' "$linha" | awk -F' \\| ' '{print $1}')
  DE=$(printf '%s' "$linha" | awk -F' \\| ' '{print $2}')
  PARA=$(printf '%s' "$linha" | awk -F' \\| ' '{print $3}')
  DESC=$(printf '%s' "$linha" | awk -F' \\| ' '{print $4}')
  ALVO="$MOD/$ARQ"

  if [ ! -f "$ALVO" ]; then
    printf "%2d  %-22s SEM ARQUIVO\n" "$N" "$ARQ"
    SOBREVIVERAM=$((SOBREVIVERAM + 1))
    continue
  fi

  # The pattern must match exactly one line. Zero means the code moved and the
  # mutant is now testing nothing; more than one means it fires somewhere it
  # was not aimed. Both are silent failures if not checked here.
  QUANTAS=$(grep -Fc -- "$DE" "$ALVO" 2>/dev/null || echo 0)
  if [ "$QUANTAS" != "1" ]; then
    printf "%2d  %-22s PADRAO CASA %s VEZES (esperado 1)\n" "$N" "$ARQ" "$QUANTAS"
    echo "      $DE"
    SOBREVIVERAM=$((SOBREVIVERAM + 1))
    continue
  fi

  cp "$ALVO" "$BACKUP/orig"
  RESTAURA="$ALVO"
  RODARAM=$((RODARAM + 1))

  # Replace with awk on fixed strings: sed would need the pattern escaped, and
  # these patterns are Lua source full of `*`, `[`, `.` and `/`.
  awk -v de="$DE" -v para="$PARA" '
    {
      i = index($0, de)
      if (i > 0) { $0 = substr($0, 1, i-1) para substr($0, i + length(de)) }
      print
    }' "$BACKUP/orig" > "$ALVO.mut" && mv "$ALVO.mut" "$ALVO"

  SAIDA=$("$LUAJIT" "$MOD/tests/voxel_chars_test.lua" 2>&1)
  RES=$(echo "$SAIDA" | grep -oE '[0-9]+/[0-9]+ checks passed' | head -1)
  OK=$(echo "$RES" | cut -d/ -f1)

  cp "$BACKUP/orig" "$ALVO"
  RESTAURA=""

  if [ -z "${RES:-}" ]; then
    # No count at all means the suite crashed, which counts as killed: the
    # mutant made the code not run. Say so, because "crashed" and "failed a
    # check" are different qualities of evidence.
    printf "%2d  %-22s morto (a suite nem rodou)\n" "$N" "$ARQ"
  elif [ "$OK" = "$BASE_OK" ]; then
    printf "%2d  %-22s SOBREVIVEU  %s\n" "$N" "$ARQ" "$RES"
    echo "      $DESC"
    SOBREVIVERAM=$((SOBREVIVERAM + 1))
  else
    printf "%2d  %-22s morto  %s\n" "$N" "$ARQ" "$RES"
  fi
done < "$LISTA"

echo
if [ "$RODARAM" -eq 0 ]; then
  echo "NENHUM MUTANTE RODOU"
  exit 2
fi
if [ "$SOBREVIVERAM" -eq 0 ]; then
  echo "MUTANTES OK: a suite matou os $RODARAM"
  exit 0
fi
echo "$SOBREVIVERAM de $RODARAM SOBREVIVERAM: a suite passa por cima dessas linhas"
exit 1
