# Roadmap towards v2

Everything open, ordered by what I would build first, with what each item
actually changes once it lands. Written to be the input to a specification, so
each item says what it unblocks and what it costs, not just what it is.

Ordering rule: an item comes earlier when finishing it makes later items
cheaper or safer, not when it is more exciting. Three of the first four are
unglamorous on purpose.

**Updated 2026-08-10.** Items 5 and 6 were answered by measurement rather than
built, item 8 is done, and item 0 was added after an external review named a
risk this document had missed. Item 26 was added from a reference Kim brought
in, and it is the first roadmap item that arrived already built. Where an
item's plan turned out to be wrong, the wrong version is kept next to the
correction: this file is read to decide what to build, and a plan that quietly
changes teaches nothing.

**Done since this file was written:** the judge's whole loop (items 1 and 8's
machinery, waiting only on picks), the axis defect in the life channel, an
assertion linter, a local-headroom gate, a lock so the tools stop killing each
other, a LOVE error handler so a failure reaches stdout instead of a window, and
roughly forty checks that passed for reasons unrelated to what they claimed.

---

## Tier 0 — nothing else is worth much until these land

### 1. DONE: the judge is fed and it works

**State:** the machinery exists and is proven. `Laboratorio.command` shows two
variants, one key records a pick, `tools/juiz/juiz.sh` measures every variant
and fits a Bradley-Terry model. Its self-test recovers a known rule from 200
synthetic picks at 92.5% out of sample against 75% for the best single column.
What is missing is real picks.

**What changes:** this is the only thing in the project that can rank art
without a person in the loop, and it is a precondition for every generator idea
we have. We measured that an AI redraw satisfied every numeric constraint we
own and produced worse art; until a judge exists, any agent iterating against
our gates converges on something that scores well and looks wrong.

**Cost:** thirty to sixty of Kim's picks, roughly twenty minutes. Then the model
either beats the best single feature out of sample or it does not, and both
answers are useful: beating it means we can score candidates, failing means the
thing that decides preference is not in the feature list, which tells us what to
measure next.

### 2. DONE: the project is en-US

**State:** decided, not started. Over 3500 comment lines are in Portuguese, plus
README, CHANGELOG, docs and test names.

**What changes:** the repository stops being closed to the community that feeds
it. This project exists because of outside reports and pull requests, so a
language barrier costs exactly the most valuable input we have.

**Cost:** high and irreducible. Almost every comment here explains a defect that
was paid for and why a decision went the way it did, so machine translation
would destroy the value that makes them worth keeping. It has to be read and
rewritten file by file. Suggested order: `main.lua` first (it is what a
contributor opens), then the tools, then the tests, then the docs.

### 3. Release identity and format

**State:** guarded, blocked on a token. `release_check.sh` now fails when the
author is not `last-swagger` and warns when the body is over 40 lines or has no
media. The nine published releases are signed by the personal account.

**What changes:** the project stops publishing under the wrong name, and the
release page starts being something a player can read in fifteen seconds. A
release author cannot be edited after creation, so this only fixes forward.

**Cost:** a personal access token from the `last-swagger` account, then an hour
to wire it into a `release.sh` that builds, signs, attaches the media the clip
and trailer tools produce, and verifies with the game's own parser.

---

## Tier 1 — the quality of what already exists

### 4. DONE: the trailer's four missing things all landed

**State:** it records, and the obvious defects are fixed (English captions, no
wall pushing, first person shown as a before and after pair).

**What changes:** it becomes the artefact that carries every release and every
Discord post, which is the difference between a feature existing and a feature
being seen.

**Two of the four missing things landed on 2026-08-10, and both were one call.**

**Time of day**, unblocked by item 13's investigation. Every shot now pins its
hour and the hour is restored afterwards, because `setIndex` writes to the
save. It also fixed something nobody had noticed: the host's default is `sync`,
which follows the wall clock, so **the trailer was not reproducible** and the
same shot list filmed morning and evening gave different footage. Any
comparison between two recordings was partly measuring the hour. Proved rather
than assumed: the full list filmed as day against the same list as night
measures 14 dB PSNR.

**Camera movement inside a shot.** `Pipelines.setLevel` takes an integer rung
and floors it, which reads like a jump. It is not: the host TWEENS.
`VoxelState` keeps `Voxel.angle = from + (goal - from) * ease(t)` and eases
toward the goal every frame, so setting a rung mid shot hands the camera a
destination rather than a position. `degrauFim` in a shot is now the whole
feature. The opening shot tips the world over WITHIN the shot instead of
between two cuts, which is what the caption was already claiming.

