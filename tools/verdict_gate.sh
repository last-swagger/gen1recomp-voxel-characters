#!/bin/bash
# THE BATTERY'S VERDICTS STILL REACH THEIR READERS (roadmap T1.5).
#
#   bash mods/voxel_characters/tools/verdict_gate.sh
#
# From the repo root. No luajit, no display, no LOVE. Runs in milliseconds.
#
# WHY THIS EXISTS. The battery's verdict lines are not prose, they are an
# interface. Two things read them and neither is obvious from the battery's own
# source: the pre-commit hook summarises them, and `release.sh` prints them into
# a release rehearsal. Translating `FALHOU` to `FAILED` and `BATERIA OK` to
# `BATTERY OK` is a one-line edit that can silently unhook both.
#
# It is not hypothetical. The hook used to grep a hardcoded list of step names,
# four gates were added, and it went on printing four of eight with no sign
# anything was missing. That is the exact shape of failure this guards: not a
# red gate, a quiet one.
#
# WHAT IT CHECKS
#
#   1. the banner: VERMELHA=0 says BATTERY OK and exits 0, VERMELHA=1 says
#      BATTERY RED and exits 1. The red half matters more, because a green run
#      never executes it and nobody would notice it broken;
#   2. a passing verdict line matches the pre-commit hook's summary pattern and
#      release.sh's, both LIFTED OUT of those files rather than restated here;
#   3. a FAILING verdict line matches NEITHER, or the summary would report a
#      failure as a success, which is worse than printing nothing;
#   4. the in-game verdict greps accept English as well as Portuguese, which is
#      what lets the drivers be converted without a flag day;
#   5. no Portuguese banner text survives anywhere under tools/.
#
# Everything real is lifted from the file that owns it. A copy of a regex in a
# gate is a copy that goes stale, and a stale copy passes while the real one
# breaks.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
MOD="$(cd "$AQUI/.." && pwd)"
RAIZ="$(cd "$MOD/../.." && pwd)"
cd "$RAIZ" || exit 1

BATERIA="$MOD/tools/bateria.sh"
HOOK="$MOD/tools/hooks/pre-commit"
RELEASE="$MOD/tools/release.sh"
falhas=0
diga() { printf '%s\n' "  $*"; }
TMP="$(mktemp -d -t vcverdict)" || exit 1
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------- 1. banner
#
# The banner tail is lifted rather than restated, so restructuring bateria.sh
# breaks this loudly instead of leaving the gate agreeing with itself.
awk '/^if \[ \$VERMELHA -eq 0 \]; then/ { dentro = 1 } dentro' "$BATERIA" > "$TMP/banner.sh"
if [ ! -s "$TMP/banner.sh" ] || ! grep -q 'exit \$VERMELHA' "$TMP/banner.sh"; then
  diga "the banner could not be lifted out of bateria.sh; it has been"
  diga "  restructured, and this gate is no longer reading the real code"
  falhas=$((falhas + 1))
else
  for estado in 0 1; do
    SAIDA=$(VERMELHA=$estado bash "$TMP/banner.sh" 2>&1); RC=$?
    if [ "$estado" = "0" ]; then esperado="BATTERY OK"; rc_esperado=0
    else esperado="BATTERY RED"; rc_esperado=1; fi
    if [ "$SAIDA" = "$esperado" ] && [ "$RC" = "$rc_esperado" ]; then
      printf "  %-40s %s, exit %d\n" "banner with VERMELHA=$estado" "$SAIDA" "$RC"
    else
      diga "banner with VERMELHA=$estado said [$SAIDA] exit $RC," \
           "expected [$esperado] exit $rc_esperado"
      falhas=$((falhas + 1))
    fi
  done
fi

# ------------------------------------------------- 2 and 3. the two readers
#
# `verdict` is lifted too, and then run for real, so what the readers are
# tested against is the actual bytes the battery prints rather than a
# hand-typed imitation of them.
awk '/^verdict\(\) \{/ { dentro = 1 } dentro { print } dentro && /^\}/ { exit }' \
  "$BATERIA" > "$TMP/verdict.sh"
if ! grep -q 'printf' "$TMP/verdict.sh"; then
  diga "verdict() could not be lifted out of bateria.sh"
  falhas=$((falhas + 1))
