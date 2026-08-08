# Voxel Characters

Gives the overworld cast real thickness when a Dramatic Shape Voxel Mod
lineage is running.

The voxel world is 3D, but every person in it is a flat sprite card. This mod
extrudes those sprites into voxel slabs built from their own pixels, so the cast
reads as part of the diorama instead of standing in it like cardboard.

It is a companion mod. It does not contain, redistribute, or derive code from
any voxel mod. It calls the host's exported API at runtime, on the player's
own machine; it does not modify the Voxel Mod, it ships no art, and turning
it off restores the original card on the next frame.

## Install

1. Download the latest release zip.
2. In game, open **MODS** and choose **Import mod .zip**.
3. Enable **Voxel Characters**. Restart if prompted.

## Requirements

- gen1recomp `0.1.51` or newer
- One of these host mod ids, exporting `Voxel3D`, `ImageCache` and
  `SpriteBillboards` with a working `SpriteBillboards.mesh`:
  - `DRAMATIC_SHAPE`, the original Dramatic Shape Voxel Mod by DramaticShape
  - `BATTLE_ART_VOXEL_FORK`, the fork by absol89
  - `DRAMALESS_SHAPE`, the fork by artyrambles

This mod accepts a host by what it can do, not by its version number. It
probes the host's exported API for the three modules above; a host that
answers with all three, and whose `SpriteBillboards.mesh` is a function, is
accepted. The reported version is logged either way and only earns a warning
when it falls outside the range this mod has been tested against; it never
blocks an accepted host. That matters because the host lineages version
independently and inconsistently, sometimes with a suffix a version parser
cannot read, sometimes with a manifest that reports one number while its own
code reports another, so a hard version gate kept rejecting hosts whose API
was intact and working.

If more than one of these host ids is installed at once, the first one found
in the list above is used. That is deterministic order for breaking a tie,
not a ranking of the hosts, and none of them is treated as more official or
more supported than another.

Without any of these hosts installed, this mod loads, logs one line
explaining what it looked for, and does nothing else. Open **OPTIONS** and it
still shows a single `STATUS: NO HOST` row, so the mod being present and idle
is visible instead of silent. See Options below for what `STATUS` reports
once a host is found.

## Options

Seven rows, under **OPTIONS**:

```
STATUS:        read only, see below
VOXEL CHARS:   OFF / 1 / 2 / 3 / 5 / 10
SIDE COLOR:    BODY / OUTLINE
SHAPE:         SLAB / CARVED / CARVED+
GROUND SHADE:  OFF / ON
BLINK:         OFF / ON
TOP EDGE:      OFF / ON
```

`STATUS` is read only and recomputed live every time the menu opens, never
cached. With no host it reads **NO HOST**. With a host patched, it reads one
of:

- **ACTIVE**, drawing voxel characters normally.
- **FIRST PERSON**, intentional: a solid does not inherit the flat card's
  cylindrical billboard contract in first person, so this mod returns the
  original card on purpose while the camera is there. Not a defect.
- **REPLACED**, another mod swapped `SpriteBillboards.mesh` after this one
  had already patched it, so this mod's version is no longer active.
- **MASK ERROR**, **BUILD ERROR** or **DRAW ERROR**, when half or more of
  the last 8 sprite draws failed to voxelize, tracked as a proportion over
  that sliding window rather than a run of failures in a row, so a sprite
  that fails every other frame still escalates even though it never fails
  twice in a row. The label names whichever kind of failure is most common
  across that window, not just the most recent one. A single bad sprite
  among many working ones does not trigger this. The underlying error for
  each distinct cause is written to the log once.

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

