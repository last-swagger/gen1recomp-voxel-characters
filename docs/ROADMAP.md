# Roadmap: from a solid that stands still to a character that is alive

This is the plan for the next major direction of Voxel Characters. It exists because the previous
direction ran out of room, and the reason it ran out is measurable rather than a matter of taste.

Nothing here is released. The branch `melhoria-grafica` carries the work.

## Why this direction and not more shape

Every unit of depth this mod adds becomes surface that carries no art, because the artist drew a
character from the front and never drew the top of its head. Measured at the game's camera on
`red.png`:

```
  flat card    100% of drawn pixels are the artist's work
  SLAB          73%
  CARVED        31%
```

Two ceilings were measured, not guessed:

- **The carved visual hull cannot go further.** Shape-from-silhouette never reconstructs a
  concavity: an armpit, the gap between arm and torso, the space between legs. It returns the
  largest volume compatible with the silhouettes it was given. The 31% is close to the family's
  upper bound, not a tuning failure.
- **A limb rig is not present in the art.** Segmenting by what moves between the standing and
  walking pose gives, on `red` and `blue`, one single blob covering the whole lower half. Not
  separate legs and arms. Sheets with richer animation (`bruno`, `lance`) do decompose, but the
  two characters a player looks at most do not.

Meanwhile the two things that actually impressed the community were the solid itself and the blink.
Neither is about preserving the artist's pixels. Both are about the character reading as a living
thing. Shape has a proven ceiling; life has none.

## The channel this plan is built on

The host asks this mod for a mesh once per character per frame, and draws it on the next line. The
cached mesh can be rewritten at runtime, whole vertices at a time, position included. The blink
already does this in production, for two texels, twice per blink.

Measured cost of using it fully, ten characters on screen, vsync disabled so the number is the code
and not the monitor:

```
  draw only                          0.237 ms/frame
  + rewrite   8 vertices per char   +0.019 ms
  + rewrite 120 vertices per char   +0.015 ms
  + rewrite 400 vertices per char   +0.179 ms      a whole character, every frame

  frame budget at 60 fps: 16.7 ms
```

Rewriting the entire character every frame costs about one percent of the frame. There is no
performance wall between the first step of this plan and the last.

**But the mesh is created with the `static` usage hint** (`Voxel3D.newMesh`), and the host's own
heavy animation path (`StadiumRig`) creates `dynamic` meshes and uploads in batch, with a comment
saying that is exactly what the hint is for. Dense per-frame rewriting of a static buffer is the
misuse the hint exists to prevent. Two independent reviews flagged this. The plan below therefore
avoids per-frame rewriting wherever a baked alternative exists.

## The problem that shapes every step: one mesh, many characters

The mesh is cached per sprite and frame, and **shared by every instance using that sheet**. Two
Rockets in a room are the same mesh drawn twice. If it breathes, they breathe in perfect unison,
which reads as a robot chorus rather than as life.

The mod is called with `(def, frame)` and nothing else, so there is no instance identity at that
point. **There is one, one function later.** The host builds `billboardMatrix(px, py, y, mirror)`
and hands it to `Voxel3D.draw(mesh, texture, model, pull, sunModel)`. That matrix is a plain table
of sixteen numbers.

Measured, not assumed:

```
  Voxel3D.draw signature   identical in all three living host lineages
  model[12] - 8            returns py EXACTLY, immune to the mirror and to camera lean
  model[4]  - 8            off by exactly 8 depending on the mirror, which we cannot see
  first person blend > 0   the only case that dirties z, and this mod draws a flat card there
```

So a stable per-instance value is available for two array reads, at the cost of patching a second
host function.

## The steps

Each step is cheap to undo, and the next only makes sense if the previous one worked.

Everything below marked DONE was measured, not asserted. The measurements are named where they
live so anyone can re-run them.

### 1. Prove the position arrives clean in the running game — DONE

`tools/ingame/probe_draw.lua` wraps `Voxel3D.draw` in the live game and checks eight properties.
All eight passed, in Viridian City with 25 characters on screen:

```
  P1 the wrap intercepts        50 character draws in one frame
  P2 m[12]-8 is the WORLD py    every entity on the map has its draw
  P3 instances are distinct     25 characters, 0 position collisions
  P4 the value is stable        0 of 60 frames diverged
  P5 the mirror does not dirty  m[12] moved 0.000; m[4] moved +16
  P6 the camera rung does not   0 of 7 rungs changed it
  P7 walking stays continuous   largest jump 1.00 px, zero NaN
  P8 the CAMERA does not leak   0 of 24 frames, with the camera moving
```

