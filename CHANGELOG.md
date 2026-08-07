# Changelog

All notable changes to Voxel Characters.

This project is built with the community that plays it. Anyone who reported a
bug, asked a question that exposed one, or pointed at a reference that changed
the direction is named in the entry their contribution landed in.

## [1.4.0] - 2026-08-07

### Added

- **`GROUND SHADE: OFF / ON`.** When enabled, the mesh applies the host contact
  term to vertices in the lowest six pixels: `0.12 * 2.4`, fading out linearly
  by height 6. Default is OFF, so the release does not impose a new visual loss
  on users who only want the existing SLAB default.

- **`BLINK: OFF / ON`.** When enabled, verified standing front SLAB eye texels
  close for about 0.12 seconds on a per-sheet 3 to 6 second cycle. Walking
  frames stay open. Default is OFF, matching `SHAPE: SLAB`: the existing look
  stays opt-in stable unless the player asks for the new animation.

### Changed

- **SLAB top and bottom faces now search body color vertically per pixel.**
  `SIDE COLOR: BODY` already promised that new extrusion faces use nearby body
  pixels instead of outline pixels. Left and right sides kept that promise
  because they resolve UV per pixel, but top and bottom still used horizontal
  runs and only moved when the whole run was outline and the whole adjacent
  line was body. Mixed runs are common, so many top and bottom faces stayed
  black. Top and bottom are now emitted per pixel and search along Y with the
  same 4 pixel limit as the side search.

  Static SLAB quad count after the change and the unconditional eye split:
  `red.png` frame 3 moves from 372 to 652 quads, and the worst case moves from
  480 to 864 on `boulder.png` frame 0. The eye split adds 542 quads across the
  303 measured SLAB meshes, 0.27%, so it stays unconditional and independent of
  the `BLINK` option. This remains below the 1,044 quads measured for CARVED on
  `red.png` frame 3.

- **Front face shade now uses 0.90.** The README said the baked character shade
  table matched the host world mesh, but the front face was still 1.00. It now
  matches `Voxel3D.FACE_SHADE.front`. The side shade remains symmetric at 0.78
  because the host mirrors sprite cards after requesting
  `SpriteBillboards.mesh(def, frame)`, and baked east and west vertex shades
  would otherwise swap sides under mirroring.

- **Verified SLAB eyes are emitted as front-face quads.** The old rectangular
  front run could not address individual eye texels. Eye pixels now split out
  as their own front quads whether `BLINK` is OFF or ON, so the cached geometry
  stays identical and only UVs change in place.

### Notes

- **CARVED already emitted top and bottom per voxel.** The proof is in
  `buildCarvedMesh`: the `for sx = sideBounds.minX, sideBounds.maxX` loop emits
  `topUv(lx, ly, dy)` directly in the per-voxel top and bottom face branches,
  currently `main.lua:1396` and `main.lua:1400`.

- Blink phase is per sheet. The host does not pass an entity id or world
  position to `SpriteBillboards.mesh(def, frame)`, so NPCs that share the same
  sprite sheet blink together.

## [1.3.0] - 2026-08-07

### Fixed

- **SLAB draws the walking pose, not the union of every pose.** `buildSlabMesh`
  now tests each frame's own opacity instead of the mask `maskFor` accumulates
  over the whole sheet, so top, side and bottom faces recompute per pose along
  with front and back, which already worked because they sample the current
  frame through the shader's alpha discard. On Red's sheet, frame 0 versus
  frame 3 silhouette agreement moved from IoU 0.9503 (520 differing pixels) to
  0.90 at the default camera rung, and thickness now actually changes that
  count instead of holding flat at 520/520/536 across depth 1, 3 and 10.

  Reported by **Pikon** and **Colonel_Aureliano**, who both described the same
  symptom within a minute of each other: "It kinda looks like all Red's
  sprites are appearing at once when walking left to right."

