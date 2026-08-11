# Execution state

Durable state for autonomous execution. Written so that a session that starts
cold, or a second orchestrator, can pick up without asking anyone. Updated as
work lands, not as work is planned.

Everything from `## Roadmap V2 execution` down is the V2 record and is history.
The section directly below is the live one, and it tracks `ROADMAP_V3.md`.

---

# Roadmap V3 execution

**Branch `vida-v2`, nothing pushed, nothing tagged, no credential used.**

## Current state, measured

**The FULL battery is green.** Run 2026-08-10 on the MBP with Kim's
authorisation, against this working state synced over: every gate, including
the ruler and all five in-game gates.

```
637/637 offline · lint clean · chunk-local headroom 71 of 200 (129 in use)
modkit ok · option docs ok (17 options, 20 rows) · RUNNER SELFTEST OK (16 cases)
execution state ok · en-US sweep ok · audio gate ok · fx sfx ok · reason field ok
verdict contract ok · output contract ok
RULER OK (36 checks) · in-game 20/16/16/8/6 passed, 0 failed
BATTERY OK
```

`--rapido` is 13 gates; the reason field is 7d, the verdict contract 7e and the
output contract 7f.
The figures above are a FULL battery run on the MBP, 2026-08-11, from the
tempdir copy described under the T1.5 slice 1 write-up.

**The banner is `BATTERY OK` / `BATTERY RED` now**, not `BATERIA`. Anything
grepping the old string finds nothing; nothing did, which was checked before
changing it.

**`MUTANTES OK: the suite killed all 5.`** The last gate in the definition of
done now has a result. Clean base 621 checks; each declared mutation dropped the
count and died (612, 619, 617, 617, and 585 for the test-file mutant).

**Checkpoint commit, local only: `af6e803`** on `vida-v2`, 26 files, nothing
pushed, tagged or released. Work has continued in local commits since; `8429d0d`
was the head before the reason-field slice. It exists because `mutantes.sh` refuses a dirty
tree, on purpose, since it mutates `main.lua` and restores from a trap.

Left deliberately uncommitted: `docs/ROADMAP_ONE_SHOT_PROMPT_DRAFT.md`, which
was already modified before this session began and is Kim's own work. It did not
need to be committed to unblock anything: `mutantes.sh` only inspects `*.lua`
(`tools/mutantes.sh:49`), so a modified Markdown file was never in its way. Worth
knowing before anyone commits somebody else's draft to clean a tree.

## Workstreams

| Item | Owner | Files owned | State | Evidence |
|---|---|---|---|---|
| T0.1 option docs | this session | `README.md`, `CHANGELOG.md`, `tools/options_documented.lua`, `tools/bateria.sh` | **landed** | gate green at 16 options / 19 rows; 4 broken states each proved to fail |
| T0.2 controlled runner | this session | `tools/runner/**`, `tools/render/conf.lua`, `tools/bateria.sh` | **slice 1 landed** | `RUNNER SELFTEST OK`, 16 cases |
| T0.2 slice 1.1 hygiene | this session | `tools/runner/runner.sh`, `tools/runner/README.md` | **landed** | the argv-flattening defect below, refused and covered by two new cases |
| T0.2 slice 2 measurement | this session, run on the MBP with Kim's authorisation | `tools/runner/measure_delta.sh`, `tools/runner/window_probe/**`, `tools/runner/deltas.txt` | **measured** | output delta ZERO (sha256 identical, floor identical); window NOT hidden, macOS clamped it back on screen |
| T0.3 execution state | this session | `docs/EXECUTION_STATE.md`, `tools/execution_state_gate.lua`, `tools/bateria.sh` | **landed** | gate green at 6 required sections / 5 rows; found 3 real gaps on its first run, listed under T0.3 below |
| T1.3 audio gate | this session | `tools/audio_gate.sh`, `tools/bateria.sh` | **landed** | `AUDIO GATE SELFTEST OK`, 7 cases; fixtures measured at -91.0 / -18.1 / -3.1 dBFS |
| T1.5 en-US, slice 1 | this session | `tools/lint_asserts.lua`, `tools/hooks/pre-commit` | **landed** | lint output en-US; hook summary went from 4 of 8 gates to 8 of 8 |
| T1.5 en-US, slice 2 | this session | `tools/en_us_sweep.lua`, `tools/en_us_scope.txt`, `release.sh`, `release_check.sh`, `so_comentarios.{lua,sh}`, `audio_gate.sh`, `runner/runner.sh` | **landed** | surface 22 lines to 0; 101 deferred lines declared with reasons; 4 broken states proved to fail |
| T1.5 en-US, slice 3 (`ajusta.lua`) | Codex desktop, verified by this session | `tools/juiz/ajusta.lua`, `tools/en_us_scope.txt` | **landed** | `--autoteste` green; `--estados` TSV intact at 171 rows x 4 cols; sweep surface 0 |
| item 16 follow-up: life ceiling | this session | `tests/voxel_chars_test.lua` | **landed** | 621/621; ceiling now sweeps 6 life options and reacts to ATTENTION at 3.5 where it did not before |
| T1.1 lab motion, gate + bridge | this session | `tools/render/host_matrix.lua`, `tests/voxel_chars_test.lua`, `tools/render/main.lua` | **landed** | 625/625; identity host rejected at 74% error; REGUA OK and renders byte-identical with the channel on and off |
| T1.1 slice 2, preview wired | this session | `tools/render/{main,lab,host_matrix}.lua` | **landed** | `LABPROBE motion=off options=9 moved=false` against `motion=on options=16 moved=true`; REGUA OK |
| T1.2 named anchors | this session | `main.lua`, `tests/voxel_chars_test.lua` | **landed** | 629/629; 4 mutations of the derivation each caught; full battery green on the MBP including ruler and in-game |
| T1.2 slice 2, animation events | this session | `main.lua`, `tests/voxel_chars_test.lua` | **landed** | 631/631; 4 mutations caught including a no-hysteresis one the first gate missed; full battery green on the MBP |
| T2.3 slice 3, audio capture path | this session | `tests/voxel_chars_test.lua`, docs | **landed** | recorder proven to see calls, and to catch a stray one at 181 plays |
| T1.4 round 4, exemplar+reason | this session | `tools/juiz/dados/NOTAS_DO_CRITICO.md` | **still cannot be run; blocker was step 1, now built** | protocol written; no result asserted. Needs a calibration session where reasons are typed, plus a critic that has not seen round 3's key |
| T1.5 slice 4, banner and verdict contract | this session | `tools/bateria.sh`, `tools/verdict_gate.sh`, `tools/release.sh`, `tools/ingame/monta.sh`, `tools/hooks/pre-commit`, `tools/en_us_scope.txt`, docs | **landed** | full battery green on the MBP, 20/16/16/8/6 in-game; 6 of 6 mutations caught; found release.sh printing 5 of 11 gates |
| T1.5 slice 5, tools/ingame and tools/render output | this session | `tools/ingame/*`, `tools/render/*`, `tools/output_contract.lua`, `tools/sala_de_teste.sh`, `tools/en_us_scope.txt`, `tools/bateria.sh` | **landed** | sweep 108 deferred lines to 5; full battery green on the MBP with in-game 20/16/16/8/6, the same counts as before the conversion |
| T2.1 defect: the ruler could not see the authored layer | this session | `main.lua`, `tools/render/{main,check}.sh`, `tools/render/main.lua` | **fixed** | `authprobe` reported `fs=MISSING`; now `io=FOUND mod=6 frames`, checked by the ruler on every run |
| T2.5 lab randomiser | this session | `tools/randomiza.lua`, `tools/randomiza_gate.lua`, `tools/measure_regions.py`, `tools/bateria.sh` | **landed** | deterministic from a seed; 4 of 4 real mutations caught, 1 equivalent mutant identified as uncatchable |
| T2.2 slice 3, the three-panel card | this session | `tools/render/preset_card.sh` | **landed** | original / authored / randomised, all three byte-different; reproducible from a seed |
| T2.2 slice 2, a preset renders | this session | `tools/render/{main,check}.lua/sh`, `tools/measure_regions.py` | **landed** | `alpha_diff=0 colour_diff=3530`: silhouette identical, colour changed; round-tripped preset renders byte-identical; `head` refused for want of a measured boundary |
| T2.2 slice 1, preset format | this session | `authored/preset.lua`, `tools/preset_gate.lua`, `tools/measure_regions.py`, `tools/bateria.sh` | **landed** | 67 sheets measured to ONE three-tone ramp; all 255 presets round-trip exactly; 14 refusals; 5 of 5 mutations caught |
| T2.1 slice 3, regions drive PART LAG | this session | `main.lua`, `tests/voxel_chars_test.lua`, `tools/authored_gate.lua`, `tools/ingame/menu.lua`, `README.md`, `CHANGELOG.md` | **landed** | 643/643; AUTHORED REGIONS OFF by default, one entry point; 5 of 5 runtime mutations caught after two gaps were closed; full battery green on the MBP |
| T2.1 slice 2, regions measured | this session | `tools/measure_regions.py`, `authored/sheets/red.lua`, `authored/schema.lua`, `tools/authored_gate.lua`, `tools/bateria.sh` | **landed** | 6 frames measured off the real sprite; 20 refusals enforced; 5 of 5 stale-region mutations caught; found the walk bob and the absent bag |
| T2.1 slice 1, authored layer schema | this session | `authored/**`, `tools/authored_gate.lua`, `tools/render/main.lua`, `docs/DISCLOSURE_DRAFT.md`, `tools/bateria.sh` | **landed** | 11 refusals enforced, 6 of 6 mutations caught, 0 authored pixels shipped; provenance splits three ways; full battery green on the MBP |
| T1.4 reason field | this session | `tools/render/{reason,lab,main}.lua`, `tools/juiz/reason_gate.{lua,sh}`, `tools/render/check.sh`, `tools/bateria.sh` | **landed** | 171 states / 30 pairs / 30 key lines byte-identical with a hostile reason on every one of the 106 recorded choices; 7 encoder mutations caught; `REGUA OK` on the MBP with the quote/pipe/equals round trip |
| T1.4 critic context, round 3 | this session | `tools/juiz/dados/*_r3.txt`, `NOTAS_DO_CRITICO.md` | **run, inconclusive; critic NOT approved** | 60.0% against a 53.3% baseline, margin +6.7 inside a +/-12.6 standard error |
| T2.3 slice 4, playback | this session | `main.lua`, `sfx/*.wav`, `tools/fx_sfx_gate.sh`, docs | **landed** | 637/637; off-guard defeat caught as `1 source(s), 5 play(s)`; full battery green on the MBP with the assets packaged |
| T2.3 SFX, generated | this session | `tools/fx_sfx.lua`, `tools/fx_sfx_gate.sh`, `tools/bateria.sh` | **landed** | fireball -10.6 dBFS, bolt -10.1, control -91.0; 5 of 5 mutations caught; runtime playback is slice 3 |
| T2.3 FX demo | this session | `main.lua`, `README.md`, `CHANGELOG.md`, `tests/voxel_chars_test.lua`, `tools/ingame/menu.lua` | **landed** | 634/634; 5 of 5 mutations caught after the gate was rebuilt to count live effects; full battery green on the MBP |

## Blocked on Kim

Mirrors `ROADMAP_V3.md` section 4. **Agents do not work around this table.**
Nothing in it is waiting on engineering, and nothing below it should be
"unblocked" by finding a clever substitute.

| # | What is needed | Why nobody else can | State of the rest |
|---|---|---|---|
| K1 | A personal access token for `last-swagger` | Credential. A release author is set at creation and cannot be edited afterwards, so this only fixes forward. | `release.sh` built and rehearsed; `--publicar` required to publish |
| K2 | His eye on the options that ship OFF: `FOOTFALL`, `CAMERA FIT`, `FRONT SHAPE`, `TOP DOME`, `STEP WEIGHT`, `PART LAG`, `ATTENTION`, `FIRST PERSON` | Taste, and he is the one who ships it | every one has a clip recipe; `monta.sh` can assemble them |
| K3 | The judge against critic call on `FRONT SHAPE` and `TOP DOME` | A taste question dressed as a measurement, and both sides are measured | both arguments written up in `tools/juiz/dados/NOTAS_DO_CRITICO.md` |
| K4 | Explicit approval to push, tag, publish or post | Outward facing and not reversible | local commits on a feature branch are routine |
| K5 | Unpausing the battle probe | He paused it | nothing, deliberately |

**Not on this table, and worth the distinction:** the `native-offscreen`
measurement was never blocked on Kim, only on a free display. It ran on the MBP
on 2026-08-10 with his authorisation and is now answered. See "Gate deltas".

## T0.1, what landed

`tools/options_documented.lua` loads `main.lua` under the outer repository's
love stub and captures the schema the mod hands to `mod.options:define`, which
is the same door the offline suite uses. So the list of options is read from the
code and a new option is covered the moment it enters `OPTIONS`, with no edit to
the gate. It checks four things: every option has a README row, the row lists
every level, the row's stated default equals the registered default, and the
CHANGELOG names the option together with one of its levels.

The level requirement is what makes the CHANGELOG check mean something.
`FIRST PERSON` appeared twice in `CHANGELOG.md` while the option was
undocumented, both times as a value of the read-only `STATUS` row, so a plain
substring search would have passed it.

**Documented as a consequence:** `FOOTFALL`, `ATTENTION`, `PART LAG` and
`FIRST PERSON`, plus the `[Unreleased]` preamble that claimed nothing changed
for a player, the README's row count (16 stated, 19 real) and its advertised
check count (480 stated, 620 real). Two places where the README contradicted
itself once `FIRST PERSON: SOLID` existed were fixed too: the `STATUS` table row
and the "What it does not do" bullet both said the flat card comes back always.

**Proved it fails** on four broken states, each mutated, run, and restored with
a checksum: an option in the schema documented nowhere; a README default that
disagrees with the code; a README row missing a level; a CHANGELOG entry that
no longer names its option. All four exited 1. `shasum -a 256 -c` confirmed
`main.lua`, `README.md` and `CHANGELOG.md` byte identical afterwards.

