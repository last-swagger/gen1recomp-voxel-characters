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
#   7b. the audio gate's selftest, the instrument before what it judges. There is no audio in the mod yet, so this
#      verifies the INSTRUMENT and nothing about the product: it exists before
#      the sound does, which is the same order the ruler came in. Skipped with a
#      reason if ffmpeg is missing, rather than turning an optional dependency
#      into a red battery;
#   7c. the FX demo's two sounds, regenerated and measured through that gate. A
#      committed WAV can only be checked once, by whoever listened to it; a
#      generator can be re-derived and re-measured on every run;
#   7d. the reason field on a choice, checked against the RECORDED choices and
#      through the real judge tools. 106 choices were collected before the field
#      existed and they have to keep parsing exactly as they do today; a format
#      that needs its old records migrated is a format that loses them;
#   7e. the battery's own verdict lines, which are an interface and not prose:
#      the pre-commit hook summarises them and release.sh prints them into a
#      release rehearsal. Both patterns are lifted from those files and run
#      against what `verdict` really prints. It found release.sh printing 5 of
#      11 gates on its first run;
#   7f. the strings the display-backed gates grep for. Renaming one side of
#      those pairs does not turn a gate red, it turns it GREEN AND EMPTY, and
#      the only end-to-end proof is a full battery on a machine with a screen.
#      This is the cheap static half that runs on every commit;
#   7g. the authored layer, whose risk is identity rather than engineering. A
#      mod that quietly starts drawing its own pixels while its README says it
#      derives everything from your ROM has broken something a gate cannot
#      repair, so the first slice ships none and this holds it to that;
#   7h. the authored regions, re-measured off the real sprite. Bounds written
#      by hand go stale silently: the sprite is the source of truth and a
#      number in a data file is only a copy of it. Decodes the PNG itself, so
#      it needs no display;
#   7i. the character preset format. Every preset in the space round-trips, and
#      no colour outside the art's measured three-tone ramp is expressible: the
#      creator cannot manufacture a tone the game has never shown;
#   7j. the lab randomiser, which proposes preset candidates for the judge.
#      Reproducible from a seed, never from the clock, because a set that
#      cannot be regenerated cannot be re-examined after it fails;
#   7k. the alpha channel, which must be fully in or fully out. A voxel builder
#      extrudes from the opaque region, so a half-transparent pixel becomes a
#      face that is drawn and see-through, or one kept on one side and skipped
#      on the other, and the artifact shows up in geometry far from its cause.
#      Already true today, and true by accident rather than by contract;
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
VERMELHA=0
PULADOS=""

passo() { printf "\n\033[1m== %s\033[0m\n" "$1"; }
verdict() {  # $1 = nome, $2 = codigo de saida
  if [ "$2" -eq 0 ]; then printf "   %-44s ok\n" "$1"
  else printf "   %-44s FAILED\n" "$1"; VERMELHA=1; fi
}

cd "$RAIZ" || exit 1

passo "1. offline: the maths"
"$LUAJIT" "$MOD/tests/voxel_chars_test.lua" 2>&1 | tail -1
verdict "suite" "${PIPESTATUS[0]}"

passo "2. checks that check nothing"
"$LUAJIT" "$MOD/tools/lint_asserts.lua" 2>&1 | tail -1
verdict "lint of assertions" "${PIPESTATUS[0]}"

passo "3. chunk-local headroom (COMPILE error if exceeded)"
bash "$MOD/tools/folga_locais.sh" 2>&1 | tail -2
verdict "folga_locais" "${PIPESTATUS[0]}"

passo "4. packaging: does the game accept the mod?"
python3 "$RAIZ/tools/modkit.py" validate "$MOD" 2>&1 | tail -1
verdict "modkit" "${PIPESTATUS[0]}"

passo "5. option docs: can a player find every option?"
"$LUAJIT" "$MOD/tools/options_documented.lua" 2>&1 | tail -10
verdict "options_documented" "${PIPESTATUS[0]}"

# The runner's own selftest, not a visual run. It proves the controlled runner
# reports a problem when there is one (no verdict, no artifact, unusable
# backend), which is the only claim it is allowed to make until a backend's
# delta against native is measured. Nothing below has been moved onto it.
passo "6. the controlled runner fails when it should"
bash "$MOD/tools/runner/runner.sh" selftest 2>&1 | tail -3
verdict "runner selftest" "${PIPESTATUS[0]}"

# The state file is what a cold session, a compaction or a handoff lands on, so
# it is gated like anything else. The required sections come from ROADMAP_V3.md
# section 9.7, not from a list inside the gate.
passo "7. the durable execution state is complete"
"$LUAJIT" "$MOD/tools/execution_state_gate.lua" 2>&1 | tail -6
verdict "execution_state" "${PIPESTATUS[0]}"

# The tool surface stays en-US. Scope and exemptions live in
# tools/en_us_scope.txt as data, each deferral carrying a reason, and a deferral
# that stops matching anything fails: a stale exemption covers the next
# regression silently.
passo "7a. the tool surface is en-US"
"$LUAJIT" "$MOD/tools/en_us_sweep.lua" 2>&1 | tail -5
verdict "en-US sweep" "${PIPESTATUS[0]}"

