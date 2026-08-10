#!/bin/bash
# THE CONTROLLED VISUAL RUNNER (roadmap T0.2), slice 1.
#
#   tools/runner/runner.sh probe [backend]
#   tools/runner/runner.sh selftest
#   tools/runner/runner.sh run <backend> [options] -- "<one shell command string>"
#
# Everything after `--` is ONE argument, handed to `sh -c` as written. Several
# arguments are refused, not joined: see WHY ONE STRING in cmd_run.
#
# WHY THIS EXISTS. The visual tools are useful partly BECAUSE they are visible:
# they film the real game, drive real menus, and make a bad state obvious. The
# side effect is that a wall of LOVE windows takes the computer away from the
# person using it, and that is not only annoying, it corrupts measurements: an
# occluded window with vsync on stalls the whole love.run loop (5 frames in 90
# seconds, see docs/TRAPS.md), and "rerun it, I was using the machine" is a
# result nobody can compare against anything.
#
# WHAT THIS IS NOT, and it is the whole reason the file is shaped this way: it
# is NOT a claim that a different renderer measures the same thing. Software GL
# in a container is a different rasteriser, a different LOVE build and a
# different driver, so every pixel threshold measured natively is measuring a
# different scene there. This project's own rule is that a threshold is only
# evidence when a floor was captured by the SAME procedure. So a backend here
# carries a DELTA state, the delta starts UNMEASURED, and nothing in this file
# will quietly upgrade it.
#
# THREE RULES THIS FILE ENFORCES, each one paid for somewhere in this repo:
#
#   1. NO EMPTY GREEN. A wrapped command that exits 0 having printed no verdict
#      did not pass, it did not measure. `tools_bin.sh` records the original
#      defect: with $LOVE unset, `$($LOVE ... | grep ...)` returned an empty
#      string and a check comparing two outputs passed by comparing empty with
#      empty. bateria.sh already counts verdicts from both sides for the same
#      reason. So does this.
#
#   2. NO SILENT FALLBACK. If you ask for the docker backend and docker cannot
#      run it, this refuses. It does not run natively and let you believe the
#      run was contained, because the whole point of asking for a backend is
#      that you care which one produced the number.
#
#   3. NO SHARED LOVE. LOVE is exclusive per machine, so a LOVE-backed backend
#      takes the same lock every other tool takes (reentrant across a process
#      tree via VC_TRAVA_DONO), instead of killing whatever is measuring.
#
# Run from the REPO ROOT or from anywhere: this resolves its own paths. The
# WRAPPED command still has to obey its own rules, and almost all of them are
# repo-root only.
set -u

# This file sits at <mod>/tools/runner/, so the mod root is two levels up and
# the repo root is two above that. Written out because the first version had
# MOD pointing at tools/ and every path built on it silently missed: the probe
# reported "LOVE binary not found" on a machine with LOVE installed, because
# it was sourcing tools/tools/tools_bin.sh. Same family as the defect love.sh
# exists to prevent.
AQUI="$(cd "$(dirname "$0")" && pwd)"
MOD="$(cd "$AQUI/../.." && pwd)"
RAIZ="$(cd "$MOD/../.." && pwd)"
[ -f "$MOD/tools/tools_bin.sh" ] || {
  echo "runner.sh: cannot find the mod at $MOD (tools_bin.sh missing)" >&2
  exit 2
}
DELTAS="${VC_DELTAS:-$AQUI/deltas.txt}"
IMAGEM="${VC_RUNNER_IMAGE:-voxel-characters-runner:local}"
RUNS_BASE="${VC_RUNS:-/tmp/vc-runs}"

# ------------------------------------------------------------------ backends
#
# native            what every tool does today: real macOS GL, real window.
#                   The reference. Delta is zero by definition because it IS
#                   the procedure every threshold was measured under.
#
# native-offscreen  same binary, same GL, window parked off the visible area
#                   through tools/render/conf.lua. Canvas-based tools only:
#                   they render into an FBO and encode it, so nothing needs to
#                   reach a screen. REFUSED for tools/ingame, which capture the
#                   presented back buffer and would photograph nothing.
#
# docker            Linux LOVE under xvfb with software GL. Different
#                   rasteriser, different LOVE build. Scaffolded, not usable
#                   yet; `probe docker` says exactly what is missing.
BACKENDS="native native-offscreen docker"