**Named hole, so nobody assumes it is covered:** the gate does not check the
README's advertised check count, because deriving that means running the suite
it is a step alongside.

## T0.2, what landed and what it deliberately does not claim

`tools/runner/runner.sh` with three subcommands: `probe`, `selftest`, `run`.
Every run gets `${VC_RUNS:-/tmp/vc-runs}/<stamp>-<label>/` holding `meta.txt`
(backend, delta state, host, mod revision, command), `stdout.log`,
`verdict.txt` and `artifacts/`. Outside the repository on purpose, so a run can
never dirty the tree that `release.sh` refuses to publish from.

Three refusals, and the selftest proves all three:

- **No empty green.** Exit 0 with no verdict is "no measurement", not a pass.
- **No silent fallback.** An unusable backend refuses AND does not execute the
  command. The selftest proves the non-execution with a sentinel file, because
  refusing after running is not refusing.
- **No shared LOVE.** LOVE-backed backends take the existing reentrant lock.

**Backends and their honest state:**

| Backend | Available here | Delta vs native |
|---|---|---|
| `native` | yes | reference, by definition |
| `native-offscreen` | yes | **ZERO on output**, but it does not hide the window |
| `docker` | image not built | **UNMEASURED** |

`native-offscreen` parks the harness window at -4000,-4000 through
`tools/render/conf.lua` when `VC_RUNNER_OFFSCREEN=1`. Only the position moves;
size, depth and vsync decide the output and are untouched. It is refused for
`tools/ingame/*`, which capture the presented back buffer and would photograph
nothing off the visible area.

## T0.2 slice 1.1, the runner ran a different command than it recorded

Found by review, reproduced, fixed. The runner documented
`run <backend> [options] -- <command...>` and then executed
`/bin/sh -c "$*"`, which flattens the argument vector into a string that `sh`
splits again on whitespace. Reproduced exactly:

```
-- bash -c 'echo TESTE PASSOU'
```

became `sh -c "bash -c echo TESTE PASSOU"`, which runs `bash -c echo` with
`TESTE` as `$0` and `PASSOU` as `$1`, printed one empty line, and left a 1-byte
`stdout.log`. `meta.txt` recorded `command bash -c echo TESTE PASSOU`, so **the
record of what ran was wrong in the same way the run was**, which is the part
that matters: a wrapper built to refuse empty green cannot execute something
other than what it logged.

The trap is that some multi-argument forms survive the flattening by luck
(`-- env FOO=1 bash x.sh` happens to re-parse identically) while others quietly
run something else. So the fix is the conservative one: **the contract is
exactly one shell command string, and more than one argument is a usage error**
refused before the backend gate, the run directory or the lock. Preserving argv
properly was the alternative and was rejected: it would keep two ways to say
the same thing, and the failure mode of the wrong one is silent.

The refusal prints the correctly requoted command. That detail was itself a
second defect: the first version suggested `-- "$*"`, the flattened string,
which is exactly the broken command it had just refused. An error message that
tells you to run the wrong thing is worse than one that only says no.

Covered by two selftest cases, and both halves are needed: the negative proves
several arguments refuse **without running** (sentinel file, because refusing
after running is not refusing), and the positive proves the documented form with
a nested subcommand still reaches the shell intact. Without the positive, the
negative would keep passing even if `run` could no longer execute anything.

**Proved without a display, which is worth more than the claim:** loading
`conf.lua` under a fake `love` table and dumping the resulting config shows
that with the flag unset the table is exactly what it was before this change
(no `window.x`, no `window.y`), and with the flag set the ONLY difference is
those two keys. Title, width, height, depth, vsync and every disabled module
are byte identical in both. So the default path is untouched by construction,
and the mode cannot be secretly changing the scene through some other field.
That is a different claim from "the rendered pixels are identical", which was
answered separately on the MBP: they are identical. See "Gate deltas".

`docker` has a reviewable `Dockerfile` (Linux LOVE, xvfb, llvmpipe) and is not
built. `probe docker` prints the build command as the next action.

## T0.2 slice 2, the measurement, built here and RUN on the MBP

**Why it needed a machine of its own.** Measuring this delta needs a `native`
reference run, and `native` is the procedure with a real window: there is no
version of it that hides. The `native-offscreen` run could not be assumed
invisible either, which turned out to be the finding. So both sides of the
experiment take the screen, and it ran on the MBP with Kim's authorisation
rather than on the machine he was using.

The measurement is one auditable command:

- `tools/runner/measure_delta.sh`, with `--dry-run` that prints every step and
  launches nothing.
- `tools/runner/window_probe/`, a tiny LOVE game that asks the window where it
  actually is and prints a `W1 PASSOU` / `W1 FALHOU` verdict.

**Five steps, and step 2 is the one that makes it honest.** Native runs twice
before anything is compared across backends, because a byte comparison only
means something if the target is byte-deterministic to begin with. If the two
native runs already differ, the script reports INCONCLUSIVE and writes nothing:
a difference against the offscreen run would say nothing about the backend.
The precedent that makes bytes the right instrument is the ruler's own check
that the same card built twice is the same file.

**The window probe has a control, for the same reason.** It runs under the
offscreen flag AND under normal mode. Without the control, "off screen" could
just be how this machine always reports, and the probe would be measuring
nothing. Normal mode is expected to report the window ON a display; if it does
not, the probe says so and proves nothing.

**It cannot write a false ZERO.** Every render must have produced a non-empty
file before any comparison happens, because two missing files compare equal and
that is the exact defect `tools_bin.sh` records. Floor unstable means no
verdict is written at all.

One thing the script separates on purpose: output equivalence and window
invisibility are two different claims. Identical bytes with a window that still
appears is a real `ZERO` and a mode that buys nothing, so the script writes the
`ZERO` and prints a warning pointing at a separate user session, Space or
display instead.

**Slice 2 hygiene, found by review before the measurement ever ran.** The
writer appended and the reader took the FIRST matching line, so re-measuring a
key would have left the superseded verdict in force. A stale `ZERO` is the worst
version of that: it is the one that would let a threshold be trusted on a
backend already shown to differ. Fixed on both sides so they cannot disagree
about which measurement is current: `measure_delta.sh` keeps at most one line
per backend+target by replacing, and `runner.sh` reads the last match anyway, in
case a duplicate is ever added by hand. Covered by `measure_delta.sh
--selftest`, text only, run from `runner.sh selftest` so the battery covers it.

Worth noting because it is the second time in this item: both defects so far
were in the bookkeeping rather than in the rendering, and both were found by
reading the tool against its own contract rather than by running it.

## T0.3, and the gate found three gaps in this very file

`tools/execution_state_gate.lua`, battery step 7. It reads the required sections
out of `ROADMAP_V3.md` section 9.7 and demands them here, so the contract lives
in one place. Add a required section to the roadmap and the gate starts asking
for it with no edit to the gate, which is the same principle
`options_documented.lua` uses against the `OPTIONS` table.

**What it found on its first run, none of it noticed by reading:**

1. **The live section had no "Blocked on Kim".** The one section the roadmap
   says agents may not work around. It went unnoticed because the V2 history
   below has such a table and the eye finds it there, which is why the gate
   scopes its search to the live window between the two H1 headings and treats
   anything below the V2 heading as history.
2. **No date anywhere in the live section.** A measured block with no date
   cannot be told from a stale one.
3. **The T0.3 workstream row had an empty evidence cell**, written by me one
   turn earlier while adding the row.

**Checks, and they are structural on purpose:** every required section present
in the live window; the live window ahead of the history; a date; and every
workstream row carrying an owner, a state and evidence that is not the word
"done" (the roadmap asks for a commit or a measurement). It does not judge
prose. A gate that fires on a legitimate edit gets waived by the second day.

**Proved it fails** on five broken states, each mutated, run and restored under
checksum: a required section renamed away; the date removed; an evidence cell
emptied; evidence replaced with "done"; and a section ADDED to the roadmap's
9.7, which the gate immediately started requiring. That last one is the case
that proves it reads the contract rather than a copy of it.

## T1.3, the audio gate exists before the audio does

`tools/audio_gate.sh`, battery step 7b. Three checks, and the off path carries
the most weight:

- **A1** the off path is silent, at or below -60 dBFS.
- **A2** the on path has signal, measured against **the off path from the same
  run** rather than against a guessed constant.
- **A3** the on path peaks under -6 dBFS, so a demo effect cannot blast over the
  game.

It refuses a file it could not measure, because an unmeasurable file is not a
silent file and a tool that wrote no audio did not play anything. That is the
same false green `tools_bin.sh` records, in a new medium.

**The fixtures were measured, not assumed**, and that mattered: lavfi's `sine`
peaks at **-18.1 dBFS** at default amplitude, not at 0, so a selftest built on
the theoretical number would have been calibrated against nothing. Measured
values now anchoring the tests: silence -91.0, a reasonable effect -18.1, too
loud -3.1 dBFS.

**Proved it fails** on six states: an off path that plays something, an on path
with no signal, an on path over the ceiling, a missing file, an empty file, and
one positive case. Plus a seventh that checks the MEASUREMENT itself tells the
three fixtures apart, because if `medir` returned the same number for
everything, all six verdicts would still land where they were expected.

**Named holes.** -60 and -6 dBFS are defensible starting points, not
measurements: the real ceiling should come from comparing against the game's own
music and SFX levels, and there is nothing to compare with yet. A2's floor is
not a guess, it comes from the off path in the same run. And this measures
nothing about the mod today: it verifies the instrument only.

## T1.5 first slice, and a defect it uncovered in my own earlier work

**Checked the contract before renaming anything**, because the hazard on record
is that renaming a verdict word breaks whatever greps for it. Result:
`release.sh` and the pre-commit hook both gate on the **exit code**
(`if ! bash ...`), not on any string. So the battery's output text is free to
change and the contract is numeric.

**Converted:** `tools/lint_asserts.lua`, the one Portuguese string the quick
battery prints on a green run, plus its failure message. Its two citations in
`ROADMAP_V3.md` were updated in the same pass, since the implementation is what
made them false.

**The defect this turned up, and it was mine, from three slices ago.** The
pre-commit hook summarised a successful run by grepping a hardcoded list of step
names, `(suite|lint|folga|modkit)`. Four gates were added to the quick battery
since then, so the hook had quietly been reporting **four of eight**: a green
commit showing half of what it ran. Fixed by matching the SHAPE `veredito`
prints (three spaces, a padded label, then the verdict) instead of a list of
names, so a gate added later appears without editing the hook. Verified: the old
pattern matched 4 lines, the new one matches 8.

**Deliberately deferred: the `BATTERY OK` / `BATTERY RED` banner.** It is
quoted literally in eight places across four documents, including the roadmap's
own statement of this problem, and T1.5's gate is a full battery run, which needs
a display. Renaming a banner and rewriting its citations in a display-blocked
turn is more churn than value. Filenames stay untouched for the same reason and
should move in one commit with every reference, never file by file.

## T1.5 slice 2: the scope, in data, and what it is not

**The scope decision now lives in `tools/en_us_scope.txt` rather than in
anyone's head**, one rule per path with a zone and a reason:

| Zone | Meaning | Lines |
|---|---|---|
| `surface` | text a human reads, and the tool can be validated with no display. Must be en-US. | **0** |
| `deferred-needs-love` | output only exercised or parsed by something needing LOVE (`tools/ingame`, `tools/render`) | 90 |
| `deferred-full-battery` | convertible, but the gate for the change is a full battery (`bateria.sh` banner) | 3 |
| `deferred-api` | option values and command-line keys; a rename is an API change, not a translation | 0 declared so far |
| `internal` | identifiers, test names, fixtures. Nobody reads these as product text. | 5 |

**Converted this slice, surface 22 lines to 0:** `release.sh` (10 strings),
`release_check.sh` (the `sim`/`nao` sentinel, producer and consumer in the same
file), `so_comentarios.lua` and `.sh`, `audio_gate.sh` (`PASSOU`/`FALHOU` to
`PASSED`/`FAILED`, which the verdict regexes accept equally), and `runner.sh`'s
usage examples.

**What made the detector worth building.** The first exploratory grep reported
`audio_gate.sh` and `measure_delta.sh` as the worst offenders. Both are mine and
both are written in English: it was matching **identifiers** (`avalia`,
`veredito`, `saida`), file names in string form (`card_antes.png`), and option
values (`VC_CLIP_DEGRAU=alto`). So the sweep extracts the CONTENTS of string
literals on lines that print, strips format specifiers, interpolations and
paths, and only then looks for Portuguese. Identifiers never enter the
comparison.

**Two failure modes, both proved:** a Portuguese string in a surface path, and a
deferred rule that no longer matches anything. The second one caught me
immediately: I had exempted `mutantes.sh` on the strength of the crude grep, and
its output is already en-US, so the gate rejected my own scope file. An
exemption nobody removes is how a gate stops gating.

**The per-line escape hatch requires a reason.** `# en-us: <why>` exempts the
line or the statement below it, and a marker with no reason does not exempt
anything (proved). It exists for one real case: the runner's selftest feeds
`FALHOU` on purpose, because the verdict regexes accept `FALHOU|FAILED` and the
Portuguese half is what the in-game drivers still emit. Testing only the English
half would leave the branch that fires in production unexercised. That case now
runs both halves, which is why the runner selftest went from 14 cases to 15.

**Still deferred, and these are the reasons rather than a shrug:** the
`BATTERY OK` banner (quoted in 8 places across 4 docs, gate is a full battery),
everything under `tools/ingame` and `tools/render` (their output is parsed by
gates that need a display, so converting blind means changing text a gate greps
without being able to run that gate), and all filenames.

## T1.5 slice 3: the judge fitter is no longer deferred

`tools/juiz/ajusta.lua` was the largest single remaining display-free surface
and already had its own `--autoteste`, so it did not belong behind the
full-battery deferral once slice 2 made the sweep honest. Converted the printed
surface and generated model-file comments to en-US while leaving the command
names and input data keys alone: `--estados`, `--ajusta`, `--autoteste`,
`--pesos`, `--pares`, `folha=`, `escolha=`, and the default `modelo.txt` remain
API/data, not prose.

