# Changelog

All notable changes to Voxel Characters.

This project is built with the community that plays it. Anyone who reported a
bug, asked a question that exposed one, or pointed at a reference that changed
the direction is named in the entry their contribution landed in.

## [1.5.0] - 2026-08-08

### Added

- **A `STATUS` row says why voxel rendering is or is not happening.** The
  options menu always registers its rows now: with no supported host it
  shows a single `STATUS: NO HOST` row instead of showing nothing at all,
  and with a host it shows `STATUS` first, read fresh every time the menu
  opens, never cached. It reads one of `ACTIVE`; `NO HOST`; `FIRST PERSON`,
  meaning this mod is intentionally returning the flat card because a solid
  does not inherit the camera's cylindrical billboard contract, not a
  defect; `REPLACED`, when another mod swaps `SpriteBillboards.mesh` after
  this one has already patched it, which `warnChainedMesh` cannot see
  because it only catches patching that happens before; or `MASK ERROR`,
  `BUILD ERROR` or `DRAW ERROR`, when a sprite's mask cannot be built, its
  mesh fails to build, or its draw call throws inside the outermost
  wrapper. Every one of those failure paths used to fail silently with the
  error discarded; each now logs its message once per distinct cause.

  Escalating to a named error tracks the proportion of failures across a
  sliding window of the last 8 draw results, at half or more, rather than a
  run of consecutive failures: a sprite that fails every other frame still
  escalates even though it never fails twice in a row, and a single bad
  sheet among many working ones still cannot escalate on its own. The label
  names whichever failure kind is most common across that window, not just
  the most recent one.

  `patch()` is atomic: it builds every reference in local variables and
  writes to the host's table before committing anything to this mod's own
  state, and `STATUS` and the options rows gate on an explicit "patch
  completed" flag, never on whether a reference happens to be set. A host
  whose table rejects a write, such as one that protects `mesh` but allows
  new keys, a plausible way to guard a public API without blocking
  extension, fails the whole patch cleanly: any partial write already made
  to the host's table is rolled back to what it held before, and `STATUS`
  reports `NO HOST` rather than a `REPLACED` pointing at a conflict that
  does not exist.

  Reported by **AngelusRole**, whose flicker and host reports both landed
  in this version; by **Tyler Durden**, whose host reported itself as
  version `7.0`; and by **TwoTracks**, who reported a host that is
  accepted, whose options menu appears, and which still draws nothing.
  TwoTracks' case is not solved by this change. The mods on the list they
  gave do not replace `SpriteBillboards.mesh`, and the first person path
  only reads `cardBlend`, it does not write it, so both leading hypotheses
  were ruled out during the investigation. What this change adds is the
  `STATUS` row itself, so the next report from that machine can say which
  silent path is actually happening instead of just "nothing draws."

- **Characters can blink while walking, not only standing.** SLAB blinks on
  the front and side standing frames and, when a sheet's eye mark survives
  the walk, the front and side walking frames too. Whether a walking pose
  blinks is decided at mesh build time, sheet by sheet and pose by pose,
  never by a hand written list: the eye mark used is the standing frame's
  mark shifted by that sheet's `poseOffset` between the two frames, and
  before that mark is used its tone at the shifted coordinate is checked
  against the tone at the source coordinate. If any eye mark on a sheet
  does not survive that check, that sheet stays open in that pose, exactly
  like a sheet with no eye entry at all; there is no half closed eye.

  This is the fix for the defect the v1.4.1 `BLINK` option shipped with:
  validating only the standing frame closed the "eye" over skin on the
  walking frame, because the face shifts down a row while walking, and
  walking blink was disabled entirely as the workaround. Measured on the
  already validated eye marks: reading a mark at the same raw coordinate
  transfers on only 4 of 38 sheets for the front pose and 15 of 34 for the
  side pose; compensating by `poseOffset` raises that to 35 of 38 and 33 of
  34. The sheets that still do not transfer, `girl`, `lance`, `seel` and
  `middle_aged_woman`, are the ones whose head is genuinely redrawn between
  poses, the same sheets already known from the top of the head fix below.

  The blink option's cache key still carries no blink bit, on purpose, and
  does not need one here either: whether a pose blinks is decided from
  `frame`, the sprite's base name and its own pixels, all of which are
  already part of the mesh cache key, so a walking pose and a standing pose
  for the same sheet always land in separate cache entries and can never
  share blink state.

  Adds eye marks for `lorelei` (front `{5,7} {6,7} {9,7} {10,7}`, side
  `{5,6}`) and for `gramps` (side `{5,7}`, alongside its existing front
  mark), all derived from the same signature already validated across 174
  front marks and 57 side marks: a single dominant column and row, at the
  same relative position as other validated marks. `monster` and
  `bike_shop_clerk` are deliberately left without any mark, and `bird`,
  `fairy`, `fisher`, `granny`, `gym_guide` and `seel` without a side mark:
  each scored a tie or an off center candidate with no clear winner, so
  there is no evidence to add one, and every one of them keeps the default
  open eye rather than a guessed mark.

  Reported by **Kim** after testing v1.4.1 in game.