**P8 was the one that decided everything else.** The position is world space, not camera relative,
so phase-by-position does not turn into a wave when the player walks.

Two corrections to what this document said before: `m[4]` is `px`, or `px + 16` when mirrored, not
plus or minus 8. And each character is drawn **twice** per frame from the same call site, because
the host draws the water reflection copy through the same function.

### 2. Extend the capability probe to the second patch point — DONE

`probeCapabilities` asks whether `Voxel3D.draw` exists and is callable. When it does not, the draw
wrap is never installed, the three life options do not appear in the menu, and the LIFE row reads
`NO CHANNEL`. The rest of the mod works untouched.

### 3. Baked phases instead of runtime rewriting — DROPPED, and this is why

This step existed to avoid rewriting a `static` vertex buffer every frame. **The whole problem
turned out to be avoidable**: the animation lives in the model matrix, which the host allocates
fresh per character per frame, so there is no buffer write at all.

The algebra that makes it work: the host builds

```
  M = T(px+8, y, py+8) . Rx(lean - pi/2) . [S(-1,1,1)] . T(-8,0,0)
```

and a local scale `S(1,s,1)` commutes with both the mirror and the `T(-8,0,0)`, so
`M . S(1,s,1)` puts the scale exactly where it belongs: before the lean, pivoted on the feet.
Only column 2 of the matrix changes; the other twelve numbers are copied. Two independent reviews
were asked to break this and both confirmed the injection point.

So the static-buffer objection and the untested ARM handheld risk both disappear, not because
they were answered but because nothing writes a buffer any more.

What it costs, measured in Viridian City with 25 characters on screen, vsync off, warmed up first
and interleaved A/B/A/B so warm-up drift cannot pass for effect:

```
  all three off      4.412 and 4.150 ms      mean 4.281
  all three on       4.377 and 4.517 ms      mean 4.447
  difference         0.166 ms of a 16.7 ms budget
  ruler noise floor  0.261 ms
```

The difference is **smaller than the noise floor**, so the honest statement is not "it is cheap"
but "this ruler cannot measure it." An earlier version of this benchmark reported the feature
making the game 2.6 times faster, which is impossible; that was mesh construction landing on
whichever condition ran first.

### 4. Breathing — DONE

`BREATH`, off by default, three levels. Scales the solid vertically about its feet, out of phase
per character. Measured on screen by `tools/ingame/probe_life.lua`, in an empty room so nothing
else can move:

```
  everything off      envelope    0 pixels     (the control)
  BREATH SUBTLE       envelope   36 pixels
  BREATH NORMAL       envelope  246 pixels
  BREATH STRONG       envelope  275 pixels
  VOXEL CHARS off     envelope    0 pixels     (proves the change is ours)
```

### 5. Judge it in the game, not in the harness — DONE

`tools/ingame/run.sh` now reaches the overworld and photographs the mod with nobody clicking
anything. Two independent bugs were in the way and neither was what the symptom suggested: the
scripted boot ignores `POKEPORT_GAME` and was booting a version that was not ready, and vsync on
an occluded window stalls the whole loop at under a frame per second. Details in the commit.

Two things the owner asked for after seeing the first screenshots, both done:

**The player was landing on things.** `U.teleport` writes the player to the requested tile with no
validation at all, so it parked him on a sign. `tools/ingame/pouso.lua` runs the seven checks the
engine itself uses (bounds, walkable, sign, warp, warp tile, pad or hole, NPC) and returns the
nearest tile that passes. Roughly twenty drivers in this repo hand-roll some subset of that; none
covers all seven.

**Stills cannot judge motion.** `tools/ingame/clip.sh <dir> <key=value>` records the same scene
twice, with the option off and on, and assembles `off.mp4`, `on.mp4`, a side-by-side `ab.mp4`
(left is always off) and `ab.gif`. Three lessons are baked into it: record indoors, because the
day cycle changes the sky between the two takes; crop the video instead of zooming the game camera,
which tilts down and fills the frame with floor; and walk the character for `MOTION LAG`, because
a spring at rest makes both sides identical.