**Validation:** `luajit mods/voxel_characters/tools/juiz/ajusta.lua --autoteste`
passes and now prints in en-US. Removing the specific deferral for
`juiz/ajusta.lua` from `tools/en_us_scope.txt` keeps the sweep green, with
surface still at 0 and deferred lines now at 98.

## A second writer touched this repo, and the contract says to say so

`tools/juiz/ajusta.lua` was translated to en-US by **another session**, not this
one, while this session was working. It was the exact slice queued up next here.
The execution contract says a file has one owner at a time, and it had two.
Nothing was lost, because the other session's work was good and this one had not
started editing that file, but the near miss is the point: two sessions in one
checkout is how a conflict gets discovered by a broken gate instead of by a plan.

**Verified rather than accepted**, because a delegated result is not evidence:
`--autoteste` passes; `--estados` still emits the TSV the harness consumes, 171
rows of 4 tab-separated columns; the report guard for too little data still
fires; the sweep finds no Portuguese left in the file. The scope entry that
deferred it was removed too, correctly, and the sweep's stale-exemption check
would have caught it if it had not been.

**One thing it did not cover:** `tools/juiz/dados/modelo.txt` still carries a
Portuguese header, because it is a committed ARTEFACT generated before the
translation. The code that writes it is already en-US (`ajusta.lua:493`), so the
header fixes itself the next time the judge is fitted, and that needs a display.

**And it exposed a gap in my sweep:** the detector only looked at `print`,
`echo` and `io.write`, so text written into a file with `handle:write(...)` was
invisible. A file this project generates and keeps is as much its surface as a
log line. Fixed, and it found 3 more deferred lines.

## item 16 follow-up: the ceiling swept four of six, and two of them were inert

The absolute life-safety ceiling reads its maxima from the schema, which is what
item 16 fixed. **The list of keys it applied them to was still written by hand,
with four entries**, and this branch ships six life options. So the "absolute
ceiling no future level can break" had not been covering `ATTENTION` or
`PART LAG` since the day they landed.

Fixed by deriving the set as well: every option offering a numeric level, minus
an explicit list of the ones that move a vertex rather than the draw matrix
(`depth`, `front_shape`, `top_dome`, `step_weight`). **The failure mode flips**:
a new option is swept unless somebody writes down why it is exempt, instead of
escaping by nobody remembering the file exists. A check asserts the swept count
never drops back below six.

**Widening the set was necessary and not sufficient, and the proof is the
interesting part.** With `ATTENTION` in the sweep, raising its top level from
1.0 to 3.5 still tripped no ceiling assertion. The reason: ATTENTION only leans
when somebody is close, and the ceiling harness never placed anyone, so the term
was multiplied by an attention that never woke up. A branch nothing exercises
looks exactly like one that works. Adding an eye at 10 units, the distance
ATTENTION's own tests use for "close", makes the ceiling bind: 3.5 now fails
`|kx| * 16 stays under 3px` and 2.0 correctly does not.

**What it still cannot bound, measured and written down so nobody assumes
otherwise:** `PART LAG` is a delay in seconds. Raising it from 0.16 to 2.0
changes when the head arrives, not how far it travels, so no amplitude
assertion reacts; PART LAG's own two tests are what fail. "Swept" does not mean
"bounded" for every option alike.

Suite went 620 to 621 checks. The shipped maxima all sit inside the ceiling with
an eye present, which is now measured rather than assumed.

## The full battery, with a baseline before it

Run on the MBP, 2026-08-10. **Two runs, and the first one is why the second
means anything.**

**Baseline first, nothing copied.** The MBP's own checkout at `857f697`, its own
code, its own battery: `BATTERY OK`, 607/607 offline, headroom 41, `REGUA OK`,
in-game 20/16/16/8/6. Without that, a red in the second run could not be told
from a machine that was already red.

The baseline also revealed the two checkouts are further apart than the commit
hashes suggested. **Headroom 41 on the MBP against 75 here**, and 607 checks
against 621: the MBP predates roadmap item 0's refactor entirely. The
bundle-and-amend workflow gives the same logical work different hashes, so
comparing revisions was never going to show that. The measured numbers did.

**Then this working state, synced over and run again:**

| Step | Result |
|---|---|
| offline suite | 621/621 |
| lint, headroom, modkit | ok, 75 free |
| option docs, runner selftest, execution state, en-US sweep, audio gate | ok, all five new gates |
| **the ruler** | **REGUA OK** |
| **in-game**: probe_life, menu, probe_draw, probe_fp, probe_grid | **20 / 16 / 16 / 8 / 6 passed, 0 failed** |
| verdict | **BATTERY OK** |

**What this answers, and it was the open question:** the five gates added to the
quick half did not disturb the ruler or the in-game gates. The in-game counts
are **identical to the baseline**, and the ruler is green with the
`native-offscreen` branch present in `conf.lua`. That branch being inert had
only been proved by dumping the config table; it is now proved by the ruler
itself, which is the instrument that would notice.

The LOVE lock survived the new neighbours too: the runner selftest takes and
releases it a dozen times immediately before the ruler asks for it, and the
ruler got it.

**The MBP was left exactly as found**, verified rather than assumed: `HEAD
857f697`, `dirty 0`, matching the state recorded before the sync. Tracked files
restored with `git checkout -- .`, and the 18 untracked paths removed from the
list captured before anything was copied, never with a blanket clean.

## The hook fix was inert for three slices, and committing is what showed it

`tools/hooks/pre-commit` was fixed earlier in this session to summarise a green
run by the SHAPE `veredito` prints instead of a hardcoded list of four step
names. The fix was real in the source and **had no effect**, because
`instala_hooks.sh` installs by `cp` and `.git/hooks/pre-commit` was still the
copy taken at 13:24, before the edit.

Nothing revealed it until the checkpoint commit actually ran the hook and it
printed four gates out of nine. Editing the source of an installed copy changes
nothing until it is reinstalled, and no gate in this repository watches for
that drift. Fixed by re-running `tools/instala_hooks.sh`; the installed hook now
reports all nine.

**Worth carrying:** the same shape exists anywhere else this project installs by
copying. A gate that lives in two places is only as current as the copy that
runs.

## Gate deltas: MEASURED, and the answer is split

Run on the MBP on 2026-08-10 with Kim's explicit authorisation, dispatched into
the GUI session because LOVE needs a window server and plain ssh has none.
Host `Kims-MacBook-Pro`, LOVE 11.5, mod rev `857f697`.

| Question | Answer |
|---|---|
| Is the target byte-deterministic? | **Yes.** native twice, sha256 identical, so bytes are a valid instrument here. |
| Does `native-offscreen` change the output? | **No. ZERO.** sha256 identical to native. |
| Does it stop the window appearing? | **No.** macOS clamped the requested -4000,-4000 to x=-280 y=60 on a 1512x982 display, leaving 40px of a 320px window visible. |

**Both halves matter and they point opposite ways.** The rendering is safe: if a
way is ever found to hide the window, the pixels will not move. But as built the
mode buys nothing, because the window still shows. `deltas.txt` records `ZERO`
for the output and spells the window result out in the same line, so nobody can
read the verdict as permission to rely on the mode.

**Nothing has been moved onto the backend, and no threshold changed.** The
window probe's control did its job: normal mode reported the window on screen at
x=596 y=391, which is what makes "on screen in both modes" a finding rather than
a machine that always reports that way.

**Next mechanism to try, since position does not work:** a separate macOS user
session, a dedicated Space, or a second display. All three are outside what a
`conf.lua` line can reach.

Re-running the measurement is one command from the repo root:

```
bash mods/voxel_characters/tools/runner/measure_delta.sh
```

It writes its own line into `deltas.txt` with the evidence attached, so the
record and the measurement cannot drift apart.

## Three defects the MBP run found, all mine

The measurement worked. Getting it to run is what exposed these.

1. **Version skew broke the lock, and the error blamed the wrong thing.** The
   MBP's `tools/tools_bin.sh` predates the reentrant lock (zero occurrences of
   `VC_TRAVA_DONO`; this machine has three). `measure_delta.sh` takes the lock
   once for the whole measurement so nothing interleaves between three renders
   about to be compared byte for byte, and on that host the parent locked out
   its own children: all three renders refused, and the log said "ANOTHER TOOL
   IS USING LOVE" while naming this script's own pid. A misleading error is
   worse than a missing one, because it sends you hunting a process that does
   not exist. Now detected, reported with the real cause, and degraded to
   per-run locking instead of failing.

2. **`--collect` was broken for every path it will ever meet.** It expanded the
   pattern with a bare `for f in $padrao`, which word-splits on spaces before
   globbing, and LOVE writes to `~/Library/Application Support/LOVE/...`. The
   pattern tore into `.../Application` and `Support/LOVE/...`, so the runner
   reported "0 collected" for three files sitting right there. It passed the
   selftest for slices because the fixture used a temp path with **no spaces**:
   the test passed by avoiding the only condition that matters. Fixed, and the
   new case fails against the old code, which is how it was proved.

3. **The evidence label was backwards.** The variable held "on screen" and the
   string said "off screen", so the first recorded line read
   `window off screen=true` when the truth was the exact opposite. A record that
   states the inverse of what happened is worse than no record. Renamed and
   rewritten to `offscreen-mode window ON SCREEN=true`.

The MBP was left exactly as found: `conf.lua` restored from a backup taken
first, `tools/runner/` removed, temporary files deleted, `git status` clean.
Nothing was committed, pushed, tagged or published on either machine.

## Assumptions logged

| Assumption | What would falsify it | Cost if wrong |
|---|---|---|
| An off-screen window does not change canvas output, because the harness renders into an FBO and encodes it | a delta run showing any pixel difference between `native` and `native-offscreen` on the same target | revert one env-var branch in `conf.lua`; nothing else depends on it |
| `t.window.x/y = -4000` is honoured by LOVE 11.5 on macOS and does not clamp back onto the display | watching a run: if the window still appears, the mode buys nothing | the mode is inert, not wrong; delete it |
| Docker is worth pursuing for the offline harness before the in-game tools | the save-path work turns out to cost more than a second macOS session would | drop the docker backend, keep `native-offscreen` and a separate user session |
| The docker backend takes the same LOVE lock as native, conservatively | measuring that a container LOVE and a host LOVE genuinely do not interfere | a serialisation we did not need, costing wall clock only |
| New tooling is named in en-US even though `tools/` is mostly Portuguese | T1.5 deciding to rename everything at once instead | three file names |
| A structural gate on the state file will not cry wolf on Kim's own edits, because it checks presence and shape and never prose | the gate firing on an edit that was fine | loosen the check that fired, or drop it; it is four independent checks, not one |
| Battery step order is still meaningful with two doc gates added before the ruler | a failure in step 5 or 7 masking something the ruler would have said first | reorder; both new steps are offline and cheap, so they can move anywhere in the fast half |

## Next actions, in order

**0. Tier 0 has nothing open that engineering can move.** T0.1, T0.3 and T0.5
are landed with gates. **T0.2's measurement is done**: output delta ZERO, window
not hidden, no gate moved onto the backend. T0.4 is `blocked-on-Kim` (K1). So
the critical path now runs through Tier 1, and the next items there split
cleanly:

| Tier 1 item | State |
|---|---|
| T1.1 lab motion preview | **landed**, both slices, verified on the MBP |
| T1.2 anchors and events | **in progress**, the next item |
| T1.3 audio gate | **landed** |
| T1.4 critic context | needs renders, and the judge's own data |
| T1.5 en-US remainder | the battery banner and filenames, both gated on a full battery |
| T1.6 release positioning | Kim's eye (K2) |

The "needs a display, so verification is impossible" framing that used to sit
here is gone: the MBP is authorised and has served as the verification host for
two full batteries, a ruler run and the T1.1 probes.

**Superseded.** That read was written before the MBP was authorised as a
verification host. Visual maths no longer has to be landed blind: T1.1 was
implemented and verified there, and T1.2 is being done the same way.

1. **T0.2 measurement: done.** `native-offscreen` renders byte-identically to
   `native` (floor established by running native twice), and it does **not**
   hide the window: macOS clamped the requested -4000,-4000 to x=-280 y=60,
   leaving 40 px of a 320 px window visible. No gate was moved onto the
   backend and no threshold changed. Full evidence in "Gate deltas" above and
   in `tools/runner/deltas.txt`.

2. **The blocker moved, it did not clear.** Hiding the window is not something
   a `conf.lua` position can do on this OS, so the next mechanism has to be one
   of these, and all three are machine configuration rather than code:

   - a separate macOS user session, driven with `launchctl asuser`;
   - a dedicated Space the runner launches into;
   - a second display, physical or virtual.

   Each needs a decision from Kim about how his machines are set up, which is
   why none of it is queued as autonomous work.

3. **The other route to a contained runner is docker, and its first step is
   display-free**: the macOS LOVE save path is hardcoded in five shell tools
   (`card.sh`, `calibra.sh`, `clip.sh`, `trailer.sh`, `juiz.sh`). One resolver
   replacing five literals. It cannot be validated without a display, because
   every one of those tools needs LOVE to exercise, so it is written down here
   rather than started blind.

4. **Full battery: done, green, with a baseline.** See "The full battery" above.
   The five new gates disturb neither the ruler nor the in-game gates.

5. **`mutantes.sh`: done, 5 of 5 killed**, after the local checkpoint commit
   `af6e803` cleaned the tree. Every gate in the definition of done now has a
   result.

6. **Escalating the measured target** from one render to `check.sh` is now
   lower value than it looked. `native-offscreen` renders identically and does
   not hide the window, so there is nothing to gain by hosting the ruler on it
   until a real hiding mechanism exists. Park it behind that.

## T1.1: the gate has teeth, and the roadmap's own gate was wrong

**Built the measuring side first, as the roadmap asks.** Three things landed,
and the preview itself is deliberately not wired yet.

