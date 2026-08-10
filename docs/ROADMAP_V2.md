# Roadmap towards v2

Everything open, ordered by what I would build first, with what each item
actually changes once it lands. Written to be the input to a specification, so
each item says what it unblocks and what it costs, not just what it is.

Ordering rule: an item comes earlier when finishing it makes later items
cheaper or safer, not when it is more exciting. Three of the first four are
unglamorous on purpose.

**Updated 2026-08-10.** Items 5 and 6 were answered by measurement rather than
built, item 8 is done, and item 0 was added after an external review named a
risk this document had missed. Where an item's plan turned out to be wrong, the
wrong version is kept next to the correction: this file is read to decide what
to build, and a plan that quietly changes teaches nothing.

**Done since this file was written:** the judge's whole loop (items 1 and 8's
machinery, waiting only on picks), the axis defect in the life channel, an
assertion linter, a local-headroom gate, a lock so the tools stop killing each
other, a LOVE error handler so a failure reaches stdout instead of a window, and
roughly forty checks that passed for reasons unrelated to what they claimed.

---

## Tier 0 — nothing else is worth much until these land

### 1. Feed the judge

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

### 2. Convert the project to en-US

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

### 4. Trailer, from 6/10 to something we would post

**State:** it records, and the obvious defects are fixed (English captions, no
wall pushing, first person shown as a before and after pair).

**What changes:** it becomes the artefact that carries every release and every
Discord post, which is the difference between a feature existing and a feature
being seen. Concretely still missing: camera movement inside a shot instead of a
static frame, variety in time of day, a shot that holds on one face long enough
to read the blink, and a recorded mod set that excludes other people's mods so
nothing on screen is theirs.

**Cost:** low per improvement, and each one is a line in the shot list rather
than code.

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

**So the open question is now sharper than the one I started with: what does
FIRST PERSON: SOLID actually buy at full blend?** The in-game probe measures at
blend 0.58, mid-transition, where the lean has not finished easing out and depth
is still visible; it found 1664 differing samples there. Nobody has measured the
settled case with a character guaranteed in frame.

**What changes:** if the answer is "nothing at blend 1.0", the feature's value is
entirely in the transition, which is honest and worth saying out loud in the
release notes rather than implying a solid you can walk around. If the answer is
"something", the number to tune is the depth at grazing angles, and the table
above is it. Either way this is one measurement, not a design.
### 7. Stop the tools killing each other

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

### 13. Weather and wind

Roadmapped rather than built because it depends on mods we do not control. The
mechanism already ships: wind is one more shear term in `lifeApply`, exactly
like `SWAY`. What is missing is a source, and the first question is whether the
host or another mod exposes a wind or weather state we can read.

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

### 14. Mutation testing as a habit

Twice in one session a suite passed while asserting nothing real. `close()`
returns a boolean and I passed it a message as if it were an assertion, so six
checks ran and counted nothing; the count went from 552 to 558 when they were
repaired. The habit that caught it is cheap: break the thing on purpose and
confirm the suite notices. **What changes:** green stops being taken on faith.
Worth a script that mutates a named line, runs the suite and reports how many
checks died.

### 15. A check for assertions that assert nothing

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

### 17. Both machines running gates

The MacBook Pro runs the whole battery with the same numbers. Right now it is
idle while this machine measures. **What changes:** a full battery in half the
wall-clock, and a second opinion on anything that smells machine-specific.

### 18. A skill and a hook for the battery

The battery is seven commands run from the repo root, and the order matters.
**What changes:** one command runs it, a pre-commit hook runs the offline suite,
and neither depends on remembering. Also the place to encode "check the ruler
before trusting a measurement", which is a rule that has already been forgotten
once per session.

### 19. Retire what the harness outgrew

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

### 23. A clip guard that can tell "no effect" from "no option"

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

### 24. The first-person gate depends on luck and knows it

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