**The other two landed the same day, and both were also one call.**

**A shot that holds on one face.** The shot list only ever chose a camera RUNG,
which is an angle, not a distance. The host has a distance:
`CamControl.zoomBy(notches)`, positive pulls OUT. The blink shot now closes in
three notches and runs six seconds, which is long enough to catch two blinks on
a 0.12 s event with a period of seconds. The zoom is undone at the end of each
shot rather than at the end of the run, because every following shot's framing
assumes the default.

**A recorded mod set that is only ours.** `Loader:setEnabled` turns the others
off for the recording and back on afterwards. Measured: it disabled
`overworld_wild_spawns`, `example_mew_starter` and `nuzlocke`, and restored all
three. `DramaticShapeVoxelMod` is never disabled, because without the host
there is nothing to film. This one is not cosmetic: `overworld_wild_spawns`
puts Pokemon in the overworld, so a viewer could not tell which of three mods
they were looking at, and we would have been showing somebody else's work
without saying so.

**Cost:** low per improvement, and each one is a line in the shot list rather
than code. That has now been true twice, which is worth trusting.

### 5. RESOLVED BY MEASUREMENT: the grid is not ours to add

**Measured, and it inverted the plan.** The prediction was that our solid would
get the wireframe for free, because the grid is the scene shader measuring
distance to integer planes in MODEL space and our mesh goes through that shader.
It does not: the grid changes 54700 samples with the mod on and 54701 with it
off. It never touches us.

The reason is in the host, and it is a decision rather than an oversight.
`VoxelScene.drawCast` calls `Voxel3D.seams(false)` around the character pass,
and the comment above it says why:

> Characters carry no wireframe out here, whatever the V-GRID row says. The
> seams are what makes the WORLD read as built out of voxels, and the people
> walking around in it are the one thing that should read as drawn instead. A
> grid over a 16x16 sprite lands a line every couple of display pixels and turns
> a face into a mesh.

So our mod already behaves correctly, by inheritance, and turning the grid ON
for characters would not be filling a gap: it would be contradicting the host's
author on a point he thought about. It remains a possible product option with a
stated cost, and the cost is specific: the solid's side and top faces carry no
art at all, so seams over them emphasise exactly the invented surface.

**What changed instead:** `tools/ingame/probe_grid.lua` now guards the contract.
If the wireframe ever starts appearing on characters, somebody changed something
and we find out the same day. Cost of the whole item: one measurement.

### 6. First-person depth: measured, and it asks a harder question than it answered

The plan was to measure art share per depth at the first-person camera and pick
the value that holds the bar the overworld table uses (73.4%). Both halves of
that plan turned out to be wrong, and the measurements say why.

**Head on, depth is invisible.** At pitch 0 the SLAB's silhouette is exactly the
flat card at every depth, which is the conformity property the ruler already
asserts as IoU 1.000. Art share does not move, so there is no bar to hold:

```
pitch 0, facing the camera        art 100% front, identical at depth 1, 3, 5, 10
```

**The cost only appears at an angle**, and there it is steep:

```
pitch 0, yaw 30    depth 1   art 94.7%   side  5.3%
                   depth 3   art 85.7%   side 14.3%
                   depth 5   art 78.5%   side 21.5%
                   depth 10  art 65.2%   side 34.8%
```

By the overworld bar, depth 5 is the largest that holds it here.

**But the host makes first-person cards face the eye.** `billboardMatrix` yaws
the card about its feet toward the camera as the blend rises, easing the lean
out as the yaw eases in. A settled first-person view is therefore head-on, which
is exactly where depth shows nothing.

**The open question was: what does FIRST PERSON: SOLID actually buy at full
blend? ANSWERED 2026-08-10, and the answer is nothing.**

`probe_fp` sweeps eight blends and prints each one. The shape is unambiguous
and it reproduces byte for byte across four runs:

```
blend 0.13   CARD-SOLID   579   (0.7%)
blend 0.21                633
blend 0.31                624
blend 0.42                674
blend 0.53                936
blend 0.64               2091   (2.4%)
blend 0.74               5206   (5.9%)   <-- the peak
blend 0.83                  0   (0.0%)   <-- gone
```

The effect grows through the transition, peaks at blend 0.74, and is **exactly
zero** by 0.83. That is the host hiding the player's own card as the blend
completes, which it does deliberately.

**So the value of FIRST PERSON: SOLID is entirely in the transition**, and that
has to be said plainly in the release notes rather than implying a solid you
can walk around. It is honest and it is still worth having: 5.9% of the frame
at the peak is the player's own body, which used to collapse to a flat card
exactly when the camera was closest to it.

