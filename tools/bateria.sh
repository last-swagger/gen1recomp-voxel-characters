#!/bin/bash
# Runs the whole battery, in the order that makes a failure mean something.
#
#   bash mods/voxel_characters/tools/bateria.sh                 foco (padrão)
#   bash mods/voxel_characters/tools/bateria.sh --rapido        todos os gates offline
#   bash mods/voxel_characters/tools/bateria.sh --sem-jogo      offline + renderização
#   bash mods/voxel_characters/tools/bateria.sh --tudo          inclui os probes no jogo
#
# Perfis para rodar só o que a mudança precisa:
# --foco: suite lógica, lint de assertions, limite de locais, validação estrita,
#         hosts declarados e conteúdo distribuído.
# --rapido: todos os gates offline; não abre o jogo nem executa a régua.
# --sem-jogo: gates offline e régua de renderização.
# --tudo: gates offline, régua e probes dentro do jogo.
# Use --foco no dia a dia; escolha explicitamente os perfis mais caros.
set -u
if [ "$#" -gt 1 ]; then
  echo "Uso: bateria.sh [--foco|--rapido|--sem-jogo|--tudo]" >&2
  exit 2
fi
AQUI="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$(dirname "$0")")"
MOD="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$AQUI/..")"
RAIZ="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${VC_ENGINE_ROOT:-$MOD/../..}")"
TEST_ROOT="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${VC_TEST_REPO_ROOT:-$RAIZ}")"
MODO="${1:---foco}"

case "$MODO" in
  --foco|--rapido|--sem-jogo|--tudo) ;;
  *)
    echo "Uso: bateria.sh [--foco|--rapido|--sem-jogo|--tudo]" >&2
    exit 2
    ;;
esac

LUAJIT=$(command -v luajit || echo /usr/local/bin/luajit)
VERMELHA=0
PULADOS=""

passo() { printf "\n\033[1m== %s\033[0m\n" "$1"; }
verdict() {  # $1 = nome, $2 = codigo de saida
  if [ "$2" -eq 0 ]; then printf "   %-44s ok\n" "$1"
  else printf "   %-44s FAILED\n" "$1"; VERMELHA=1; fi
}

cd "$TEST_ROOT" || exit 1

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
if [ "$MODO" = "--foco" ]; then
  python3 "$RAIZ/tools/modkit.py" validate "$MOD" --strict 2>&1 | tail -3
else
  python3 "$RAIZ/tools/modkit.py" validate "$MOD" 2>&1 | tail -1
fi
verdict "modkit" "${PIPESTATUS[0]}"

passo "4b. supported hosts are ordered before the mod"
python3 "$MOD/tools/host_manifest_gate.py" 2>&1 | tail -4
verdict "host_manifest" "${PIPESTATUS[0]}"

passo "5. option docs: can a player find every option?"
"$LUAJIT" "$MOD/tools/options_documented.lua" 2>&1 | tail -10
verdict "options_documented" "${PIPESTATUS[0]}"

if [ "$MODO" = "--foco" ]; then
  passo "6. lint do conteúdo distribuído"
  python3 "$RAIZ/tools/modkit.py" lint "$MOD" 2>&1 | tail -3
  verdict "modkit lint" "${PIPESTATUS[0]}"
  echo
  if [ "$VERMELHA" -eq 0 ]; then
    echo "FOCUSED BATTERY OK"
  else
    echo "FOCUSED BATTERY RED"
  fi
  exit "$VERMELHA"
fi

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

passo "7l. the HD sheet paints the same picture as the ROM sheet"
"$LUAJIT" "$MOD/tools/hd_equivalence.lua" 2>&1 | tail -8
verdict "hd equivalence" "${PIPESTATUS[0]}"

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

if [ "$MODO" = "--tudo" ]; then
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
  # THE TWO GEN 2 GATES ARE DELIBERATELY NOT IN THIS LOOP -- hosts.sh, which
  # proves the mod attaches on Gold, and ingame/gold.sh, which proves the
  # harness can drive it. Kim's call, 2026-08-18, and the reason is cost: this
  # step is already the slow one, and Gen 2 cannot be overlapped with Gen 1 to
  # hide it. Only one LOVE runs at a time on a machine (tools_bin.sh holds the
  # lock, see the header), so every Gold boot is wall-clock added on top of the
  # seven below, not beside them.
  #
  # Run them by hand while working on Gen 2:
  #
  #   bash tools/ingame/hosts.sh        # attaches, on every host and both games
  #   bash tools/ingame/gold.sh         # lands and walks, with the mod attached
  #
  # THE RELEASE RUNS THEM, so out of here is not out of everything. They are
  # release.sh step 2c, which is where the cost is affordable: once per release
  # instead of on every run of this. Leaving them out of BOTH is what the gap
  # used to be, and it mattered because 1.8.1's notes promise publicly that
  # every release is booted against each voxel host before it ships -- a
  # promise whose only gate, until 2026-08-18, was somebody remembering.
  #
  # So if a Gen 2 gate ever moves or gets renamed, release.sh has to learn it
  # too. Two places, on purpose: the daily loop stays cheap and the promise
  # still has something standing behind it.
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
