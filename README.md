# Voxel Characters

Gives the overworld cast real thickness when the
[Dramatic Shape Voxel Mod](https://github.com/DramaticShape/DramaticShapeVoxelMod)
is running.

The voxel world is 3D, but every person in it is a flat sprite card. This mod
extrudes those sprites into voxel slabs built from their own pixels, so the cast
reads as part of the diorama instead of standing in it like cardboard.

It is a companion mod. It does not modify the Voxel Mod, it ships no art, and
turning it off restores the original card on the next frame.

## Install

1. Download the latest release zip.
2. In game, open **MODS** and choose **Import mod .zip**.
3. Enable **Voxel Characters**. Restart if prompted.

## Requirements

- gen1recomp `0.1.51` or newer
- Dramatic Shape Voxel Mod `1.5.0` through `1.x`

Without the Voxel Mod installed, or with a version outside that range, this mod
loads, logs one line, and does nothing at all. The options row does not even
appear. It never breaks a game it cannot support.

## Options

Two rows, under **OPTIONS**:

```
VOXEL CHARS:   OFF / 1 / 2 / 3 / 5 / 10
SIDE COLOR:    BODY / OUTLINE
```

`VOXEL CHARS` controls slab thickness in voxels. Default is **3**.

**OFF** returns the original flat card immediately, no restart. That makes it the
cleanest way to compare before and after.

The effect only shows while the Voxel Mod's **VOXEL** mode is on. Press `3` first
(or use its VOXEL options row). Tip: the Voxel Mod's `5` key draws a wireframe on
every voxel, which is the fastest way to see what the thickness is doing.

Thickness `1` through `5` stays inside the depth budget the Voxel Mod calibrated
for flat cards. `10` is there for open routes but can clip into walls in tight
interiors, because this mod does not control that budget.

`SIDE COLOR` controls only the new side, top and bottom faces created by the
extrusion. Default is **BODY**.

**BODY** looks inward from outline pixels and colors those new faces from nearby
body pixels. This fixes the black side faces that thick outlines produced in
v1.0.0.

**OUTLINE** keeps the original outline pixels on those new faces. Front and back
always stay on the original sprite art in both modes.

## Compatibility

- **Sprite replacement mods work.** Geometry is built from whatever sheet the
  engine hands over, so custom character art voxelizes with no extra authoring.
- **Battles are untouched.** They draw through a different path.
- **The see-through-walls silhouette stays flat**, on purpose. See below.

## Known limitations

Deliberate trade-offs, not a to-do list.

**A faint dark seam on the side faces.** The Voxel Mod's sun pass draws the flat
card, so the shadow map holds no record of the slab's sides, and those sides end
up asking a flat-sheet shadow map whether they are lit. Fixing it would mean
replacing the mesh that the sun pass and the player's silhouette share, and that
silhouette is drawn with an inverted depth test, where a mesh carrying front and
back faces repaints the character on open ground. A subtle seam is the better
side of that trade.

**Disabling from the MODS panel needs a restart.** The engine has no unload hook
for an already-loaded mod, so switching it off there only lands on the next boot.
Use `VOXEL CHARS: OFF` instead, which applies on the next frame.

**Depth 10 can clip into walls.** Covered under Options.

**Deep outlines can still show dark side faces.** `SIDE COLOR: BODY` searches up
to 4 pixels inward. An outline or gradient deeper than that keeps the original
outline color on the side face.

**Outline detection is a Gen 1 sprite heuristic.** The mod treats the darkest
luminance on the sheet as the outline tone. That matches the discrete colors of
the shipped art, but anti-aliased or gradient replacement sprites may not be
recognized as outline. In that case the face falls back to the v1.0.0 behavior,
not anything worse.

## How it works

For mod developers, and for anyone deciding whether to trust this.

The Voxel Mod exports its internal namespace, and its own test drivers use that
door (`tests/bike_shop_shots.lua`). This mod goes in the same way:

```lua
mod.find("DRAMATIC_SHAPE").exports.lib   -- the V namespace
  → V.require("SpriteBillboards")        -- the cached module table
  → replace the .mesh field              -- VoxelScene calls it by field
```

`shadowQuad` and `invalidate` are left alone. `shadowQuad` in particular must not
be replaced: it feeds the inverted-depth silhouette described above.

The mesh is built over the union of every walk frame, with each frame clipped in
texture space by the shader's own alpha discard. Side walls are emitted per pixel
so an animating silhouette cannot leak through what used to be interior. Front,
back, top and bottom merge into horizontal runs, which takes a typical character
from about 1,100 quads down to about 440.

For `SIDE COLOR: BODY`, the mod identifies the sheet's outline tone and samples
nearby body-colored pixels for the new side, top and bottom faces. Horizontal
side faces search inward per pixel; top and bottom runs move only when the whole
run is outline and a whole adjacent line is body color, so the run merge cannot
mix unrelated sprite columns. Front and back never use that correction because
they are the visible sprite art, not new extrusion faces.

Camera pitch is baked into the geometry as a counter rotation, because the Voxel
Mod leans character cards back by the camera pitch and a leaning solid would tip
over. Pitch is quantized into one degree buckets and meshes are kept in a 64
entry LRU, so cycling through the VOXEL ladder cannot flood memory.

If another mod has already replaced `SpriteBillboards.mesh`, this one chains over
it and logs a warning. If another mod replaces it afterwards there is no host
hook to negotiate order, so that conflict can only be diagnosed from load order.

Every failure path falls back to the original card: an unsupported version, a
sheet whose layout cannot be derived without guessing, a mesh that fails to
build. The worst case is flat characters, never a broken game.

## Tests

```
luajit mods/voxel_characters/tests/voxel_chars_test.lua
```

55 assertions covering the version guard, the options rows and their persistence,
geometry and vertex format, per-frame clipping, pitch bucketing, cache keying and
LRU eviction, and side-face color selection.

## Credits

Built on the Dramatic Shape Voxel Mod by DramaticShape, and on
[gen1recomp](https://github.com/bryanthaboi/gen1recomp) by bryanthaboi.

The per-pixel voxelization follows the approach their own `Structures.lua` already
uses for props, and the face shading table matches theirs so the cast lights the
same way as the world around it.