### Changed

- **Voxel Characters now accepts a host by what it can do, not by its
  version number.** A capability probe checks that `exports.lib` exists and
  that its `require` returns the three modules this mod actually calls,
  `Voxel3D`, `ImageCache` and `SpriteBillboards`, with `SpriteBillboards.mesh`
  a function. A host that passes the probe is accepted no matter what
  version it reports; the version is logged always and only earns a
  warning when it falls outside the range this mod has been tested
  against. A host that fails the probe is rejected with a message naming
  the module that was missing, and a required module whose `require` call
  throws no longer takes the whole mod load down with it. The accepted
  host ids are `DRAMATIC_SHAPE`, the original Dramatic Shape Voxel Mod;
  `BATTLE_ART_VOXEL_FORK`, the fork by absol89; and `DRAMALESS_SHAPE`, the
  fork by artyrambles. That id list is still written by hand, because the
  mod API only offers `find(id)` and has no way to list every loaded mod,
  so an id has to be known before its capability can even be probed.

  The version gate this replaces had inverted itself. Measured before this
  change: a host reporting an unreadable version string such as `banana`
  was accepted, while a host reporting a readable but old version such as
  `1.3.1` was rejected, even with a complete and working API. The host
  lineages version independently and inconsistently: a suffixed tag a
  parser cannot read, a tag that parses higher than a newer release by
  date, a release whose manifest reports one version while its own code
  reports another. A version gate over that keeps failing in a new way
  with every release; deciding by capability instead removes the whole
  class of failure.

  Requested by **Colonel_Aureliano**, who asked about compatibility with
  the "stalthiem drama less voxel" fork; **absol** had also warned earlier
  about the `DS Voxelmod - Stahl's Edit` lineage before it was public.
  Reported by **AngelusRole**, who found that disabling Wilds of Kanto no
  longer worked around the problem in v1.4.1, because the host he runs,
  Dramaless Shape Voxel Mod `1.6.2.ST`, was not recognized by that release
  at all. Also reported by **Tyler Durden**, whose host reported itself as
  version `7.0` and was rejected by every known range even though its
  exported API was complete.

- **`TOP EDGE` now defaults to ON.** This is intentionally not the conservative
  default from v1.4.1. With `SIDE COLOR: BODY`, `TOP EDGE: OFF` is not neutral:
  the highest exposed SLAB top face can sample body color below the outline and
  draw a bright hat-colored cap above the dark contour. Turning the edge on by
  default removes that artifact instead of adding a new effect. Players can
  still choose OFF when they want the pure host top shade.

  Reported by **Kim** in game on Red's hat. Suggested earlier by **Jirai
  Gumo**, who described the same need for a darker top edge before the field
  report existed.

- **Credits reworded so the viability statement is not read as ranking one
  host lineage over another.** The wording named one specific project as
  what made this mod possible, while a player could be running any of the
  three accepted hosts. Crediting the Dramatic Shape Voxel Mod as the
  original author of the lineage is a fact, not a side taken, so that
  credit stays explicit; the viability statement is now about the lineage
  and its exported API in general, not about one project by name.

### Fixed

- **The top of the head no longer flickers while walking with `SIDE COLOR:
  BODY`.** The walking pose is the standing pose moved down one row in the
  sprite art, a deliberate step. SLAB read the reference frame for new top
  and side faces at the same coordinate as the walking frame instead of
  compensating for that shift, so the top of a hat resolved to a different
  band of the art on every other step. A new `poseOffset` measures the shift
  between two frames by opaque mask overlap and compensates the reference
  lookup in `verticalUv` and `sideUv` before falling back to the previous,
  uncompensated read. Measured on `red.png`: 306 of 2194 top face pixels
  (13.9%) changed color between the standing and walking frame at the same
  screen position before this fix, 0 after.

  CARVED's `topUv` and `sideUv` had the same defect in their own reference
  search. The fix there compares frames only within the same view, the
  front pose against the front pose or the profile pose against the profile
  pose, never front against profile: a visual hull's profile silhouette is
  a different shape than its front silhouette by nature of the art, and
  comparing them would measure that shape difference, not the walk offset.
  `poseOffset` now refuses to compensate at all between two frames of
  different views.

  Reported by **AngelusRole** on Discord.