It also settles the depth question that item 6 sharpened. A settled first
person view shows nothing of the mod either way, so tuning depth for grazing
angles in first person would be tuning something nobody sees.

**What changes:** if the answer is "nothing at blend 1.0", the feature's value is
entirely in the transition, which is honest and worth saying out loud in the
release notes rather than implying a solid you can walk around. If the answer is
"something", the number to tune is the depth at grazing angles, and the table
above is it. Either way this is one measurement, not a design.
### 7. DONE: a lock, and a clear refusal

**State:** a hazard we hit today. `run.sh`, `clip.sh` and `trailer.sh` all begin
with `pkill -x love`, so starting one kills any measurement already running. The
truncated output reads like a short measurement rather than an interrupted one.

**What changes:** measurements stop being silently wrong when two things run at
once, which matters more now that the MacBook Pro can run the battery too. A
lock file plus a clear refusal is the whole fix.

**Cost:** an hour.

---

## Tier 2 — new capability

### 8. Judge v2: pixel features and the generator loop

**State:** the fitter reads mesh features only. The metric this project has
always judged by, the pixel share of the frame that is the artist's work, needs
a provenance render per variant.

**What changes:** the judge gains the feature it most needs to beat, and once it
beats it, candidates can be generated and scored without a person, with the
person only seeing the top few. That is the loop Kim described: v1, v2, v3, each
generation informed by the last.

**Cost:** medium. The provenance render exists; feeding one variant per row
through it is the work.

### 9. Per-part secondary motion

**State:** blocked. Body-wide inertia already ships. Real hair and bag lag needs
the mesh split into regions drawn with their own matrices.

**CORRECTION, and it matters because this document is about to become a spec.**
Two of the three things previously written here were wrong, and an adversarial
review caught them:

- **The cap faces blocker is real.** SLAB emits top and bottom only where the
  neighbouring row is empty (`main.lua:1662`, `:1669`) and CARVED does the same
  against solid neighbours (`:2066`, `:2070`). Cutting anywhere else exposes the
  inside of the back wall, because the host draws with culling disabled.

- **The shadow blocker was invented.** I wrote that `setDrawRange` is sticky
  state on a mesh `ShadowMap.draw` renders outside our wrap, so a forgotten
  range truncates the shadow. `setDrawRange` appears nowhere in this codebase
  except in the two roadmap files that claim it, and the shadow pass draws
  `SpriteBillboards.shadowQuad` (`VoxelScene.lua:853`), the original flat quad,
  not our slab. Our own file says in capitals not to patch `shadowQuad`
  (`main.lua:8`). The shadow was never going to be truncated because the shadow
  never touches our mesh. What survives in weakened form is that a draw range
  is sticky per mesh OBJECT, and our mesh is shared between every instance of a
  sheet in the frame, so a range set for one instance is still set for the next.
  That is a real hazard and a much smaller one.

- **"The top N rows is a contiguous prefix" is false for SLAB.** Front and back
  faces are emitted row by row, but side faces accumulate into `sideRuns`
  (`main.lua:1511`) and are emitted only after the whole row scan, sorted by key
  (`:1694`). A prefix split would drop or misplace every side face.

**Three more blockers the review found, all verified:**

- **Animation state is per character, not per region.** One `lifeInstance`
  carries one lag vector and one phase (`main.lua:2642`), `lifeDrawWrap`
  computes one transform (`:2893`) and applies it once to the whole mesh
  (`:2942`).
- **Region identity does not exist.** `ourMeshes` records `{ base, frame,
  frames }` (`main.lua:3012`), which is enough to know a mesh is ours and
  nothing about which part of it is hair.
- **The mesh is shared between instances**, so any per-region state has to live
  beside the draw call and not on the mesh.

**What changes:** characters stop moving as one rigid piece, which is the
difference between a breathing statue and something that reads as alive.

**Cost:** high, and higher than this document said an hour ago. It needs the
emission order reworked so a region is addressable at all, which is a change to
both builders and not a draw-range trick.

### 10. Attention and anticipation

**State:** designed, not started, with one hard rule already settled: never
rotate in Y. Side faces carry 0.0% art and the only reason nobody sees that
today is that the game never turns a character.

**What changes:** NPCs stop being scenery. A character that notices the player
is the cheapest possible step from "the world has depth" to "the world has
people in it", and it needs hysteresis so it reads as attention rather than as
twitching.

### 11. Laboratory: regions and host settings

**State:** the lab shows one character, every mesh option, all 67 sheets, and
records A/B picks.

