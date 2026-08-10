# Controlled visual runner

Roadmap `T0.2`. A way to run the visual tools without them taking the screen
away from whoever is using the machine, and without pretending that a different
renderer measures the same thing.

**Slice 1 status: the runner exists and is gated by its own selftest. No
backend other than `native` has had its delta measured, so nothing here is
allowed to stand in for a native threshold yet.**

## Why

The visual tools are useful partly because they are visible: they film the real
game, drive real menus, and make a bad state obvious. The cost is that a batch
of them turns the machine into a slideshow of LOVE windows, and that is not
only annoying:

- An occluded window with vsync on stalls the whole `love.run` loop, measured at
  5 frames in 90 seconds (`docs/TRAPS.md`). It reads exactly like "stuck at the
  launcher".
- "Rerun it, I was using the machine" is a result that cannot be compared to
  anything, and reruns are how intermittency hides.
- `screencapture` on a shared machine grabs whatever is in front, which twice
  grabbed a personal conversation (`docs/TRAPS.md`).

## Commands

```
bash mods/voxel_characters/tools/runner/runner.sh probe [backend]
bash mods/voxel_characters/tools/runner/runner.sh selftest
bash mods/voxel_characters/tools/runner/runner.sh run <backend> [opts] -- "<command string>"
```

`probe` says what can run here and what is missing, with the next action for
anything unusable. It exits non-zero only when you name a specific backend that
is unusable.

`selftest` needs no display, no LOVE and no docker. It is a battery step.

`run` options:

| Option | Meaning |
|---|---|
| `--label <name>` | names the run directory |
| `--verdict <erx>` | extended regex that must appear in the output |
| `--collect <glob>` | copy matches into `<rundir>/artifacts` after the run, repeatable |
| `--expect-artifacts <n>` | fail if fewer than n files were collected |
| `--allow-no-verdict` | for wrapping something that legitimately prints nothing |

### The command after `--` is exactly one string

It is handed to `sh -c` as written. More than one argument is **refused**, not
joined, and the refusal happens before anything is created or executed.

```
right:  -- "bash -c 'echo TESTE PASSOU'"
wrong:  -- bash -c 'echo TESTE PASSOU'
```

The wrong form used to be accepted and silently ran the wrong command. `$*`
flattens the argument vector, `sh -c` splits it again on whitespace, and the
quoting is gone by then: that example became `bash -c echo` with `TESTE` as
`$0` and `PASSOU` as `$1`, printing one empty line into a 1-byte `stdout.log`.
`meta.txt` recorded the flattened string, so the record of what ran was wrong
in the same way the run was.

Some multi-argument forms survive the flattening by luck, which is what makes
it dangerous rather than merely broken. A wrapper whose whole job is refusing
empty green cannot run a different command than the one it recorded, so the
contract is explicit and violating it is a usage error. The refusal prints the
correctly requoted command, ready to copy.

## Output directory

Every run gets its own directory, outside the repository so it can never dirty
the working tree (`release.sh` refuses a dirty tree):

```
${VC_RUNS:-/tmp/vc-runs}/<YYYYmmdd-HHMMSS>-<label>/
  meta.txt        backend, delta state, host, mod revision, cwd, command
  stdout.log      everything the command printed
  verdict.txt     what the runner concluded and why
  artifacts/      whatever --collect gathered
```

`meta.txt` records the backend and its delta state on purpose. A number found
in a log six weeks later is worthless if nobody can say which renderer produced
it.

## Backends

| Backend | Available | Delta vs native | Good for |
|---|---|---|---|
| `native` | yes, needs LOVE | reference | anything, including thresholds |
| `native-offscreen` | yes, needs LOVE | **ZERO on output**, measured | nothing extra yet: it does not hide the window |
| `docker` | image not built | **UNMEASURED** | nothing yet, see below |

**`native-offscreen` was measured on 2026-08-10 and the answer is split.** Its
rendered output is byte-identical to `native`, with the floor established by
running native twice, so the mechanism is output-safe. But it does not do the
one thing it exists for: macOS clamped the requested `-4000,-4000` back to
`x=-280 y=60` on a 1512x982 display, leaving 40 px of a 320 px window visible.
Position is not a way to hide a window on this OS. The next thing to try is a
separate macOS user session, a dedicated Space, or a second display, none of
which a `conf.lua` line can reach. Until then the mode buys nothing and no gate
should move onto it.

### native

What every tool does today: real macOS GL, real window. This is the procedure
every threshold in this repository was measured under, so it is the reference
rather than something with a delta.

### native-offscreen

The same LOVE binary and the same GL, with the window parked off the visible
area by `tools/render/conf.lua` when `VC_RUNNER_OFFSCREEN=1`.

Only the window POSITION moves. Size, depth and vsync are what the output
depends on, so none of them is touched: changing them under a flag would mean
the runner had silently measured a different scene.

**Canvas-based targets only.** The render harness draws into a canvas and
encodes it, so its pixels never depend on the window reaching a display.
Everything under `tools/ingame/` captures the *presented* back buffer through
`love.graphics.captureScreenshot`, so off the visible area there would be
nothing to capture and it would look like a pass. The runner refuses that
combination rather than letting you find out from an empty PNG.