**1. One definition of the host's matrix.** `tools/render/host_matrix.lua` is
pure Lua with no love and no harness context, so the offline suite and the
laboratory read the same construction. It was written out inline in the suite
before; giving the lab a second copy is how the lab would drift from what the
suite proves, invisibly, because both would stay self-consistent.

**2. The 4-rung contract now tests the lab's matrix, and rejects a wrong one.**
The existing conjugation test took the matrix as a parameter, so the same
measurement runs against the shared synthetic host and against the identity,
which is what a lab that "just draws it" would effectively use. Measured: the
identity gives **74% error at rung 15**, far past the 10% ceiling. Breaking
`host_matrix.forRung` to return identity fails **three** checks: the 4-rung
contract, the identity check, and the z-drift check at 0.1545 px against a
0.0160 ceiling.

**3. The bridge, opt-in.** The harness's `Voxel3D` stub had no `draw`, which is
the real reason the lab is blind to matrix-only options: with no draw channel
the mod's `probeCapabilities` never installs the wrap, so BREATH, SWAY, MOTION
LAG, FOOTFALL, ATTENTION and PART LAG do not exist in there at all. Added
behind `labmotion=1`, because handing every harness mode a draw channel would
change what the mod installs in every measurement this project trusts.

**Verified on the MBP, and the second check is the one that matters:**

- `REGUA OK` with the change present.
- The same render with `labmotion=1` and without is **byte-identical**
  (sha256 `69cc13b1...`), so the channel does not perturb output.
- **The wrap actually installs**: `LABMOTION: the mod wrapped Voxel3D.draw, the
  life channel is live`, and silence without the flag. That check exists because
  the byte-identical render is equally consistent with "installed and inert on a
  still frame" and with "never installed", and a bridge to nowhere looks exactly
  like a bridge.

**The roadmap's T1.1 gate was corrected in place**, because implementation
contradicted it. It asked the lab to reproduce "the world displacement the
in-game probe measures at all four camera rungs", and no such measurement
exists: `probe_life.lua` pins the camera to rung 35 and reports an envelope in
CHANGED SCREEN PIXELS. Its own published numbers give it away, 36 / 246 / 275
pixels for amplitudes 0.010 / 0.020 / 0.035, which is area-like and not even
proportional, so not even a unit-free ratio survives the comparison. Comparing
the lab against the game needs a probe that measures displacement per rung, and
that is a separate item rather than a precondition.

## T1.1 slice 2: the preview runs the mod's code, not a copy of it

**The rule the manager set, and the design that follows from it:** nothing in
the harness recomputes breath, sway, lag, footfall or attention. The laboratory
hands the mod's own wrapped `Voxel3D.draw` the shared host matrix, reads back
what came out, and draws the difference `H^-1 * M'`. Since H is a pure rotation
its inverse is exact, and a preview built this way cannot agree with itself
while disagreeing with the game.

`drawCell` gained an optional mesh-space transform applied before projecting.
Nothing sets it unless `labmotion` is on.

**The invariant that makes it safe to put on screen**, asserted offline rather
than assumed: with every life option off the mod returns `M' = H`, so the
difference is the identity and the preview cannot move a vertex it should not.
The companion check is the one that matters more, because a still preview looks
like a working feature: with BREATH on the difference must NOT be the identity.

**Measured on the MBP:**

| Run | Result |
|---|---|
| lab without the flag | `LABPROBE motion=off options=9 moved=false` |
| lab with the flag | `LABPROBE motion=on options=16 moved=true` |
| the ruler, flag present | `REGUA OK` |
| render, flag on against flag off | byte-identical |

Nine options against sixteen is the whole point: the seven that live in the draw
matrix were invisible in there and now exist.

`labquit=1` is what made any of this gateable. A laboratory that can only be
inspected by looking at it cannot be part of a battery, and "I saw it move" is
not evidence anyone can re-run.

**Two defects of my own, both found by running it:**

1. **The diagnostic printed 2799 times.** The lab reloads the mod for every mesh
   it builds, and classifying the options builds hundreds. A log that buries
   everything else is its own kind of useless. Prints once now.
2. **A mis-specified fixture, not a failing gate.** I checked "flag on, all life
   off" expecting `moved=false` and got `moved=true`. The lab initialises from
   schema DEFAULTS and ignores `opt=`, and BREATH ships ON at SUBTLE, so
   `moved=true` was correct and the test was wrong. The invariant it was
   reaching for is the offline one above, which does hold. Worth writing down:
   the answer looked like a failure and the setup was the failure.

## T1.2: anchors, measured against a body whose anatomy is ground truth

**The gate came first and failed for the right reason** (`mod._anchors is not
exposed`), then the anchors were built until it passed.

**Why a synthetic body.** On a real sheet nobody can say where the hand "should"
be, so a test written against `red.png` would assert whatever the code happened
to produce. The gate builds a 16x16 character whose anatomy is decided in the
test: head rows 1-4, torso 5-10, ARMS rows 6-7 sticking out to x=2 and x=13,
legs 11-15. Every assertion is against that construction rather than against the
output.

**Four anchors, derived from the vertices the builder actually emitted:** feet
and head at the extremes with the width that touches them, centre at the mean of
every vertex so it follows the body's mass rather than the middle of the cell,
and hand at the furthest reach from the centre line, taken on the front plane so
it sits on the surface an effect leaves from rather than inside the character's
own thickness. Each records its BAND, which is the only part identity this mesh
has, and is what lets an anchor arrive late with the part it names.

**What the gate asserts**, at all four camera rungs, with `MOTION LAG`, `SWAY`,
`BREATH`, `FOOTFALL`, `ATTENTION` and `PART LAG` all on, an eye standing close
and the character walking:

1. head and feet land on the body's real extremes, and feet < centre < head;
2. the hand is at ARM HEIGHT and at the silhouette's edge, both, since a point
   at arm height in the middle of the torso is not a hand and neither is a point
   at the edge at hip height;
3. head and feet are in DIFFERENT bands, or nothing can lag;
4. the anchors move at all while the body is alive;
5. head and feet do not move by the SAME amount, which is what proves each is
   riding its own band's matrix rather than one transform for the whole body.

**Proved the gate has teeth**, four mutations of the real derivation, each
caught with a message naming the defect:

| Mutation | What the gate said |
|---|---|
| head taken from the low end | `head anchor at y=0.0, the body's head is at 14` |
| hand parked on the centre line | `hand anchor at x=8.0, the hands are at x=2 and x=13` |
| every anchor forced into one band | `head and feet are in the same band (1), so nothing can lag` |
| anchors read without undoing the baked rotation | `head anchor at y=6.8, the body's head is at 14` |

**The last one is the bug I actually wrote.** The builder bakes `Rx(correction)`
into every vertex, which mixes y and z: the head sits at y=14, z=0 as drawn and
arrives in the vertex array at y=11.06, z=10.57. Reading anchors straight off
the vertices produced a "head" two thirds down the body and a "hand" at the
wrong height, and the caller then applied the same rotation a second time. The
anchors are computed in character space now, by undoing the bake.

**And the three built-in rejection checks are not vacuous**: making the
"head and feet swapped" fixture a no-op makes its rejection check fail, so it is
asserting something rather than passing by construction.

**Verified on the MBP**: the full battery, including the ruler and all five
in-game gates, green with the builder change present. The builder is where this
landed, so a green offline suite alone would not have been enough.

**Named limits, so nobody assumes more than was built.** Anchors exist for SLAB
only, which is the default and the mode this game wants; CARVED has its own
builder and no anchors. `hand` is the furthest reach, not an anatomical hand:
this mod has no rig, so on a sheet whose arms are tucked in that point is a
shoulder or a hip. The anchor reports its `reach` so a caller can decide whether
that is an arm. And `mod._anchors` is not a public API: the roadmap holds a
presentation API until two real consumers exist, and today there are none.

**Events are NOT in this slice.** The roadmap's list includes "projectile
fired", which is speculative while no projectile exists, and the useful ones
(footfall impact, blink closed, attention noticed) are per-INSTANCE rather than
per-mesh, so they need the draw wrap's instance state and a gate of their own.
Shipping an event system with no consumer and no measurement is the thing the
manager's own constraint rules out.

## T1.2 slice 2: three events, and only the three that already existed

**`footfall`, `blink_closed` / `blink_open`, `attention_noticed` / `attention_lost`.**
Each is an edge on state the mod was already computing, named rather than
invented:

- footfall is the STRIDE INDEX advancing, `floor(andado / LIFE_CELL)`, which is
  the instant the amplitude's cosine peaks at +1. A condition would hold for
  several frames and fire several times for one step;
- blink needed no new state at all. `applyBlinkUv` already had the transition,
  because its early return is what stops the UV swap being rewritten every
  frame. The event is that line, named;
- attention is `inst.notou` flipping, a real hysteresis with two different
  thresholds, 34 in and 46 out.

**"Projectile fired" is deliberately absent.** There is no projectile, so an
event for one would be a promise instead of a measurement. It belongs to T2.3.

**The mailbox is emptied by the READER, not the writer**, because the host draws
each character twice per frame (the water reflection) and PART LAG issues one
draw per band. Clearing on write would let the last band's silence erase the
first band's footstep.

**Four mutations, four catches:**

| Mutation | What the gate said |
|---|---|
| footfall as a condition, not an edge | `fired 15 times over 120 px, expected about 7` |
| the mailbox never emptied | `fired 791 times over 120 px` |
| blink on every mesh request | `with every source off, no event fires (1 arrived)` |
| both attention thresholds collapsed to one | `noticed at 39.5 away; the inner threshold is 34` |

**That last one only fails because the gate was rewritten after it passed.**
The first version walked the character AWAY from the eye and compared where it
noticed against where it let go. That measures the outer threshold and nothing
else, so a mod with both thresholds set to 40 sailed through. It now approaches
AND retreats, and the distance between noticing and letting go IS the
hysteresis. A gate that cannot tell hysteresis from no hysteresis was worse than
no gate, and only mutating the mod on purpose exposed it.

**Three defects found on the way, all mine:**

1. **`mod._events` collided with the suite's own field.** The mod handle already
   carries an `events` namespace and the test harness keeps registered handlers
   on `mod._events`. Renamed to `mod._animEvents`. It would have been silent in
   production and was loud only in the suite, which is where it surfaced.
2. **The driver never asked for the mesh again.** `applyBlinkUv` runs in the
   MESH PROVIDER, not in the draw wrap, and the host requests a mesh per
   character per frame. A driver that built once and then only drew could never
   see the eye change, and reported that blink does not fire.
3. **Attention swallowed its first transition.** The nil guard meant a character
   already standing next to the player when it first drew never announced that
   it noticed. The mod's own logic treats an unset instance as oblivious, so nil
   had to count as "has not noticed".

**Verified on the MBP**: full battery green, ruler and all five in-game gates,
with the wrap and the mesh-provider path both touched.

**Scope unchanged**: all three candidate events turned out to be measurable, so
`ROADMAP_V3.md` needed no correction this time.

## T2.3: the gate was blind, and rebuilding it changed the code

**The demo works and is committed. The interesting part is the two rounds it
took to be able to prove it.**

`DEMO FX: OFF / FIREBALL / BOLT`, off by default. One effect per footfall,
leaving the character's hand, drawn through the same `Voxel3D.draw` the bodies
use, reading the anchors and the footfall edge T1.2 built. FIREBALL travels and
fades over 0.55 s, BOLT flashes for 0.18 s. No save data, no battle, no link
play, no encounter. Chunk-local cost: 71 free.

**Round one measured the wrong thing.** The first gate inferred liveness from
the NUMBER OF DRAW CALLS in a frame. It could not fail: with both off-guards
deliberately defeated, the OFF run still passed. Draw-call counting confuses "no
effect exists" with "no effect was drawn on the frame I happened to sample", and
spawns are rare enough that the difference decided the answer.

**Round two counts live effects directly**, through `mod._fxVivos()`, an
internal test hook alongside `_anchors` and `_animEvents`. That removed the
sampling question, and immediately exposed something better.

**The off path had THREE guards, and that was a defect rather than safety.** The
option check, the family lookup at spawn, and a second family lookup when
retiring. Because a spawned effect stored the option's NAME and the retire pass
looked it up again, defeating one or two guards produced effects that died the
instant they were born: nothing observable changed, so the gate passed either
way. Three guards nobody can test are worth less than one that a test can break.
The effect now carries the resolved family, and the off path is a single
checkable thing.

**The bound needed a scenario that provokes it.** At walking pace a footstep
arrives every 0.53 s against a 0.55 s lifetime, so about one effect is alive at
a time and removing `FX.MAX` changes nothing. The gate now also sprints: four px
per frame puts a footstep every four frames against a 33 frame lifetime, where
without a cap eight or nine would pile up.

**Five mutations, five caught**, where the first gate caught three:

| Mutation | Round one | Round two |
|---|---|---|
| both off-guards defeated | blind | `with DEMO FX off, 2 effect(s) were alive` |
| `FX.MAX` removed | blind | caught by the sprint |
| effects never expire | caught | caught |
| spawns every frame | caught | caught |
| both families same lifetime | caught | caught |

**And the full battery caught what no offline gate could.** The in-game `menu`
driver failed with `nao esperadas: [demo_fx]` and `esperado 19 nossas`: it keeps
its own list of the rows a player should see, which is the point of it. Adding
the option to that list is part of adding the option. Nothing offline could have
told me, and the manager's rule about running the MBP when the wrap is touched
is what surfaced it.

**The SFX exist and are measured; nothing plays them yet.** See below.

## T2.3 slice 2: two real sounds, generated rather than committed

**Generated, and that was the more testable path.** Two small WAVs in the
repository could only ever be checked once, by whoever listened to them; after
that a gate can confirm the bytes are unchanged and nothing else. A generator is
code, so `fx_sfx_gate.sh` re-derives both sounds on every battery run and asks
the question that matters: are they audible, and are they inside the ceiling.
It also keeps binary blobs out of a repository whose promise is that it ships no
assets.