**What changes:** it becomes the tool that makes rigging tractable, by drawing
the region boundaries and cap faces we would need to cut along, and it becomes
the place to see our characters under the host's own settings (grid, shading,
camera) rather than only under ours. Both are things Kim asked for and both pay
off exactly when items 5 and 9 start.

---

## Tier 3 — parked, with the reason recorded

### 12. Battle rendering probe

Paused by Kim, kept visible because an earlier note read as closing it and did
not. "Battle art is dead" answered whether battle sprites can enrich the
*overworld* character, where it still holds. Rendering the battle itself is a
different question, and three of the arguments that killed variable depth do not
survive the change of camera: the top-face law was measured under a camera that
looks down, the AI depth map's 52% art was measured there too, and the missing
side view is the one view a battle never shows. **The cheap first step is a
capability probe of the battle path**, the same step 1 the overworld got: find
out whether there is a seam to patch before designing what goes through it.

### 13. RESOLVED BY INVESTIGATION: there is no weather to read

The item said the mechanism already ships (wind is one more shear term in
`lifeApply`, exactly like `SWAY`) and that the open question was whether
anything exposes a wind or weather state. **It was never looked at. It has
been now, and the answer is no.**

**Nothing publishes weather.** Not the host, not another installed mod, not the
core. The host says so in its own changelog: its day/night module "carries the
hour **and not the weather**" (`DramaticShapeVoxelMod/CHANGELOG.md:1653`).
There is no `Weather.lua` in its 60 `lib/` modules. `Sky.lua:16` says "No
clouds, nothing moving", so there is not even a cloud layer to steal a
direction from. The core's `BattleState.field.weather` is battle scoped and
vanilla Gen 1 never writes it; a test asserts it stays nil. The one file named
for weather is `mods/examples/example_weather`, a battle ruleset example.

**What does exist is `DayNight`**, reachable by the same
`V.require("DayNight")` path this mod already uses for `VoxelState` and
`FirstPerson`, so consuming it is not a new class of coupling. And it has a
function whose signature is startling in context:

```lua
DayNight.shearAt(t)  -->  kx, kz, moon      lib/DayNight.lua:139
```

Two shear components, in **drift per pixel of height**, which is exactly the
unit `lifeApply(m, s, kx, kz, sx, corr)` consumes.

**That is a coincidence of units, not a wind source, and the distinction is the
whole finding.** The comment above it says what it is: "the shadow shear that
body throws, drift per pixel of height, opposite the bearing, cot(elevation)
long". Feeding it into the life channel would lean every character away from
the sun, in proportion to how low the sun sits. That is a real effect and it
might even look good, but calling it wind would be naming it after something it
is not, and this project has a rule about that.

**And it would mostly not move.** `DayNight.time()` returns a CONSTANT under
the four pinned settings (DAY, NIGHT, DUSK, DAWN), advances per frame only
under CYCLE, and under the default SYNC follows the machine's wall clock, which
means it drifts over real hours. So for most players the value is either frozen
or moving too slowly to perceive. A source that does not vary is not a source.

**What this unblocks instead, and it is item 4.** Time of day is both readable
and **settable**: `DayNight.setting` is a `ModSetting`
(`lib/DayNight.lua:69`) with values `{sync, day, night, dusk, dawn, cycle}`,
and `setting:setIndex(n, game)` is already called programmatically by the
host's own `forceSync`. Pinning DUSK for one trailer shot is a single call.
"Variety in time of day", which item 4 lists as missing, stops being a wish and
becomes a line in the shot list.

**Cost of this item: one investigation, and it closed.** If wind is ever wanted
it has to be invented here, with its own state and its own reason to vary,
rather than read from somewhere.

---

## 0. The risk that outranks everything above

**`main.lua` uses 159 of LuaJIT's 200 chunk locals. Headroom: 41.**

**Measured, and the measurement corrected the claim.** Both this document and an
external review read `main.lua:52-58` and reported the file as sitting at 199,
one local from not compiling. That comment records where the file WAS before the
refactor that introduced the generic `OPTIONS` table, not where it is. Appending
chunk locals until LuaJIT refuses puts the real figure at 41 free
(`tools/folga_locais.sh`).

So the risk is real and not imminent, which changes what to do about it: no
refactor is needed now, a gate is. Exceeding `LUAI_MAXVARS` is a **compile**
error, so the symptom is not a broken feature, it is the entire mod failing to
load for everyone, and it arrives on whichever commit crosses the line rather
than on the one that caused the growth.

`tools/folga_locais.sh` now measures the headroom and fails below a floor of 15.
It counts by construction rather than by reading `local` out of the text, which
would miss multiple assignment, block scope and every declaration inside a
function.