- **SLAB and CARVED now align to the sprite cell, not the opaque bounds.**
  `buildSlabMesh` positioned X against the opaque bounding box
  (`lx - m.minX`) instead of the sprite cell the host pivots at x = 8. 40 of
  67 sheets have `minX = 1`, so their whole body drew one pixel left of the
  flat card it stands in for, jumping the moment the mod toggles on or off.
  SLAB also had the same bug on Y: sheets with empty bottom rows were anchored
  to the lowest opaque pixel instead of the bottom of the cell. CARVED had both
  coordinate-space defects as well. Both builders now emit X and Y in sprite
  cell coordinates, and CARVED's per-role rotation compensation was moved to
  the cell width while preserving the side frame's horizontal padding.

- **First person no longer produces a spiked body.** The host's first-person
  shader moves every vertex toward the eye, which a flat card tolerates and a
  solid volume does not: each corner moves a different amount and the
  geometry can cross the near plane. `voxelMesh` now falls back to the
  original card whenever `FirstPerson.cardBlend()` reports any blend, ahead of
  both SLAB and CARVED, matching this mod's contract that every failure path
  lands on the flat card and never a spiked one.

  Reported by **Colonel_Aureliano**, running Dramatic Shape 1.7.0 with Kanto
  First Person and a hand-cleared manifest conflict field, a combination
  neither author supports.

- **CARVED uses the sprite-cell mirror axis exactly once.** `buildCarvedMesh`
  now mirrors the back view with `cellW - 1 - lx`, the same sprite-cell axis
  used when the upward-facing role is rotated into place, and keeps role 1's
  hull indexed in the front frame's cell space. The previous v1.2.1 bbox axis
  fixed the global-bbox regression but diverged from v1.3.0's cell-space
  geometry; the first v1.3.0 fix moved the axis to the cell but still mirrored
  role 1 both during intersection and during presentation, so asymmetric sheets
  could draw outside the flat card instead of only carving material away.

- **SLAB merges provably identical vertical side faces.** `buildSlabMesh` still
  preserves separate side quads whenever the resolved UV changes, but adjacent
  left/right side faces with the same X, same side, same shade and same UV now
  become one vertical run. That removes complexity made unnecessary by the
  v1.3.0 per-frame occupancy fix without changing what any merged face samples.

### Notes

- **CARVED was audited for the frame-union defect and did not share it.** Its
  solid test already samples the specific front, back and side pose frames,
  never the sheet-wide union, so the silhouette fix above is SLAB-only.

## [1.2.2] - 2026-08-07

### Fixed

- **Stable side, top and bottom colouring in SLAB.** SLAB now resolves new side,
  top and bottom face colours from fixed role reference frames before falling
  back to the current pose, matching the CARVED stability rule while preserving
  SLAB's rectangular run UVs.

  Reported by **Kim**, who found the remaining cap flicker in the default SLAB
  mode after v1.2.1. **Pikon** had confirmed the same symptom in v1.2.0.

## [1.2.1] - 2026-08-07

### Added

- **`SHAPE: CARVED+`.** CARVED+ starts from the three-view CARVED hull and uses
  front-view tone to recess darker body pixels by up to two voxel columns. The
  recess is capped by the side-view depth so thin replacement sprites always
  keep at least one voxel layer.

### Fixed

- **Stable top and bottom colouring in CARVED.** Top and bottom faces now choose
  their body-colour texel from fixed reference views before falling back to the
  walking frame, so a shifted walk sprite does not blink between outline and
  body colours.

  Reported by **Kim**, who spotted the flicker on the top of Red's cap.

- **Back-view carving alignment.** The back silhouette is mirrored around the
  front/back pair's own X axis instead of the whole sheet's opaque bounds. Side
  views can extend wider than the front view, and using that global bound was
  cutting legitimate voxels from asymmetric sprites.

## [1.2.0] - 2026-08-07

### Added

