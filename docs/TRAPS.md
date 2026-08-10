# Traps

One page, organised by what you will see when one of these bites, not by
subsystem. Every entry below already cost real time once and is documented at
the place it happened; this page only collects them so the next session does
not pay for them again. Nothing here is invented: each entry links to the
comment or commit it comes from.

## "Every measurement comes back identical, no matter what changed"

**Cause.** vsync is on and the window is occluded (the normal case when a
tool runs from a shell, behind the editor). `love.graphics.present()` waits
for a screen flip the macOS compositor will not schedule while nobody is
looking at the window, so the whole `love.run` loop stalls: measured at 5
frames in 90 seconds. This reads exactly like "stuck at the launcher", zero
photos and an empty log, and it is not our code: the project's own drivers
hang the same way without the fix.

**Fix.** Every driver calls `love.window.setVSync(0)` before it measures
anything.

**Read more.** `tools/ingame/driver.lua:25-36`, `tools/ingame/probe_life.lua:462-466`
(numbered as trap 1 of two there).

## "I called `VoxelState.setLevel` and nothing happened"

**Cause.** `VoxelState.setLevel` does not command anything. The host
engine's `Pipelines` owns the camera rung and rewrites `Voxel.level` every
frame, so any value written through `VoxelState` is overwritten before the
next draw. The symptom reads as "the blend never rose", which looks like the
feature does not exist rather than like the wrong door was used.

**Fix.** Go through `Pipelines.setLevel("voxel", n)` instead, the same door
the host itself uses.

**Read more.** `docs/HANDOFF.md:210-212`, `tools/ingame/probe_fp.lua:40`,
`tools/ingame/clip.lua:87-103`.

## "A script that drives LOVE just hangs, and the log is empty"

**Cause.** By default LOVE answers an uncaught error by opening a window with
the message and waiting for a keypress. From inside a script that is
indistinguishable from heavy work: the tool only dies on its own timeout,
with an empty log, while the actual cause sits written on a window nobody is
looking at. This happened three times in one session before it was fixed.
Screenshotting the window to read it was tried and abandoned: on a shared
work machine `screencapture` grabs whatever is in front, which twice was a
personal conversation.

**Fix.** Every entry point under `tools/ingame/` calls the shared error
handler first, which prints to stdout and exits instead of opening a window.
`tools/love.sh` also refuses a bad game path up front, because a bad path
fails inside LOVE's own boot, before any of our files load, where no handler
can catch it.

**Read more.** `tools/ingame/erro.lua:1-16`, `docs/HANDOFF.md:27-29,193-198`.

## "The offline test suite dies instantly, or ends in a bare hex address, with zero checks counted"

**Cause.** The suite only runs correctly from the repository root. Its
`require("tests.love_stub")` resolves against the CURRENT DIRECTORY (see the
`package.path` prepend at the top of the test file), and the stub it needs
lives at the outer repo's `tests/`, not inside the mod. Run from anywhere
else, `require` fails before a single check registers, and the last line of
output collapses to something that looks like a crash address, not a
count. `mutantes.sh` once invoked the suite with no `cd` and would have
reported every mutant killed: a report claiming the tests were perfect at the
exact moment it measured nothing.

**Fix.** Always run test and lint commands from the repo root, exactly as
written in this mod's own gates:
`luajit mods/voxel_characters/tests/voxel_chars_test.lua`.

**Read more.** `tests/voxel_chars_test.lua:1-2` (repo-root `tests/`, not
`mods/voxel_characters/tests/`), `docs/EXECUTION_STATE.md:184-190`,
`docs/HANDOFF.md:27-29`.

## "A render or in-game tool refuses to start, or a measurement comes out truncated"

**Cause.** Only one LOVE process can usefully run at a time on a given
machine. `run.sh`, `clip.sh` and `trailer.sh` each start by killing any
running LOVE, so a second tool starting mid-measurement silently truncates
the first one; this happened once, when the trailer killed a feature
extraction halfway through and the partial file read as a short result
instead of an interrupted one.

**Fix.** `tools/tools_bin.sh` now holds a lock (a directory, because `mkdir`
is atomic) before starting LOVE: a second tool refuses and names who is
holding it, instead of killing the first tool's run. The lock stores the
holder's PID so a crashed owner is detected and recovered automatically,
which matters because a lock that stays stuck after a crash teaches people to
delete it by reflex, and then they delete a live one too.

**Read more.** `tools/tools_bin.sh:44-70` (the `VC_TRAVA` lock, held around
every LOVE invocation).