**What changes when this is addressed:** the mod stops being one edit away from
not loading at all. And note which file this is. An earlier draft of this
roadmap proposed splitting the render harness because it had grown to six jobs,
which is true and comparatively harmless: the harness failing is a bad day, the
mod failing to compile is every player's install. The production file is the one
that needed naming and it was the one missing.

**Cost:** medium, and it is the same shape as the refactor that already happened
once here, so there is a precedent in the repository to copy rather than a
design to invent.

---

## Cross-cutting: testing, practices, and the harness itself

These are not features, and skipping them is how the features above go wrong.

### 14. DONE, and its first run found a hole

Twice in one session a suite passed while asserting nothing real. `close()`
returns a boolean and I passed it a message as if it were an assertion, so six
checks ran and counted nothing; the count went from 552 to 558 when they were
repaired. The habit that caught it is cheap: break the thing on purpose and
confirm the suite notices.

**Built** as `tools/mutantes.sh` plus a declared list in `tools/mutantes.txt`.
It refuses a dirty tree, requires each pattern to match exactly one line,
restores from a trap so an interrupted run cannot leave the mod mutated, and
measures its baseline from the same run rather than from a number written in a
document.

**The first real run found a hole in the suite immediately**, which is the
strongest possible argument for the tool existing:

```
main.lua | a22 = s*c*c + n*n - kz*n*c  ->  + kz*n*c     SURVIVED, 603/603
```

Flipping the sign of the MOTION LAG term in the conjugated matrix changes
nothing that any of 603 checks look at. **The suite verifies the magnitude of
the lag and nothing about its direction**, so the body could lean INTO the step
instead of trailing behind it and the suite would stay green.

That is the same family as the defect that already shipped here: MOTION LAG
once sheared the body 45 degrees and passed 465 offline and eight in-game
checks, because every one asked whether something changed and none asked in
which direction.

Note the trap in writing the fix, because it is subtle: a test comparing two
opposite directions to each other does NOT catch this. Flipping the sign
inverts both, so "these two are opposite" still holds. The assertion has to be
absolute, that the top of the body is displaced AGAINST the direction of
travel.

### 15. DONE: a check for assertions that assert nothing

The `close()` bug is mechanically detectable: a call to a predicate helper whose
result is discarded. A small linter over the test file would have found all six
instantly. **What changes:** the failure mode that produced the most convincing
wrong result in this project becomes impossible to reintroduce.

### 16. Tests that ask "how much", not "did it change"

MOTION LAG sheared the body 45 degrees and passed 465 offline checks and eight
in-game checks, because every one of them asked whether something changed and
none asked by how much. The magnitude bounds added afterwards are the pattern.
**What changes:** every option with a number in the menu gets a test tying that
number to a physical quantity and an absolute ceiling no future level can break.

### 17. DONE: both machines ran gates all day

The MacBook Pro runs the whole battery with the same numbers. Right now it is
idle while this machine measures. **What changes:** a full battery in half the
wall-clock, and a second opinion on anything that smells machine-specific.

### 18. DONE: one command, plus a pre-commit hook

The battery is seven commands run from the repo root, and the order matters.
**What changes:** one command runs it, a pre-commit hook runs the offline suite,
and neither depends on remembering. Also the place to encode "check the ruler
before trusting a measurement", which is a rule that has already been forgotten
once per session.

### 19. DONE: the harness is 1415 lines across four modules

`tools/render/main.lua` is over 2000 lines and now holds the contact sheet, the
self-test, the metrics, the laboratory, the A/B mode and the feature extractor.
It works and it is well covered, but it is one file doing six jobs. **What
changes:** splitting it makes each job testable on its own; not splitting it
makes the next feature harder than the last. Worth doing before item 8 adds a
seventh.

---

## 20. The generator and critic loop

Kim brought in a method that went around the community: an FPS prompt by Mat
Shammer that produces a polished game by structuring the work into three
pillars rather than asking for a better result. Delegation to specialised
subagents, a rigorous visual critique loop where one agent creates and another
compares against a reference and demands corrections, and autonomy so the loop
runs without a person in it.

**Why it fits here better than it fits most projects.** The critique pillar is
the one everyone copies and the one that usually fails, because a critic with no
ground truth is just a second opinion with more confidence. This project already
measured the exact failure it produces: an AI redraw here satisfied every
numeric constraint we owned and produced worse art. A visual critic would have
approved it too, for the same reason, unless something outside the loop can tell
it that it is wrong.

**What we have that closes that hole:** the judge. Kim's pairwise picks are
ground truth that neither the generator nor the critic can argue with. So the
loop we should build is Shammer's with one extra edge:

```
  generator  ->  candidate render  ->  critic agent (visual)  ->  fix
                        |                     |
                        +---> numeric gates <-+
                                    |
                        judge trained on human picks
                                    |
                     calibration: does the critic agree
                     with Kim on the pairs Kim already judged?
```

**The calibration step is the whole point and it is cheap.** Before the critic
is allowed to drive anything, run it on the pairs Kim has already decided and
measure how often it picks the same side. A critic that agrees 55% of the time
is a coin flip wearing a lab coat; one that agrees 85% can be trusted to
pre-filter candidates so Kim only sees the close calls. That number is the
gate, and it is the same shape as the judge's own out-of-sample gate.

**What changes when this lands:** the iteration loop stops needing a person for
every step, and Kim moves from picking between two variants to setting the
direction and reviewing the finalists. That is the shift Shammer's method
promises, and here it arrives with a way to know whether it is working.

**Delegation, concretely.** The pieces are already separable and match the
subagent split cleanly: geometry builders, the shading options, the life
channel, the harness, the in-game gates, the clip and trailer tools, the release
pipeline. Each is a file or two with its own tests, which is what makes a
subagent's blast radius survivable.

**Autonomy, with the brake this project earned.** Loops here run against gates
that can pass for trivial reasons, and this session alone found three: a helper
that returned a boolean instead of asserting, a pair of variants that were
identical on screen, and a measurement truncated by another tool. An autonomous
loop must therefore end each round by re-running the ruler that checks the
ruler, not just the tests.

---

## 21. Hooks and the release pipeline

Kim's requirement: every release carries images and video, the clips are
professional, and the tooling supplies the accessories rather than the person.

**What exists:** `clip.sh` films any option side by side with captions drawn by
the game, `trailer.sh` records a shot list, `release_check.sh` verifies the game
can install the result and now also checks who signed it and whether the body
carries media.

**What is missing, in order:**

1. **`release.sh`**: build, sign as the right account, attach the zip plus the
   GIF and mp4 the clip tool produced, publish, then verify with the game's own
   parser. One command, and it refuses rather than publishing something the
   updater cannot see.
1b. **The explainer card is done**, see item 26. `card.sh` builds a before and
   after with numbered callouts from a recipe, and the before half can be
   rendered from a released tag rather than illustrated.
2. **Clip polish**: a lower third with the option name and level, a title card,
   consistent framing across features, and an output preset that fits Discord's
   size limit without looking compressed.
3. **A shot library**: named locations and camera setups the trailer and the
   clips both draw from, so a feature filmed today matches one filmed in March.
4. **Automatic assembly**: given a list of features in a release, produce the
   montage without a person choosing shots.

## 22. What the AI agents working here need

Not a feature, but it decides how fast everything above goes.

- **The memory is in Portuguese and the repo is going to en-US.** The memory can
  stay Portuguese, it is private, but it must stop being the only place where a
  hard-won fact lives. Anything an outside contributor would need belongs in the
  repo.
- **The traps are recorded but scattered.** Vsync stalls an occluded window,
  `VoxelState.setLevel` is overwritten every frame by the engine's Pipelines, a
  pipe closing hides a process that never exits, tools kill each other with
  `pkill`. Each is documented at the place it bit, which is right, but there is
  no single page a new agent reads first.
- **The rule that keeps being forgotten is "run the ruler before trusting a
  measurement".** It should be a hook, not a habit.
- **Mutation testing needs to be a command**, not something I remember to do.
  Both times it ran this session it found something.

### 23. DONE: a clip guard that can tell "no effect" from "no option"

`clip.sh` now refuses to publish an A/B whose two sides are byte identical,
which is the historical defect: an option written to the save without emitting
the event, so the cached mesh never rebuilt and the two halves were the same
image. Measured limit: with animation on, the two sides are filmed in sequence
and the motion phase advances between them, so they always differ and the guard
cannot see an option that arrived and did nothing.

**What changes:** the difference BETWEEN the sides gets compared against the
variation WITHIN one side. If they are the same size, the option changed
nothing, whatever the option says. That is the same shape as the floor the life
probe measures with its own procedure, and the same shape as the judge's
"features cegas" report: a comparison is only evidence when something else
establishes the scale.

### 24. DONE twice: two gates depended on luck and knows it

`probe_fp.lua` sweeps all four facings, measures the mod on against off, and
keeps the facing where a character is actually on screen. That was built to stop
zero from meaning two opposite things, and it works: on a run where nobody is in
frame it refuses the verdict instead of reporting a pass.