else
  { echo 'VERMELHA=0'; cat "$TMP/verdict.sh"
    echo 'verdict "some gate" 0'; echo 'verdict "another gate" 1'
  } > "$TMP/linhas.sh"
  bash "$TMP/linhas.sh" > "$TMP/linhas.txt" 2>&1
  grep ' ok$' "$TMP/linhas.txt" > "$TMP/passa.txt"
  grep -v ' ok$' "$TMP/linhas.txt" > "$TMP/falha.txt"

  # The hook's own pattern, and release.sh's, taken from the files themselves.
  PAD_HOOK=$(grep -oE "grep -E '[^']+'" "$HOOK" | head -1 | sed "s/^grep -E '//; s/'$//")
  PAD_REL=$(grep "bateria.log" "$RELEASE" | grep -oE "grep -E '[^']+'" | head -1 \
            | sed "s/^grep -E '//; s/'$//")
  for par in "pre-commit hook:$PAD_HOOK" "release.sh:$PAD_REL"; do
    quem="${par%%:*}"; pad="${par#*:}"
    if [ -z "$pad" ]; then
      diga "$quem no longer contains a summary pattern this gate can find;"
      diga "  it may have been restructured, and the contract is unchecked"
      falhas=$((falhas + 1))
      continue
    fi
    n_ok=$(grep -cE "$pad" "$TMP/passa.txt")
    n_mau=$(grep -cE "$pad" "$TMP/falha.txt")
    if [ "$n_ok" -lt 1 ]; then
      diga "$quem would summarise NOTHING: its pattern does not match a passing"
      diga "  verdict line. Pattern: $pad"
      diga "  Line:    [$(head -1 "$TMP/passa.txt")]"
      falhas=$((falhas + 1))
    elif [ "$n_mau" -gt 0 ]; then
      diga "$quem would report a FAILING verdict as a pass. Pattern: $pad"
      falhas=$((falhas + 1))
    else
      printf "  %-40s matches pass, rejects fail\n" "$quem"
    fi
  done
fi

# ------------------------------------------- 4. the in-game greps are bilingual
#
# This is what lets the drivers under tools/ingame be converted one at a time
# instead of in a flag day. If a counter ever stops accepting one language, a
# converted driver silently counts as zero verdicts.
for arquivo in "$BATERIA" "$MOD/tools/runner/runner.sh" "$MOD/tools/ingame/monta.sh"; do
  nome="${arquivo#$MOD/}"
  linhas=$(grep -nE "(PASSOU|FALHOU)" "$arquivo" | grep -E "grep" || true)
  if [ -z "$linhas" ]; then
    printf "  %-40s no verdict grep\n" "$nome"
    continue
  fi
  mau=0
  while IFS= read -r l; do
    case "$l" in
      *PASSOU*PASSED*|*PASSED*PASSOU*|*FALHOU*FAILED*|*FAILED*FALHOU*) ;;
      *) diga "$nome greps a Portuguese verdict with no English alternative:"
         diga "  $(printf '%s' "$l" | sed 's/^[0-9]*: *//')"
         mau=1 ;;
    esac
  done <<EOF
$linhas
EOF
  [ "$mau" -eq 1 ] && falhas=$((falhas + 1))
  [ "$mau" -eq 0 ] && printf "  %-40s verdict greps accept both\n" "$nome"
done

# --------------------------------------------- 5. no Portuguese banner is left
#
# The en-US sweep cannot catch this one: it matches Portuguese WORDS, and
# `BATERIA` is not in its list precisely because it looks like an acronym.
#
# This file is excluded from its own search: it has to name the old string in
# order to explain what it is looking for. Excluded BY EXACT PATH rather than by
# a pattern, so it cannot quietly grow into an exemption for anything else.
RESTOS=$(grep -rl "BATERIA" "$MOD/tools" 2>/dev/null | grep -v "^$MOD/tools/verdict_gate\.sh$" || true)
if [ -n "$RESTOS" ]; then
  diga "the Portuguese banner still appears in:"
  printf '%s\n' "$RESTOS" | sed "s|^$MOD/|      |"
  falhas=$((falhas + 1))
else
  printf "  %-40s gone from tools/\n" "the old BATERIA banner"
fi

if [ "$falhas" -eq 0 ]; then
  echo "VERDICT CONTRACT OK: both readers still read what the battery prints"
  exit 0
fi
echo "VERDICT CONTRACT FAILED: $falhas problem(s)"
exit 1