**The clip immediately paid for itself.** `MOTION LAG` was shearing the body nearly 45 degrees:
the level number was being used as a slope instead of a head displacement in pixels, because the
divide by the 16 px cell height that `SWAY` has was missing. At level 0.70 the head moved 11 world
pixels, most of a tile, and the character read as falling over rather than walking with weight.

All 465 offline checks and all eight in-game checks passed with that bug in place. Every one of
them asked *did it change*; not one asked *by how much*. That gap is now closed with magnitude
bounds in the offline suite, including an absolute ceiling that no future level can exceed without
a test failing.

### 6. Desynchronise — DONE

An instance tracker matches each draw to a remembered character by cell, then by nearest
neighbour within 24 px, so a character keeps its phase while it walks. The phase advances with the
**clock**, never with position, which is what stops a walking character from breathing at double
speed. Two characters in the same room are out of phase because they were seeded from where they
stood.

### 7. Per-sheet personality — DONE

`LIFE_PERSONALITY`, keyed by sheet name, multiplies rate, breath and sway. A sleeping gambler
breathes slowly and does not sway; a swimmer sways more; a guard at attention barely moves. And
`poke_ball` and `boulder` are pinned to zero, because an item ball that breathes is the most
obvious possible defect of this whole idea.

### 8. Secondary motion — PARTLY DONE, and the rest is named honestly

`MOTION LAG` gives the body inertia: a second-order spring per instance shears the solid backward
from its feet while it moves and overshoots when it stops.

**What it is not:** per-part motion. A single matrix transforms the whole mesh one way; it cannot
hold the bag back while the torso follows the step. Both external reviews said so and both are
right. What ships here reads as weight, not as hair.

Real per-part secondary motion needs the generated mesh split into regions (body, head, bag) and
each region drawn with its own matrix. That is the next real piece of work on this front, and it
is not started.

### 9. The parallel front, which depends on none of the above

The branch already carries three finished, unreleased options: `FRONT SHAPE`, `TOP DOME` and
`STEP WEIGHT`. All measured, all tested, all off by default.

**Enables:** having something to ship even if the animation direction is slow or dies.

### 10. What does not happen without a decision

No release. Six new options now sit on this branch with conservative defaults, and none of them
has been judged by eye on a real screen by the person whose taste decides.

## Standing decisions

- **Patching more of the host is authorised.** The cost is that a future fork can break more of
  this mod, which is why step 2 is not optional.
- **Every visual change ships as a menu option with a conservative default.**
- **The silhouette gate is not negotiable:** `IoU 1.000` against the flat card at pitch 0.
- **Measurement guards against regression; it does not decide whether something looks good.** An AI
  redraw once satisfied every numeric constraint in this project and produced worse art.


---

# Next: the world notices you

1.6.0 is out. What follows was decided by crossing three independent reads of
the same question, and the disagreements are where the useful part is.

## What was asked

Three candidates plus an open slot, put to two external reviewers and to a
reading of our own code:

- **A. Split the mesh into regions** drawn with their own matrices, so a head or
  a bag can lag behind a torso.
- **B. React to the world** instead of only to the clock: notice the player,
  lean into weather, settle when alone.
- **C. Use the battle art** already on the player's disk, 56x56 against the
  overworld's 16x16, twelve times the pixels.
- **D. Something none of us had thought of.**

## A. Regions: NOT next, and the reason is ours, not theirs

One reviewer called it a trap; the other said it is worth doing but only as
continuous vertical bands, never as a limb rig. Reading our own builders found
two blockers that neither of them named, and they are the ones that decide it:

**The cut row has no faces.** Top and bottom quads are emitted only where the
silhouette is exposed (`if not at(sx, ly - 1)`). At an interior row boundary
that test is false on both sides, so slicing there leaves a hole, and the host
draws with culling off. You would not see a gap, you would see the inside of the
far wall.

**The draw range is sticky global state on a shared mesh.** `setDrawRange` is
set on the mesh, not on the draw call, and the same mesh is drawn by
`ShadowMap.draw` **outside our wrap**. Any range left set truncates the shadow.
Every one of the five early-return paths in the draw wrap would have to reset it.

The good news, for later: emission is already row-major top to bottom in both
builders, so "top N rows" is already a contiguous prefix. `CARVED` needs no
reordering at all. Blink survives, because it captures vertex indices live at
emission rather than recomputing them, so restructuring loops is safe and only
permuting the finished arrays would corrupt it silently. **This is moderate
work, not a rewrite, and it is worth doing after the cheaper wins.**