- **A single misbehaving entity mod no longer disables voxel rendering for
  the whole play session.** The host's `SpriteBillboards.mesh` builds a
  cache key with `def.image .. "#" .. frame` and has no type guard on
  either value; a `nil` frame coming from any entity mod threw there,
  uncaught, inside the host's draw loop. The exception reached the mod
  pipeline's error boundary, which marked the whole Voxel Characters patch
  as broken for the rest of the session. One entity with a bad pose, on a
  single frame, turned off voxel rendering for every character until the
  game restarted. All five places in this mod that fall back to the host's
  original mesh function now go through a wrapper that catches that
  failure and returns `nil` instead of letting it propagate, so only the
  misbehaving entity's billboard is skipped for that frame; every other
  character stays voxel. A dropped billboard is logged once per session,
  not once per frame, since the failure can repeat every frame at 60 Hz.

  Reported by **AngelusRole** on Discord, who had to disable Wilds of Kanto
  for Voxel Characters to keep working. Disabling it only helped because it
  restarted the mod set, not because anything on its side was at fault.

- **`poseOffset(a, b)` is now symmetric: always the exact negative of
  `poseOffset(b, a)`.** On a genuine score tie between a positive and a
  negative vertical shift, the "prefer the smaller value" tie-break rule
  chose the negative shift in both directions when each direction scanned
  independently, since each scan applied the same rule without knowing
  what the other had chosen. Blink's eye compensation above calls
  `poseOffset` in the opposite direction from the geometry color
  compensation, so this could silently disable a blink that should have
  transferred; the tone check already caught the resulting bad coordinate
  and fell back to an open eye, so no closed eye ever pointed at the wrong
  texel, but a transfer that should have worked did not. The scan now
  always runs for the pair in a canonical order, from the lower frame index
  to the higher one, and negates the result when asked for the reverse
  direction, so the two directions can never disagree. The scan itself also
  no longer recomputes the source frame's opacity for every candidate
  offset, only the target frame's, since only the target side depends on
  the candidate.

## [1.4.1] - 2026-08-07

### Added

- **`TOP EDGE: OFF / ON`.** When enabled, exposed SLAB top faces use shade
  `1.00 * 0.82`, giving hats and hair a darker false top-down edge. Default is
  OFF because this intentionally stops those character top faces from matching
  the host world shade `+Y up = 1.00`.

  Suggested by **Jirai Gumo**, who called out the top of Red's hat as a place
  where a second dark outline could help the layered character models read from
  above.

### Fixed

- **Voxel Characters now finds the active fork host.** The bootstrap accepts
  `BATTLE_ART_VOXEL_FORK` from absol89's Battle Art Voxel Fork as an accepted
  host id alongside `DRAMATIC_SHAPE`. If both host ids are installed and
  supported, the fork is chosen first; that is deterministic list order for
  when more than one host is present, not a ranking of the hosts. The mod
  now checks each host for both `exports.lib` and the supported version
  range before choosing it, so an out-of-range fork no longer blocks another
  valid host from loading. If no usable host exists, the warning says what
  it found and why each candidate was rejected.

- **The fork id is now an optional dependency too.** This gives the loader the
  same soft ordering edge for `BATTLE_ART_VOXEL_FORK` that it already had for
  `DRAMATIC_SHAPE`, so Voxel Characters does not run before a fork-only install
  has exported its API.

- **The fork requirement is documented as `>=1.7.0 <2.0.0`.** That is the real
  supported range in code. The fork tags are not monotonic semver by release
  date: `1.7.6` is the newest by date, while `v1.68` parses as `1.68.0` and
  compares higher, so both are intentionally accepted.

  Reported by **Colonel_Aureliano**, who isolated this through a clean reinstall
  after props voxelized correctly but NPCs stayed flat and the options had no
  visible effect.

- **SLAB no longer emits hidden top, bottom and side faces inside the body.**
  `buildSlabMesh` now emits a top face only when the pixel above is transparent,
  a bottom face only when the pixel below is transparent, a left side face only
  when the pixel to the left is transparent, and a right side face only when the
  pixel to the right is transparent. The old `0.03` SLAB face inset is now zero
  because those same-plane internal faces are no longer emitted. On `red.png`
  frame 0, top and bottom faces drop from 176 each to 16 each, `side_e` and
  `side_w` drop from 176 each to 17 each, and total quads drop from 742 to 104.

  The defect existed since v1.0.0. v1.4.0 did not create it; v1.4.0 changed
  those contour faces to body color, which removed the visual camouflage from
  hidden faces that had been present all along.

  Reported by **absol**, who described voxel flicker and grid-like gaps visible
  through Red's face.

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
