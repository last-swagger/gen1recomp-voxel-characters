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