`tools/fx_sfx.lua` is pure Lua, no LOVE and no display. FIREBALL is noise
through a lowpass whose cutoff falls, so it reads as something leaving the hand;
BOLT is a crack with a fast decay and a high ring, so it reads as an impact. The
noise comes from a small LCG rather than `math.random`, which is what makes two
runs byte-identical and lets the gate catch a generator that has started
drifting.

| | peak | mean |
|---|---|---|
| fireball | -10.6 dBFS | -25.8 |
| bolt | -10.1 dBFS | -32.3 |
| silent control | -91.0 | |

**The first version peaked at -7.9 and -7.4**, which passes a -6 ceiling by
under two decibels. That is enough for a resample or a different encoder to push
it over, and close enough to the limit that a demo effect would sit on top of
the game's own music. Backed off to land near -10.5, still plainly audible.

**Five mutations, five caught:** a silent effect shipped as SFX, an effect made
far too loud, both families given the same sound, generation made
non-reproducible, and a "silent" control that is not silent. That last one
matters most: every other measurement is taken against it, so a control with
signal in it would quietly raise the floor and let a quiet effect pass as loud.

**One mutation was too weak and had to be redone**, which is worth recording
because it is the same shape as two earlier ones this session: seeding from
`os.time()` looked like non-determinism and was not, because both generations
happen inside the same second. Reseeding from `os.clock()` at microsecond
granularity is genuine drift, and the gate caught it.

**Runtime playback is slice 3, deliberately.** The mod has no audio subsystem,
the harness disables `love.audio` outright, and the gate the manager asked for
("on plays exactly when the FX fires, no looping spam") needs a capture path
that does not exist yet. Claiming the demo has sound today would be the
placeholder this slice was told to avoid, so the README says plainly that it is
silent for now.

**No MBP run for this slice**: nothing visual and nothing in the wrap was
touched, only tools and docs.

## T2.3 slice 3: the capture path, and a stop that was the right call

**The capture path is built. Playback is not, and stopping there was the
instruction rather than a shortfall.**

`tests/love_stub` has no audio at all, so there is nothing for the mod to call
and nothing to record. The suite installs its own `love.audio` for the duration
of the measurement: a recorder that logs every request with a timestamp instead
of making a sound. It is a MEASUREMENT DEVICE and is documented as one. It
proves what the mod ASKS for and never that a speaker moved.

**The positive control is the load-bearing part.** "Zero audio calls" is
worthless on its own, because a recorder that records nothing reports zero too.
So the recorder is handed a deliberate call first and has to see it. Proved both
ways: a recorder stripped of its logging fails the control, and a stray
`love.audio.play` added to the draw wrap is caught at **181 plays**.

**What it asserts today** is the honest contract while playback does not exist:
the mod requests no audio, with `DEMO FX` off AND on. A demo that half-plays is
worse than one that is openly silent, and the README now says the silence is
checked rather than assumed.

**Why playback stops here, and it is a decision rather than fatigue.** Runtime
playback needs sample data, and there are only two ways to get it:

1. **Duplicate the DSP inside `main.lua`.** A second copy of the algorithm that
   `tools/fx_sfx.lua` already owns. This session has removed that exact shape
   three times (the host matrix, the anchors, the FX family lookup) and putting
   one back for convenience would be the worst kind of consistency.
2. **Ship a WAV.** `.modkitignore` is an exclusion list, so a file in the mod
   directory is packaged: this would be **the mod's first shipped asset**, and
   the README's opening promise is that it ships none. The roadmap explicitly
   permits breaking that for this demo, and it also says a broken promise needs
   the five-question gate and a plain disclosure. That is Kim's call.

So slice 4 is: decide where the sound comes from, then wire playback and turn
this harness from asserting silence to asserting the full contract. The recorder
already carries timestamps, so the four questions need nothing new built:

- one play per FX spawn, and none at all when off;
- no repeat within a frame, the same doubled-draw hazard the visual gate has;
- the peak passing `audio_gate.sh`, which the generator's output already does;
- the play landing in the SAME frame as the spawn, **one sixtieth of a second
  being the declared tolerance**.

Real capture, meaning a machine with audio recording what actually comes out, is
beyond even that and is where the runner's controlled environment would earn its
keep.

**No MBP for this slice**: only the test file and docs changed.

## T2.3 slice 4: playback, and the mod's first shipped asset

**Kim's call, taken and recorded.** Two WAVs in `sfx/` are versioned and
packaged. `.modkitignore` is an exclusion list, so anything not named there
ships: these are the first files this mod distributes that are not read from the
player's own game. The README's opening promise was edited to say so where a
player reads it, rather than leaving the sentence technically true by omission.

**What stops them being an opaque blob.** `fx_sfx_gate.sh` regenerates both
sounds from `tools/fx_sfx.lua` and compares them to the packaged files byte for
byte, then runs the shipped files through `audio_gate.sh` in their own right.
Versioned audio is exactly the kind of file nobody re-examines: it arrives once,
sounds fine to whoever added it, and after that a diff can only say the bytes
changed. Proved by editing two bytes of `sfx/fireball.wav`, which the gate
rejects.

**Playback lives on the same line as the spawn**, inside the wrap, guarded by
`pcall` like every other host capability here. The source is created once per
family and the failure is remembered too, so a missing file is not retried on
every footstep. Spawn and play cannot drift apart because there is no second
code path with its own idea of when a footstep happened.

**The contract, measured:**

| Claim | How |
|---|---|
| off plays nothing | recorder sees zero sources and zero plays |
| one play per spawn | counted against `mod._fxNascidos()`, not against footfalls, because the cap can refuse a spawn |
| no spam in a frame | plays grouped by instant; the host draws each character twice |
| same frame as the effect | driver notes the clock when the spawn counter moves, recorder notes it when a sound is asked for, and the two are compared. **Tolerance 1/60 s** |
| the measured file is the played file | the play argument has to name `sfx/fireball.wav` |

**Sync is two independent observations on purpose.** Comparing a timestamp the
audio path recorded against one the audio path also supplied would assert that a
number equals itself. The spawn instant comes from the mod's counter, watched by
the driver; the play instant comes from the recorder.

**Four mutations caught:** the sound played twice per spawn, a different file
played, a hand-edited shipped WAV, and the off-guard defeated, which the audio
assertion caught as `1 source(s), 5 play(s)` alongside the visual one.

**One mutation was ineffective and had to be replaced**, the third time this
session: putting the fault inside the spawn block proves nothing, because the
block is already unreachable when the option is off. The meaningful mutation is
always the upstream guard.

**Full battery green on the MBP**, ruler and all five in-game gates, with
playback in the wrap and the assets in the package. Both were reasons the run
was required rather than optional.

**What is still not proved, and it is worth naming.** The recorder shows what
the mod ASKS for. Nothing here proves a speaker moved: that needs a machine
recording its own output, which is where the controlled runner would earn its
keep. The peak that a player would hear is the peak `audio_gate.sh` measured in
the file, which is the closest honest statement available today.

## T1.4: the palette was not the missing thing

**Research with a gate, and the gate says no. The critic is not approved to
drive anything.**

The cheapest of the three experiments the handoff proposed: give the critic the
art's tone system before it judges. Source pair 229 / 133 / black, non-front
tones at 0.91x that pair, `OBJ_SHADE` front 0.90 / back 0.68 / side 0.78 /
top 1.0 / bottom 0.55, and the fact that top, side and bottom carry 0% of the
artist's work. No per-pair hints: nothing about which options were on, because
that would be leaking the answer rather than supplying context.

```
pairs                 15
critic (with palette) 60.0%   (9 of 15)
always-commonest      53.3%   (key: 7 A, 8 B)
margin                +6.7 points
standard error        +/- 12.6 points
95% interval          35% .. 85%, which contains the baseline
degenerate reference  always A 46.7%, always B 53.3%
```

**Two findings that matter more than the number.**

**Seeing the difference did not help.** Each pair was scored for how well it
could be resolved at all, recorded before the answers were revealed: high
confidence 3/5, medium 1/2, low 5/8. If the palette were the missing knowledge,
the pairs that could be seen clearly are exactly where it should have shown up.
It did not.

**The critic answered 13 A and 2 B; Kim answered 7 A and 8 B.** The palette
rule, applied honestly, is heavily one-sided: it prefers whichever side
manufactures fewer tones on invented surface, and that lands on one side far
more often than Kim's choices do. This measured what round 2's notes suspected:
the two are answering different questions, and more context about the ART does
not close a gap that is about the PERSON.

**Method, including its weakness.** The verdicts were written and checksummed
before the answer key was fetched, so the ordering cannot be argued with
afterwards. The weakness is real: a no-context arm cannot be run cleanly by the
same critic on the same pairs, because having formed one set of judgements
contaminates the second. Round 2's 62.5% against a 62.5% baseline is the nearest
no-context reference and it is a different pair set.

**What this rules in.** Of the three cheap experiments, the only one left is the
one that adds information about the person rather than the pixels: show the
critic a pair Kim decided together with his reason. It is now the only one with
a reason to expect anything.

**No more pairs were collected and Kim was not asked**, per the contract.

**The MBP has 22 untracked files left in place**, deliberately not deleted: they
are copies of this working tree from the render run. `git clean -nd` in
`~/Projects/gen1recomp/mods/voxel_characters` lists them and `git clean -fd`
would remove them, which is Kim's call rather than something to do to somebody
else's machine automatically.

## T1.4 round 4: the experiment needs an input that does not exist

**No number this time, and that is the finding.**

The third experiment is "show the critic a pair Kim decided together with his
reason". **The reason was never recorded.** `tools/render/lab.lua:571` writes a
choice as timestamp, sheet, pose, frame, clock, camera rung, yaw, which option
was varied, its two values, the pick, and the two full option states. That is
all of it. A grep for any reason-like word across the 106 choices returns zero.
Kim pressed a key and the tool wrote which side; the why never left his head.

So the input cannot be recovered from the dataset, and the only place it exists
is Kim, whom this round's contract forbids asking. Building a result out of an
invented reason would be worse than having none.

**Held-out pairs were not the blocker.** 76 of the 106 choices were never
sampled by round 3 (`prepara 30` steps by 3, takes 30, 15 survive the drops), so
there is ample unseen material whenever there is something to test.

**The second blocker is the critic, which is me.** After round 3 it knows its
palette rule over-picks A and that Kim's picks are near even. Any improvement it
showed now could not be separated into "the exemplar taught it" and "it
corrected a bias it had just been told about". A critic that has seen a key is
spent for that key's question; round 4 needs a fresh session or a different
model.

**What was built instead**, written into `NOTAS_DO_CRITICO.md` so the next round
is turnkey: record the reason at the moment of choice, in a field that avoids
`|` because `calibra.sh:132` splits the states on it and stays optional so the
existing 106 choices keep parsing; take the exemplar from a pair whose key is
already spent, since a contaminated pair is the right thing to teach with and
the wrong thing to test on; test only on the 76 never-sampled choices;
pre-register the decision rule and checksum it before seeing any test pair;
checksum the verdicts before fetching the key; and report the margin against
always-commonest with its standard error.

**The one code change it needs was deliberately not made in that round**, and
has since been made as its own slice: see the section below. Adding a field to
the choice line touches a format that `calibra.sh` and `ajusta.lua` both parse,
so it deserved its own parser gate over the existing file. Doing it as a
footnote to a research round is how a format quietly breaks.

**The critic remains out of the loop.** Nothing in this round changes that.

## T1.5 slice 5: the display-backed output is en-US, gated statically

The sweep went from **108 deferred lines to 5**, and the five that are left are
fixture names inside `so_comentarios_test.lua`. Both directory-wide deferrals,
`tools/ingame` and `tools/render`, are deleted: the sweep's own stale-exemption
rule demanded it as soon as they stopped matching anything, which is the rule
working rather than a formality.

**The hazard here is not a red gate, it is a green empty one.** Half these gates
work by running something under LOVE and grepping its output, so the printed
text is an interface between two files that never mention each other:
`check.sh` greps "modo escolha:" and the only thing making that work is a
`print` in `lab.lua`. Rename one side and the grep matches nothing, the count is
zero, and several of these checks would simply stop measuring while still
printing a line.

So `tools/output_contract.lua` came first, as step 7f: for every gate that
greps, each prose literal it searches for must appear in the source of something
that prints. It is static, so it runs in milliseconds on every commit, which is
the point. The end-to-end proof is a full battery on a machine with a screen,
and that is far too slow to be the only thing between a rename and a dead gate.

**It was useless on its first version and the mutations are what showed it.**
The producer corpus was a whole directory, and `tools/render` contains
`check.sh`, so when `lab.lua` stopped printing "modo escolha:" the string was
still found in check.sh's own grep line. The gate was confirming that check.sh
greps what check.sh greps; four deliberate half-done renames all passed. Every
consumer is now excluded from every producer corpus, and the same four are
caught. Three more rounds of refinement followed, each from a false alarm rather
than a theory: `.` had to count as regex machinery, a run of two or more spaces
is a printf column boundary and not text, and Lua string concatenation has to be
joined back up because `driver.lua` splits `"control floor %d, mod on against "`
from `"off %d, of %d"` across a seam that only exists in the source.

**It then caught two half-done conversions in my own bulk pass**, which is
exactly what it was built for: `check.sh` still grepping `autoteste` after the
harness had started printing `selftest`, and `run.sh` left with a hybrid
`", mod on against desligado"` in a regex whose other half had moved.

**One find that predates all of this:** `run.sh` greps for `driver error`, and no
driver has printed it in some time. It sits in a `head -3` of diagnostic hints
rather than in an assertion, so it fails open, and it is recorded as an
exemption with that reasoning rather than quietly deleted.

**The verdict contract gate was inverted, not extended.** It used to require the
in-game counters to accept Portuguese as well as English, which was right while
the drivers still printed Portuguese. Once they stopped and the alternatives came
out of the greps, it found no Portuguese to check and reported "no verdict grep":
passing, and measuring nothing. It now requires every driver to PRINT an English
verdict and every counter to ACCEPT one, which is both true and stronger, since
either half alone can be satisfied by a file that has stopped working.

