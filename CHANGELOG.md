# Changelog

All notable changes to Voxel Characters.

This project is built with the community that plays it. Anyone who reported a
bug, asked a question that exposed one, or pointed at a reference that changed
the direction is named in the entry their contribution landed in.

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
