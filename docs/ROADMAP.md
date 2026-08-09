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

### 1. Prove the position arrives clean in the running game

Wrap `Voxel3D.draw`, read the matrix, log the position. Change nothing else. The arithmetic is
already proved on paper; this proves it with NPCs walking, turning and stopping.

**Enables:** knowing in an afternoon whether the ambitious version exists at all. If the number
arrives dirty, the plan shrinks to subtle shared animation and this document is amended to say so.

### 2. Extend the capability probe to the second patch point

The probe already refuses a host that does not export the modules this mod calls. It must also
check the second function, and the feature must simply not switch on when the host does not match,
leaving the rest of the mod working.

**Enables:** touching more of the host without betting the whole mod on it. This is what let v1.5.0
survive the original repository going offline twice.

### 3. Baked phases instead of runtime rewriting

Build a small number of pre-deformed variants of each mesh and select between them, rather than
rewriting vertices while the game draws.

**Enables:** animation with no runtime buffer writes at all, which removes the static-buffer misuse
and the driver risk on weaker hardware that neither review could rule out.

### 4. Breathing

The upper body rises and falls by a fraction of a pixel. Not an animation a player watches; the
absence of the frozen feeling.

**Enables:** exercising the whole new machine with the smallest possible effect, where a mistake is
easy to see and easy to switch off.

### 5. Judge it in the game, not in the harness

The offline harness measures geometry in two seconds, but it draws on flat grey at ten times the
real on-screen size and cannot show motion at all. The in-game gate exists and works; what it still
fails at is getting past the launcher unattended.

**Enables:** comparisons from the real game instead of asking the owner to record video.

### 6. Desynchronise

With per-instance position, two identical NPCs in a room breathe at different points in the cycle
automatically, because they stand in different places.

**Enables:** the difference between two puppets on one string and two people. This is the step that
turns the trick into an illusion that holds.

### 7. Per-sheet personality

A small table saying this one breathes slowly, that one sways, this one barely moves. The mod
already has exactly this shape of table for eye marks, with 112 entries.

**Enables:** characters with temperament without anyone drawing a new pixel.

### 8. Secondary motion

Hair, bag and coat lagging behind the step.

**Enables:** the demonstrable moment. This is what separates an animated model from a character in
any 3D game, and it is what a ten second clip can carry.

### 9. The parallel front, which depends on none of the above

The branch already carries three finished, unreleased options: `FRONT SHAPE`, `TOP DOME` and
`STEP WEIGHT`. All measured, all tested, all off by default.

**Enables:** having something to ship even if the animation direction is slow or dies.

### 10. What does not happen without a decision

No release, and no work on secondary motion before breathing has proved the machine. The order is
the point: each step is cheap to undo, and stopping at any of them leaves something that works.

## Standing decisions

- **Patching more of the host is authorised.** The cost is that a future fork can break more of
  this mod, which is why step 2 is not optional.
- **Every visual change ships as a menu option with a conservative default.**
- **The silhouette gate is not negotiable:** `IoU 1.000` against the flat card at pitch 0.
- **Measurement guards against regression; it does not decide whether something looks good.** An AI
  redraw once satisfied every numeric constraint in this project and produced worse art.