**`REGUA OK` / `REGUA TORTA` became `RULER OK` / `RULER CROOKED`.** Unlike the
battery banner this one really is parsed: `sala_de_teste.sh:96` compares against
the string. That pair is now checked too, along with the `runner.sh` selftest
fixture that used the old banner as a required-string case.

**`runner.sh` deliberately keeps its bilingual counter.** Narrowing it would have
broken its own selftest, which has a Portuguese fixture precisely to prove the
counter accepts both, carrying an `# en-us:` escape that says so. Tidying a file
the sweep does not even flag is not worth breaking a gate for.

**Full battery green on the MBP**, 2026-08-11: 13 offline gates, `RULER OK`, and
in-game **20/16/16/8/6 passed, 0 failed**, which is exactly the count from before
the conversion. That equality is the real evidence: if any driver's verdict word
had broken, its counter would have read zero verdicts and reported
"NO VERDICT (the driver measured nothing)" rather than a lower pass count.

**Filenames were NOT renamed, and Kim has since closed that as a decision**
rather than leaving it pending: they are `deferred-api`, not surface text. See
the section below.

## T1.5 slice 4: the banner is en-US, and the verdict lines are a contract

`BATERIA OK` / `BATERIA VERMELHA` are now `BATTERY OK` / `BATTERY RED`, and the
per-gate word `FALHOU` is `FAILED`. The internal flag and the `veredito()`
function that prints them were renamed with it, because a file printing FAILED
while its own variable is called FALHOU is the half-converted state this item
exists to close. 15 citations across three docs updated; Kim's draft untouched.

**Nothing parsed the banner**, which was checked before changing it rather than
assumed: the pre-commit hook and `release.sh` both match on the SHAPE of a
verdict line, and everything else keys on the exit code.

**But the verdict LINES are parsed, and that is where the risk was.** They are an
interface with two readers and neither is visible from the battery's source. So
`tools/verdict_gate.sh` now guards it, running as step 7e:

- the banner in both states, lifted out of `bateria.sh` and executed: `VERMELHA=0`
  must say `BATTERY OK` and exit 0, `VERMELHA=1` must say `BATTERY RED` and exit
  1. The red half matters more, because a green run never executes it;
- a passing verdict line must match the hook's pattern and `release.sh`'s, both
  LIFTED from those files rather than restated, and a FAILING line must match
  neither, or a summary would report a failure as a pass;
- the in-game verdict counters must accept English as well as Portuguese, which
  is what lets `tools/ingame` be converted one driver at a time instead of in a
  flag day;
- no Portuguese banner text left under `tools/`.

**It found a real defect on its first run.** `release.sh` summarised the battery
with `^\s+\S+\s+ok$`, which requires the gate's NAME to be a single word, so it
printed **5 of 11**: every gate called "option docs", "reason field", "audio gate
selftest", "runner selftest", "lint of assertions", "en-US sweep" or "fx sfx" was
silently dropped from the release rehearsal. The pre-commit hook had the same
class of defect, was found earlier and fixed; this second copy was missed
because nobody re-reads a summary that still prints something. Fixed to the same
pattern the hook uses.

**It also found `tools/ingame/monta.sh` grepping `FALHOU` with no English
alternative**, which slice 2 would have broken silently: a converted driver would
have produced no failure reason at all. Made bilingual before slice 2 touches
anything.

**Mutations, 6 of 6 caught:** the red banner reverting to Portuguese, a red
battery exiting 0, `verdict` losing one leading space, the hook narrowing back to
single-word names, `release.sh` widening to match failures too, and `monta.sh`
dropping the English alternative. Each was verified to fail for its own reason,
not incidentally, and all four files restored with matching checksums.

**Full battery green on the MBP**, 2026-08-11: 13 gates, `REGUA OK`, and the five
in-game drivers at 20/16/16/8/6 passed with 0 failed, which is exactly the
historical count, so the rename did not disturb the verdict counting.

**Three offline gates went red on the MBP and were NOT the change.** The tempdir
copy was missing the repo-root entries the battery reaches for: `tests/` for the
love stub, `tools/` for modkit, and `main.lua`/`baserom.gb` for the game itself.
Without `main.lua`, LOVE opened its "no game" screen and sat there at 4% CPU
producing nothing, which from outside looks exactly like a slow gate. Worth
knowing before anyone reads a machine difference as a code defect.

## T1.4 slice: a choice can carry a reason, and nothing downstream noticed

Step 1 of the round 4 protocol, done as its own slice with its own gate.

**The format.** `reason=<percent-encoded>` between the pick and the first `|`:

```
... escolha=B reason=kim%20disse%20%22o%20chato%20%7C%20le%20melhor%22 | A: ... | B: ...
```

Four constraints had to hold at once and they came from four different parsers:
`key=(%S+)` forbids spaces, the A/B split forbids a pipe, `estadoCanonico`
harvesting `key=value` forbids an equals sign of its own, and `(.*)$` on state B
forbids the end of the line entirely. Percent-encoding everything outside
`[%w%-%.~_]` satisfies all four without a rule per parser, and being an
allowlist it cannot be broken by a character a future parser cares about.

**No existing parser changed.** That was the design goal and it held: `ajusta.lua`
and `calibra.sh` are untouched apart from comments.

**Empty means the field is absent**, so a choice made without a reason is byte
for byte the line the lab has always written. Verified on real LOVE, not
inferred.

**Measured.** `tools/juiz/reason_gate.sh` runs the real `ajusta.lua --estados`
and the pair selector lifted out of `calibra.sh` over the 106 recorded choices,
then over the same choices with a hostile reason on every line, and requires
byte-identical output: **171 states, 30 pairs, 30 answer-key lines, all
unchanged**. On the MBP the ruler proved the write path end to end: a reason
containing a quote, a pipe and an equals sign came back out identical, and the
line still parsed in the judge.

**Mutations, 7 of 7 caught:** reason written raw; pipe, space and equals each
leaked through the allowlist; empty reason still emitting a field; decode never
unescaping; and one mutation of the gate itself proving that appending the field
after state B does corrupt state B, so the placement is load-bearing.

**Two gate defects found and fixed while building this**, both mine:
- the end-to-end drift check first injected a reason with a bare pipe and stayed
  green when the encoder was deliberately broken. A bare pipe is harmless, since
  the split looks for `|` followed by `A:` and backtracks past a lone one. It
  takes a reason containing `| A:` itself to hijack the split. The injected
  string was changed to that;
- the ruler's "a choice without a reason omits the field" check reported **ok**
  on a run where LOVE never started: no file, so no `reason=` in it, so the
  field was "correctly omitted". A check for the ABSENCE of something passes
  hardest when nothing happened at all. It now requires the file to exist first.

**Precision about coverage**, since overstating a gate is worse than not having
one: a single leaked character does not shift the state list, because hijacking
the split needs `|`, a space and `:` together, and `estadoCanonico` ignores
non-`key=value` junk anyway. Single-character leaks are caught by the structural
checks in `reason_gate.lua`. Neither half of the gate subsumes the other.

**Typed before the pick.** `w` in choice mode opens a one-line field, enter
stashes, escape discards, and the stash attaches to the next pick then clears.
The 106 choices exist because a choice costs two keystrokes; demanding prose
after every pick would have ended that. `labreason=<text>` stands in for the
typing so the headless gate can exercise the write path.

**Round 4 is still not runnable.** No recorded choice carries a reason yet, and
the critic that would take the test has already seen round 3's key.

## The ruler could not see the authored layer at all, and nothing said so

Found while preparing the A/B pair T2.1 and T2.4 both need. It is the most
useful thing this stretch produced, and it was invisible to every gate.

**LOVE resolves a relative path against the GAME directory.** For the real game
that is the repo root, so `mods/voxel_characters/authored/sheets/red.lua`
resolves and the mod works. For the render harness the game directory is
`tools/render`, so the same read fails. `AUTHORED REGIONS` therefore worked
perfectly in the game and did **nothing at all** in the laboratory, in every
card and in every judge pair.

**Why no gate caught it.** The suite proves the loader against a STUBBED
filesystem, which tests the loader's logic and says nothing about the path. The
authored gate reads the files with `dofile` from the repo root, where they
obviously exist. Both were green and both were answering a different question
from the one that mattered.

A one-shot probe, `authprobe=1`, asked the only question that did:

```
AUTHPROBE ... fs=MISSING  io=FOUND  mod=6 frames        (after the fix)
AUTHPROBE ... fs=MISSING                                (before)
```

**Two wrong fixes before the right one.** The probe first sat at chunk scope and
never fired, because `opts` is not parsed until `love.load`. Then the harness
tried to `love.filesystem.mount` the repo root, and LOVE 11 refuses: mount only
accepts a path inside the save directory or the source. The fix that works is a
fallback in the mod itself, reading the same relative path through plain Lua io
when LOVE cannot see it, which resolves whenever the process started from the
repo root: how every tool here is documented to run. It reads a file the mod
SHIPS, never the player's data.

**Now checked by the ruler on every run**, so it cannot regress quietly: the
ruler asserts the mod resolves all six of Ash's measured frames from inside the
harness.

**The output contract gate then caught my check.** It grepped `mod=6 frames` as
one literal, and no source contains that string, because the harness composes it
from a format and a number at runtime. The count is data, so it is matched as a
character class and asserted separately. That gate has now caught four
half-finished couplings, three of them mine.

**A note for whoever ships audio next:** `sfx` playback uses the same
`(mod.path or ".") .. "/..."` shape, so it is presumably invisible to the
harness for the same reason. It works in the game, which is where it is gated,
so nothing is broken today. It is worth knowing before somebody tries to hear an
effect in the laboratory and concludes the sound is missing.

## T2.5 the lab randomiser, and T2.2 slice 3: the three-panel card

**The randomiser proposes preset candidates the judge has never been asked
about.** Every pair the judge has seen so far varies one option at a time from a
base somebody chose by hand; the point of a randomiser is proposing looks nobody
would have typed.

Deterministic from a seed, using the same explicit LCG as `fx_sfx.lua` and never
the clock. This project has been burned by `os.time()` handing out the same seed
twice inside a second, and a set that cannot be regenerated cannot be
re-examined after it fails.

**There is no "identity preset" to exclude, and that is measured.** A first
design picked "every region at the darkest tone" as a stand-in for the
unmodified character and excluded it. That reference is arbitrary and describes
nothing in the art. The real question is whether any preset can reproduce the
original, and a preset flattens a region to ONE tone, so it could only do that
where the region already uses one. Measured:

```
red body  3 tone(s)
red feet  2 tone(s)
red hair  2 tone(s)
```

Every region uses more than one, so every candidate is a visible change and
nothing needs excluding. The gate re-measures this rather than trusting the
comment: a future sheet with a single-tone region WOULD have a candidate that
renders the character unchanged, and it should not be proposed to Kim as an
idea.

**Mutations: 4 real ones caught** (the LCG ignoring its seed, the shuffle not
shuffling, a tone index escaping the ramp, every candidate being the same one).
A fifth, removing the clamp on over-asking, is an **equivalent mutant**: the copy
loop reads past the end of a table, assigning nil creates no entry, and the
observable behaviour is identical. No gate can catch it and none should, so the
clamp is documented as readability rather than safety instead of the gate being
contorted to notice a change that is not one.

**The three-panel card** closes T2.2's last gate condition: original Ash, a
hand-chosen authored preset, and a randomised one, side by side. It refuses to
build if any two panels are byte-identical, which is the failure that matters —
if the preset path silently stopped applying, three identical characters would
look deliberate.

Built with ffmpeg rather than `card.sh`, and that is a deliberate trade: the
compositor's card mode is built around exactly two panels with its callout
layout computed from that, so making it N-panel is a refactor whose only
beneficiary is this one picture and whose risk lands on `shading.card`, a
published figure. ffmpeg is already a dependency of the clip and audio paths.

The randomised panel comes from the seed rather than a roll at build time, so
the card is reproducible: one that changed on every build could not be compared
with the one somebody looked at last week.

**One environment defect found:** `set -u` with an empty array is an unbound
variable in bash 3.2, which is what macOS ships, so the conditional argument had
to become a branch.

## T2.2 slice 2: a preset actually renders, and changes only the colour

`preset=<text>` in the harness recolours whole rows of the sheet before any mesh
is built, so every builder, metric and silhouette check downstream sees an
ordinary sheet and needs no knowledge of presets at all. **Lab and harness only**
— the roadmap puts the creator in the laboratory, not in the game, and nothing
in the shipped mod reads a preset.

**Two of this item's four gate conditions are now measured rather than argued.**

*"The composed character passes the same silhouette and provenance checks as a
runtime one."* A preset only ever writes a new colour into an already-opaque
pixel, so the opaque set cannot move — but this project has been wrong about a
"cannot" before, so the ruler measures it:

```
o preset recolore sem mexer na silhueta    alpha_diff=0 colour_diff=3530
```

Zero alpha differences and three and a half thousand colour differences. Zero of
both would mean the preset did nothing, which is the empty green the check is
shaped to refuse. Provenance is unchanged too: `art 100.0%  auth 0.0%` with the
preset on, because a recolour adds no faces and ships no pixels.

*"A preset round-trips: serialise, reload, and render the same card byte for
byte."* The text goes through `parse` and `serialise`, and the render from the
round-tripped text is byte-identical to the render from the original.

**`head` is refused, not approximated.** Slice 2 of T2.1 declined to measure the
head-and-shoulder line because it does not resolve from the side view. So a
preset naming `head` is turned away here with that reason rather than given a
guessed boundary: the format can express it, this sheet cannot place it, and
inventing a row would put a made-up number back into the one path built to avoid
them. Regions that ARE measured — hair, body, feet — apply from the measured
bounds.

**The PNG reader refused LOVE's own output, and that was half right.** The
silhouette check first reported `UNREADABLE ... colour type 3`, because LOVE
writes indexed PNGs and the reader handled RGBA only. Refusing loudly was
correct; staying refused was not. It now handles palette and RGB as well, and
still refuses anything it cannot decode honestly.

**Still open on this item:** the three-panel card, original against an authored
preset against a randomised one. It needs the randomiser, which is being built
in parallel.

