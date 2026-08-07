# Field reports

What testers have reported, what was measured about it, and where it stands.
Every entry names the person who found it. Read alongside `CHANGELOG.md`, which
records what shipped; this file records what is still open and what was learned
from something that turned out not to be a defect.

Thread: Discord `BOIS CLUB GAMES`, `👷│pkmn-mods`, 2026-08-07.

## Open

### Sprites of every direction visible at once while walking sideways

**Pikon**, on v1.2.0: *"It kinda looks like all Red's sprites are appearing at
once when walking left to right."* **Colonel_Aureliano** reported the same
symptom independently in the same minute.

Not yet reproduced. This is a different symptom from the cap flicker and it
should not be assumed to be the same defect wearing a different description.

Where to look first: `buildSlabMesh` builds one mesh over the **union of every
walk frame**, and relies on the shader's own alpha discard to clip each frame in
texture space. Any face whose UV resolves into a frame other than the one being
drawn escapes that clip, because the discard tests the texel the UV points at,
not the frame the engine asked for. Side faces sample reference frames
(`sideUv`), so they are the first place to check.

The render harness can settle it: draw frames 0 and 3 at the same camera and
compare the provenance of each visible pixel. A side face that survives into a
frame it does not belong to will show up as invented surface outside the
silhouette of the frame being drawn.

### First person: body floats and trails black streaks

**Colonel_Aureliano**, with a photo. Running Dramatic Shape **1.7.0** plus
**Kanto First Person**, with the manifest's conflict field cleared by hand to
let them coexist. The figure hangs off the ground and long black spikes hang
below it.

Three things are true of first person that are not true of the diorama, and any
of them could produce this:

1. **The host adds a yaw we do not compensate.** `VoxelScene.billboardMatrix`
   applies `rotateY(FirstPerson.cardYaw(...) * b)` before the lean
   (`VoxelScene.lua:288-295`). `leanCorrection()` in this mod cancels only the
   `rotateX` term. A flat card can be spun to face the eye and still look
   correct from every angle. **A solid body cannot**: spinning it turns its
   depth axis through the world.
2. **The pivot assumes a 16 wide card.** The host anchors the card with
   `Mat4.translate(-8, 0, 0)` so the yaw happens about its middle. This mod
   emits `x = lx - m.minX`, so a sprite whose opaque pixels span 14 columns
   produces a mesh 14 wide whose middle is at 7, not 8.
3. **The requested frame stops being one of four.** With `cardBlend > 0.5` the
   host asks for a continuous apparent facing rather than a compass direction
   (`VoxelScene.lua:234-241`). The carved builders derive their role from
   `frame % 3` and rotate the whole mesh by it, so a continuously changing frame
   means a continuously flipping mesh.

Note the configuration is one the author of neither mod supports: the conflict
field exists because these two are declared incompatible, and it was removed by
hand. That is not a reason to dismiss the report. It is a reason to state what
this mod does and does not claim in first person, and to make the failure a
clean fallback to the flat card rather than a body with spikes coming out of it.

### CARVED leaks outside the card in the upward pose on some sheets

Found by the render gate, not by a person. A visual hull is an intersection of
silhouettes, so it can only remove material: it must never draw where the flat
card it replaces is empty. That makes `leak = 0` a criterion with a proof behind
it rather than a threshold someone picked.

Measured at zero pitch and zero yaw, twelve sheets, upward-facing pose:

```
blue        leak  650   miss  782
red daisy channeler agatha biker beauty clerk cook   leak 0
nurse       leak    0   miss  792     seel  leak 0  miss 2428
bruno       leak    0   miss  661
```

`miss` is not a defect here. It is the material the hull carved away.

Cause, confirmed by reading both sites: `mirrorX` mirrors the back view onto the
front view's columns about the front and back bounding box
(`main.lua:775-777`), which is the v1.2.1 correction and is a texture-space
question. The role rotation added in v1.3.0 mirrors placement about the sprite
cell (`m.cellW - x`), which is a geometry question. Two mirrors, two axes. They
agree only when the art is symmetric inside its cell.

Whichever way it is resolved, the two must be derived from one axis rather than
chosen independently, or this returns the next time either is touched.

### Battle sprites

Asked for by **Colonel_Aureliano** and **Pikon**, six minutes apart, and again
after release.

Battle draws through `BattleBillboard`, a separate path this mod does not touch.
The constraint is not effort: a battle sheet has two views and they are
**opposite** ones, front and back. A slab is possible from that. A carve is not,
because intersecting two opposite silhouettes yields no depth evidence at all.

### "Not actual voxels yet"

**WakaWaka**. Fair as stated for **SLAB**, which extrudes a silhouette to a
uniform depth and is the default. **CARVED** does build a real volume, and is
measurably too much of one: see below.

## Measured, and worse than reported

**Ferretonin** said of CARVED: *"you lose all details."* **Kim** agreed. The
render harness now puts a number on it. Share of visible pixels that still
sample the artist's sprite art, at the default camera rung:

```
red.png frame 0            facing camera   turned 45 degrees
  flat card                     100.0%            100.0%
  SLAB                           71.9%             61.6%
  CARVED                         30.7%             18.3%
  CARVED+                        38.1%             24.2%

nurse.png, a three frame sheet
  CARVED                         30.2%             19.2%
```

Sixty nine percent of a carved character is upward facing surface carrying no
art. It is not specific to the player's sheet. The cause is that the carve reads
the Gen 1 side view as a metric depth, and that view is a stylised drawing, not
an orthographic projection of a body: `red.png` comes out 13 voxels deep on a
16 wide sprite, which is a cube.

## Closed

- **Cap flickering red to black.** Reported by **Pikon** on v1.2.0 and by
  **Kim** for SLAB specifically. Fixed in v1.2.2, which found the same defect in
  the slab's side faces as well. Confirmed in the harness: frames 0 and 3 now
  resolve the cap to the same tone at every camera rung. **Pikon has not
  confirmed on v1.2.2**, only on v1.2.0.
- **Black side faces.** **Pikon**, v1.0.0. Fixed in v1.1.0.
- **Install failure.** **Ferretonin**. Resolved by disabling other mods.
- **Scope was undersold.** **Rob** asked what the mod actually covers and
  revealed that item balls on the ground are object events with sprites, so they
  are voxelised too. The description said otherwise.

## Reference material offered

**ty_mcdk** pointed at **3D Dot Game Heroes** and asked for depth that varies
per character. That reference is why this mod looked for orthographic views in
the art and found that Gen 1 sheets already contain three.

**Nukularkoffee** posted a render and said *"this should be the goal now"*,
adding *"some occlusion, bloom and light fx would go a long way"* and *"pbr
materials would be goated"*, then noted himself that the image *"could be ai
tho"*.

The image is a smooth shaded, high resolution, physically lit scene. It is not
reachable from here and should not be used as a target: sprite resolution is
fixed at 16 by 16 in the engine, the palette is four tones, and this mod owns
neither the lighting nor the world. Chasing it would mean optimising toward
something that cannot be built.

One thing in it does transfer, and it is the thing he named first. The figures
in that render read as solid because of **occlusion**, contact darkening where
surfaces meet. That is expressible in the `shade` channel of the host's own
vertex format, and the Voxel Mod already does exactly this for the world
(`ChunkMesher.lua:260-288`). The reference is wrong as a target and right as a
diagnosis.