The problem is how often that happens. Measured across runs of the same
command: once it found a facing with 531 differing samples, once all four
facings returned 0. The probe teleports into a Pokemon centre and hopes an NPC
is in the camera's cone, and where the NPCs are is not something it controls.

**What changes:** the gate stops depending on the room. The player's OWN card is
guaranteed present below blend 0.9, because that is the case the whole feature
exists for, so the control belongs there rather than at full blend where the
host hides it. A gate that fails half the time for reasons unrelated to the code
trains people to rerun it until it is green, which is worse than no gate.

**A SECOND INSTANCE, found 2026-08-10 by running the whole battery as one
command for the first time.** The menu gate's M8 failed. Run on its own it
passed. Measured five times:

```
OFF 13, STRONG 59   passed        threshold is STRONG > OFF + 40
OFF 12, STRONG 48   failed
OFF 13, STRONG 45   failed
OFF 13, STRONG 56   passed
OFF 13, STRONG 48   failed
```

**Three failures out of five, with nothing wrong.** The floor is rock steady
(12 or 13 every time); it is the measurement of the effect that swings by 30%.

The cause is the one this project has already written down once, in a different
gate: it photographed the screen twice, 46 frames apart, and reported the
difference. That number depends on where in the BREATHING CYCLE the two
photographs land, not on how large the breathing is. A fixed interval measures
phase.

Fixed by sweeping a whole period and keeping the largest difference, which is
what amplitude controls. **The threshold was deliberately not lowered**, and
that is the point worth keeping: +40 would have gone green instantly at +30 and
the gate would have kept measuring the wrong thing, more quietly.

The lesson generalises past this gate: **the first full run of the battery as a
single command immediately found a flaky gate that months of running pieces by
hand had not.** Running things separately hides intermittency, because a human
who sees a red re-runs it, and a green rerun ends the investigation.

### 25. RETRACTED: the blink test now localises, and there was no defect

An earlier version of this item reported that the frame-3 mesh might be served
with frame-0 UVs, and called it a possible defect in something shipped. **That
was wrong, and the way it was wrong is worth keeping.**

I dumped every UV in the mesh, sorted them, looked at the first 40 and saw them
all between u = 0.026 and 0.05, which is frame zero. Those were the SIDE and TOP
faces, which sample a body texel from wherever they find one, and sorting puts
the smallest u first. Measuring only the FRONT faces: 22 quads, u from 0.5214 to
0.6151, inside frame 3's range of 0.5000 to 0.6667. Nothing wrong.

I looked at a subset and concluded about the whole, which is the failure this
project has a rule against, and I published it as a finding.

The real reason a point-UV lookup could not find the eye is legitimate and
smaller: SLAB emits RUNS, one quad per horizontal run of texels, so an open
eye quad has no single UV.

**Done instead:** the test counts how many FRONT faces change UV when the eye
closes and requires it to be a handful rather than all of them. Making the blink
touch every vertex makes it fail with "22 of 22", which is the mutation it
exists to catch.

---

## 26. DONE: the remaster explainer card

Kim brought in a reference generated with Gemini, kept at
`docs/refs/remaster-explainer-gemini.png`: a voxel head shown before and after
a "remaster", with five numbered callouts down the side, each one tied by a
line to the place in the picture where it happens.

There are two separate things in that image and they are worth very different
amounts, so they are separated here.

### 26a. The FORMAT, which we adopted and built

**Done.** `tools/render/compose` gained a `mode=card`, and
`tools/render/card.sh` builds one from a recipe file:

```
bash mods/voxel_characters/tools/render/card.sh \
  mods/voxel_characters/tools/render/cards/shading.card shading.png
```

The recipe is data and the shell only executes it, the same split the trailer
uses, so a card published in a release note is reproducible from something in
the repository rather than from a command somebody typed once.

**What changes:** a release note stops saying "improved shading" and starts
showing where to look. This is the accessory item 21 asked for and the first
one that is finished.

**Four things it does that the reference cannot**, and they are the reason
this was worth building rather than generating:

- **The before half can come from a released tag.** `before_tag=v1.5.0` runs
  the harness against that version's `main.lua` through `VOXEL_CHARS_MAIN`, so
  a release comparison is a measurement rather than an illustration of what we
  remember the old build looking like. A picture in a release note is a public
  claim.
- **It refuses two halves that are pixel identical**, exiting non-zero. That is
  the defect the clip tool already shipped once: an option written to the save
  without emitting the event, so the mesh never rebuilt and both sides were the
  same image. A card is a stronger claim than a clip because it names the
  changes in writing, so it refuses instead of warning.
- **It crops both halves to the union of their content boxes**, never to each
  one's own, because cropping them separately re-centres them and the before
  and after appear to jump.