## T2.2 slice 1: the preset format, and the measurement that shaped it

**The measurement came first and it decided the design.**
`tools/measure_regions.py --palette` over every sheet the game has:

```
distinct tone ramps across 67 sheet(s):
  67 sheet(s)  #000000 #555555 #aaaaaa
```

Sixty-seven sheets, one ramp, three values. Not "mostly" and not "a family of
similar palettes": the same three bytes on every character, which is what a Game
Boy four-shade palette looks like once the lightest shade is the transparent
background.

**That settles the critic's objection, against the obvious design.** Reviewing
this art the critic argued it has a coherent tone system that an arbitrary hue
picker manufactures tones outside of. A colour wheel in a creator would do
exactly that: every colour it can produce except three is outside the system
every character in the game shares.

So **a preset does not choose colours.** It chooses, per region, WHICH of the
three existing tones that region uses. Ash's cap can become the tone his shirt
already is; it cannot become a tone this game has never shown, because the
format has no way to say so.

**The roadmap's gate is answerable more strongly than it was asked.** It wanted
palette choices "proven by rendering the extremes rather than by argument",
which assumes a continuous space worth sampling. The constrained format makes it
finite: every subset of four regions over three tones is **255 presets**, and
the gate enumerates and round-trips all of them rather than picking extremes.

**Serialisation is one pasteable line**, `preset1 sheet=red head=3 body=1`,
because it has to survive a Discord message and being typed back by hand. A
version prefix comes first so a future format change is recognised rather than
mis-parsed, which is the failure that makes people abandon a text format. The
region order is fixed rather than `pairs()`, or the same preset could serialise
two ways and "the same card byte for byte" would be a promise the format cannot
keep.

**Two surfaces are refused separately**, because they fail differently: a bad
TABLE is a programming error, and bad TEXT is what arrives when somebody pastes
a preset out of a chat window. 14 refusals in total, each with a reason, and a
positive control on both so the validator cannot pass by refusing everything.

**The ramp in the code is re-measured against the art on every run.** `preset.lua`
carries the three tones as data so the mod never has to read the player's cache
to know what a preset means, and a copy can drift; the gate re-runs the palette
measurement and fails if it has. It also fails if the sheets ever stop sharing
ONE ramp, because then a preset would mean a different colour depending on who
wore it, and that needs rethinking rather than patching.

**Mutations, 5 of 5 caught:** accepting a tone index above the ramp, the code
ramp drifting from the art, serialise abandoning its fixed order, unknown
regions ignored instead of refused, and the version prefix going unchecked.

**Not done, deliberately:** nothing renders a preset yet, nothing in the mod
reads one, there is no creator UI and no save data. The roadmap's remaining two
conditions for this item, the composed character passing the same silhouette and
provenance checks and the three-way comparison card, need a display and come
next.

## T2.1 slice 3: the measured regions now cut PART LAG, behind an OFF switch

`AUTHORED REGIONS`, levels OFF and ON, **default OFF**. It changes nothing on
its own: it only alters WHERE `PART LAG` divides the body. Off, the body is four
equal slices of the CELL, exactly as before. On, and only for a sheet shipping
measured metadata, it is divided along the FIGURE, and the feet band begins
where the legs actually part.

This is the first option whose behaviour depends on material shipped WITH the
mod rather than derived from the player's ROM. It still ships **zero pixels**;
what it ships is a description of where the parts are.

**The defect it addresses, restated as the number slice 2 measured.** A walking
frame sits a row lower in its cell than a standing one, and the old rule divides
the cell, so every boundary lands a row up the body mid-stride. On the synthetic
figure the gate uses, which starts a quarter of the way down its cell, the cell
rule spends its **entire first band on empty space**: a quarter of PART LAG's
range delaying nothing at all.

**What the gate proves**, and each part is a way the slice could have been
hollow:

1. with the option off the band ranges are exactly what they always were;
2. with it on the quads MOVE between bands, so the option is not an internal
   path with no output;
3. the cell rule leaves the head band empty and the region rule does not, which
   is the defect and its fix stated as two numbers;
4. **toggling on an already-built sprite rebuilds it.** Its own check, because
   every other measurement builds a fresh handle and would pass on a cache key
   that ignored the option. That is the v1.4.0 defect Colonel_Aureliano
   reported: touching the menu changes nothing until something evicts the mesh;
5. an OBJECT sheet is refused even carrying well-formed measurements;
6. impossible bounds fall back to the cell rather than being used.

**Two gate gaps, found by mutation and closed.** Dropping the option from the
cache key passed, because nothing built the same sprite twice. And breaking the
foot-split snap passed, because it left the feet band EMPTY, and empty is
smaller than the cell rule's band, which is what the check was comparing. Both
now covered; 5 of 5 runtime mutations caught.

**Slice 1's byte-identical assertion expired loudly, as designed.** It asserted
`main.lua` never mentioned the authored layer, which made "off changes nothing"
true by construction. Slice 3 wired the layer in, so the gate failed with its own
replacement instructions rather than silently going along with it. What replaces
it: the authored path must have **exactly one entry point**, the option must
default to its first level, that level must be OFF, and the loader must require
`kind == "living"`. The byte-identical evidence itself lives where it can: the
suite compares band ranges with the option off, and the ruler renders the whole
battery.

**Objects are refused twice, in two different places, on purpose.** The schema
governs the DATA and the loader governs what the runtime does with a sheet that
got past it. The second is the one that would actually animate an item ball.

**Cost:** two chunk locals, leaving 69 of 200 free.

## T2.1 slice 2: Ash's regions are measured, and the numbers have a gate

Slice 1 named the regions and refused to say where they were, because pixel
bounds written before anything can check them are invented numbers.
`tools/measure_regions.py` is the thing that can check them. It decodes the PNG
itself with zlib and the standard library, so it runs offline on every commit as
battery step 7h; the sprite is the source of truth and a number in a data file
is only ever a copy of it.

**Two findings came out of measuring, and both are worth more than the numbers.**

**The walking frames sit ONE ROW LOWER than the standing frames.** That is the
sprite's own bob, and it matters here more than anywhere: `PART LAG` cuts the
body into bands with `math.floor(y / cellH * REGION_BANDS)`, measured from the
CELL and not from the figure. Every band boundary therefore lands one row too
high on every walking frame. This slice does not fix that. It puts a number on
the exact reason the roadmap wants authored regions at all.

**Ash has no bag, and its absence is a finding rather than an omission.** The
roadmap's motivating example for this whole item is letting `PART LAG` "cut
along a bag strap instead" of in equal bands. On this sheet there is no strap to
cut along: the front and side views show none, and the back views have a
mid-tone block across the shoulders that could be a pack or could be the back of
his shirt, with nothing at sixteen pixels square deciding between them. So `bag`
is not declared. Guessing bounds would put an invented number in the one file
whose whole purpose is that its numbers are measured, and the narrower claim
reverses easily: if Kim says the block is a pack, it becomes a region with his
word recorded as the source.

**What is measured, and the list is short on purpose.** Only facts that follow
from the pixels without interpreting a shape: the opaque bounding box, the run
of rows from the top with no light tone in them, the lowest row whose silhouette
is two separated runs, and the bob. `footSplit` is `nil` on two frames and that
is a measurement rather than a gap: the side standing pose has both feet
together and the back walking pose shows one foot.

**One field was renamed for honesty mid-slice.** It began as `capBottom`. From
the front the light tone is Ash's face, so the rows above it really are the cap
crown; from behind there is no face, so the same measurement runs down to his
hands, and frames 1 and 4 report 5 and 6, neither of which is a cap. The field
is now `lightFreeBottom`, named for what it measures rather than what it means,
and a separate `hairFrames` list says where it may be read as hair.

**That list had a hole, and the mutation found it.** Claiming the back frame as
cap passed, because the schema only checked that the frame had been measured at
all. The discriminator turned out to be measurable rather than a judgement: from
the front the first light pixels are a FACE and sit in the central half of the
cell, and from behind they are HANDS at the edges. `capReadable` asks exactly
that, and claiming frame 1 now fails with the reason.

**The measurement then corrected my own eyeball call.** `hairFrames` was written
as the two front frames from reading the sprite by hand. The measurement says
the two SIDE frames resolve too, because the face in profile still lands inside
the middle. Widened to follow the evidence rather than my first reading.

**Mutations, 5 of 5 caught:** the walk bob hand-edited away, one cap bound nudged
by a single row, a foot split invented where the feet are together, the whole
measured block removed, and the back frame claimed as cap. The schema's refusal
list grew from 11 to 20, every new one a shape a hand edit makes.

**modkit caught something worth keeping.** `red.lua` ships, and it named the
player's imported sprite cache in a comment; MK301 refuses any shipped Lua that
points at that tree, and it is right to. The comment now names the tool, which
is where the path belongs, because the tool does not ship and the data does.

**The bob finding is PINNED, not just written down.** `authored_gate.lua` now
asserts two things together: that the PART LAG band rule still divides by
`cellH`, and that the sheet's largest measured bob is still 1. Both have to hold
for the number in these write-ups to mean anything. Fixing PART LAG to cut from
the figure makes the first assertion fail, which is correct: the finding is then
retired on purpose by editing the gate, rather than quietly outliving the defect
it describes. Both halves were mutation-tested.

**Nothing changed in the render path.** No runtime integration, no overlay
pixels, no lab preset, no save data, no gameplay. The authored pixel count is
still zero and `main.lua` still does not open the directory, so the
byte-identical guarantee is unchanged and still asserted the same way.

## T2.1 slice 1: the authored layer exists as a schema and ships no pixels

The narrowest useful slice of the item whose risk is identity rather than
engineering. **Nothing in the mod reads any of it**, which is deliberate: the
shape of the data and the rules it must obey are settled and gated before a
single authored pixel is drawn.

**What landed.**

- `authored/schema.lua` — the schema and its validator. Three provenance
  classes named (`artist`, `invented`, `authored`), five fixed region names,
  three overlay types, and a hard rule that living metadata is refused on an
  object sheet.
- `authored/sheets/red.lua` — Ash, the living fixture. Regions **named and
  deliberately not measured**: writing pixel bounds now would be inventing
  numbers before anything can check them. Ships zero pixels.
- `authored/sheets/poke_ball.lua` — the object fixture, which exists to be
  refused.
- `tools/authored_gate.lua` — battery step 7g.
- `docs/DISCLOSURE_DRAFT.md` — the release-note text, written while the honest
  answer is still "nothing", which is much easier than writing it later.
- The harness provenance report **splits three ways** now, printing `auth%` on
  every line even though it is 0.0% everywhere.

**Why `auth%` prints while it is always zero.** A number that appears only once
it is non-zero teaches nobody to look for it, and the release that ships the
first authored texel is exactly the release where somebody should already know
where to look. The gate fails the battery if the count is anything but zero, so
the claim cannot quietly stop being true; making it stop being true requires
editing that gate on purpose, and that edit is the moment the disclosure gets
rewritten.

**The object fixture has real teeth, not a comment's worth.** Its `kind` is
cross-checked against `STILL_OBJECTS` in the mod's own source, which is where
the runtime already decides what is alive. Two places disagreeing about whether
an item ball breathes is how an item ball ends up breathing, and this project
has the precedent: `boulder`, `clipboard`, `fossil`, `old_amber`, `paper`,
`poke_ball` and `pokedex` are pinned to zero life by hand because a general rule
once made them pulse. Deleting `poke_ball` from that list turns this gate red.

**Byte-identical, in its strongest available form.** The usual way to prove an
off path changes nothing is to render both ways and compare. Here the runtime
does not open the directory at all, and the gate asserts that by searching
`main.lua` for the word. When that stops being true the assertion fails with a
message saying it must be replaced by a real authored-off render comparison,
rather than passing on an argument that has expired.

**Mutations, 6 of 6 caught:** the item ball declaring itself alive, Ash starting
to ship 12 authored pixels, the object rule going unenforced, unknown fields
being ignored instead of refused, the runtime dropping `poke_ball` from
`STILL_OBJECTS`, and the runtime starting to reference `authored/`. The first
attempt at the fifth was a bad mutation whose pattern did not match the real
line; re-run correctly, it was caught.

**Assumptions logged, both reversible.**

1. **`authored/` ships in the package.** modkit accepts it. Excluding it now
   would mean remembering to un-exclude it later, which is a trap; and shipping
   it means the package itself carries the honest "zero authored pixels"
   declaration. Reversible with one line in `.modkitignore`.
2. **Regions are named, not measured.** The honest first version says WHICH
   regions a sheet has, which the schema can validate, and leaves WHERE they are
   to the slice that can measure them against the real sprite.

**What this slice deliberately did not do:** no overlay pixels, no runtime
integration, no lab preset UI, no save data, no gameplay, battle, link or
encounter changes, no art pack. Those are later slices and most of them need
Kim's eye first.

## Filenames stay Portuguese: decided, and closed

**Kim's decision, 2026-08-11: do not rename them.** They are `deferred-api`, not
remaining surface text, and T1.5 is finished rather than partly done.

`bateria.sh`, `folga_locais.sh`, `mutantes.sh`, `sala_de_teste.sh`,
`instala_hooks.sh`, `so_comentarios.sh`, `juiz/`, `ajusta.lua`, `calibra.sh`,
`gera.sh`, `rodada.sh`, `monta.sh`, `dados/escolhas.txt` and
`Laboratorio.command` are command-line keys by the definition already written
into `en_us_scope.txt`: "option values and command-line keys that a rename would
break for anyone with a script or a saved command."

They are typed by hand, pasted into Discord, quoted in release notes that are
already published, written into this file as reproduction commands, and saved in
shell history and in the MBP notes. A rename lands cleanly in git and breaks
every one of those the moment somebody re-runs an old command.

**Nothing is pending on this.** No deprecation shims, no forwarding scripts, no
follow-up item. A contributor reads `bateria.sh` and learns one word, which is
cheaper than a migration nobody asked for.

## The next implementable item

**T2.1, the authored character layer**, started here as a narrow data-and-gate
slice. It is the architectural door both the creator tooling and richer FX walk
through, and everything above it is now landed or decided.