`BLINK` swaps known eye texels to nearby skin texels for a short
closed-eye frame. Default is **OFF**, so enabling the mod does not impose a new
visual change beyond the selected shape and thickness. Blink applies to SLAB
front and side frames, standing or walking, with a verified eye entry and a
safe nearby body texel. The walking pose is not a fixed exception: it blinks
whenever that sheet's eye mark, taken from the standing frame and shifted by
the same pose offset SLAB uses for its side, top and bottom faces, still
lands on the same tone in the walking frame. If it does not, that sheet
stays open in that pose, never half closed, the same way sheets with no eye
entry or a color match that cannot be found within 4 pixels stay open. Back
frames stay open on every sheet; there is no confirmed back eye mark.

`TOP EDGE` darkens only exposed **SLAB** top faces. Default is **ON**. With
`SIDE COLOR: BODY`, **OFF** is not the neutral state on every sprite: a top face
can sample body color below the top outline and draw a bright cap above a dark
contour. ON keeps that top contour reading as an edge. Players can still turn
it OFF when they want the host-matching `+Y up = 1.00` shade on character tops.

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
local host = first host whose exports.lib probes for the required modules
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

When `BLINK` is available for a SLAB sheet, verified eye pixels are split out
of the merged front run as their own quads even while blinking is disabled.
That keeps the cached mesh topology identical in both eye states. Blinking
then mutates only those vertices' UVs in place, from the eye texel to a
nearby body-color texel found by the same 4 pixel body search used by
`SIDE COLOR: BODY`. Time is never part of the mesh cache key.

On a walking frame, the eye mark used is the standing frame's mark moved by
that sheet's `poseOffset` between the two frames, and it is only split out
as its own quad if the tone at that moved coordinate in the walking frame
still matches the tone at the mark's own coordinate in the standing frame.
This is decided once per sheet per pose at mesh build time from the sheet's
own pixels, never from a fixed frame list, so a redrawn head simply stays
open in that pose instead of blinking over the wrong texel. Frame and base
name are already part of the mesh cache key, so a walking pose's eye state
can never leak into the standing pose's cached mesh or the other way
around.

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
hook to negotiate order, but `STATUS` now reads `REPLACED` in that case, so the
conflict does not have to be diagnosed from load order alone.

Every failure path falls back to the original card: a host that fails the
capability probe, a sheet whose layout cannot be derived without guessing, a
mesh that fails to build, an unexpected exception in the mesh call itself.
The worst case is flat characters, never a broken game, and `STATUS` now
names which of those paths is happening instead of leaving it silent.

## Tests

```
luajit mods/voxel_characters/tests/voxel_chars_test.lua
```

265 assertions covering the host capability probe and its fallback to a
named log reason, the `STATUS` row and its patch and draw-result states, the
options rows and their persistence, slab geometry and vertex format, carved
visual-hull surface faces, per-frame silhouette projection, absolute role
position, depth-axis orientation, pose-offset color compensation between
walking and standing frames in both SLAB and CARVED, three-frame carve
sheets, carve fallback, pitch bucketing, cache keying and LRU eviction,
side-face, top-face and bottom-face color selection, three-view carving,
face shade values, ground contact shading, top-edge shading, blink gating
including the walking-pose eye transfer check against both synthetic sheets
and lorelei's own art, hidden SLAB top and bottom face culling, CARVED+
relief direction, thin-sprite depth limits, and the wrapper that keeps a
misbehaving host or entity mod from taking down voxel rendering for the
whole session.

## Credits

This mod is possible because the Dramatic Shape Voxel Mod lineage exports a
namespace this mod can call into at runtime. The Dramatic Shape Voxel Mod,
by DramaticShape, is the original of that lineage. This mod also accepts
two forks of it as equally usable hosts: the Battle Art Voxel Fork by
absol89, and the Dramaless Shape Voxel Mod by artyrambles. None of the
three is treated as more official than another; see Requirements for how a
host is chosen when more than one is installed.

Also built on [gen1recomp](https://github.com/bryanthaboi/gen1recomp) by
bryanthaboi.

This mod contains no code from any of the above. It calls their exported
API at runtime, on the player's own machine. The per-pixel voxelization
follows the approach their own `Structures.lua` uses for props, and the
face shading table matches theirs so the cast lights the same way as the
world around it.
