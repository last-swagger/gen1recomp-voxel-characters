# Voxel Characters

Gives the overworld cast real thickness when the
[Battle Art Voxel Fork](https://github.com/absol89/DramaticShapeVoxelMod)
or legacy Dramatic Shape Voxel Mod is running.

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
- Battle Art Voxel Fork `>=1.7.0 <2.0.0`, mod id `BATTLE_ART_VOXEL_FORK`
- Legacy Dramatic Shape Voxel Mod `1.5.0` through `1.x`, mod id
  `DRAMATIC_SHAPE`

The fork is the reference host and is preferred if both host ids are installed.
Its tags are not monotonic semver by release date: `1.7.6` is the newest by
date, while `v1.68` parses as `1.68.0` and compares higher, so both are inside
the supported fork range.
Without a supported host installed, or with a version outside the host's range,
this mod loads, logs one line, and does nothing at all. The options row does
not even appear. It never breaks a game it cannot support.

## Options

Six rows, under **OPTIONS**:

```
VOXEL CHARS:   OFF / 1 / 2 / 3 / 5 / 10
SIDE COLOR:    BODY / OUTLINE
SHAPE:         SLAB / CARVED / CARVED+
GROUND SHADE:  OFF / ON
BLINK:         OFF / ON
TOP EDGE:      OFF / ON
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

`SHAPE` selects the geometry builder. Default is **SLAB**, which is the v1.1.0
behavior: the current sprite silhouette is extruded to the selected fixed depth.

**CARVED** builds a visual hull from each character sheet's front, back and side
views. The side view controls real depth, so a wide character gets a deeper body
than a narrow one. The depth number above is still used by **SLAB**; **CARVED**
derives its depth from the art.

CARVED is rough, and testers have said so. A visual hull keeps the outer
silhouette and flattens everything inside it, so surface detail that is not part
of the outline reads as lost compared to SLAB. That is a property of the method,
not a bug to be tuned out, and it is why the default is still SLAB. CARVED+ below
is the first attempt at putting some of that detail back.

**CARVED+** starts from **CARVED** and adds tone relief on the front surface. It
uses two recess steps: `red.png` has three opaque body tones beyond the outline,
so more steps would overfit the pixel art. This can read as extra volume around
the waist, neck and arms, but it can also cut grooves where the original artist
darkened pixels only to separate shapes, such as the cap from the forehead. That
is why it is a separate step and not the default. The recess is capped by the
side-view depth so at least one voxel layer remains, including very thin custom
sprite sheets.

`GROUND SHADE` adds a host-style contact shade to the lowest six pixels of the
solid mesh. Default is **OFF**. It is meant only to plant the character on the
floor, not to add full ambient occlusion across the body.

`BLINK` swaps known front-facing eye texels to nearby skin texels for a short
closed-eye frame. Default is **OFF**, so enabling the mod does not impose a new
visual change beyond the selected shape and thickness. Blink only applies to
the standing front SLAB frame, with a verified eye entry and a safe nearby body
texel. Walking frames, sheets with no entry, object sheets, and eyes that cannot
find body color within 4 pixels stay open.

`TOP EDGE` darkens only exposed **SLAB** top faces. Default is **OFF**. When
enabled, those faces use shade `0.82` instead of the host-matching `1.00`, which
can read as a false top-down edge on hats and hair. The trade-off is deliberate:
with it ON, the character's upward faces no longer match a world wall using
`+Y up = 1.00`.

The carved modes do not merge horizontal runs yet. On `red.png` frame 0, **SLAB**
now builds 104 quads: the exposed top and bottom faces are 16 quads each instead
of 176 each, and the `side_e` and `side_w` faces are 17 quads each instead of
176 each. On `red.png` frame 3, **CARVED** builds 1,044 and **CARVED+** builds
1,018. The unconditional eye split adds 542 quads across the 303 measured SLAB
meshes, 0.27%, so it is not tied to the `BLINK` option.

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

**CARVED cannot reproduce concavity.** A visual hull is the intersection of
silhouettes, not a full model. If a cap brim exists only in the front view, the
hull has no separate side-depth evidence for that recess, so the brim volume can
continue through the back. **CARVED+** tries to carve some of that interior space
from tone, but tone is ambiguous in Gen 1 art: it marks both contour and volume.

**CARVED needs three views.** Sheets with front, back and side frames can be
carved, including stationary three-frame NPC sheets. One-frame sheets still fall
back to **SLAB** because the mod has no side or back silhouette to intersect.

**Characters that share one sheet blink together.** The host calls
`SpriteBillboards.mesh(def, frame)` without an entity id or world position, so
the blink phase is derived from the sprite sheet name. Two NPCs using the same
sheet will close their eyes at the same time.

## How it works

For mod developers, and for anyone deciding whether to trust this.

The host Voxel Mod exports its internal namespace, and its own test drivers use
that door (`tests/bike_shop_shots.lua`). This mod goes in the same way:

```lua
local host = first host whose exports.lib and version range are supported
host.exports.lib                         -- the V namespace
  → V.require("SpriteBillboards")         -- the cached module table
  → replace the .mesh field               -- VoxelScene calls it by field
```

`shadowQuad` and `invalidate` are left alone. `shadowQuad` in particular must not
be replaced: it feeds the inverted-depth silhouette described above.

In **SLAB**, the mesh is built from the pose actually being drawn: a pixel is
occupied only if it is opaque in that exact frame, not if it is opaque in any
frame on the sheet. Before v1.3.0 the occupancy test read the union of every
walk frame instead, relying on the shader's alpha discard to clip each pose
back down; that worked for front and back, which sample the current frame, but
not for the invented side, top and bottom faces, whose UVs deliberately land on
a texel that is never discarded, so every pose showed the walk cycle's full
silhouette at once. Side walls are still emitted per pixel, which used to be
required so an animating silhouette could not leak through what was interior to
that union; the mask is pose-exact now, but sides still emit per pixel unless an
adjacent vertical run has the exact same resolved UV. Front and back merge into
horizontal runs. Top and bottom are emitted per pixel so `SIDE COLOR: BODY` can
search vertically for a nearby body texel even when a horizontal run mixes body
and outline pixels.

When `BLINK` is available for a SLAB sheet, verified front-facing eye pixels are
split out of the merged front run as their own quads even while blinking is
disabled. That keeps the cached mesh topology identical in both eye states.
Blinking then mutates only those vertices' UVs in place, from the eye texel to a
nearby body-color texel found by the same 4 pixel body search used by
`SIDE COLOR: BODY`. Time is never part of the mesh cache key.

In **CARVED**, each pose uses the front, back and side frames as orthographic
silhouettes. A voxel is solid only when all three views agree. The back view is
mirrored on X before the intersection because it is the opposite view of the same
body. The side frame in Gen 1 art is the character facing left; this mod treats
the leftmost opaque side column as the body's front and maps later columns
toward the back. Meshes are rotated per requested frame so the camera still sees
the same silhouette that the old flat card showed for that frame.

In **CARVED+**, the front tone then recedes that front surface by up to two voxel
columns. Light pixels stay at the hull surface; darker body pixels step inward.
The outline tone is not used to calibrate the range, but outline-dark pixels can
still receive the deepest recess after the body range is known, which is the
intentional contour-versus-volume trade-off described above.

For `SIDE COLOR: BODY`, the mod identifies the sheet's outline tone and samples
nearby body-colored pixels for the new side, top and bottom faces. Horizontal
side faces search inward per pixel. Top and bottom faces search vertically per
pixel, up to the same 4 pixel limit. SLAB emits side, top and bottom faces only
where the adjacent sprite cell is transparent, so stacked or adjacent pixels do
not create hidden faces inside the body. Those exposed faces sit on the exact
pixel boundary. Front and back never use that correction because they are the
visible sprite art, not new extrusion faces.

The baked face shade values match the host world mesh:

```
front:  0.90
back:   0.68
side:   0.78
top:    1.00
bottom: 0.55
```

With `TOP EDGE: ON`, exposed SLAB top faces use `1.00 * 0.82`.

The two side directions intentionally share one value. The host mirrors sprite
cards after asking `SpriteBillboards.mesh(def, frame)` for geometry, so a mesh
with different baked east and west shades would swap lighting when the same
sheet is mirrored.

When `GROUND SHADE` is **ON**, each vertex below height 6 receives the same
contact term used by the host ground shading, with strength 2.4:

```lua
shade * (1 - 0.12 * 2.4 * (1 - y / 6))
```

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

190 assertions covering host detection, version guards, the options rows and
their persistence, slab geometry and vertex format, carved visual-hull surface
faces, per-frame silhouette projection, absolute role position, depth-axis
orientation, three-frame carve sheets, carve fallback, pitch bucketing, cache
keying and LRU eviction, side-face, top-face and bottom-face color selection,
three-view carving, face shade values, ground contact shading, top-edge shading,
hidden SLAB top and bottom face culling, CARVED+ relief direction and
thin-sprite depth limits.

## Credits

Built on the Battle Art Voxel Fork by absol89, the legacy Dramatic Shape Voxel
Mod by DramaticShape, and
[gen1recomp](https://github.com/bryanthaboi/gen1recomp) by bryanthaboi.

The per-pixel voxelization follows the approach their own `Structures.lua` already
uses for props, and the face shading table matches theirs so the cast lights the
same way as the world around it.
