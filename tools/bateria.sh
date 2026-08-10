#!/bin/bash
# Runs the whole battery, in the order that makes a failure mean something.
#
#   bash mods/voxel_characters/tools/bateria.sh            everything
#   bash mods/voxel_characters/tools/bateria.sh --rapido   offline only, no LOVE
#   bash mods/voxel_characters/tools/bateria.sh --sem-jogo  offline + ruler
#
# WHY THE ORDER IS PART OF THE TOOL. The battery is seven commands and running
# them in the wrong order wastes an hour reading the wrong failure:
#
#   1. the offline suite first, because it is four seconds and it is the only
#      thing that tells you the maths is right;
#   2. the assertion linter, because a green suite that asserts nothing has
#      happened here twice and it looks exactly like a green suite;
#   3. chunk-local headroom, because exceeding it is a COMPILE error, so the
#      symptom is not a broken feature, it is the mod failing to load for
#      everyone;
#   4. the option docs, because an option a player cannot find in the README is
#      an option that did not ship, and release.sh builds the release body from
#      CHANGELOG.md. Four options once landed on this branch documented
#      nowhere. It runs in --rapido on purpose, so the pre-commit hook catches
#      it while the option is still being written;
#   5. the controlled runner's selftest, which needs no display and no docker.
#      It only proves the RUNNER fails when it should; it does not run anything
#      visual and it does not replace any gate below;
#   6. the durable execution state, because a long autonomous run that loses its
#      own state file is a run that starts over. Reads the required sections out
#      of the roadmap rather than from a list here;
#   7b. the audio gate's selftest. There is no audio in the mod yet, so this
#      verifies the INSTRUMENT and nothing about the product: it exists before
#      the sound does, which is the same order the ruler came in. Skipped with a
#      reason if ffmpeg is missing, rather than turning an optional dependency
#      into a red battery;
#   8. THE RULER, before any measurement is trusted. Ten defects in one session
#      were the harness posing as a defect in the mod. This is the rule that
#      keeps being forgotten, which is why it is a step and not a habit;
#   9. the in-game gates, which are slow and need the game, and are only worth
#      running once everything above is green.
#
# Only one LOVE runs at a time on a machine (tools_bin.sh holds a lock), so
# steps 4 and 5 are serial by construction, not by choice.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
MOD="$(cd "$AQUI/.." && pwd)"
RAIZ="$(cd "$MOD/../.." && pwd)"
MODO="${1:-tudo}"

LUAJIT=$(command -v luajit || echo /usr/local/bin/luajit)
FALHOU=0
PULADOS=""

passo() { printf "\n\033[1m== %s\033[0m\n" "$1"; }
veredito() {  # $1 = nome, $2 = codigo de saida
  if [ "$2" -eq 0 ]; then printf "   %-44s ok\n" "$1"
  else printf "   %-44s FALHOU\n" "$1"; FALHOU=1; fi
}

cd "$RAIZ" || exit 1

passo "1. offline: the maths"
"$LUAJIT" "$MOD/tests/voxel_chars_test.lua" 2>&1 | tail -1
veredito "suite" "${PIPESTATUS[0]}"

passo "2. checks that check nothing"
"$LUAJIT" "$MOD/tools/lint_asserts.lua" 2>&1 | tail -1
veredito "lint of assertions" "${PIPESTATUS[0]}"

passo "3. chunk-local headroom (COMPILE error if exceeded)"
bash "$MOD/tools/folga_locais.sh" 2>&1 | tail -2
veredito "folga_locais" "${PIPESTATUS[0]}"

passo "4. packaging: does the game accept the mod?"
python3 "$RAIZ/tools/modkit.py" validate "$MOD" 2>&1 | tail -1
veredito "modkit" "${PIPESTATUS[0]}"

passo "5. option docs: can a player find every option?"
"$LUAJIT" "$MOD/tools/options_documented.lua" 2>&1 | tail -10
veredito "options_documented" "${PIPESTATUS[0]}"