## B. React to the world: YES, with one hard rule

The reviewer who liked it most called it the largest gain per unit of risk. The
other one agreed for scale and **refused it for yaw**, and that refusal is
correct, because it lands on a ceiling we measured ourselves.

**Never rotate in Y.** The side faces of every character carry 0.0% of the
artist's art, and the only reason the player never sees that is that the game
never yaws. A character that turns to look at the player would expose them.

So the effect must be built from what does not rotate in Y: lean, scale, shear,
timing. That is enough for attention (the body inclines toward the player),
anticipation (posture rises as they approach), and settling (it decays when they
leave). Both reviewers independently warned about the same failure: reaction
that snaps at an exact radius reads as nervous. It needs hysteresis and a
damped spring, which the instance tracker already has.

## C. Battle art: DEAD, and this closes it

The roadmap has kept this open since it was written. One fact retires it:
**battle sprites have no walk cycle and exist in only two directions.** There is
nothing to animate a character walking north, east or west with. Add 19 of 67
sheets having a counterpart, and twelve times the pixel density sitting beside
16x16 neighbours, and it is not a near miss, it is the wrong asset.

## D. What neither of us had: the footfall

The strongest new idea is the cheapest. **Squash on the step's impact**, synced
to the walk frame, which this mod already knows: the mesh cache is keyed by
frame and the draw wrap can read it. A small vertical squash at the moment the
feet meet, released at the top of the step, transmits the weight transfer of the
walk cycle to the solid without segmenting a single limb.

Both reviewers, from different directions, arrived at the same shape: **more
inertia, no anatomy.**

## The order

1. **Footfall squash.** Cheapest, physical, uses the frame we already have.
2. **Attention and anticipation**, with hysteresis, and no yaw ever.
3. **Per-instance temperament**, extending the personality table from amplitudes
   to responsiveness: a child reacts faster, a guard barely at all.
4. **Regions**, once the two blockers above are solved on purpose rather than
   discovered by a seam in a screenshot.

## One disagreement left open, to be measured and not argued

One reviewer proposes easing the 90 degree turn over 0.08 to 0.12 seconds,
arguing the eye cannot register missing side art that briefly. Our own
measurement says those faces carry no art at all. **That is a testable
disagreement and we now have the tool to settle it**: `clip.sh` films the same
turn with and without, side by side. Measure before building.

## Tooling, which earned its own line

The owner is right that tooling has paid off more than any single feature. Two
of the three defects found today were found by tools built the same day, and the
third was found by a person because no tool covered that surface.

- `tools/ingame/menu.lua` presses keys in the real options menu. It exists
  because the A-on-STATUS bug shipped past every other gate, and it measured
  something worth knowing on its first run: our rows start at index 43 of 48,
  and `BREATH` is 45 presses of DOWN away from the player.
- `tools/release_check.sh` asks the game whether a release is installable, by
  running the game's own updater code against the live GitHub response. It
  exists because every release from 1.0.0 to 1.6.0 was invisible to the in game
  updater and no test we owned could have seen it: the bug lived in the shape of
  a filename on GitHub.

## Parked, with the reason written down

Two lines the owner asked to keep visible without starting them.

**Battles.** Paused deliberately, not dropped. Worth recording because an
earlier note here read as closing it and did not: the verdict "battle art is
dead" answered *can battle sprites enrich the OVERWORLD character*, where it
still holds, since a battle sprite has no walk cycle and cannot animate someone
walking north. Rendering the battle itself is a different question, and three of
the arguments that killed variable depth do not survive the change of camera:
the top-face law was measured under a camera that looks DOWN, the AI depth map's
52% art was measured there too, and the missing side view is the one view a
battle never shows. Before any depth estimator, the cheap step is a capability
probe of the battle path, the same step 1 the overworld got: find out whether
there is a seam to patch at all.

**Weather and wind.** Roadmapped rather than built, because it depends on mods
we do not control and on game state we have not confirmed exists. The mechanism
is already shipped and proven: wind is one more shear term in `lifeApply`, which
post-multiplies the draw matrix exactly like `SWAY` does today. What is missing
is not geometry, it is a source. The first question is whether the host or
another mod exposes a wind or weather state we can read, and that is a
measurement, not a design.