- **The ruler checks it**, with four checks including a floor: the same card
  built twice has to be the same file, or comparing cards measures drawing
  noise instead of content.

**One of those four checks was hollow when written**, and mutation testing
caught it the same hour. It compared a card with four callouts against a card
with none, and passed with callout drawing entirely disabled: with no callouts
the card is a different height, so it was comparing canvas size. It now
compares two cards with identical text and only the coordinate changed, which
cannot differ for any reason except the tether being drawn.

### 26b. The CONTENT, point by point, against what this mod actually is

The five key changes in the reference are a description of a generic voxel
remaster. Measured against this project, **none of the five is open work: two
already ship, one is closed by the geometry of a slab, and two would move our
central metric the wrong way.** That is a more useful answer than a task list,
because it says why the mod looks the way it does.

**Point 3, bevelled edges: we have it, and as shade rather than geometry.**
`FRONT SHAPE` steps the front face into three pixel-aligned tones toward the
edge of each horizontal run and `TOP DOME` does the same for the cap. The
reference chamfers real geometry; we cannot, and the reason is measured rather
than stylistic. The ruler asserts IoU 1.000 between the SLAB silhouette and the
original flat card across five sprites and six frames, because this game's
camera looks at the artist's front face. A real bevel moves vertices and breaks
that contract on the first frame. Our options are built so that strength scales
the shade multiplier and never a vertex position, which is why any strength
above zero produces identical geometry.

**Point 4, colour gradation: we have it**, and the option's own help text is
"false roundness without a gradient" for the same reason. Hue is preserved
because the tone steps are multipliers on the artist's own texel.

**Point 2, lighting and ambient occlusion: measured, and the answer is that
there is nothing to occlude.**

I first wrote here that neighbour occlusion was "the open one worth taking" and
that the information was already in the builders. That was written from
plausibility, and it was wrong. The harness has had a full AO prototype since
before this item existed, with the host's own constants and corner rule, and it
was built to test exactly this. Measuring it, on `red` frame 0:

```
AO complete,        head on (pitch 0)    4654 pixels change
AO complete,        camera rung 35       4115
neighbour term only, head on                0     <-- nothing at all
neighbour term only, camera rung 35      1481
```

**Head on, with the ground term switched off, neighbour occlusion changes
exactly zero pixels.** All 4654 of the head-on difference is the contact term,
which already ships as `GROUND SHADE`. The 1481 that survive at the camera rung
are entirely on top and side faces, which carry 0% art.

The reason is geometric and it is the same law this project already wrote down
from the other side. A slab is an extrusion, so it has no concavity in depth,
and a visual hull cannot have any, because an intersection of silhouettes is
convex along that axis. The front face is one flat plane, so **no
geometry-derived lighting model can vary within it.** That is not a limitation
of our AO implementation; it is why `FRONT SHAPE` shades by position within a
run instead. Position in the run is the only variable a flat face has.

Neighbour AO would pay off on `CARVED`, which has real corners. `CARVED` also
has 1068 quads against SLAB's 104, thirteen times the upward-facing surface,
and it trades the artist's front face for stair steps. That trade is already
measured and already refused.

**Note the sequence, because it is the recurring failure in this file.** I
wrote the confident version into the roadmap first and measured second, and the
measurement inverted it. The prototype that answered it was already in the
repository, written for this exact question.

**Point 1, finer textures simulating materials: no, and it is the one that
would hurt.** This project judges itself by the share of on-screen pixels that
are the original artist's work, currently 73.4%. Procedural roughness is
invented pixel by definition, so it moves the number in the wrong direction
while replacing Game Boy palette colours with material simulation. That is not
a remaster of this art, it is a different art.

**Point 5, higher render resolution: no, and the host's author already argued
this.** The comment beside `Voxel3D.seams(false)` says the world should read as
built out of voxels and the people walking in it should read as drawn.
Supersampling only the characters makes them the one sharp thing in a soft
scene, which is the same mistake in the opposite direction.

**What this item is worth, given that none of it is buildable:** the reference
came in as a wish list and leaves as an explanation. Every one of the five
points is either shipped, refused with a number, or impossible on an extrusion,
and each of those answers already existed somewhere in this repository and had
never been written next to the question. Anyone who brings this reference back
in six months, including me, gets the answer instead of the work.

**One measurement is still missing and it is worth naming.** The harness only
builds voxel occupancy for `slab` (`tools/render/main.lua:1088`), so running it
with `ao=1` on `carved` changes zero pixels. That zero is the instrument, not
the finding, and it looked exactly like a result for a minute.