## "A gate barely passes, or an effect looks real but disappears on the next run"

**Cause.** A threshold compared against a guessed or fixed number, instead of
against a floor captured by the SAME procedure (same run, same sequence,
only the option under test toggled), measures the scene as much as it
measures the option. This bit this project at least four separate times in
one session: the clip guard, the in-game photo control, the LIFE cost
benchmark, and the first-person transition. In one of those, a threshold
chosen as a fraction of the frame passed a neutralised mod by a single
sample; two runs of the identical procedure, changing nothing else, is what
finally showed what the scene contributes on its own.

**Fix.** Any pixel- or cost-based gate needs a control run with the option
held at its baseline (usually OFF), captured the same way as the measured
run, and compares against THAT, not against a guessed constant.

**Read more.** `docs/HANDOFF.md:204-209`, `tools/ingame/clip.lua:296-299`,
`tools/ingame/driver.lua:285`, `tools/ingame/probe_fp.lua:305-330`,
`tools/ingame/probe_life.lua:532-551`.

## "A gate fails sometimes and passing again on rerun feels like enough"

**Cause.** A gate that fails intermittently for reasons unrelated to the code
trains whoever runs it to rerun until it goes green, which is worse than no
gate at all: a red result stops meaning anything. The project's own first
person control gate did this twice. The second time, `tools/bateria.sh`
running the whole battery as a single command for the first time caught a
menu gate (`M8`) that passed alone but failed 3 of 5 runs inside the battery:
measuring a fixed 46-frame interval sampled the BREATHING CYCLE at whatever
phase it happened to land on, not the size of the effect. Lowering the
threshold would have gone green again immediately and hidden the same defect
more quietly.

**Fix.** Do not lower a threshold to make an intermittent gate pass. Sweep
the whole relevant period and keep the extreme (or otherwise remove the
phase dependency), and run the full battery as one command: running pieces
by hand hides intermittency, because a person who sees red reruns it and a
green rerun ends the investigation before the cause is found.

**Read more.** `docs/ROADMAP_V2.md:630-667` (both instances, the second
found 2026-08-10), `CHANGELOG.md:33-35`.

## "A check has a message and looks like an assertion, but a mutant that should fail it survives"

**Cause.** `close(a, b)` (defined in the test file) RETURNS a boolean; it
does not register a check on its own. A call like
`close(pullEm(20, 6), 4, "message")` runs, the "message" is an ignored third
argument, and the check counts for nothing: six of these were found in the
suite, and fixing them jumped the total from 552 to 558. They read exactly
like a real check to a reviewer glancing over the diff, which is what makes
the mistake dangerous. `closePercent` (same file) is the same shape and the
same risk.

**Fix.** Always wrap a boolean-returning predicate in `check(...)` or
`eq(...)`, never call it bare for its return value.
`tools/lint_asserts.lua` catches this class of bug structurally now (any
local function whose every `return` is a boolean, called with its result
discarded) and is one of this mod's gates.

**Read more.** `tests/voxel_chars_test.lua:74-76` (the `close` function
itself), `tools/lint_asserts.lua:1-23` (the six discarded checks, and the
rule that finds the whole family).

## "An agent looks for this mod's git history and reports it as untracked"

**Cause.** `mods/voxel_characters` is a nested git repository with its own
remote, separate from the outer `gen1recomp` repo it sits inside. An agent
told only a branch name, with no mention of which repo, looked at the outer
repo, found the mod's files untracked there, and correctly refused to guess
rather than search further.

**Fix.** Any spec or handoff that touches this mod's git history must say
explicitly that the repository is `mods/voxel_characters` itself, not the
outer checkout.

**Read more.** `docs/HANDOFF.md:183-186`.

## "A character looks wrong only when it turns to face sideways"

**Cause.** The mod's whole volume, SLAB or CARVED, is built from art the
artist drew from the front, back, and (for CARVED) inferred side runs, never
from a real side view. Side faces carry 0% art. The mod's camera never
changes yaw, which is the only reason this has never shown up: the rule
"never rotate a character in Y" is load-bearing today, not a style choice,
and it stays load-bearing until side faces get real art of their own.

**Fix.** Do not add yaw rotation to characters (attention, turning to face
the player, and similar features) without first addressing side face art;
until then, treat any camera or character yaw change as suspect.

**Read more.** `main.lua:107-127` (why CARVED, not SLAB, is the
camera-independent mode, and why that trade only matters once yaw moves),
`main.lua:2186`, `docs/ROADMAP_V2.md:292-295` (item 10, "never rotate in Y").
