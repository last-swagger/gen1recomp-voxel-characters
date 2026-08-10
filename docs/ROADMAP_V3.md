# Roadmap v3: from a body that lives to a character that is authored

v1 proved that a flat overworld card can be given volume and life out of the
player's own pixels, with nothing shipped and nothing written to disk. That
worked, and it is released. v3 asks the next question, which is not "how much
more 3D can we buy" (that ceiling was measured, twice) but "how much more
*character* can we buy". The answer probably requires shipping something: a
mask, an overlay, a part, an effect, a sound. This roadmap treats that as a
research axis with gates, not as a forbidden idea, and it keeps the pure
runtime path as the control it has always been.

The aesthetic rule has not changed and it is not "more is better": preserve the
read of the original sprite, and buy just enough volume and life that the
character belongs in the voxel world. What changes in v3 is that the rule is
now allowed to be tested against an authored alternative instead of assumed.

## How to read this file

This supersedes `docs/ROADMAP.md` and `docs/ROADMAP_V2.md`. Both stay in the
repository as history, because several of their entries record a plan that was
wrong next to the measurement that corrected it, and that pairing is the most
useful thing in them. Nothing here should be re-derived from them; where they
disagree with this file, this file is newer and says why.

Items are numbered by tier (`T0.1`, `T1.2`) instead of by discovery order. The
old flat numbering ran to 26, had an item `20` twice and an item `0` after
tier 3, and is quoted in commit messages and code comments, so
[the appendix](#appendix-c-old-item-numbers) maps every old number to where its
subject now lives.

Every item carries four lines:

- **State.** One of `open`, `built, needs judgement`, `closed by measurement`,
  `parked`, `blocked on Kim`.
- **What changes.** The observable difference when it lands. Not "improves
  immersion".
- **Cost or risk.** What it spends, and what it can break.
- **Gate.** The evidence required before it counts as done. An item with no
  gate is not on this roadmap.

---

## 1. Current state

**v1.6.0 is released** and is the first release the game's own updater can see,
because the package now ships as `.zip` rather than `.modpkg`. Twelve
player-facing options shipped in it.

**Branch `vida-v2` carries 101 unreleased commits on top of v1.6.0, none
pushed.** Twenty-four of the twenty-seven items in the v2 roadmap are closed.
The three that remain are not unfinished code: one needs a credential, one was
paused by Kim, and one is built and failing its own calibration gate, which is
the gate working.

Measured on this branch, 2026-08-10, running the offline half of the battery
for this document rather than quoting a previous run:

```text
620/620 offline checks        (tools/bateria.sh --rapido, step 1)
assertion linter clean        (step 2)
chunk-local headroom 75 free of 200, 125 in use, floor 15   (step 3)
modkit validate ok            (step 4)
BATERIA OK
```

The last full run, which needs the game and a display, reported `REGUA OK` with
20 checks, `BATERIA OK` on every in-game gate, and `MUTANTES 5/5`.
`release_check.sh` is red on purpose: it asserts the release author is
`last-swagger`, and the nine published releases are signed by the personal
account.

### What ships in the branch that a player can reach

Four options landed after v1.6.0 and all four ship OFF, per the house rule that
anything new starts turned off:

| Option | What it does | Default |
|---|---|---|
| `FOOTFALL` | compresses the body on each step, synced to the walk frame | OFF |
| `ATTENTION` | leans toward a nearby player, with hysteresis, never a yaw turn | OFF |
| `PART LAG` | delays the upper body behind the lower one, in vertical bands | OFF |
| `FIRST PERSON` | keeps characters solid in first person with a capped pull | CARD |

The mod's menu is now nineteen rows: `STATUS` and `LIFE` read-only, `CAMERA FIT`
as a button, and sixteen options.

### What is proven, and worth not re-deriving

- **The channel.** The host asks for a mesh per character per frame and draws it
  with `Voxel3D.draw(mesh, texture, model, pull, sunModel)`. The animation
  multiplies a small transform into that per-instance model matrix. It does not
  rewrite static vertex buffers, so the whole static-buffer hazard the first
  roadmap worried about does not exist on this path.
- **Instance identity.** `model[12] - 8` returns world `py` exactly, in every
  tested host lineage, stable under mirror, camera rung, walking and camera
  movement. That is why a room of identical NPCs sharing one mesh can each move
  differently. Position seeds identity; the phase then advances by clock, never
  by position, which is what stops a walking character breathing at double
  speed.
- **The cost.** Ten characters, everything on, interleaved A/B/A/B against a
  warmed baseline: 0.166 ms of difference against a 0.261 ms ruler noise floor
  and a 16.7 ms frame. The honest statement is not "it is cheap", it is "this
  ruler cannot measure it".
- **The art share.** Provenance is measured with an identity-colour pass, not
  from RGB. At the default camera rung and depth: flat card 100% artist pixels,
  SLAB 73%, CARVED 31%. SLAB emits 104 quads with 16 facing up; CARVED emits
  1068 with 216 facing up. Upward faces carry no art and the camera looks down
  at them.
- **The silhouette contract.** IoU 1.000 between the SLAB silhouette and the
  original flat card at pitch 0, asserted by the ruler across five sprites and
  six frames. Every shading option is built so that strength scales a shade
  multiplier and never a vertex position, which is why any strength above zero
  produces identical geometry.

---

## 2. Contradictions reconciled

The source documents disagree in places, because the same day of work changed
the facts under them. Resolved here from the newest evidence rather than
averaged.

**1. The judge: "30 picks blocked on Kim" against "106 choices and it works".**
Both were true hours apart. `docs/EXECUTION_STATE.md` contradicts itself: its
"Blocked on Kim" table still asks for thirty A/B picks, and a later section in
the same file reports the fit. Resolved: **the dataset exists (106 choices over
45 sheets) and the judge works out of sample. The generator is built. The
critic is not trusted.** More picks are no longer a blocker, but targeted picks
on a *new* axis (authored parts, effect colour) will be needed when that axis
exists, because the current dataset only covers options the mod already had.

**2. en-US: "in flight" against "DONE".** Neither is precisely right, and the
scope matters, so here is the measured state.

- Public artefacts are en-US: `README.md`, `CHANGELOG.md`, `manifest.json`,
  `docs/HANDOFF.md`, `docs/TRAPS.md`, `docs/EXECUTION_STATE.md`.
- Code comments are en-US: a sweep for Portuguese function words in `--` and
  `#` comments across every `.lua` and `.sh` returns two incidental hits, both
  quoting a filename or a test string.
- **Not converted, and this is the part the handoff overstates:** the tool CLI
  surface. Dozens of user-facing strings still print Portuguese (`BATERIA OK`,
  `BATERIA VERMELHA`, `AVISO`, `uso:`), the
  drivers emit `PASSOU` and `FALHOU`, and the tool filenames are Portuguese
  (`bateria.sh`, `mutantes.sh`, `folga_locais.sh`, `juiz/`, `calibra.sh`,
  `gera.sh`, `sala_de_teste.sh`, `so_comentarios.lua`, `monta.sh`, `pouso.lua`).
- **`Laboratorio.command` is Portuguese in name and in comments**, and the sweep
  could not have caught it: the sweep covered `.lua` and `.sh`, and a `.command`
  file is neither. It is also the one clickable entry point in the repository,
  which makes it the first file a curious contributor opens.
- **`docs/ROADMAP.md` still carries a Portuguese correction block** at lines
  284 to 296.

That is `T1.5`, and it is small. Note the one piece of luck in it:
`bateria.sh` already greps `PASSOU|PASSED` and `FALHOU|FAILED`, so the driver
verdicts can be renamed without breaking the battery.

**3. `PART LAG`, `ATTENTION`, lab region overlays, release media tooling, shot
library, montage, headroom.** All done or done-except-publishing. None of them
is in the v3 implementation backlog. What v3 asks about them is what comes
*after*, and which of them belongs in the next release.

**4. Item `20` twice, item `0` late.** Structure repaired by tier numbering,
facts kept, old numbers mapped in [appendix C](#appendix-c-old-item-numbers).

**5. `ROADMAP.md` against `ROADMAP_V2.md` on emission order and the shadow
pass.** V2 is right and V1 is wrong, twice over. SLAB emission is *not* a
contiguous prefix: front and back faces are emitted row by row, but side faces
accumulate into `sideRuns` and are emitted after the whole row scan, sorted by
key, so a prefix split would drop or misplace every side face. And the shadow
blocker was invented: `setDrawRange` appears nowhere in this codebase except in
the two roadmap files that claimed it, and the shadow pass draws
`SpriteBillboards.shadowQuad`, the original flat quad, not this mod's slab.
What survives is smaller and real: a draw range is sticky per mesh *object*, and
the mesh is shared between every instance of a sheet in the frame.

**6. New, and the draft prompt had it backwards: the four new options are
code-visible and doc-invisible.** `README.md` documents thirteen options and
sixteen rows; the code has sixteen options and nineteen rows. `ATTENTION`,
`PART LAG` and `FIRST PERSON` appear in neither the README nor the changelog,
and `FOOTFALL` is in the README but not the changelog. The `[Unreleased]`
section opens with "Nothing here changes what a player sees", which was true
when it was written and is now false four times over. `release.sh` takes the
release body from `CHANGELOG.md`, so publishing today would ship four
undocumented player-facing options. That is `T0.1`, and it is the cheapest
release-safety item on this roadmap.

**7. Small drifts corrected while writing this.** Headroom measures 75 free
today where the handoff records 74 and a commit message records 77; the floor is
15 and none of the three is a concern. The README's test line advertises 480
checks where the suite now reports 620. `NOTAS_DO_CRITICO.md` cites
`main.lua:424` for `OBJ_SHADE`, which now sits at `main.lua:517`.

---

## 3. Decisions closed by measurement

These are not backlog. Do not reopen any of them without a new measurement that
overturns the recorded one, and if you have that measurement, replace the entry
rather than adding a second opinion beside it.

**Depth spends art.** Every unit of depth exposes surface the artist never
drew. Flat 100%, SLAB 73%, CARVED 31% at the game's camera. The values move
with camera and measurement setup; the law does not.

**SLAB is not the bottom of a quality ladder.** It preserves the artist's front
face, which is what this game's camera spends its time looking at. CARVED gives
a silhouette correct from any angle and costs thirteen times the upward-facing
surface. `SHAPE` is a choice between two different things and the menu order is
historical.

**A visual hull cannot make a dent.** Shape-from-silhouette returns the largest
volume compatible with the silhouettes, so armpits, the gap between arm and
torso, and the space between legs do not survive. The 31% is close to the
family's upper bound, not a tuning failure.

**No geometry-derived lighting model can vary inside the front face**, because a
slab is an extrusion and an extrusion has no concavity along depth. Measured
with the host's own AO algorithm and constants: head on with the ground term
off, neighbour occlusion changes exactly zero pixels. The 1481 pixels that
survive at the camera rung are all on top and side faces, which carry no art.
The contact term already ships as `GROUND SHADE`. This is why `FRONT SHAPE`
shades by position within a run: position in the run is the only variable a flat
face has.

**`FIRST PERSON: SOLID` is worth exactly its transition.** The blend sweep
reproduces byte for byte across four runs: the effect grows to 5.9% of the
frame at blend 0.74 and is exactly zero by 0.83, because the host hides the
player's own card as the blend completes. Release notes must not imply a solid
body you can walk around at settled first person. The transition is still worth
having: that 5.9% is the player's own body, which used to collapse to a flat
card exactly when the camera came closest to it.

**The grid is not ours to add.** The host calls `Voxel3D.seams(false)` around
the character pass on purpose, so the world reads as voxel-built and the people
read as drawn. Measured: the grid changes 54700 samples with the mod on and
54701 with it off, so it never touches our mesh. `probe_grid.lua` now guards
the contract. Turning seams on for characters would not fill a gap, it would
contradict the host's author on a point he thought about, and the cost is
specific: seams over side and top faces emphasise exactly the invented surface.

**There is no weather to read, and shadow shear is not wind.** Nothing
publishes weather: not the host, not another installed mod, not the core.
`DayNight.shearAt(t)` returns two shear components in drift per pixel of
height, which is the same unit the life channel consumes, and that is a
coincidence of units rather than a source. Feeding it in would lean every
character away from the sun. It would also mostly not move: `DayNight.time()`
is constant under four of six settings and follows the wall clock under the
default. If wind is ever wanted it has to be invented here, with its own state
and its own reason to vary. What the investigation did unblock is time of day,
which is readable *and* settable, and which turned the trailer's "variety in
time of day" into one call per shot.

**Battle art does not help an overworld walking character.** Battle sprites
have no walk cycle and exist in two directions, so there is nothing to animate
walking north with, and only 19 of 67 sheets have a counterpart at twelve times
the pixel density of their neighbours. Rendering battles themselves is a
different question and is parked, not killed (`T3.1`).

**Never rotate a character in Y.** Side faces carry 0.0% of the artist's art,
and the only reason nobody has seen that is that the game never yaws.
`ATTENTION` is built entirely around this rule: it is lean, scale, timing,
hysteresis and spring response.

**Per-part motion needed region identity, not a draw-range trick.** SLAB emits
top and bottom caps only where the neighbouring row is empty, so cutting
anywhere else exposes the inside of the back wall, which the host draws with
culling disabled. Animation state was per character, not per region.
`ourMeshes` knew a mesh was ours and nothing about which vertices are hair. All
of that had to be built, and it was, which is why `PART LAG` reads as a head
arriving late instead of as a body moving as one rigid piece.

**A numeric gate can reward worse art.** An AI redraw here satisfied every
numeric constraint the project owns and produced a worse result. That is the
reason the judge exists, and the reason no critic drives anything before
calibration.

---

## 4. Blocked on Kim

Agents do not work around this table. Everything else on this roadmap is
executable without him.

| # | What is needed | Why nobody else can do it | What is already done |
|---|---|---|---|
| K1 | A personal access token for `last-swagger` | Credential. A release author is set at creation and GitHub does not allow editing it afterwards, so this only fixes forward. | `release.sh` is built and rehearsed end to end. Rehearsal is the default; `--publicar` is required to publish. |
| K2 | His eye on the options that ship OFF: `FOOTFALL`, `CAMERA FIT`, `FRONT SHAPE`, `TOP DOME`, `STEP WEIGHT`, `PART LAG`, `ATTENTION`, `FIRST PERSON` | Taste, and he is the one who ships it. The house rule is that a new visual change ships off until the community has seen it. | Every one has a clip recipe available, and `monta.sh` can assemble them into one video. |
| K3 | The judge-against-critic call on `FRONT SHAPE` and `TOP DOME` | It is a taste question dressed as a measurement, and both sides are measured. | Both arguments are written down, with numbers, in `tools/juiz/dados/NOTAS_DO_CRITICO.md`. |
| K4 | Explicit approval to push, tag, publish or post | Outward-facing and not reversible. | Local commits on a feature branch are routine and need no approval. |
| K5 | Unpausing the battle probe | He paused it. | Nothing, deliberately. |

**K3 is the interesting one and it should not be automated away.** The judge,
fitted on Kim's own 106 choices, ranks `FRONT SHAPE` and `TOP DOME` *above* off,
at 78.7% out of sample against a 69.6% best-single-column baseline, five-fold
cross validated, with a margin more than twice the spread. The critic, shown
only rendered PNGs and never the code, argues against both: it reverse
engineered the mod's tone system from pixels alone, reporting non-front faces at
"0.91x the source pair" where `main.lua:517` sets `front = 0.90`, and its
objection follows from that reading. Those options manufacture up to six tones
outside a coherent two-level system, all of them on surface the artist never
drew, and top-face brightening pushes a pixel *brighter* than the sprite's
lightest colour, so the brightest thing on the character becomes invented
surface.

They are not answering the same question. The judge reports what Kim picked; the
critic reports what is consistent with the art's own system. A loop that
resolves that by picking whichever number is larger has resolved nothing.

---

## 5. Tier 0: release safety and foundations

Nothing above this tier is worth much until these land. Three of the four are
unglamorous on purpose.

### T0.1 Document what already shipped into the branch

**State:** open. The cheapest item here and the only one that is release
blocking.

**What changes:** `ATTENTION`, `PART LAG` and `FIRST PERSON` get README rows
with their levels and defaults; the README's row count and its advertised check
count stop being wrong (sixteen rows against nineteen, 480 checks against 620);
and `CHANGELOG.md`'s `[Unreleased]` section stops claiming that nothing here
changes what a player sees while carrying four new player-facing options. The
changelog entries name the people who asked, per the house rule: players asked
for solid first person, which counts as a request and not as approval.

**Cost or risk:** an hour of writing. The risk of skipping it is concrete:
`release.sh` builds the release body from `CHANGELOG.md`, so the next publish
ships four options no note mentions, and the first person entry in particular
has to say the transition-only truth rather than implying a solid you can walk
around.

**Gate:** a check that reads the `OPTIONS` table out of `main.lua` and requires
every label to appear in `README.md` and in a changelog section, added to
`bateria.sh`. Build it by reading the mod's own schema, never from a
hand-written list. That is exactly the hole left open in the life-ceiling test,
which writes its maxima by hand and would therefore not cover a new, stronger
level. Prove the gate by adding a fake option and confirming it fails.

### T0.2 Controlled visual runner

**State:** open. First in dependency order, because every visual and audio
prototype below depends on running LOVE repeatedly, and today that means
flashing windows on the machine somebody is using.

**What changes:** render, clip, trailer, card and in-game gates can run without
owning the primary screen. This is a measurement improvement as much as a
workflow one: fewer foreground windows means fewer occluded-vsync stalls, fewer
truncated runs, and fewer results discarded because a person needed the
computer.

Research order, and the first step is already half answered:
`tools/render/README.md` states flatly that there is no headless path, because
LOVE requires an OpenGL context.

1. **Headless first.** Linux LOVE in Docker under `xvfb` with software GL,
   writing screenshots, video and logs to a mounted output directory.
2. **Inspectable second.** The same runner exposed through VNC or noVNC, or
   simply as a saved mp4, so it can be watched on purpose rather than by
   accident.
3. **Mac-native fallback.** Where software GL changes the output, run in a
   separate macOS user session, Space or display, or on the MBP, for which
   `tools/sala_de_teste.sh` already assembles a working test room in about
   twenty minutes.
4. **Final visual judgement stays native** until the delta is measured.

**Cost or risk:** medium, and the risk is the one this project has a rule
about. A different renderer is a different procedure, so every threshold that
moves to the runner is measuring a new scene until its floor is re-measured
there. A runner that quietly makes a gate greener is worse than no runner.

**Gate:** three things, in order. First, the same gate run natively and in the
runner, with its control floor captured by the same procedure in both, and the
delta reported rather than assumed to be zero. Second, a gate that *should*
fail (a neutralised mod, an option that does nothing) fails in the runner too.
Third, `bateria.sh` gains a runner mode and the whole battery passes through it
with per-gate deltas recorded in `docs/EXECUTION_STATE.md`. Until all three
hold, the runner hosts the gates whose floors have been re-measured and nothing
else, and it never blesses a final screenshot or a trailer shot.

### T0.3 Execution contract and durable state

**State:** open, and the contract itself is [section 9](#9-autonomous-execution-contract)
of this file. What is open is the state discipline around it.

**What changes:** a loop or overnight run stays recoverable across context
compaction, a failed command, a remote machine and a handoff, because status,
owners, dependencies, assumptions, evidence and blockers live in the repository
rather than in a session. Previous parallel batches landed with zero conflicts
because file ownership was declared per dispatch, and that only works if it is
written down.

**Cost or risk:** low, and the risk of skipping it is the failure mode this
whole roadmap exists to avoid: an overnight run that returns a list of questions
instead of verified work.

**Gate:** `docs/EXECUTION_STATE.md` carries the sections named in
[section 9.7](#97-persistent-state), and a cold session can name the current
owner of every in-flight item and the next action for each from that file
alone. Test it the way this project tests everything else: hand the file to an
agent with no other context and see whether it starts in the right place.

### T0.4 Release identity and publishing

**State:** blocked on Kim (`K1`). Kept in tier 0 so it is visible, and kept
separate from implementation so nothing useful waits on a credential.

**What changes:** the project stops publishing under the wrong account, and the
release page becomes something a player can read in fifteen seconds.

**Cost or risk:** one token, then one command. The risk is publishing with the
wrong account, which only shows up after publishing, which is too late.

**Gate:** the split is the gate. Agents may build, rehearse and verify:
`release.sh` refuses a dirty tree, requires the battery and the mutants green,
takes the body from `CHANGELOG.md`, refuses without a section for the version,
and renames the package to `.zip` because the in-game updater cannot see a
`.modpkg`. Agents may not publish, tag, push or post. `release_check.sh` then
asks the game's own `ModUpdate.parseReleases` whether the published result is
installable, warns over 40 body lines or missing media, and fails on the wrong
author.

### T0.5 Chunk-local headroom, as a guardrail and not a refactor

**State:** closed by measurement, kept as a gate.

**What changes:** nothing, until it does. Exceeding `LUAI_MAXVARS` is a
*compile* error, so the symptom is not a broken feature, it is the entire mod
failing to load for every player, and it arrives on whichever commit crosses
the line rather than on the one that caused the growth.

**Cost or risk:** zero to keep. The risk is that authored layers, FX and SFX all
add module-level state to `main.lua`.

**Gate:** `tools/folga_locais.sh` counts by construction, by appending chunk
locals until LuaJIT refuses, rather than by reading the word `local` out of the
text, and fails below a floor of 15. Measured today: 75 free of 200. Do not
start a refactor until the floor is actually threatened, and if new work eats
twenty locals in a week, say so in the execution state rather than waiting for
the gate.

---

## 6. Tier 1: instruments before the things they measure

This project's strongest habit is building the ruler before trusting the
measurement. Every item in this tier is an instrument for something in tier 2,
which is why they come first.

### T1.1 The laboratory becomes the decision surface, and it cannot judge motion yet

**State:** open, and this is the correction the earlier plan needs. The lab
already shows one character, every option that changes the mesh, all 67 sheets,
a region overlay along the rows where a cut is safe, and it records A/B picks.
**It is blind to every option that lives in the model matrix**, and it is blind
on purpose: `lab.lua` classifies options by building each level and comparing
mesh signatures, sweeping both a walking pose and a full 6-second clock, and
hides any option that changes no vertex, because a control that does nothing is
worse than an absent control. `BREATH`, `SWAY`, `MOTION LAG`, `FOOTFALL`,
`ATTENTION` and `PART LAG` all post-multiply a matrix the host supplies, and in
the lab there is no host and no matrix.

**What changes:** the lab gains a synthetic host, meaning a fabricated
per-frame model matrix plus a clock and a fake walk state, so the life channel
can be previewed and compared where it is cheapest to look. Then it gains the
hooks tier 2 needs: authored part preview, palette controls, effect and
projectile triggers, audio preview, A/B recording, and a reproducible recipe
per variant in the same data-not-shell split the trailer and the card already
use.

**Cost or risk:** medium. The risk is specific and it is the reason this item
carries a hard gate: a fabricated matrix that does not match what the host
builds produces a lab that shows a lie confidently. The host's matrix is
`M = T(px+8, y, py+8) . Rx(lean - pi/2) . [S(-1,1,1)] . T(-8,0,0)`, and the
builders bake `Rx(corr)` into every vertex while the host cancels it, which is
the exact ground on which the life channel once animated in the camera's axis
instead of the character's.

**Gate:** the lab's synthetic transform, composed with the rotation baked into
the vertices, must reproduce the world displacement the in-game probe measures
for the same option and level, at all four camera rungs, within the probe's own
floor. Prove it fails: force the lab's matrix to skip the conjugation and
confirm the comparison rejects it. Until that holds, the lab may preview motion
with a visible "not measured in game" marker and may not feed the judge with
motion pairs.

### T1.2 Named anchors and animation events

**State:** open. Prerequisite for FX, and useful to the creator and to any
future mod API, which is why it is here and not inside `T2.3`.

**What changes:** a character exposes named anchor points (hand, head, feet,
centre of mass) and named events (footfall impact, blink closed, attention
noticed, projectile fired). A fireball then originates from a hand rather than
from the centre of a bounding box, and an authored part has somewhere to attach.

**Cost or risk:** low to medium. The risk is that anchors derived from the mesh
drift once `PART LAG` moves bands independently and `ATTENTION` leans, so an
anchor measured at rest is wrong exactly when something is happening.

**Gate:** a driver records anchor positions through a walk cycle with
`MOTION LAG`, `ATTENTION` and `PART LAG` all on, and proves each anchor stays
within a stated tolerance of the body part it names, at all four camera rungs.
Then prove the gate: move an anchor to the wrong band and confirm it fails.

### T1.3 The audio gate, before any sound exists

**State:** open. There is no audio anywhere in this mod today: a sweep for
`love.audio`, `newSource` and any sound API across `main.lua` and every tool
returns nothing. SFX is a new subsystem, not an extension of one.

**What changes:** sound becomes measurable instead of anecdotal. "It played" is
not evidence, in the same way "it changed" was not evidence for `MOTION LAG`
when it was shearing the body 45 degrees past 465 offline checks and eight
in-game checks.

**Cost or risk:** low. `ffmpeg` is already a dependency of `clip.sh` and
`trailer.sh` and can measure a captured track, so this needs no new tool
family.

**Gate:** three assertions and all three must be able to fail. The off path is
silent, measured as a floor rather than asserted. The on path has signal above
that floor. Peak volume sits under a stated ceiling, so a demo effect cannot
blast over the game. Prove the gate by handing it a silent file on the on path
and a loud one on the off path.

### T1.4 The critic earns its calibration, or it drives nothing

**State:** built, failing its own gate, and that is the gate working.

`gera.sh` proposes combinations of existing options, ranks them with the judge
and renders finalists. It searches the space the mod already exposes, where
every point is something a player could set by hand, which is a deliberate
choice: the space the judge was *trained* on varies one option at a time from a
fixed base, so it has never once been asked what `FRONT SHAPE` and `TOP DOME`
do together, and those two are the pair the judge ranks highest alone.
`calibra.sh` grades a critic against pairs Kim already decided and prints the
baseline beside the agreement.

```text
round 1    7 pairs   critic 42.9%   always-B 57.1%   -14.2
round 2   16 pairs   critic 62.5%   always-B 62.5%     0.0
```

Round 1's pair set was broken and **the critic is what found that out**: one
side had rendered blank, two pairs had the character cropped out of frame, one
differed by under 5% brightness. Four of seven pairs were not about taste at
all. The harness now measures each of those by eye-equivalent
(`compose mode=conta`), drops cropped, near-empty, near-identical and duplicate
pairs, and round 2 ran on a clean set. With 16 pairs the standard error is
about 12 points, so a tie is genuinely all that can be claimed.

**What changes:** if the critic beats the baseline by a real margin, it
pre-filters candidates and Kim sees finalists and close calls instead of every
pair. If it does not, nothing is allowed to run on it, which is the outcome the
gate has produced twice.

**Cost or risk:** low per experiment, and the next three are all cheaper than
collecting more pairs, because the critic currently sees a PNG with no context.
It does not know the game's palette. It does not know which surfaces are
invented. It has never been shown a pair Kim decided together with his reason.
Give it any one of those three and re-calibrate. When authored layers exist,
give it the authored-versus-runtime distinction too.

**Gate:** `calibra.sh conta` already encodes it, and the thresholds are the
tool's own: at or below the always-commonest-answer baseline the critic knows
nothing whatever its agreement looks like; above baseline but under 75% it
breaks ties only, because one in four finalists would be wrong; at or above 75%
it may pre-filter. Re-calibrate whenever the critic's prompt changes. Keep the
prose either way: on the pairs it could see, the critic argued against
darkening top faces and against stepping shade toward run ends, which is this
project's own position reached independently, and a number alone would have
discarded it.

### T1.5 Finish en-US where it is not finished

**State:** open, small, and mis-recorded as done. See
[contradiction 2](#2-contradictions-reconciled).

**Partly landed.** The display-free surface is now guarded by
`tools/en_us_sweep.lua` and `tools/en_us_scope.txt`. `lint_asserts.lua`'s
output is en-US, the pre-commit hook's summary was fixed while doing it (it
grepped a hardcoded list of step names and had quietly been showing four of
eight gates), and the sweep has converted the safe tool surface including
`release.sh`, `release_check.sh`, `so_comentarios`, `audio_gate.sh`,
`runner.sh`, and `tools/juiz/ajusta.lua`. The current sweep reports 0 surface
lines and 98 deferred lines declared with reasons.

The battery's own `BATERIA OK` / `BATERIA VERMELHA` banner is deliberately
still Portuguese: it is quoted in eight places across four docs, and the gate
for this item is a full battery run, which needs a display. Renaming a banner
and rewriting its citations in a display-blocked turn is more churn than value.
The remaining deferred strings live in `tools/ingame` and `tools/render`, whose
output is parsed by display-backed gates, plus filenames and API/data values.

**What changes:** a contributor running the battery stops reading
`BATERIA VERMELHA`, and the remaining tool output stops depending on Portuguese
for routine development. The repository exists because of outside reports and
pull requests, so a language barrier costs exactly the most valuable input it
has.

**Cost or risk:** low, with one real hazard: renaming a file or a verdict word
breaks whatever greps for it. `bateria.sh` counts `PASSOU|PASSED` and
`FALHOU|FAILED` from both sides deliberately, because zero failures is not
enough (a driver that printed nothing must read as "no measurement", not as
"pass"), so the verdict words can be renamed under that. Tool filenames appear
in the hooks, the docs, the battery and the release script.

**Widen the sweep before trusting it again.** The pattern that declared this
item done covered `.lua` and `.sh`, which is why `Laboratorio.command` survived
it untouched. Whatever runs next covers every executable and every doc, or it
will report clean for the same reason.

**Cost note:** convert output strings first, filenames last, and do the
filenames in one commit with every reference, never file by file.

**Gate:** the full battery passes after each commit, `grep -rn` finds no
remaining reference to an old name, and the pre-commit hook still fires. Prove
the rename gate by pointing the battery at a renamed driver and confirming it
reports no verdict rather than a pass.

### T1.6 Release positioning, and the clip that earns it

**State:** blocked on Kim (`K2`), with the engineering done.

**What changes:** the next release contains the subset of built-but-off options
that Kim's eye approves, each with a clip or card that shows a player why to
care in seconds.

The tooling is finished and there is no more of it to build for this:
`clip.sh` films any option side by side, left always off, with a title card and
lower thirds drawn by the game rather than by a `drawtext` build nobody else
has; `card.sh` builds a before-and-after with numbered callouts from a recipe,
and its before half can be rendered from a released tag, which makes a release
comparison a measurement rather than an illustration; `monta.sh` joins one clip
per feature into a single video with consistent framing; `trailer.sh` records a
shot list with time of day pinned per shot and camera movement inside a shot;
`planos.lua` holds the shot library so a feature filmed today matches one
filmed in March.

**Cost or risk:** low. The risk is releasing a feature nobody can see the point
of, which is what the ordering rule below exists to prevent.

**Gate:** two rules, both explicit. Do not release a visual feature before it
has a clip or card that explains why a player should care. Do not build a
game-facing UI before the lab proves the idea is worth a UI.

---

## 7. Tier 2: the next player-visible capability

This is the strategic opening, and it is where a v1 promise gets tested rather
than defended. v1 promised no shipped character art, no disk mutation, and
every on-screen pixel traceable to the player's own files. Those promises were
useful: they kept the project honest while it proved that runtime pixels could
carry convincing volume and life. **Preserving original pixels was a constraint
that served v1, not the purpose of v2.**

Kim has authorised breaking any of them where that is the path to characters
that feel alive, authored and worth looking at. The promise with the most upside
to break is *no shipped character art*, and it is also the one to break most
deliberately, because it changes the mod's identity from "derives everything
from your ROM" to "adds an authored character presentation layer". That is not a
defect if the roadmap names it plainly and earns it.

Breaking a promise still needs a gate. Every item in this tier answers all five:

1. What player-visible gain does this buy that runtime-only geometry cannot?
2. Is the shipped material optional, fallback-safe and clearly disclosed?
3. Does it improve Kim's pairwise judge results and real in-game clips?
4. What maintenance does it cost per sheet, per host fork, per game version?
5. Does it make the mod feel more like itself, or just like a generic remaster?

### T2.1 The authored character layer

**State:** open. This is the architectural door the creator and richer FX both
walk through, so it comes before either.

**What changes:** the mod gains a second presentation path. Pure runtime
derivation stays as the default and as the control; an authored path may add
small shipped material that guides the result. The smallest experiments worth
running first, and deliberately not a full art pack:

- One or two overlay or mask types, for example eyes, rim accents, or a region
  mask that guides shading, never a sprite replacement.
- Per-sheet authored metadata: region maps for head, body, hair, bag and feet;
  living against object; responsiveness; deformation weights. This is the piece
  most likely to pay off beyond its own item, because `PART LAG` currently cuts
  in vertical bands found from cap rows, and authored regions would let it cut
  along a bag strap instead.
- One living character and one object sheet in the first pass, so a rule cannot
  accidentally make an item ball or a boulder alive. That failure already has a
  precedent: `poke_ball` and `boulder` are pinned to zero life for exactly this
  reason.

**Assumption, logged and reversible:** the authored path ships as its own mode
beside the pure runtime mode rather than replacing it, so the v1 promise stays
available to anyone who wants it and the control never disappears. If that turns
out to double the maintenance for no gain, the narrow commit is revertable.

**Cost or risk:** high, and the risk is identity rather than engineering. A mod
that quietly starts drawing its own pixels while its README says otherwise has
broken something more expensive than a gate. Disclosure is part of the
deliverable, not a follow-up.

**Gate:** five things. Provenance is reported honestly, meaning the metric
splits into artist pixels, mod-invented surface, and shipped-authored pixels as
three separate numbers rather than two. Pure runtime remains reachable and is
the default, proven by a gate that runs the whole battery with the authored path
off and requires byte-identical output to today. A/B clips and judge pairs are
built from the same scene, so the comparison is not measuring the camera. Kim's
pairwise picks on authored against pure move in the authored direction, or the
experiment is recorded as closed rather than tuned until it wins. And a
release-note disclosure draft says exactly what is now authored, in plain words,
before any of it ships.

### T2.2 Character creator, as a paper doll in the lab

**State:** open, and it starts in the lab. Not a game-facing UI, not save
integration, not NPC-wide customisation.

**What changes:** a character can be composed from authored parts (head or
face, hair or hat, torso, legs, accessory) with palette controls for skin, hair
and outfit, rendered through the same voxel and life pipeline as everyone else,
including blink, breath, footfall, attention and part lag. Ash first, with a
small part stack.

**Cost or risk:** high, and the hard questions belong in the item rather than in
a later surprise:

- Does the creator apply only to the player, or also to NPC sheets?
- Are parts shipped as art, generated from existing sprites, or both?
- How do custom colours interact with the Game Boy palette and with the judge's
  current features? The critic's objection is directly relevant here: the art
  has a coherent two-level tone system, and an arbitrary hue picker manufactures
  tones outside it.
- Does changing the player's look touch save data, or is it a local visual
  preset only?
- How do clips, cards and the judge compare a custom character against the pure
  original?

**Assumption, logged and reversible:** a preset is local visual state, never
save data, and the first version applies to the player only. Both are cheap to
widen later and expensive to walk back.

**Gate:** the composed character passes the same silhouette and provenance
checks as a runtime one, or the difference is stated and defended. Palette
choices are constrained to something the tone system can absorb, proven by
rendering the extremes rather than by argument. A preset round-trips: serialise
to a small text or JSON blob, reload it, and render the same card byte for byte.
And one card shows original Ash, one authored preset and one randomised preset
side by side.

### T2.3 Character FX and SFX prototype

**State:** open, and it is explicitly a capability demo rather than a combat
system. The reference is *The Binding of Isaac*: Ash fires small readable
effects, a fireball and a lightning bolt.

**What changes:** the mod demonstrates that it can own character-authored
effects, motion, impact and sound, not only passive body deformation. Smallest
useful slice:

- One trigger, from the lab or a driver or a clearly named demo option, firing
  from Ash's current position and facing.
- Two visual families: a fireball and a lightning or bolt effect.
- One short SFX per family, or a procedural fallback if packaged audio is not
  ready.
- Projectile lifetime, travel, a hit or fade animation, and optionally a small
  light or screen-space flash.
- Works in the voxel overworld with no gameplay consequences.
- A clip recipe and a montage slot, because showing it is the point.

**Design guardrails.** Do not pretend this is Gen 1 authentic; it is a
deliberate capability demo and the release note should say so. Keep it isolated
from save data, battles, link play and normal encounters. Ship it OFF, behind a
clearly named demo option. Film it through the controlled runner, because
flashing effects and looping SFX are exactly the tool output that should not own
somebody's desktop. Validate with video and audio artefacts, never with a still.

**Cost or risk:** high, and it is the first item here that adds a new subsystem
rather than extending one. There is no audio path today. There is no particle
path today. Both add module-level state to a file with 75 chunk locals of
headroom, so `T0.5` is a live constraint on this item and not a formality.

**Gate:** the trigger-off path draws nothing and plays nothing, proven as a
negative gate that can fail. The trigger-on path produces measurable pixels
above a floor captured by the same procedure, and measurable audio inside
`T1.3`'s ceiling. An effect originates from the `T1.2` hand anchor rather than
from the character's centre, proven by measurement. The battery stays green with
the demo option off, byte-identical to today. And a clip exists, because a
capability nobody can see is not a demonstration.

### T2.4 What comes after `PART LAG` and `ATTENTION`

**State:** open as questions, not as implementation. Both features are built and
neither should be rebuilt.

**What changes:** the questions get answered with evidence instead of by
extension for its own sake.

- Should `PART LAG` stay a vertical-band effect, or do authored region masks
  (`T2.1`) buy enough to justify their cost? Today the safe cut rows are the
  distinct Y values on classified cap quads, which is honest and coarse.
- Does `ATTENTION` need per-sheet temperament or triggers beyond player
  proximity? The personality table already keys rate, breath and sway per sheet
  and pins `poke_ball` and `boulder` to zero, so responsiveness is a natural
  extension of an existing mechanism rather than a new one.

**Cost or risk:** low to medium each, and the real risk is spending tier 2 time
on refinements while the authored layer, the thing that changes what the mod can
be, waits.

**Gate:** either question may only be answered by a clip pair plus a judge pair,
never by a numeric gate alone, because both are asking whether something reads
better rather than whether it changed.

### T2.5 Opportunities that stay unpromoted until something needs them

Scanned, kept, and deliberately not scheduled. Each becomes real when a
consumer for it exists.

- **A character presentation API for other mods.** If authored parts, presets,
  FX anchors and SFX exist, compatibility mods will want them rather than
  patching the same internals. A plausible first contract: register a preset or
  override for a sheet, query an effect anchor, request a one-shot effect
  without owning the renderer, and ask whether the authored path is active.
  **Gate:** one internal caller plus one compatibility smoke test. Do not build
  a general SDK until two real consumers exist.
- **Preset import and export.** Serialise a look to a small blob, share it,
  reload it. **Gate:** byte-stable round-trip, already folded into `T2.2`.
- **A lab randomiser.** Mutate part choices, palettes, effect colours and life
  personality, so the judge can ask Kim about surprising candidates rather than
  hand-authored guesses. **Gate:** generated candidates pass the visibility and
  framing checks `calibra.sh` already applies before reaching the judge. No
  blank, cropped, identical or unreadable pairs, because that exact set of four
  defects is what made calibration round 1 meaningless.
- **A host compatibility matrix.** Dramatic Shape, Battle Art Voxel Fork,
  Dramaless Shape, and what each supports. Authored assets, FX and creator paths
  increase coupling. **Gate:** capability probes, never version gates. The mod
  already attaches by capability and logs version numbers without acting on
  them, because three forks version independently and a hard gate kept rejecting
  hosts whose API was intact.

---

## 8. Tier 3: probes and parked work

### T3.1 Battle rendering capability probe

**State:** parked by Kim (`K5`), and the parked state is actionable so it does
not need re-deriving when it unpauses.

**What changes:** nothing yet. The first milestone is not "make battle sprites
voxel". It is: find the battle draw path, decide whether a safe patch seam
exists, render a harmless probe, and decide from evidence whether battle
rendering deserves a roadmap at all. That is the same step 1 the overworld got.

**Cost or risk:** low for the probe. Note why it survives at all when battle
*art* is closed: three of the arguments that killed variable depth do not
survive the change of camera. The top-face law was measured under a camera that
looks down, the AI depth map's 52% art figure was measured there too, and the
missing side view is the one view a battle never shows.

**Gate:** the probe reports whether the seam exists and does not change what a
player sees. It stays off the critical path; it is independent of the authored
and FX direction and should not steal time from either.

### T3.2 Ideas that are refused until a measurement overturns them

Do not roadmap these. Each already cost the time to answer once.

- Voxel grid seams on characters.
- Weather or wind read from host state, and calling day/night shadow shear
  "wind".
- Battle art as an input to overworld walking characters.
- Yaw-facing attention, or any character yaw at all before side faces have real
  art.
- Geometry bevels that break the silhouette IoU contract.
- Per-frame static-buffer rewrites, when model-matrix animation works and costs
  less than the ruler can measure.
- Trusting an uncalibrated visual critic.
- Lowering a threshold to make a flaky gate pass.
- Publishing, tagging, pushing or posting from an agent without Kim's word.
- Supersampling only the characters. The host's author already argued this from
  the other side: the world should read as built from voxels and the people
  should read as drawn, so making characters the one sharp thing in a soft scene
  is the same mistake in the opposite direction.
- Procedural material roughness on the front face. It is invented pixel by
  definition, moves the provenance metric the wrong way, and replaces Game Boy
  palette colours with material simulation. That is not a remaster of this art,
  it is different art.

### T3.3 Promises that are no longer absolute, and what each needs

These are open axes now, not non-goals. Each needs an explicit argument and the
five-question gate from tier 2, not permission.

- Shipped character art, especially small authored overlays or masks.
- Authored region masks.
- Procedural or AI-assisted character detail, calibrated against Kim's picks
  rather than against numeric gates. The precedent is not optional reading: an
  AI redraw here satisfied every numeric constraint the project owns and
  produced worse art.
- Higher-resolution or enhanced character presentation, if it improves the
  in-game read without disconnecting characters from the voxel world.
- Breaking the pure-runtime promise where the result is visibly better and the
  release note says so plainly.

---

## 9. Autonomous execution contract

For loop and overnight runs. This section is a working rule, not a preference.
The failure mode it exists to prevent is a long run that returns a list of
questions instead of verified work.

### 9.1 No-question execution policy

**Default: keep moving, make the best reversible decision, document it,
validate it.**

Ask Kim only when all four of these hold at once:

1. The repository, docs, tests, tools, experiments, another model and the MBP
   cannot reasonably answer it.
2. The decision is not safely reversible.
3. Guessing would risk credentials, publishing, destructive data loss, a public
   promise, or the product direction itself.
4. No other independent workstream can make meaningful progress in the
   meantime.

Do not stop for: internal function names, module boundaries, whether a prototype
starts in the lab or a driver, adding a conservative default-off option,
choosing a reversible implementation strategy, writing tests, gates, clips,
cards, docs or execution state, asking another agent for review, running the MBP
or the controlled runner, or deciding the first version of an authored mask or an
FX prototype.

Do stop for: publishing, pushing, tagging or posting; the `last-swagger`
credential; choosing between two visual directions once both have evidence;
resolving a judge-against-critic disagreement that is about taste rather than
correctness; and changing the public identity of the mod in a way that cannot be
walked back.

### 9.2 Assume and roll back

Code can be reverted, so ordinary engineering uncertainty becomes an auditable
commit rather than a question.

- Prefer a reversible commit to a question.
- Put experiments behind flags, lab-only triggers, demo options or feature
  gates.
- Keep pure-runtime and current-release behaviour as controls wherever an
  authored layer, a creator or an FX path is being tested.
- Record the assumption in `docs/EXECUTION_STATE.md` or the relevant spec
  *before* moving on, not afterwards.
- If an assumption proves wrong, revert or replace the narrow commit and
  continue. A wrong assumption is not a reason to halt the loop.
- Name risky experiment branches for what they test: `exp/authored-overlays`,
  `exp/creator-paper-doll`, `exp/fx-projectiles`. Each carries one command that
  shows it, one command that tests it, and one paragraph on what would make it
  worth keeping.

This does not override the hard stops in 9.1.

### 9.3 The roadmap is a dependency graph

```text
T0.1 docs of shipped options ─┐
T0.3 execution contract ──────┼─→ everything (cheap, do first)
T0.2 controlled runner ───────┴─→ T1.1 lab · T1.3 audio gate · T2.3 FX/SFX

T1.1 lab (needs a synthetic host matrix)
        └─→ T2.1 authored layer ─→ T2.2 creator
        └─→ T2.4 what comes after PART LAG / ATTENTION
T1.2 anchors ─→ T2.3 FX/SFX
T1.3 audio gate ─→ T2.3 FX/SFX
T2.1 authored layer ─→ T1.4 critic context (authored vs runtime is a new feature)

T1.6 release positioning ─→ blocked on K2, not on engineering
T0.4 publishing ─────────→ blocked on K1
T3.1 battle probe ───────→ blocked on K5, off the critical path
```

Read two things off that graph. The runner gates three separate items, which is
why it is first despite being unglamorous. And the authored layer feeds back
into the critic, so `T1.4` is not finished when `T2.1` starts.

### 9.4 What can run in parallel, and who owns what

Two constraints shape all scheduling and neither is negotiable.

**LOVE is exclusive per machine.** `tools/tools_bin.sh` holds a lock (a
directory, because `mkdir` is atomic) around every LOVE invocation, storing the
holder's PID so a crashed owner is detected rather than requiring somebody to
delete a lock by reflex. The lock is reentrant across a process tree: whoever
creates it exports `VC_TRAVA_DONO` and a child that sees an inherited value
proceeds without taking anything. That exists because giving the ruler a lock
deadlocked it against its own call to `card.sh`. Two workstreams that both need
LOVE run on different machines or serially.

**A file has one owner at a time.** Isolated file scope is what made three
parallel batches land with zero conflicts. Every dispatch says explicitly what
it may not touch.

| Workstream | Files it owns | Needs LOVE | Parallel-safe with |
|---|---|---|---|
| Docs of shipped options (`T0.1`) | `README.md`, `CHANGELOG.md`, one new gate | no | everything |
| Controlled runner (`T0.2`) | new `tools/runner/`, `bateria.sh` | yes, heavily | text-only work |
| Lab synthetic host (`T1.1`) | `tools/render/lab.lua` | yes | runner work on another machine |
| Anchors (`T1.2`) | `main.lua` draw wrap, one new driver | yes | anything not touching `main.lua` |
| Audio gate (`T1.3`) | new tool, `tools/ingame/` capture | yes | lab work on another machine |
| Critic context (`T1.4`) | `tools/juiz/` | yes for renders | lab, runner |
| en-US remainder (`T1.5`) | `tools/**` strings, then filenames | no | nothing during the filename commit |
| Authored layer (`T2.1`) | `main.lua` builders, new asset dir | yes | anything not touching `main.lua` |

`main.lua` is the contention point for three items. Sequence them rather than
splitting the file, and remember why: it holds 125 of LuaJIT's 200 chunk locals,
and exceeding the ceiling is a compile error for every player.

### 9.5 Compute pool

| Resource | Has LOVE | Used for |
|---|---|---|
| Mac Studio | yes | orchestration, LOVE work, integration |
| MacBook Pro (`ssh mbp`) | yes | second LOVE workstream, full battery |
| Controlled runner (`T0.2`) | yes, once built | non-judgement gates, clips, unattended runs |
| Subagents | no | text-only work: docs, tests, scripts, review |
| `codex`, `gemini` CLI | no | independent review from a different model family |

MBP dispatch goes through the GUI session, never plain ssh:

```text
osascript -e 'tell application "Terminal" to do script "bash /tmp/mbp_runner.sh"'
```

The CLI keeps credentials in the login Keychain and an ssh session cannot unlock
it. The symptom is "OAuth session expired", which is not an expired token. Code
moves by `git bundle --all` plus `scp` plus `git fetch`, so nothing is pushed.
`tools/sala_de_teste.sh` assembles the test room on a second machine and then
runs the battery there to prove it assembled, because the things a repository
clone does not bring are now a list in a script rather than something to
rediscover.

**Any spec or handoff that touches git must say that the repository is
`mods/voxel_characters` itself**, a nested repo with its own remote, not the
outer `gen1recomp` checkout. An agent told only a branch name looked at the
outer repo, found the mod's files untracked, and correctly refused to guess.

### 9.6 The uncertainty ladder

Climb it in order. Escalating from rung 1 is the behaviour this contract
exists to stop.

1. Read the code, the docs and `docs/TRAPS.md`.
2. Run something. This project's own record is unambiguous: every defect found
   on the heaviest day of work was found by running something against real
   input, not by reviewing the idea.
3. Ask another agent, preferably from a different model family. It has earned
   its cost: `codex` found a false pass in the comment gate that nineteen
   hand-written adversarial cases had missed.
4. Cross-check against the runtime and the tests.
5. Make a reversible decision and document it.
6. Only then escalate, and only if all four conditions in 9.1 hold.

### 9.7 Persistent state

`docs/EXECUTION_STATE.md` is the durable record, updated as work lands and not
as work is planned. Required sections:

- **Current state**, as the measured battery block, with the date.
- **Workstreams**, one row each: item, owner, files owned, state, evidence
  (commit or measurement, never "done").
- **Blocked on Kim**, mirroring [section 4](#4-blocked-on-kim). Agents do not
  work around this table.
- **Assumptions logged**, each with what would falsify it.
- **Gate deltas**, for anything measured under the controlled runner instead of
  natively.
- **Next actions**, specific enough that a cold session starts in the right
  place.

### 9.8 Definition of done

An item is not done when code lands, and it is not done when an agent says it
is. It is done when:

- its stated gate passes, and that gate has been shown to fail on input that
  should fail;
- the full battery is green, run as one command rather than as pieces;
- the mutants still die (`tools/mutantes.sh`), for anything touching visual
  maths or a test helper;
- docs are updated in the same change, including the README and changelog rows
  for anything a player can reach;
- `docs/EXECUTION_STATE.md` records the evidence;
- and for anything visual, a clip, card or screenshot exists, because the
  project's own history is that every visual defect through v1.2.2 was found by
  a person watching a video while the tests stayed green.

### 9.9 Review discipline

Meaningful implementation gets a diff review against the spec, tests, edge
cases, integration points and failure behaviour. Risky work gets adversarial
review, and "risky" here means visual maths, release tooling, gates themselves,
and anything that weakens or breaks a v1 promise.

**Delegated reports are not evidence.** Integrate only after review and
independent validation. Two of the most expensive defects in this repository
were false greens that read as finished work, and one of them was a gate that
exited 0 without comparing a byte when given the path spelling its own docs
used.

### 9.10 Failure recovery and the anti-idle rule

A failed command is not a stopping point: inspect, hypothesise, fix or choose
another approach, retest. A blocked item is not a stopped roadmap: finish
everything that does not depend on the block and record exactly where it
stopped.

While LOVE is running, or the MBP, or a Docker job, or a delegated agent, use
the time for independent review, the next spec, docs, tests or research. Never
sit on a progress bar.

---

## 10. Testing rules and operational constraints

Cross-cutting, hard-learned, and each one already cost real time.

**A gate is not verification until it has failed on input that should fail.**
One day produced eight instances of this. The comment-only gate had three
separate defects found three different ways: a bare CR let a comment swallow
real code, a documented path spelling exited 0 without comparing a byte, and
comparing line k to line k reported 2697 false changes on a correct
translation. The clip's negative gate was a coin flip, proven against the
original committed code: run twice on a key the mod does not have, it published
once and refused once.

**A gate that cries wolf on correct input is more dangerous than one that
misses.** The one that misses gets found out. The one that fires on correct
input gets waived by the second day, and then it is not there at all.

**Never lower a threshold to make an intermittent gate pass.** Four gates were
intermittent and no threshold was lowered in any of them, because the number was
never the problem:

| Gate | Rate | Cause | Fix |
|---|---|---|---|
| menu `M8` | 3 of 5 | measured phase: two photographs a fixed 46 frames apart, so the result depended on where in the breathing cycle they landed | sweep a full period, keep the largest |
| `probe_fp` `P4` | 2 of 4 | used samples whose own control floor was half the frame | discard a sample whose floor exceeds 5% |
| the ruler | once | took no LOVE lock, ran beside another tool | it takes the lock |
| `probe_fp` again | once | not reproduced, recorded rather than chased | none yet |

**Run the full battery as one command.** Running the pieces by hand hides
intermittency, because a person who sees a red re-runs it and a green rerun ends
the investigation. The first time the battery ran as a single command it found a
flaky gate that months of hand-running had not.

**Measure a floor with the same procedure.** Any pixel-based or cost-based gate
needs a control run with the option held at its baseline, captured the same way
as the measured run, compared against that and never against a guessed
constant. This bit the project at least four times in one session: the clip
guard, the in-game photo control, the LIFE cost benchmark and the first-person
transition.

**Ask "how much" and "in which direction", not only "did it change."**
`MOTION LAG` once sheared the body nearly 45 degrees and passed 465 offline
checks and eight in-game checks, because every one of them asked whether
something changed. Later, a mutant that flipped the sign of the lag term
survived all 603 checks: the suite verified magnitude and nothing about
direction. Note the subtlety in fixing that class of bug, because it is easy to
get wrong: comparing two opposite directions to each other does not catch a sign
flip, since flipping inverts both. The assertion has to be absolute.

**Mutation testing is verification, not polish.** `tools/mutantes.sh` refuses a
dirty tree, requires each declared pattern to match exactly one line, restores
from a trap so an interrupted run cannot leave the mod mutated, and measures its
baseline from the same run rather than from a number in a document. Both times
it ran on its first day it found something real.

**Beware the check that is not a check.** `close(a, b)` returns a boolean and
does not register anything, so `close(pullEm(20, 6), 4, "message")` runs, the
message is an ignored third argument, and the check counts for nothing. Six of
those were in the suite and repairing them moved the count from 552 to 558.
`tools/lint_asserts.lua` now catches the whole family structurally and is a
battery step.

**Run everything from the repo root.** The offline suite resolves
`require("tests.love_stub")` against the current directory, and the stub lives
in the outer repository's `tests/`. From anywhere else the suite dies before a
single check registers, and the last line of output collapses to something that
looks like a crash address rather than a count. `mutantes.sh` once invoked it
with no `cd`, which would have reported every mutant killed: a report claiming
the tests were perfect at the exact moment it measured nothing.

**Do not conclude about a whole from a subset.** The blink "defect" that was
retracted came from dumping every UV, sorting, and reading the first forty,
which were the side and top faces. Measuring only front faces showed nothing
wrong at all.

**Standing operational rules.**

- Every driver calls `love.window.setVSync(0)` before measuring anything.
  Otherwise vsync on an occluded window stalls the whole `love.run` loop:
  measured at 5 frames in 90 seconds, which reads exactly like "stuck at the
  launcher".
- Every entry point under `tools/ingame/` installs the shared error handler
  first, so an uncaught error reaches stdout instead of opening a window nobody
  is looking at.
- Go through `Pipelines.setLevel("voxel", n)` for the camera rung.
  `VoxelState.setLevel` does not command anything: the host rewrites
  `Voxel.level` every frame.
- The pitch a measurement is taken at decides what it means. Judging geometry at
  a pitch nobody visits is how the wrong thing gets fixed, and that has happened
  here.
- Kim posts to Discord. Agents prepare drafts.
- Releases credit reporters by name, and public text carries no em dashes.
- Every visual change new to the mod ships OFF. Once the community has seen and
  approved one, on by default becomes the conservative choice.

---

## Appendix A: commands

All from the **gen1recomp repo root**, never from the mod directory.

```text
bash mods/voxel_characters/tools/bateria.sh              the whole battery, in order
bash mods/voxel_characters/tools/bateria.sh --rapido     the half that needs no game
bash mods/voxel_characters/tools/bateria.sh --sem-jogo   offline plus the ruler
bash mods/voxel_characters/tools/mutantes.sh             are the checks checking?
bash mods/voxel_characters/tools/instala_hooks.sh        pre-commit runs the fast half
luajit mods/voxel_characters/tests/voxel_chars_test.lua  the offline suite alone
bash mods/voxel_characters/tools/render/check.sh         the ruler, checking itself
bash mods/voxel_characters/tools/folga_locais.sh         chunk-local headroom
```

Visual and in-game, one LOVE at a time per machine:

```text
love mods/voxel_characters/tools/render sprite=red shapes=flat,slab frames=0
love mods/voxel_characters/tools/render lab=1                  the laboratory
mods/voxel_characters/Laboratorio.command                       the same, clickable
bash mods/voxel_characters/tools/ingame/run.sh <dir>            screenshots
bash mods/voxel_characters/tools/ingame/clip.sh <dir> <k=v>     side-by-side A/B
bash mods/voxel_characters/tools/ingame/trailer.sh <dir>        the shot list
bash mods/voxel_characters/tools/ingame/monta.sh <dir> <k=v>... release montage
bash mods/voxel_characters/tools/render/card.sh <recipe> <out>  explainer card
```

Judge and critic:

```text
bash mods/voxel_characters/tools/juiz/juiz.sh                  fit and report
bash mods/voxel_characters/tools/juiz/rodada.sh                collect pairs
bash mods/voxel_characters/tools/juiz/gera.sh [n]              generate finalists
bash mods/voxel_characters/tools/juiz/calibra.sh prepara [n]   render graded pairs
bash mods/voxel_characters/tools/juiz/calibra.sh conta         score a critic
```

Release, and the last two need Kim:

```text
bash mods/voxel_characters/tools/release.sh                 rehearse (the default)
bash mods/voxel_characters/tools/release.sh --publicar      publish (needs K1 and K4)
bash mods/voxel_characters/tools/release_check.sh [tag]     ask the game if it installs
bash mods/voxel_characters/tools/sala_de_teste.sh mbp       assemble the second machine
```

## Appendix B: where things live

| Path | What it is |
|---|---|
| `main.lua` | the mod: `OPTIONS` table, both mesh builders, the life channel, the draw wrap |
| `tests/voxel_chars_test.lua` | the offline suite, 620 checks, repo root only |
| `tools/bateria.sh` | the battery, in the order that makes a failure mean something |
| `tools/mutantes.sh`, `tools/mutantes.txt` | declared mutations and the runner |
| `tools/lint_asserts.lua` | finds checks that assert nothing |
| `tools/folga_locais.sh` | chunk-local headroom, floor 15 |
| `tools/tools_bin.sh` | the reentrant LOVE lock and binary discovery |
| `tools/render/` | the offline harness: geometry, metrics, provenance, compose |
| `tools/render/lab.lua` | the laboratory and A/B choice mode |
| `tools/render/check.sh` | the ruler that checks the ruler |
| `tools/ingame/` | drivers that boot the real game: probes, menu, clip, trailer, montage |
| `tools/juiz/` | the judge, the generator, the critic calibration, and the data |
| `tools/release.sh`, `tools/release_check.sh` | build and verify a release |
| `docs/TRAPS.md` | read this before debugging anything |
| `docs/EXECUTION_STATE.md` | durable state for autonomous execution |
| `docs/HANDOFF.md` | orientation for a session starting cold |
| `docs/ROADMAP.md`, `docs/ROADMAP_V2.md` | history, including plans that were wrong next to their corrections |

## Appendix C: old item numbers

Kept because commit messages and code comments quote them.

| Old | Subject | Now |
|---|---|---|
| 0 | chunk-local headroom | `T0.5` |
| 1 | feed the judge | done, 106 choices. Context in `T1.4` |
| 2 | en-US | done for comments and public docs; remainder is `T1.5` |
| 3 | release identity | `T0.4`, blocked on `K1` |
| 4 | trailer | done, all four missing things landed |
| 5 | the grid | closed by measurement, section 3 |
| 6 | first-person depth | closed by measurement, section 3 |
| 7 | the LOVE lock | done, section 9.4 |
| 8 | pixel features | done. The loop is `T1.4` |
| 9 | `PART LAG` | done. What comes after is `T2.4` |
| 10 | `ATTENTION` | done. What comes after is `T2.4` |
| 11 | the laboratory | done. Its next phase is `T1.1` |
| 12 | battle probe | `T3.1`, parked on `K5` |
| 13 | weather and wind | closed by investigation, section 3 |
| 14 | mutation testing | done, section 10 |
| 15 | assertion linter | done, section 10 |
| 16 | the ceiling reads the schema | done, with one hole named in `T0.1`'s gate |
| 17 | both machines | done, section 9.5 |
| 18 | one command plus a hook | done, appendix A |
| 19 | split the harness | done, 2723 lines to 1415 |
| 20 (first) | generator and critic loop | `T1.4` |
| 20 (second) | the method it came from | history, `ROADMAP_V2.md` |
| 21 | release accessories | done: `clip.sh`, `card.sh`, `planos.lua`, `monta.sh`. Positioning is `T1.6` |
| 22 | `docs/TRAPS.md` | done |
| 23 | the clip guard | done |
| 24 | flaky gates | done twice, section 10 |
| 25 | the blink test | retracted, there was no defect |
| 26 | the explainer card | done, `card.sh` |
| 26a / 26b | the card format, and the reference's five points | done and answered; four of the five are refused with numbers in `T3.2` |
