# Render harness

Loads this mod under a stub of the host API, builds the real geometry from the
player's own sprite sheets, and rasterizes it to a PNG in about two seconds.

It exists because every visual defect this mod shipped through v1.2.2 was found
by a person watching a video. Nobody working on the code could see the output.
That is the whole reason a colour bug survived three releases in the default
mode: the tests proved the code did what the spec said, and nothing proved the
spec was right.

Run it from the **repo root**, not from this directory:

```
love mods/voxel_characters/tools/render sprite=red shapes=flat,slab frames=0
```

The PNG lands in the LOVE save directory and the path is printed on stdout.
Needs a display. There is no headless path: LOVE requires an OpenGL context.

## Options

```
sprite=red,blue        sheets from assets/generated/sprites, comma separated
shapes=flat,slab       flat | slab | carved | carved_plus, plus the prototypes below
frames=0,3             frame indices; 0 1 2 are the three roles, 3 4 5 the walk
yaws=0,25,50           camera yaw in degrees, one column per entry
rungs=15,35,50,75      the Voxel Mod's own camera ladder, one row per entry
pitch=0                overrides rungs with a raw camera pitch above the horizon
depth=3                the VOXEL CHARS thickness option
side_color=body        body | outline
palette=obj            obj | grey
cell=220               pixels per cell
metrics=1              print provenance and silhouette numbers
diff=1                 print a per pixel diff of every row against row 1
ao=1                   apply ambient occlusion (prototype, see below)
recess=2 outline=front  prototype relief parameters
out=sheet.png          output filename
```

`rungs` takes the Voxel Mod's angles, which are measured from top down:
`VoxelState.ANGLES_DEG = {0, 35, 15, 35, 50, 75}` where 0 lays the card flat on
the ground and 90 stands it upright. The camera pitch above the horizon is
therefore `90 - rung`, which this converts for you. Judging geometry at a pitch
nobody visits is how you end up fixing the wrong thing, which happened here.

## What the numbers mean

**Conformance.** `shapes=flat,slab pitch=0 yaws=0 metrics=1` prints `leak`,
`miss` and `IoU` against the original flat card for the same frame.

- `leak` is drawn where the card is empty. For **CARVED this must be zero by
  construction**: a visual hull is an intersection of silhouettes, so it can
  only remove material, never paint outside. A non zero leak is misalignment,
  not a threshold someone picked.
- `miss` is the card covering something this mod does not draw. For CARVED it
  is expected and is the material the hull carved away. A sudden growth in
  `miss` is the v1.2.1 regression returning: a wrong mirror axis makes the
  intersection eat body.
- At pitch 0 with SLAB, both should be 0 and `IoU` should be 1.000.

**Provenance.** `metrics=1` also prints what share of the visible pixels come
from the artist's sprite art (`front` and `back` faces) versus surface this mod
invented (`side`, `top`, `bottom`). All five draw from the same four tone
palette, so this cannot be measured from RGB. A second render pass paints an
identity colour per surface kind and counts.

Measured at the default rung, facing the camera:

```
  flat card   100% art
  SLAB         73% art     27% upward faces carrying no art
  CARVED       31% art     69% upward faces
```

That number is the community's "you lose all details" as a quantity.

**Animation.** `frames=0,3` prints each row's silhouette against row 1. Two
walk frames of the same builder must NOT agree: if they do, the shell being
drawn is the union of every pose rather than the pose that was asked for. That
is how the v1.3.0 walk cycle defect was found, after two testers described the
symptom and neither could say which code was wrong.

## Prototype shapes

These are not part of the mod. They live here so an idea can be looked at
before it is proposed, and the ones below were all rejected on the evidence
they produced.

`sculpt` and `sculptc` build a height field: a per row depth budget taken from
the side view as a **ceiling** rather than a metric, with tone distributing that
budget inside the row. `sculptc` differs only in treating the outline as a
silhouette edge rather than as the floor of a valley.

`ao=1` applies per vertex ambient occlusion using the host's own algorithm and
constants (`ChunkMesher.lua:260-340`), including the rule that matters: a
diagonal wedged behind both of its edges adds nothing, because the corner is
already as enclosed as it can get.

What they measured:

- **AO alone is marginal on a slab.** Mean factor 0.872, minimum 0.595, and
  side by side it is hard to see. Ambient occlusion needs concavity. An
  extrusion has none along depth, and a visual hull cannot have any, because an
  intersection of silhouettes is convex on that axis.
- **Relief makes AO work.** The minimum drops to 0.432 and a deep shadow band
  appears that the slab never produces.
- **Relief costs art.** The sculpted version drops from 73% to 46% original art
  at the default rung. Every voxel of depth added shows as upward facing
  surface at the angle this game is viewed from, and that surface carries no
  art. Three separate attempts landed on the same curve.

Two failures worth keeping, because both looked like the idea failing when they
were the prototype failing. The first put relief on the back, leaving the front
flat. The second painted invented faces from each pixel's own texel, which for
outline pixels is black, reproducing exactly the defect this mod fixed in
v1.1.0.

## Conventions the harness has to respect

Three of these were learned by getting them wrong, and each one first looked
like a bug in the mod.

- **The mod emits Y up.** `buildSlabMesh` writes `cellBottom - ly`, because the
  Voxel Mod's world is Y up and the host pivots the lean at the feet.
- **Depth is negated when projecting.** The front face is at `z = 0` and the
  body extrudes toward negative z, so a naive `less` depth test keeps the back
  and renders the sprite art at `OBJ_SHADE.back`, which reads as a colour bug.
- **A canvas renders bottom up.** This shader returns clip space untouched, so
  nothing compensates, and the provenance pass has to flip Y or every row is
  scored against a different row's pixels.

The frame count comes from sheet height, the way the engine derives it
(`src/import/RomExtractor.lua:481`), never from a constant. A hardcoded 6 turns
`nurse.png` into six 8 pixel frames and `boulder.png` into six 2 pixel ones,
which is exactly the three frame carve path.