# The runner's own selftest, not a visual run. It proves the controlled runner
# reports a problem when there is one (no verdict, no artifact, unusable
# backend), which is the only claim it is allowed to make until a backend's
# delta against native is measured. Nothing below has been moved onto it.
passo "6. the controlled runner fails when it should"
bash "$MOD/tools/runner/runner.sh" selftest 2>&1 | tail -3
veredito "runner selftest" "${PIPESTATUS[0]}"

# The state file is what a cold session, a compaction or a handoff lands on, so
# it is gated like anything else. The required sections come from ROADMAP_V3.md
# section 9.7, not from a list inside the gate.
passo "7. the durable execution state is complete"
"$LUAJIT" "$MOD/tools/execution_state_gate.lua" 2>&1 | tail -6
veredito "execution_state" "${PIPESTATUS[0]}"

# The instrument for T2.3's SFX, verified before there is any sound to verify.
# It measures nothing about the mod today; it proves the ruler can tell silence
# from signal and refuses a file it could not read.
# The tool surface stays en-US. Scope and exemptions live in
# tools/en_us_scope.txt as data, each deferral carrying a reason, and a deferral
# that stops matching anything fails: a stale exemption covers the next
# regression silently.
passo "7a. the tool surface is en-US"
"$LUAJIT" "$MOD/tools/en_us_sweep.lua" 2>&1 | tail -5
veredito "en-US sweep" "${PIPESTATUS[0]}"

passo "7b. the audio gate can tell silence from signal"
if [ -n "${FFMPEG:-}" ] || command -v ffmpeg >/dev/null 2>&1; then
  bash "$MOD/tools/audio_gate.sh" --selftest 2>&1 | tail -3
  veredito "audio gate selftest" "${PIPESTATUS[0]}"
else
  printf "   %-44s SKIPPED (no ffmpeg)\n" "audio gate selftest"
fi

if [ "$MODO" = "--rapido" ]; then
  PULADOS="the ruler and the in-game gates"
else
  passo "8. THE RULER, before trusting any measurement"
  bash "$MOD/tools/render/check.sh" 2>&1 | tail -2
  veredito "check.sh" "${PIPESTATUS[0]}"
fi

if [ "$MODO" = "tudo" ]; then
  passo "9. in-game gates (slow, needs the game)"
  # THE VERDICT IS COUNTED FROM BOTH SIDES, and that is the whole design of
  # this step. Every driver prints one `NAME PASSOU` or `NAME FALHOU` per
  # check. Grepping for a success word alone passes a run where the game never
  # booted and printed nothing, which is the failure this project has already
  # had: a comparison declared DIFFEREM against a file that did not exist, and
  # a gate that counted files and passed a neutralised mod by one sample.
  #
  # So: zero FALHOU is not enough. There must also be at least one PASSOU, or
  # the driver produced no verdict at all and the correct answer is "no
  # measurement", not "pass".
  for d in probe_life menu probe_draw probe_fp probe_grid; do
    SAIDA=$(POKEPORT_VERSION=blue POKEPORT_DRIVER="$MOD/tools/ingame/$d.lua" \
            bash "$MOD/tools/love.sh" . 2>&1)
    NFALHOU=$(printf '%s' "$SAIDA" | grep -cE '\b(FALHOU|FAILED)\b')
    NPASSOU=$(printf '%s' "$SAIDA" | grep -cE '\b(PASSOU|PASSED)\b')
    if [ "$NPASSOU" -eq 0 ]; then
      printf "   %-44s NO VERDICT (the driver measured nothing)\n" "$d"
      printf '%s' "$SAIDA" | tail -2 | sed 's/^/       /'
      FALHOU=1
    else
      [ "$NFALHOU" -eq 0 ] && R=0 || R=1
      printf "     %d passed, %d failed\n" "$NPASSOU" "$NFALHOU"
      veredito "$d" "$R"
    fi
  done
elif [ "$MODO" = "--sem-jogo" ]; then
  PULADOS="the in-game gates"
fi

printf "\n"
[ -n "$PULADOS" ] && echo "SKIPPED on purpose: $PULADOS"
if [ $FALHOU -eq 0 ]; then
  echo "BATERIA OK"
else
  echo "BATERIA VERMELHA"
fi
exit $FALHOU