- **`SHAPE: SLAB / CARVED`.** CARVED builds a real voxel volume instead of a
  slab with uniform thickness. Every sprite sheet already carries three
  orthogonal views, front, back and side, and the side view is narrower than the
  front. On Red's sheet the torso is 14 columns wide from the front and 13 deep
  from the side. That difference is depth the artist recorded in 1996, and the
  slab was throwing it away. A voxel is kept where the front and side silhouettes
  agree, and only surface faces are emitted. Default stays SLAB.

  Suggested by **ty_mcdk**, who asked for variable depth and pointed at 3D Dot
  Game Heroes as the target. That reference is what sent me looking at the sheet
  layout. Without it I would have tried guessing depth from the shading, which
  would have been a worse answer to the same question.

- Standing NPCs with three-frame sheets now get CARVED. They carry front, back
  and side like walkers do, but a frame count check was excluding them. That was
  20 of the game's 73 sprite definitions, most of the people standing indoors.

### Fixed

- **The walk flicker.** Side faces alternated between body colour and black as
  the walk cycled. Measured on Red's sheet: 161 of 378 side positions were
  switching. The geometry comes from the union of every frame, but the colour
  search was reading the current frame only, so where a frame's silhouette
  differed from the union the search found body colour in one frame and fell
  back to the outline in the next. The side shell now resolves its texel once
  from the sheet's side views.

  Reported by **Pikon**, who spotted it on a video, one release after spotting
  the black faces on another one.

## [1.1.0] - 2026-08-07

### Added

- **`SIDE COLOR: BODY / OUTLINE`.** The side, top and bottom faces created by
  the extrusion now take their colour from the body instead of the outline.
  Gen 1 sprites carry a solid outline on every silhouette pixel, and each face
  was textured from the pixel that generated it, so every new face was extruded
  from the outline and came out black. Measured on Red's sheet: 34 of 34
  silhouette edge pixels are the darkest tone, and no shade multiplier lifts
  black. BODY looks inward for the first non-outline pixel and uses its colour.
  Front and back keep the original art, because the outline is what separates
  the figure from the scenery.

  The outline tone is the sheet's own minimum luminance rather than hardcoded
  black, so SGB and RED++ palette bakes still work.

  Reported by **Pikon**, who asked whether the slabs could inherit the sprite's
  colour instead of being black. They could, and the reason they were not turned
  out to be a real bug rather than a limit.

### Changed

- Default thickness is now 3. Two read as too subtle at the lower VOXEL rungs.

## [1.0.0] - 2026-08-07

### Added

- Initial release. Overworld character sprites are extruded into voxel slabs
  built from their own pixels, so the cast reads as part of the diorama instead
  of standing in it flat.
- `VOXEL CHARS: OFF / 1 / 2 / 3 / 5 / 10` under OPTIONS.
- Companion mod: it does not modify the Dramatic Shape Voxel Mod, ships no art,
  and every failure path falls back to the original card.

### Notes

- **Rob** asked what the full extent of the mod was, and the honest answer turned
  out to be wider than the announcement claimed: item balls on the ground are
  object sprites like NPCs, so they get thickness too. The description was
  corrected rather than the behaviour.
- **Ferretonin** reported that nothing changed after installing, which produced
  the diagnostic now used for every support case: the `VOXEL CHARS` row is only
  registered after the mod successfully hooks into the Voxel Mod, so seeing the
  row is proof that the install worked and the problem lies downstream.

[1.2.1]: https://github.com/last-swagger/gen1recomp-voxel-characters/releases/tag/v1.2.1
[1.2.0]: https://github.com/last-swagger/gen1recomp-voxel-characters/releases/tag/v1.2.0
[1.1.0]: https://github.com/last-swagger/gen1recomp-voxel-characters/releases/tag/v1.1.0
[1.0.0]: https://github.com/last-swagger/gen1recomp-voxel-characters/releases/tag/v1.0.0