# The instrument, verified before it is trusted to judge anything: it proves the
# ruler can tell silence from signal and refuses a file it could not read.
passo "7b. the audio gate can tell silence from signal"
if [ -n "${FFMPEG:-}" ] || command -v ffmpeg >/dev/null 2>&1; then
  bash "$MOD/tools/audio_gate.sh" --selftest 2>&1 | tail -3
  verdict "audio gate selftest" "${PIPESTATUS[0]}"
else
  printf "   %-44s SKIPPED (no ffmpeg)\n" "audio gate selftest"
fi

passo "7c. the FX demo's sounds are real, regenerated and measured"
if [ -n "${FFMPEG:-}" ] || command -v ffmpeg >/dev/null 2>&1; then
  bash "$MOD/tools/fx_sfx_gate.sh" 2>&1 | tail -6
  verdict "fx sfx" "${PIPESTATUS[0]}"
else
  printf "   %-44s SKIPPED (no ffmpeg)\n" "fx sfx"
fi

passo "7f. every string a gate greps for is still printed"
"$LUAJIT" "$MOD/tools/output_contract.lua" 2>&1 | tail -6
verdict "output contract" "${PIPESTATUS[0]}"

passo "7g. the authored layer ships nothing and cannot lie about it"
"$LUAJIT" "$MOD/tools/authored_gate.lua" 2>&1 | tail -6
verdict "authored layer" "${PIPESTATUS[0]}"

passo "7h. authored regions still match the real sprite"
python3 "$MOD/tools/measure_regions.py" --check red 2>&1 | tail -5
verdict "authored regions" "${PIPESTATUS[0]}"

passo "7i. a character preset round-trips and stays inside the art's ramp"
"$LUAJIT" "$MOD/tools/preset_gate.lua" 2>&1 | tail -4
verdict "preset format" "${PIPESTATUS[0]}"

passo "7j. the randomiser proposes real, reproducible candidates"
"$LUAJIT" "$MOD/tools/randomiza_gate.lua" 2>&1 | tail -4
verdict "randomiser" "${PIPESTATUS[0]}"

passo "7k. every sprite's alpha is 0 or 255, with nothing in between"
python3 "$MOD/tools/alpha_gate.py" 2>&1 | tail -4
verdict "alpha gate" "${PIPESTATUS[0]}"

passo "7e. the battery's verdicts still reach their readers"
bash "$MOD/tools/verdict_gate.sh" 2>&1 | tail -9
verdict "verdict contract" "${PIPESTATUS[0]}"

passo "7d. a reason on a choice changes nothing the judge reads"
bash "$MOD/tools/juiz/reason_gate.sh" 2>&1 | tail -6
verdict "reason field" "${PIPESTATUS[0]}"

if [ "$MODO" = "--rapido" ]; then
  PULADOS="the ruler and the in-game gates"
else
  passo "8. THE RULER, before trusting any measurement"
  bash "$MOD/tools/render/check.sh" 2>&1 | tail -2
  verdict "check.sh" "${PIPESTATUS[0]}"

  # A FULL TURN, which the four camera rungs never covered. Separate from the
  # ruler because it drives twenty four renders of its own and a reader should
  # be able to see which of the two went red.
  passo "8b. a full 360 turn, looking for Z-fighting"
  bash "$MOD/tools/render/zfight_gate.sh" 2>&1 | tail -4
  verdict "zfight" "${PIPESTATUS[0]}"
fi

if [ "$MODO" = "tudo" ]; then
  passo "9. in-game gates (slow, needs the game)"
  # THE VERDICT IS COUNTED FROM BOTH SIDES, and that is the whole design of
  # this step. Every driver prints one `NAME PASSED` or `NAME FAILED` per
  # check. Grepping for a success word alone passes a run where the game never
  # booted and printed nothing, which is the failure this project has already
  # had: a comparison declared DIFFEREM against a file that did not exist, and
  # a gate that counted files and passed a neutralised mod by one sample.
  #
  # So: zero FAILED is not enough. There must also be at least one PASSED, or
  # the driver produced no verdict at all and the correct answer is "no
  # measurement", not "pass".
  for d in probe_life menu probe_hd probe_walk probe_draw probe_fp probe_grid; do
    SAIDA=$(POKEPORT_VERSION=blue POKEPORT_DRIVER="$MOD/tools/ingame/$d.lua" \
            bash "$MOD/tools/love.sh" . 2>&1)
    NFAILED=$(printf '%s' "$SAIDA" | grep -cE '\bFAILED\b')
    NPASSED=$(printf '%s' "$SAIDA" | grep -cE '\bPASSED\b')
    if [ "$NPASSED" -eq 0 ]; then
      printf "   %-44s NO VERDICT (the driver measured nothing)\n" "$d"
      printf '%s' "$SAIDA" | tail -2 | sed 's/^/       /'
      VERMELHA=1
    else
      [ "$NFAILED" -eq 0 ] && R=0 || R=1
      printf "     %d passed, %d failed\n" "$NPASSED" "$NFAILED"
      verdict "$d" "$R"
    fi
  done
elif [ "$MODO" = "--sem-jogo" ]; then
  PULADOS="the in-game gates"
fi

printf "\n"
[ -n "$PULADOS" ] && echo "SKIPPED on purpose: $PULADOS"
if [ $VERMELHA -eq 0 ]; then
  echo "BATTERY OK"
else
  echo "BATTERY RED"
fi
exit $VERMELHA