### docker

Linux LOVE under `xvfb` with software GL. The recipe is in `Dockerfile` and is
reviewable, but the image is not built and the path is not usable yet.

```
docker build -t voxel-characters-runner:local mods/voxel_characters/tools/runner
```

Dependencies: a reachable Docker daemon, and the repository bind-mounted at
`/repo` (the runner does that for you).

## LIMITATIONS, and they are the reason nothing is switched over

Read this before trusting any output from a non-native backend.

1. **The save path is macOS-only, in the shell tools.** LOVE writes to
   `~/Library/Application Support/LOVE/<game>` on macOS and
   `~/.local/share/love/<game>` on Linux, and `card.sh`, `calibra.sh`,
   `clip.sh`, `trailer.sh` and `juiz.sh` all have the macOS path written in.
   So a container run cannot yet collect what the harness writes. This is the
   first thing to fix before the docker backend is worth anything, and it is a
   contained change: one resolver, five call sites.

2. **The generated assets are not in the image, by design.**
   `data/generated/` and `assets/generated/` are gitignored because they are
   derived from the player's own ROM. The container sees them only through the
   bind mount, which works on this machine and means the image is not portable
   to a machine that has not run `tools/build_data.py`.

3. **The in-game tools need more than a display.** They boot the real game,
   which needs a per-version ROM cache in the save directory
   (`$SAVE/<version>/rom-cache.complete`). That is in scope for a later slice,
   not this one.

4. **Software GL is a different rasteriser.** llvmpipe is not Apple's GL, and
   Debian bookworm ships LOVE 11.4 against the host's 11.5. Both are delta
   sources on their own. Every pixel and timing threshold in this repository
   was measured natively, and this project's own rule is that a threshold is
   evidence only when its floor was captured by the same procedure. So a gate
   moved here is measuring a new scene until its floor is re-measured here.

5. **Timing measurements do not transfer at all.** The life-cost benchmark
   compares against a ruler noise floor of 0.261 ms. Software GL in a container
   on a shared kernel has nothing to do with that number.

## How a backend stops being UNMEASURED

By measurement, written to `deltas.txt` as data. Never by editing `runner.sh`.

For `native-offscreen` that measurement is already built:

```
bash mods/voxel_characters/tools/runner/measure_delta.sh --dry-run   # prints the plan, runs nothing
bash mods/voxel_characters/tools/runner/measure_delta.sh             # needs a display
```

**It takes the screen for a few seconds and that is unavoidable**: the `native`
reference run has a real window by definition. Run it on a free machine.

It renders the same pinned target three times, native twice and offscreen once.
The two native runs are the floor: if the same render twice is not the same
file, a byte comparison across backends cannot mean anything, and the script
reports INCONCLUSIVE rather than picking whichever answer appeared. It then
runs `window_probe/` under both modes, because "the window went away" is a
separate claim from "the pixels match" and only one of them is about output.

It writes its own line into `deltas.txt` with the evidence attached, so the
record and the measurement cannot drift apart. It refuses to write anything if
a render produced no file: two absent files compare equal, which is the defect
this whole runner exists to refuse.

**One line per backend+target.** Re-measuring a key replaces its line rather
than appending beside it, and `runner.sh` reads the last match, so both sides
agree that the newest measurement is the live one. Before this, the writer
appended and the reader took the first match, which meant a re-measured key
kept reporting its superseded verdict: a stale `ZERO` would be the worst case,
since it is the one that lets a threshold be trusted on a backend already shown
to differ. Covered by `measure_delta.sh --selftest`, which is text only and
runs as part of `runner.sh selftest`.

The bar, unchanged:

1. Run the same gate under both backends, with its control floor captured by
   the same procedure in each, and report the delta.
2. Show that a gate which SHOULD fail also fails under the new backend.
   Producing output is not the same as measuring.
3. Write the line, then record it in `docs/EXECUTION_STATE.md`.

One target answering `ZERO` is evidence about that target. Escalate to
`check.sh` before hosting a real gate on the backend.

Until that exists, `native-offscreen` and `docker` are for looking at, and
`native` is for comparing with.

## What the runner refuses to do

- **No empty green.** A command that exits 0 having printed no verdict did not
  pass, it did not measure. `tools_bin.sh` records the original defect: with
  `$LOVE` unset, a check compared two empty strings and went green without
  measuring anything.
- **No silent fallback.** Ask for `docker` when docker cannot run it and the
  runner refuses. It does not run natively and let you believe the run was
  contained.
- **No shared LOVE.** A LOVE-backed backend takes the same lock every other
  tool takes, reentrant across a process tree, instead of killing whatever is
  measuring.

- **No silently different command.** More than one argument after `--` is
  refused rather than flattened, because a flattened argv re-split by `sh -c`
  can execute something other than what `meta.txt` recorded.

The selftest proves all four, plus that an unusable backend and a malformed
command line both refuse without executing anything.