**Blocked on Kim, and not workable around:**

- **A calibration session with reasons.** The field exists and is gated; what it
  does not have is data. Round 4 of T1.4 cannot run on zero annotated choices,
  and inventing them would be worse than having none. The session is cheap: open
  the lab in choice mode, keep picking at the usual two keystrokes, and press `w`
  only on the pairs where the reason comes easily. Twenty annotated choices out
  of a normal session is plenty, and they need be neither consecutive nor
  eloquent.
- **A critic that has not seen round 3's answer key.** Even with reasons
  recorded, the critic that would sit the test already knows its palette rule
  over-picks A and that Kim's picks are near even. Any improvement could not be
  separated into "the exemplar taught it" and "it corrected a bias it was just
  told about". Needs a fresh session or a different model.

Those two are the WHOLE of what blocks T1.4 round 4. The code side is done.

**Closed, so nobody reopens them:** T1.5 is finished, with Portuguese tool
filenames kept deliberately as `deferred-api`; T1.2 landed both slices; T2.3
landed all four.

**Out of reach for any amount of autonomous work**, unchanged: K1 to K5 in the
table above, and hiding the runner's window, which needs a separate macOS user
session, a Space, or a second display. Those are decisions about credentials,
taste and machine setup.

An earlier version of this section argued for doing T1.2 BEFORE T1.1, on the
grounds that anchors are read-only geometry while the synthetic matrix is a
larger claim. Kim overruled it and the order he chose turned out to be the right
one: T1.1's matrix is what lets an anchor be checked while the body is actually
moving, and without it the anchor gate could only ever have measured a still
pose. Kept because a reversed call is worth more written down than quietly
deleted.

## Commands

```
bash mods/voxel_characters/tools/bateria.sh --rapido        offline half, includes both new gates
luajit mods/voxel_characters/tools/options_documented.lua   T0.1 gate alone
bash mods/voxel_characters/tools/runner/runner.sh probe      what can run here
bash mods/voxel_characters/tools/runner/runner.sh selftest   does the runner fail when it should
bash mods/voxel_characters/tools/runner/runner.sh run native-offscreen \
  --label ruler --verdict 'REGUA OK' -- "bash mods/voxel_characters/tools/render/check.sh"
```

The last one is the shape of a real controlled run, and it is still the right
next escalation: one render has answered ZERO, the ruler has not. It needs a
display, and running `native-offscreen` buys nothing over `native` until the
window can actually be hidden, so there is no reason to prefer it yet.

---

# Roadmap V2 execution

Durable state for autonomous execution of `ROADMAP_V2.md`. History from here
down.

**Started 2026-08-10. CLOSED the same day: 24 of 27 roadmap items.** Branch
`vida-v2`, 100 commits since v1.6.0, nothing pushed.

## Final state

```
620/620 offline · REGUA OK (20 checks) · BATTERY OK on every in-game gate
MUTANTES 5/5 · chunk-local headroom 74 of 200 · working tree clean
```

**Open, and none of it is unfinished work:**

| Item | Why it is open |
|---|---|
| 3. Release identity | Needs a PAT only Kim can create. `release.sh` is built and rehearsed. |
| 12. Battle probe | Kim paused it. |
| 20. Generator loop | BUILT. Its critic does not pass its own calibration gate, which is the gate working. |

**Two new player-facing options, both OFF by default:** `PART LAG` and
`ATTENTION`. Neither changes anything for a player who does not opt in.

## The two constraints that shape all scheduling

1. **LOVE is exclusive per machine.** `tools/tools_bin.sh` holds a lock, so only
   one tool per machine can render at a time. Two workstreams that both need
   LOVE must be on different machines, or serialised.
2. **A file has one owner at a time.** Isolated file scope is what made three
   parallel batches land with zero conflicts before. Every dispatch says
   explicitly what it may NOT touch.

## Compute pool

| Resource | Has LOVE | Used for |
|---|---|---|
| Mac Studio (this session) | yes | orchestration, LOVE work, integration |
| MacBook Pro (`ssh mbp`) | yes | second LOVE workstream, full battery |
| Subagents (Studio) | no | text-only work: translation, tests, scripts |
| `codex`, `gemini` CLI | no | independent review, second opinion |

MBP dispatch goes through the GUI session (`osascript` into Terminal), never
plain ssh: the CLI keeps credentials in the login Keychain and an ssh session
cannot unlock it. Symptom is "OAuth session expired", which is not an expired
token.

## The judge works now (2026-08-10, late)

Kim made 106 choices. The loop that followed is the clearest example in this
repository of why using a tool beats reviewing it:

| step | model | best column | margin | spread |
|---|---|---|---|---|
| as built | 73.7% | 63.2% | +10.5 | not measured |
| composition by AREA not quad count | 73.6% | 70.6% | +3.0 | 6.4 |
| plus four tonal features | **78.7%** | 69.6% | **+9.1** | **4.0** |

The first row was the model leaning on an artefact: composition features were
fractions of QUAD COUNT, so FRONT SHAPE inflated them by splitting runs without
moving a vertex. Fixing it did not make the model worse, it made the baseline
honest.

The middle row was measured with cross validation replacing a 19-sample
holdout whose learning curve swung 26 points on its own. That change is what
made the third row provable rather than hopeful.

**What it says, over 45 sheets, comparing best against worst inside each
sheet:** `top_edge on` (8), `blink on` (7), `front_shape 0.22` (6),
`top_dome 0.15` (4), `slab over carved_plus` (4). FRONT SHAPE and TOP DOME both
ship OFF. `depth`, `ground_shade` and `side_color` win in both directions,
which is the model saying it depends on the character.

## Blocked on Kim, not worked around

| Item | What is needed | Why nobody else can |
|---|---|---|
| 1. Feed the judge | 30 A/B picks | It is his preference. That is the whole input. |
| 3. Release identity | PAT for `last-swagger` | Credential. `release_check.sh` is red on purpose. |
| Visual judgement | His eye on FOOTFALL, CAMERA FIT, FRONT SHAPE, TOP DOME, STEP WEIGHT | Taste, and he is the one who ships it. |

Everything else in the roadmap is executable without him.

## Workstreams

| # | Item | Owner | State | Evidence |
|---|---|---|---|---|
| A | 19. Split the harness | MBP | **landed** 1b50c21 | ruler output identical on all 31 lines except the one the floor showed varies |
| B | 2. en-US, `main.lua` | subagent | **landed** f9d9c6b | comments-only gate, 603/603, volume +2% |
| C | 2. en-US, tests | subagent | **landed** a13408e | comments-only gate proves every test name byte identical |
| D | 2. en-US, in-game drivers | subagent | **landed** c59d82f | gate on all ten, volume +4 to +8% |
| E | 14/18. mutants, battery, hooks | this session | **landed** 3e59cee | battery caught a flaky gate on its first run |
| F | 13. Wind and weather | subagent | **closed** 6d001e0 | nothing publishes weather; verified in host source |
| G | Adversarial review | subagent + codex | **findings fixed** 6c1d4db | 2 blocking, both reproduced, both fixed |
| H | 24. Menu gate was flaky | this session | **landed** b5438b1 | failed 3 of 5, now 4 of 4 with 2-4x margin |
| I | 4. Trailer: time of day | this session | verifying | day vs night measured at 14 dB PSNR |
| J | 2. en-US, `tools/` | MBP | **nearly done** | ruler output identical after translating the ruler itself |
| K | 16. MOTION LAG direction | subagent | **landed** e6e7913 | the surviving mutant now dies; 603 -> 607 |
| L | 24. First-person gate | this session | **landed** ee70241 | discarded on blends but not on its own floor |
| M | 21.1 release.sh | this session | **landed** bb49937 | rehearsed end to end; refuses without a changelog section |

## Three gates were intermittent, and the battery is what exposed all three

None of them had ever been caught, because each was run by hand, and a human
who sees a red re-runs it. A green rerun ends the investigation.

| Gate | Failure rate | Cause | Fix |
|---|---|---|---|
| menu M8 | 3 of 5 | measured PHASE: two photographs a fixed 46 frames apart, so the number depended on where in the breathing cycle they landed | sweep a full period, keep the largest difference |
| probe_fp P4 | 2 of 4 | used a sample whose own control floor was half the frame, so the signal was that movement plus the option | discard a sample whose floor exceeds 5% |
| (both) | | thresholds were NOT lowered in either case | the number was never the problem |

**And in both cases the fix was verified by measuring again, four runs each,
not by running it once and seeing green.** probe_fp's discard was additionally
proved by forcing its limit to -1 and confirming every sample is dropped with
the right message: a branch nothing exercises looks exactly like one that
works.

## Roadmap items closed or advanced, 2026-08-10

| Item | Was | Now |
|---|---|---|
| 2. en-US | not started, ~3900 lines | `main.lua`, tests, in-game drivers, harness modules done. Remaining: shell scripts and `tools/juiz`, in flight. |
| 4. Trailer | 6/10, four things missing | Two landed and both cost one line: time of day per shot, camera movement within a shot. Two remain. |
| 13. Weather | "depends on mods we do not control" | **Closed.** Nothing publishes weather; the host says so in its own changelog. |
| 14. Mutation testing | "worth a script" | **Built, and its first run found a hole in the suite.** |
| 18. Battery skill/hook | seven commands to remember | **One command**, plus a pre-commit hook. |
| 19. Split the harness | 2723 lines, six jobs | **1415 lines**, graded by output equality against a measured floor. |
| 21.1 release.sh | missing | **Built**, rehearsal by default. Publishing still blocked on the token. |
| 24. Flaky gates | one known instance | **Second instance found and fixed**; the menu gate was measuring phase. |
| 26. Explainer card | did not exist | **Built**, four ruler checks, two blocking defects found by review and fixed. |

## What is still open, and why

- **1 and 3 are Kim's**, and nothing here can substitute: thirty A/B picks and a
  personal access token.
- **9, 10, 11** are visual changes. They need his eye before they mean
  anything, and the house rule is that a new visual change ships off by default
  anyway.
- **0** is measured and gated at 41 locals of headroom. Not urgent, and the
  gate will say so the day it becomes urgent.
- **16** turned out to be mostly covered: there is an absolute safety ceiling
  that sweeps every life option at maximum and requires no term to exceed 3
  pixels of world. The remaining hole is that the ceiling test writes those
  maxima by hand instead of reading them from the mod's own OPTIONS table, so a
  new, stronger level would not be covered by it.

## The pattern worth carrying forward

**Every defect found today was found by running something against real input,
not by review of the idea.** The comment gate looked right three times and was
wrong three times. The battery found a flaky gate on its first full run that
months of running the pieces by hand had not, because a human who sees a red
re-runs it and a green rerun ends the investigation.

**Independent review earned its cost twice.** A different model family
(codex) found a false pass in the comment gate that nineteen of my own
adversarial cases missed. A Claude reviewer found two blocking defects in the
card tool, both with a reproduction, both in the artefact that goes into
release notes.

**And an agent following the documented command literally found the worst
defect of the day**: the comment gate exited 0 without comparing a byte when
given the path spelling the docs used.

## What landed

- **26. Explainer card** (4c5ecc7): `mode=card` plus `card.sh` and a recipe.
  Refuses identical halves. Four ruler checks.
- **26b. Neighbour AO** (593bafc): measured and closed. Zero pixels head on.
- **14/18. Battery, mutants, comment gate** (3e59cee): one command for the
  battery in the order that makes a failure mean something, five declared
  mutants, a pre-commit hook.
- **The comment gate, twice fixed** (6d001e0, f1ec189). Both fixes matter more
  than the tool: see below.
- **13. Weather** (6d001e0): investigated, closed. Nothing publishes weather,
  and the host says so in its own changelog. Time of day IS settable, which
  turns item 4's "variety in time of day" into one call.

## Two defects found in my own gate, in the order they matter

1. **False PASS on a bare CR.** LuaJIT accepts a lone `\r` as a line break; the
   comment stripper only looked for `\n`, so a comment swallowed the next line
   of real code and two files with different code compared equal. Found by an
   independent review (codex) after nineteen hand-written adversarial cases
   missed it. Different model, different blind spot: worth repeating.
2. **False ALARM on every real translation.** It compared line k to line k,
   which assumed a translation preserves line count. It does not. Against the
   real in-progress translation it reported 2697 changed lines, all of them the
   same code one row lower. **This is the worse of the two**: a gate that
   misses something gets found out; a gate that cries wolf on correct input
   gets waived by the second day and is not there when it matters.

Both are permanent test cases now, 27/27. And the lesson that produced the
second one: the nineteen invented cases were all one line long, which is
exactly why every one of them passed.

## Also learned, and it cost time three times today

**The offline suite only runs from the repo root**, because its
`require("tests.love_stub")` resolves against the current directory. From
anywhere else it dies without counting a check, and `tail -1` reduces that to a
hex address that says nothing. `mutantes.sh` invoked it with no `cd`, which
would have reported every mutant as killed: the report claiming the tests are
perfect at the exact moment it measured nothing. Fixed in both tools and
verified from a foreign directory. **The real fix belongs in the test file**
(resolve the stub relative to `arg[0]`), and is queued behind workstream C.

## Decisions taken without asking

- **Item 2 starts with `main.lua` and the tests, not the harness**, because
  workstream A is rewriting the harness and two owners on one file is the one
  thing that reliably produces conflicts. The roadmap already recommended this
  order for a different reason.
- **A comments-only diff is verified mechanically, not by review.**
  `tools/so_comentarios.lua` strips comments and string literals from both
  sides and requires the remainder to be byte identical. A translation that
  touches code fails the gate rather than depending on someone noticing.
- **The harness split is graded by output equality, not by structure.** The
  ruler's 19 result lines before and after must match. A split that is tidy and
  changes a number is a regression.

## Assumptions logged

- The MBP's git identity is fixed, but commits arriving from it are still
  amended to `last-swagger` before being kept, because old commits are not.
- Nothing is pushed, tagged or released. Local commits on `vida-v2` are routine
  and are what every workstream produces.