backend_valido() {
  case " $BACKENDS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# Is LOVE resolvable? Asked in a SUBSHELL on purpose: tools_bin.sh exits when
# it cannot find the binary, which is right for a tool that needs it and wrong
# for a probe whose whole job is to report what is missing without dying.
tem_love() {
  ( . "$MOD/tools/tools_bin.sh" ) >/dev/null 2>&1
}

tem_docker() {
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1
}

tem_imagem() {
  docker image inspect "$IMAGEM" >/dev/null 2>&1
}

# The delta record is DATA, not code, so a backend gets blessed by measuring
# and writing a line, never by editing this file. Format, one per line:
#   <backend> <target-key> <verdict> <evidence>
delta_de() {
  local backend="$1" alvo="$2"
  # native IS the procedure every threshold in this repo was measured under,
  # so it is the reference rather than something with a delta to measure.
  [ "$backend" = "native" ] && { echo "REFERENCE"; return; }
  [ -f "$DELTAS" ] || { echo "UNMEASURED"; return; }
  # THE LAST MATCHING LINE WINS, not the first.
  #
  # measure_delta.sh keeps one line per backend+target by replacing the old
  # one, so normally there is nothing to choose between. This reads the last
  # match anyway, because the two rules have to agree on which measurement is
  # current: if a line is ever added by hand, or by an older append-only
  # version of the writer, taking the FIRST match would report a superseded
  # measurement as the live one. Newest wins on both sides.
  local linha
  linha=$(awk -v b="$backend" -v k="$alvo" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    ($1 == b && $2 == k) { ultima = $0 }
    END { if (ultima != "") print ultima }
  ' "$DELTAS" 2>/dev/null)
  if [ -z "$linha" ]; then echo "UNMEASURED"; else
    printf '%s' "$linha" | awk '{print $3}'
  fi
}

# --------------------------------------------------------------------- probe
probe_um() {
  local b="$1" estado motivo proxima
  estado="no"; motivo=""; proxima=""
  case "$b" in
    native)
      if tem_love; then estado="yes"; motivo="real macOS GL, the reference procedure"
      else estado="no"; motivo="LOVE binary not found"
           proxima="install LOVE 11.5, or export LOVE_BIN=/path/to/love"; fi
      ;;
    native-offscreen)
      if tem_love; then estado="yes"
           motivo="canvas-based render targets only; refuses tools/ingame"
      else estado="no"; motivo="LOVE binary not found"
           proxima="install LOVE 11.5, or export LOVE_BIN=/path/to/love"; fi
      ;;
    docker)
      if ! tem_docker; then
        estado="no"; motivo="docker daemon not reachable"
        proxima="start Docker Desktop or colima, then re-probe"
      elif ! tem_imagem; then
        estado="no"; motivo="image $IMAGEM is not built"
        proxima="docker build -t $IMAGEM $AQUI"
      else
        estado="partial"
        motivo="image exists; the shell tools still hardcode the macOS LOVE save path"
        proxima="see LIMITATIONS in tools/runner/README.md before trusting output"
      fi
      ;;
  esac
  printf "  %-17s %-8s delta=%-11s %s\n" "$b" "$estado" "$(delta_de "$b" any)" "$motivo"
  [ -n "$proxima" ] && printf "  %-17s %-8s NEXT: %s\n" "" "" "$proxima"
  [ "$estado" = "yes" ] && return 0
  [ "$estado" = "partial" ] && return 0
  return 1
}

cmd_probe() {
  local pedido="${1:-}"
  echo "controlled visual runner, backend probe"
  echo "  image        $IMAGEM"
  echo "  runs         $RUNS_BASE"
  echo "  deltas       $DELTAS"
  echo ""
  if [ -n "$pedido" ]; then
    backend_valido "$pedido" || { echo "unknown backend: $pedido"; echo "known: $BACKENDS"; exit 2; }
    probe_um "$pedido" || {
      echo ""
      echo "BACKEND UNUSABLE: $pedido"
      exit 2
    }
    echo ""
    echo "BACKEND USABLE: $pedido"
    return 0
  fi
  local b
  for b in $BACKENDS; do probe_um "$b" || true; done
  echo ""
  echo "No backend is trusted for a THRESHOLD measurement until its delta"
  echo "against native is measured and written to deltas.txt. UNMEASURED means"
  echo "exactly that: usable for looking, not for comparing."
}

# ----------------------------------------------------------------------- run
uso_run() {
  cat >&2 <<'EOF'
usage: runner.sh run <backend> [options] -- "<one shell command string>"

  Everything after -- must be EXACTLY ONE argument, and it is handed to
  `sh -c` as written. Several arguments are refused rather than joined:
  see WHY ONE STRING in this file.

      right:  -- "bash -c 'echo IT WORKED'"
      wrong:  -- bash -c 'echo IT WORKED'

  --label <name>            names the run directory (default: "run")
  --verdict <erx>           extended regex that MUST appear in the output.
                            Without it, the project convention is required:
                            at least one PASSOU/PASSED and no FALHOU/FAILED.
  --collect <glob>          copy matching files into <rundir>/artifacts after
                            the run. Repeatable. LOVE writes to its save
                            directory, not to our run directory, so this is
                            how output gets gathered.
  --expect-artifacts <n>    fail if fewer than n files were collected.
  --allow-no-verdict        ONLY for wrapping something that legitimately
                            prints nothing. Says so loudly in the metadata.
EOF
}

cmd_run() {
  local backend="${1:-}"
  shift || true
  [ -n "$backend" ] || { uso_run; exit 2; }
  backend_valido "$backend" || { echo "unknown backend: $backend" >&2; echo "known: $BACKENDS" >&2; exit 2; }

  local label="run" verdict="" espera_art=0 sem_veredito=0
  local COLETA=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --label) label="${2:?--label needs a value}"; shift 2 ;;
      --verdict) verdict="${2:?--verdict needs a value}"; shift 2 ;;
      --collect) COLETA+=("${2:?--collect needs a value}"); shift 2 ;;
      --expect-artifacts) espera_art="${2:?--expect-artifacts needs a value}"; shift 2 ;;
      --allow-no-verdict) sem_veredito=1; shift ;;
      --) shift; break ;;
      *) echo "unknown option: $1" >&2; uso_run; exit 2 ;;
    esac
  done
  [ $# -gt 0 ] || { echo "no command given after --" >&2; uso_run; exit 2; }

  # WHY ONE STRING, AND WHY MORE THAN ONE IS REFUSED RATHER THAN JOINED.
  #
  # This used to document `-- <command...>` and then run `/bin/sh -c "$*"`,
  # which flattens the argument vector into a string that sh SPLITS AGAIN on
  # whitespace. The quoting a caller wrote is gone by then. Reproduced:
  #
  #   -- bash -c 'echo TESTE PASSOU'
  #
  # became `sh -c "bash -c echo TESTE PASSOU"`, which runs `bash -c echo` with
  # TESTE as $0 and PASSOU as $1, prints one empty line, and leaves a 1-byte
  # stdout.log. The meta line said `command bash -c echo TESTE PASSOU`, so the
  # record of what ran was wrong in the same way the run was.
  #
  # The trap is that SOME multi-argument forms survive the flattening by luck
  # (`-- env FOO=1 bash x.sh` happens to re-parse identically) while others
  # silently execute something else. A wrapper whose job is to refuse empty
  # green cannot itself run a different command than the one it recorded, so
  # the contract is now exactly one string and anything else is a usage error.
  #
  # Refusing HERE, before the backend gate, the run directory and the lock:
  # nothing is created and nothing is executed, which is the same rule the
  # backend refusal follows.
  if [ $# -gt 1 ]; then
    echo "REFUSED: everything after -- must be exactly ONE shell command string." >&2
    echo "  got $# arguments:" >&2
    local i=1
    for a in "$@"; do echo "    [$i] $a" >&2; i=$((i + 1)); done
    echo "  Joining them would lose your quoting: sh -c re-splits the result, so" >&2
    echo "  \`bash -c 'echo A B'\` would run \`bash -c echo\` with A and B as" >&2
    echo "  positional parameters and print nothing." >&2
    # RECONSTRUCT WITH THE QUOTING PUT BACK, never with "$*".
    #
    # The first version of this message suggested `-- "$*"`, which is the
    # FLATTENED string: exactly the broken command the refusal just caught. An
    # error message that tells you to run the wrong thing is worse than one
    # that only says no. So each argument that needs quoting gets it back,
    # with embedded single quotes escaped the standard way.
    local sugestao="" a esc
    for a in "$@"; do
      case "$a" in
        *[[:space:]\'\"\$\`\\]*)
          esc=$(printf '%s' "$a" | sed "s/'/'\\\\''/g")
          sugestao="$sugestao '$esc'" ;;
        *) sugestao="$sugestao $a" ;;
      esac
    done
    sugestao="${sugestao# }"
    echo "  NEXT: pass the whole command as ONE argument. You meant:" >&2
    echo "    $sugestao" >&2
    echo "  so quote it:" >&2
    echo "    -- \"$sugestao\"" >&2
    exit 2
  fi
  local comando="$1"

  # ---------------------------------------------------------------- gate the
  # backend BEFORE running anything. Rule 2: no silent fallback. And the
  # ordering matters for a reason this repo already paid for in calibra.sh:
  # anything destructive or observable belongs AFTER the checks, never before.
  case "$backend" in
    native|native-offscreen)
      tem_love || {
        echo "BACKEND UNUSABLE: $backend needs the LOVE binary" >&2
        echo "  NEXT: install LOVE 11.5, or export LOVE_BIN=/path/to/love" >&2
        exit 2
      }
      ;;
    docker)
      tem_docker || {
        echo "BACKEND UNUSABLE: docker daemon not reachable" >&2
        echo "  NEXT: start Docker Desktop or colima, then re-probe" >&2
        exit 2
      }
      tem_imagem || {
        echo "BACKEND UNUSABLE: image $IMAGEM is not built" >&2
        echo "  NEXT: docker build -t $IMAGEM $AQUI" >&2
        echo "  Then read LIMITATIONS in tools/runner/README.md: the shell" >&2
        echo "  tools still hardcode the macOS LOVE save path, so a container" >&2
        echo "  run cannot yet collect what the harness writes." >&2
        exit 2
      }
      ;;
  esac

  # native-offscreen is for canvas targets only. An in-game driver captures the
  # PRESENTED back buffer, so parking the window off the visible area would
  # photograph nothing and report it as a measurement, which is the exact
  # failure this runner exists to prevent.
  if [ "$backend" = "native-offscreen" ]; then
    case " $comando " in
      *tools/ingame/*|*POKEPORT_DRIVER*)
        echo "REFUSED: native-offscreen cannot host an in-game driver." >&2
        echo "  Those capture the presented back buffer; off the visible area" >&2
        echo "  there is nothing to capture, and it would look like a pass." >&2
        echo "  NEXT: use the native backend for tools/ingame." >&2
        exit 2
        ;;
    esac
  fi

  local stamp dir
  stamp="$(date +%Y%m%d-%H%M%S)"
  dir="$RUNS_BASE/$stamp-$label"
  mkdir -p "$dir/artifacts" || { echo "cannot create $dir" >&2; exit 2; }

  local rev
  rev=$(git -C "$MOD" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  local dsigla
  dsigla=$(delta_de "$backend" "$label")

  {
    echo "backend      $backend"
    echo "label        $label"
    echo "delta        $dsigla"
    echo "when         $stamp"
    echo "host         $(uname -srm)"
    echo "mod_rev      $rev"
    echo "cwd          $RAIZ"
    echo "command      $comando"
    [ "$sem_veredito" = "1" ] && echo "verdict      NOT REQUIRED (--allow-no-verdict)"
    [ -n "$verdict" ] && echo "verdict_erx  $verdict"
  } > "$dir/meta.txt"

  # THE LOCK, for anything that starts a LOVE on this machine. Reentrant: if we
  # were called from a tool that already holds it, tools_bin.sh sees
  # VC_TRAVA_DONO and this proceeds without taking anything.
  local rc
  case "$backend" in
    native|native-offscreen)
      # shellcheck disable=SC1090
      . "$MOD/tools/tools_bin.sh"
      vc_trava_pega "runner.sh($backend)" || exit 2
      ;;
  esac

  cd "$RAIZ" || exit 2
  if [ "$backend" = "native-offscreen" ]; then
    export VC_RUNNER_OFFSCREEN=1
  fi

  # No `set +e` / `set -e` dance here: this script runs under `set -u` only, so
  # a nonzero exit from the wrapped command is already just a value in $?.
  # Turning errexit ON after the run (which the first version did) would have
  # changed the behaviour of every check below it.
  if [ "$backend" = "docker" ]; then
    docker run --rm -v "$RAIZ:/repo" -w /repo "$IMAGEM" \
      /bin/sh -c "$comando" > "$dir/stdout.log" 2>&1
  else
    /bin/sh -c "$comando" > "$dir/stdout.log" 2>&1
  fi
  rc=$?

  # ------------------------------------------------------------- collect and
  # count. Guarded before expanding, because "${COLETA[@]}" on an EMPTY array
  # is an unbound variable under `set -u` in bash 3.2, which is what /bin/bash
  # is on macOS. card.sh already shipped that bug once.
  # GLOB WITHOUT WORD-SPLITTING, and this cost a full measurement run.
  #
  # The first version expanded the pattern as bare `for f in $padrao`, which
  # word-splits on spaces before globbing. Every real target here lives under
  # "~/Library/Application Support/LOVE/...", so the pattern was torn into
  # ".../Application" and "Support/LOVE/...", neither of which exists, and the
  # runner reported "0 collected" for files that were sitting right there.
  #
  # It survived the selftest because the fixture used a temp path with no
  # spaces in it: the test passed by avoiding the only condition that matters.
  # `set -f` turns globbing off so an exact path with spaces is taken whole,
  # and it is turned back on around the expansion when the pattern really is a
  # glob.
  local n_art=0
  if [ ${#COLETA[@]} -gt 0 ]; then
    local padrao f
    for padrao in "${COLETA[@]}"; do
      if [ -e "$padrao" ]; then
        # An exact path, spaces and all. The common case, and the one that broke.
        cp -R "$padrao" "$dir/artifacts/" 2>/dev/null && n_art=$((n_art + 1))
      else
        # A real pattern. IFS is emptied so only the glob splits it, never
        # whitespace inside the directory names it expands to.
        local antigo_ifs="$IFS"
        IFS=
        for f in $padrao; do
          [ -e "$f" ] && cp -R "$f" "$dir/artifacts/" 2>/dev/null && n_art=$((n_art + 1))
        done
        IFS="$antigo_ifs"
      fi
    done
  fi

  # COUNT WITHOUT `|| echo 0`, and this cost the selftest's first red.
  #
  # `grep -c` prints `0` AND exits 1 when it matches nothing, so `$(grep -c ...
  # || echo 0)` produced the two-line string "0\n0". Every `[ "$n" -eq 0 ]`
  # below then died with "integer expression expected", the failing test did
  # not increment the problem counter, and a command that printed absolutely
  # nothing was reported as RUNNER OK.
  #
  # That is the empty green this whole file exists to prevent, inside the file
  # that prevents it. The selftest caught it on its first run, which is the
  # argument for writing the selftest before trusting the tool. `head -1`
  # keeps it dead even if a future grep changes its mind about output.
  local n_pass n_fail
  n_pass=$(grep -cE '\b(PASSOU|PASSED)\b' "$dir/stdout.log" 2>/dev/null | head -1)
  n_fail=$(grep -cE '\b(FALHOU|FAILED)\b' "$dir/stdout.log" 2>/dev/null | head -1)
  n_pass=${n_pass:-0}
  n_fail=${n_fail:-0}

  local problemas=0
  fala() { echo "$1"; echo "$1" >> "$dir/verdict.txt"; }

  : > "$dir/verdict.txt"
  fala "backend      $backend   delta=$dsigla"
  fala "exit         $rc"
  fala "artifacts    $n_art collected (expected at least $espera_art)"
  fala "verdicts     $n_pass passed, $n_fail failed"

  [ "$rc" -ne 0 ] && { fala "PROBLEM: the command exited $rc"; problemas=$((problemas + 1)); }

  if [ -n "$verdict" ]; then
    if ! grep -qE "$verdict" "$dir/stdout.log" 2>/dev/null; then
      fala "PROBLEM: required output not found: $verdict"
      problemas=$((problemas + 1))
    fi
    [ "$n_fail" -gt 0 ] && { fala "PROBLEM: output carries $n_fail failure verdict(s)"; problemas=$((problemas + 1)); }
  elif [ "$sem_veredito" = "0" ]; then
    # Rule 1. Zero failures is NOT enough: a command that printed nothing
    # measured nothing, and the honest answer is "no measurement", not "pass".
    if [ "$n_pass" -eq 0 ]; then
      fala "PROBLEM: NO VERDICT. Nothing in the output says anything passed,"
      fala "         so this run proves nothing. Declare what proof looks like"
      fala "         with --verdict, or use --allow-no-verdict deliberately."
      problemas=$((problemas + 1))
    fi
    [ "$n_fail" -gt 0 ] && { fala "PROBLEM: output carries $n_fail failure verdict(s)"; problemas=$((problemas + 1)); }
  fi

  if [ "$espera_art" -gt 0 ] && [ "$n_art" -lt "$espera_art" ]; then
    fala "PROBLEM: expected at least $espera_art artifact(s), collected $n_art."
    fala "         A tool that wrote nothing did not render anything."
    problemas=$((problemas + 1))
  fi

  if [ "$dsigla" = "UNMEASURED" ] && [ "$backend" != "native" ]; then
    fala "NOTE: this backend's delta against native is UNMEASURED. Look at the"
    fala "      output, do not compare it to a native threshold."
  fi

  fala "run          $dir"
  if [ "$problemas" -gt 0 ]; then
    fala "RUNNER FAILED: $problemas problem(s)"
    return 1
  fi
  fala "RUNNER OK"
  return 0
}

# ------------------------------------------------------------------ selftest
#
# Proves the runner reports a problem when there IS one, using fake targets
# that need no display, no LOVE and no docker. A gate is not verification
# until it has failed on input that should fail, and every case below is a
# state that must NOT come out green.
cmd_selftest() {
  local falhas=0 casos=0
  # NOT `local`, and the reason is written down in tools_bin.sh already: a
  # `trap ... EXIT` declared inside a function fires when the SCRIPT exits, by
  # which time a function-local variable is out of scope. Under `set -u` the
  # cleanup then died with "tmp: unbound variable" after the summary had
  # already printed, which reads like a second failure. VC_RUNNER_TMP is a
  # global so the trap can still see it.
  VC_RUNNER_TMP="$(mktemp -d -t vcrunner)" || exit 1
  trap 'rm -rf "$VC_RUNNER_TMP"' EXIT
  local tmp="$VC_RUNNER_TMP"

  espera() {  # $1 = expected rc (0 or nonzero-as-1), $2 = name, rest = args
    local quero="$1" nome="$2"; shift 2
    casos=$((casos + 1))
    local out rc
    out=$(VC_RUNS="$tmp/runs" bash "$AQUI/runner.sh" run "$@" 2>&1)
    rc=$?
    local got=0
    [ "$rc" -ne 0 ] && got=1
    if [ "$got" = "$quero" ]; then
      printf "  %-46s ok\n" "$nome"
    else
      printf "  %-46s WRONG (rc=%s, wanted %s)\n" "$nome" "$rc" "$quero"
      printf '%s\n' "$out" | sed 's/^/       /'
      falhas=$((falhas + 1))
    fi
  }

  echo "runner selftest: does it fail when it should?"

  # A verdict and an artifact: the only shape that may pass.
  espera 0 "a real verdict passes" native --label ok \
    --verdict 'ALL GOOD' -- "echo ALL GOOD; echo PASSED"

  # Rule 1, the important one.
  espera 1 "silence is not a pass" native --label mudo -- "true"
  espera 1 "exit 0 with only noise is not a pass" native --label ruido -- "echo working hard"
  # en-us: fixture. The verdict regex accepts FALHOU|FAILED and the Portuguese
  # half is what the in-game drivers still emit, so feeding it only the English
  # half would leave the branch that actually fires in production unexercised.
  espera 1 "a failure verdict fails (PT)" native --label ruim -- "echo PASSED; echo FALHOU x"
  espera 1 "a failure verdict fails (EN)" native --label ruim2 -- "echo PASSED; echo FAILED x"
  espera 1 "a nonzero exit fails" native --label saiu -- "echo PASSED; exit 3"
  espera 1 "a missing required string fails" native --label falta \
    --verdict 'REGUA OK' -- "echo PASSED; echo something else"

  # Artifacts: a tool that rendered nothing did not render.
  espera 1 "no artifact when one was required fails" native --label semart \
    --expect-artifacts 1 --verdict 'PASSED' -- "echo PASSED"

  # And the POSITIVE half, which the negative above cannot cover: that case
  # passes precisely BECAUSE nothing was collected, so it would still pass if
  # --collect were completely broken. A branch nothing exercises looks exactly
  # like one that works, which is why probe_fp's discard was proved by forcing
  # its limit to -1 rather than by watching it stay green.
  casos=$((casos + 1))
  local alvo="$tmp/coletado.txt"
  if VC_RUNS="$tmp/runs" bash "$AQUI/runner.sh" run native --label comart \
       --collect "$alvo" --expect-artifacts 1 --verdict 'PASSED' \
       -- "echo PASSED; echo rendered > $alvo" >/dev/null 2>&1 \
     && [ -s "$(find "$tmp/runs" -path '*comart*/artifacts/coletado.txt' | head -1)" ]; then
    printf "  %-46s ok\n" "an artifact is really collected"
  else
    printf "  %-46s WRONG (--collect did not gather the file)\n" "an artifact is really collected"
    falhas=$((falhas + 1))
  fi

  # A PATH WITH SPACES IN IT, which is the only kind this tool actually meets.
  # LOVE writes to "~/Library/Application Support/LOVE/<game>", and the case
  # above passed for a year's worth of confidence while using a temp path with
  # no spaces: it was passing by avoiding the condition that matters. On the
  # MBP the real collect reported "0 collected" for three files that existed.
  casos=$((casos + 1))
  local dir_espaco="$tmp/Application Support/LOVE"
  mkdir -p "$dir_espaco"
  local alvo2="$dir_espaco/render out.png"
  if VC_RUNS="$tmp/runs" bash "$AQUI/runner.sh" run native --label espaco \
       --collect "$alvo2" --expect-artifacts 1 --verdict 'PASSED' \
       -- "echo PASSED; echo png > '$alvo2'" >/dev/null 2>&1 \
     && [ -s "$(find "$tmp/runs" -path '*espaco*/artifacts/render out.png' | head -1)" ]; then
    printf "  %-46s ok\n" "a path with spaces is collected whole"
  else
    printf "  %-46s WRONG (spaces in the path broke --collect)\n" "a path with spaces is collected whole"
    falhas=$((falhas + 1))
  fi

  # Rule 2, and it must not merely fail: it must not RUN. The sentinel proves
  # the command never executed, which is the difference between refusing a
  # backend and running the wrong one and then complaining.
  casos=$((casos + 1))
  local sentinela="$tmp/sentinela"
  local out rc
  out=$(VC_RUNS="$tmp/runs" VC_RUNNER_IMAGE="voxel-characters-runner:definitely-absent" \
        bash "$AQUI/runner.sh" run docker --label naofallback \
        -- "echo PASSED; touch $sentinela" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    printf "  %-46s WRONG (an absent image was accepted)\n" "an absent backend refuses"
    falhas=$((falhas + 1))
  elif [ -e "$sentinela" ]; then
    printf "  %-46s WRONG (it ran the command anyway)\n" "an absent backend refuses"
    falhas=$((falhas + 1))
  elif ! printf '%s' "$out" | grep -q "NEXT:"; then
    printf "  %-46s WRONG (refused without a next action)\n" "an absent backend refuses"
    falhas=$((falhas + 1))
  else
    printf "  %-46s ok\n" "an absent backend refuses, without running"
  fi

  # THE QUOTING CONTRACT, both halves.
  #
  # Negative: several arguments after -- must be refused, and refused BEFORE
  # anything runs. The sentinel is the whole test: the old code flattened argv
  # and executed a DIFFERENT command than the one it recorded in meta.txt, so
  # "it exited nonzero" is not enough here. It must not have run at all.
  casos=$((casos + 1))
  local sent_q="$tmp/quoting-sentinel"
  local out_q rc_q
  out_q=$(VC_RUNS="$tmp/runs" bash "$AQUI/runner.sh" run native --label quoting \
          --verdict PASSOU -- bash -c "echo PASSOU; touch $sent_q" 2>&1)
  rc_q=$?
  if [ "$rc_q" -eq 0 ]; then
    printf "  %-46s WRONG (multiple args accepted)\n" "multiple args after -- are refused"
    falhas=$((falhas + 1))
  elif [ -e "$sent_q" ]; then
    printf "  %-46s WRONG (it ran something anyway)\n" "multiple args after -- are refused"
    falhas=$((falhas + 1))
  elif ! printf '%s' "$out_q" | grep -q "NEXT:"; then
    printf "  %-46s WRONG (refused without a next action)\n" "multiple args after -- are refused"
    falhas=$((falhas + 1))
  else
    printf "  %-46s ok\n" "multiple args after -- refuse, without running"
  fi

  # Positive: the documented form, with a nested subcommand and nested quotes,
  # has to actually reach the shell intact. Without this the negative above
  # would pass even if `run` could no longer execute anything at all.
  espera 0 "one quoted string with a subcommand runs" native --label quoting_ok \
    --verdict 'IT WORKED' -- "bash -c 'echo IT WORKED'"

  # native-offscreen must refuse an in-game driver rather than photograph
  # nothing off the visible area.
  espera 1 "offscreen refuses an in-game driver" native-offscreen --label fp \
    --verdict PASSED -- "echo tools/ingame/probe_life.lua; echo PASSED"

  # Metadata has to carry the backend and the delta, or a number found later
  # in a log cannot be traced to how it was produced.
  casos=$((casos + 1))
  VC_RUNS="$tmp/runs" bash "$AQUI/runner.sh" run native --label meta \
    --verdict 'PASSED' -- "echo PASSED" >/dev/null 2>&1
  local metafile
  metafile=$(find "$tmp/runs" -name meta.txt -path '*meta*' 2>/dev/null | head -1)
  if [ -n "$metafile" ] && grep -q "^backend      native" "$metafile" \
     && grep -q "^delta " "$metafile" && grep -q "^mod_rev " "$metafile"; then
    printf "  %-46s ok\n" "the run records backend, delta and revision"
  else
    printf "  %-46s WRONG (metadata incomplete)\n" "the run records backend, delta and revision"
    falhas=$((falhas + 1))
  fi

  # The delta RECORD, which is the other half of this file's contract: what
  # runner.sh reads here has to be what measure_delta.sh wrote there. That
  # selftest lives next to the writer and runs from here so one command covers
  # both sides, and so the battery covers it too.
  casos=$((casos + 1))
  if bash "$AQUI/measure_delta.sh" --selftest >"$tmp/md.log" 2>&1; then
    printf "  %-46s ok\n" "the delta record keeps one line per key"
  else
    printf "  %-46s WRONG\n" "the delta record keeps one line per key"
    sed 's/^/       /' "$tmp/md.log"
    falhas=$((falhas + 1))
  fi

  echo ""
  if [ "$falhas" -eq 0 ]; then
    echo "RUNNER SELFTEST OK: $casos cases, every failing state failed"
    return 0
  fi
  echo "RUNNER SELFTEST FAILED: $falhas of $casos cases wrong"
  return 1
}

# ---------------------------------------------------------------------- main
case "${1:-}" in
  probe) shift; cmd_probe "${1:-}" ;;
  selftest) shift; cmd_selftest ;;
  run) shift; cmd_run "$@" ;;
  *)
    cat >&2 <<EOF
controlled visual runner (roadmap T0.2)

  runner.sh probe [backend]     what can run here, and what is missing
  runner.sh selftest            does the runner fail when it should?
  runner.sh run <backend> [options] -- "<one shell command string>"

Everything after -- is ONE argument, handed to sh -c as written:

  right:  -- "bash -c 'echo IT WORKED'"
  wrong:  -- bash -c 'echo IT WORKED'

backends: $BACKENDS
EOF
    exit 2
    ;;
esac
