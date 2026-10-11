# Changelog

All notable changes to Voxel Characters.

This project is built with the community that plays it. Anyone who reported a
bug, asked a question that exposed one, or pointed at a reference that changed
the direction is named in the entry their contribution landed in.

## [1.8.2]

Compatibility and release metadata correction. This release keeps the verified
game support limited to Gen 1, records PotatoVoxel as an optional host dependency
so the loader can order it correctly, and adds focused checks that can run
without booting the game.

### Fixed

- **The `Gen 2 support` line in 1.8.0 was not true, and the manifest no longer
  claims it.** `games` is now `["gen1"]`, which is what has actually been
  measured: red, blue and yellow.

  The claim came from following the project's own "Preparing Your Mod For Gen 2"
  guide. That guide explains how to DECLARE readiness; it does not test it, and
  declaring was treated as being ready. Nobody has ever booted this mod on a Gen
  2 game -- the engine snapshot in this checkout does not have one, and asking it
  for `gold` or `crystal` silently returns `red`.

  **On a current engine that declaration stops being harmless.** `games` becomes
  a gate: a mod that does not claim the running game is left out of the boot
  entirely, and one that DOES claim it is loaded on the strength of the claim. So
  the day anyone updated, this mod would have loaded into Gold having never run
  there -- and 1.8.1's public "now tested rather than claimed" would have become
  false without anyone touching a line.

  Nothing is closed off. A player who wants to try it anyway has the engine's own
  `TRY HERE ANYWAY` toggle, where the "never verified here" label comes from the
  engine instead of from a promise of ours. `"gen2"` comes back the day it boots
  and attaches, measured.

  Found while investigating **suheel**'s report of the Stadium 2 overworld mod,
  which is a Gen 2 HOST -- a different thing from a Gen 2 game, and the exact
  confusion behind the original claim.


### Added

- **The grid gate now measures V-GRID CHARS in both directions**
  (`tools/ingame/probe_grid.lua`, checks G4, G5 and G6). It used to measure
  only the host's rule -- that the world's wireframe does not touch characters
  -- and nothing measured our own row at all. So when **Kim** pressed 5, got
  the grid on the map, and saw the characters stay out of it, every gate in the
  project was green and none of them was looking.

  This turned out not to be a defect in the mod (see below), but the hole was
  real either way, and it was the same hole 1.8.0 shipped through: a gate that
  has only ever seen one configuration. Three things changed:

  - **G3 now sets V-GRID CHARS off explicitly** instead of inheriting whatever
    the save said. It was green because this machine's save happened to say
    "off"; with the shipped default (on) it would have been measuring our
    feature and calling it the host's rule.
  - **G4** turns the row on with the world grid on and requires the character
    to actually change -- measured at 1271 pixels against a floor of 300.
  - **G5 and G6** hold the other half of the promise, that V-GRID CHARS rides
    the world grid rather than competing with it. G6 exists because G5 cannot
    see it: with the grid off the host binds a shader with no seam uniform in
    it, so a mod that stopped consulting the world grid would ask for seams
    that land nowhere and look identical on screen. G6 listens for the ask
    instead of watching it work.

  The gate also holds the character still for the measurement (BREATH and BLINK
  were moving 81 pixels between photographs on their own), and it asks the mod
  which host it attached to rather than guessing an order -- all four lineages
  ship a module called `VoxelGrid` and each owns its own state.

  Mutation-tested, three mutants, all killed: the row wired to nothing, the
  host's grid made unreachable, and the world-grid check removed. The third is
  invisible to pixels and is the reason G6 exists.

### Notes

- **If pressing 5 gives the world a grid and your characters stay out of it,
  check the `V-GRID CHARS` row itself.** The row arrived in 1.7.0 defaulting to
  **off** and 1.8.0 changed that default to **on**, but a default only applies
  to a save that has no value of its own: a save that recorded "off" during the
  1.7.0 window keeps it. There is one thing that makes this hard to notice --
  while the world grid is off, the row shows `PRESS 5 FOR V-GRID` *in place of
  its value*, so it does not say what it is set to until the grid is already
  on.

  Found on **Kim**'s save, which is where this whole entry started: the mod was
  behaving exactly as written, and the reported symptom was one row set to off
  three versions ago.

## [1.8.1] - 2026-08-15

A compatibility fix. If 1.8.0 did nothing for you -- the `CHARACTERS` menu was
there but your characters stayed flat -- this is the release that fixes it, and
you do not need to change any setting.

### Fixed

- **The mod now attaches to Dramaless Shape 2.x and to PotatoVoxel.** It was
  refusing both, and the reason was ours.

  This mod asks a host for three modules before it will attach. One of them,
  `ImageCache`, was never something only a host could provide: it is a small
  cache the Dramatic Shape lineage keeps over the *engine's* own image loader,
  and its own source says it exists only because the engine deliberately does
  not cache that call. We were turning away hosts over a convenience, which is
  exactly the kind of API-shaped rejection this mod removed a version gate to
  avoid in 1.4.2. The mod now uses the host's cache when it is there and its
  own -- over the same engine call, with the same behaviour -- when it is not.

  Three of the five known host lineages were affected:

  - **Dramaless Shape 2.0.0** removed `lib/ImageCache.lua` in its "Big Fat
    Cleanup" on 13 August. 1.6.4 still had it. Because that landed two days
    before 1.8.0, this looked like 1.8.0 breaking compatibility; it was not.
    Measured while fixing it: **1.6.0 fails against Dramaless 2.0.1 in exactly
    the same way**, so any Voxel Characters release would have. The host
    changed, and this mod was too brittle to survive it.
  - **PotatoVoxel** has never shipped an `ImageCache` -- it uses a `MeshCache`
    instead. This is the honest part: 1.8.0 *listed* PotatoVoxel as a supported
    host, and it had never once attached to it. Listing a host and working with
    one are different claims and only one of them was true.
  - **Pokemon Stadium 2 Overworld Models** (the Gen 2 lineage) has no
    `ImageCache` either. Its id is still not in this mod's host list, so it is
    not yet supported -- but the reason it could never have worked is now gone.

  Reported by **Pikon** and **BYRAX** (Dramaless 2.x) and by **setogabes**, who
  asked for PotatoVoxel specifically because the other hosts are too heavy on
  their device -- the report that showed the listing had been empty all along.
  **suheel** named the Stadium 2 overworld mod, which is how that fourth
  lineage got identified.

- **Dramaless Shape 2.x no longer logs an "untested version" warning.** The
  version has never been allowed to reject a host, so this only ever produced a
  scary line in the log. 2.0.1 has now actually been tested, so the range says
  so.

### Added

- **A gate that runs the real game against every voxel host installed, one at a
  time** (`tools/ingame/hosts.sh`). This bug reached players with 669 checks
  green, and it could not have been otherwise: every gate this project owns
  either mocks the host -- and a mock has whatever the mod asks it for -- or
  boots the one host that happens to be enabled on the machine doing the
  measuring, which here has always been Dramatic Shape. Nothing measured
  "attaches to the hosts other people actually run".

  The new gate boots the game once per installed host and reads whether the
  mod attached, which the mod now reports from the inside. Run against the bug
  it is meant to catch, it fails on PotatoVoxel and Dramaless 2.0.1 and passes
  on Dramatic Shape -- which is precisely the shape of what shipped.

## [1.8.0] - 2026-08-13

**If you are coming from 1.6.0, this release carries 1.7.0 as well.** 1.7.0 was
finished and never published, so everything in its section below reaches you
here for the first time: the animation channel's `ATTENTION`, `FIRST PERSON:
SOLID`, `CAMERA FIT`, `TOP DOME`, `STEP WEIGHT`, `FRONT SHAPE`, the sound
effects for `DEMO FX`, and the Dramaless Shape and PotatoVoxel hosts. Read both
sections.


### Added

- **One row instead of twenty: `OPTIONS` now holds a single `CHARACTERS` entry,
  and everything lives behind it.** This mod had grown to twenty rows in a list
  it shares with the game and with every other mod. A submenu is also where the
  host status can be stated in full, which is the first thing anybody debugging
  this needs and the last thing that fits on a shared list. On a host too old to
  register a screen the rows spill onto the main list exactly as before, so
  nobody loses an option to this.

  Asked for by **Kim**. The pattern is PotatoVoxel's (its `main.lua:1047`),
  borrowed rather than invented.

- **From the overworld, backslash opens `CHARACTERS` directly.** Trying an
  option costs one key instead of six. It does nothing anywhere else: a menu
  pushed on top of a battle or a dialog is how a shortcut like this corrupts a
  save. Backtick was unavailable (it is the engine's dev console) and the
  function keys are worse than they look -- four are taken and macOS claims most
  of the rest as media keys before the game sees them.

- **With Modern UI installed, the submenu wears that mod's design.** No special
  case on either side: Modern UI adapts any mod option screen whose id ends in
  `Options` or `Settings`, so this screen is named for that rule. Ours used to
  end in "Menu" and would have been the one un-restyled corner of that player's
  game.

- ~~**Gen 2 support.**~~ **This claim was wrong and is corrected below, in
  1.8.2.** It confused a host whose art comes from a Gen 2 game with the Gen 2
  games themselves. This mod has never been run on one.

### Changed

- **The shipped defaults are somebody's choice now, not a safe minimum.**
  `VOXEL CHARS 3`, `SIDE COLOR OUTLINE`, `SHAPE SLAB`, `GROUND SHADE ON`,
  `V-GRID CHARS ON`, `TOP EDGE ON`, `FRONT SHAPE HIGH`, `BREATH SUBTLE`.

  Set by **Kim**, by playing with the menu until there was nothing left to
  change, then comparing the two candidates side by side on video. Four of them
  turn something ON, which overrules this mod's own "anything new ships off"
  rule deliberately: that rule protects a person who did not choose, and these
  are what the person who did choose arrived at. Anything nobody has judged yet
  still ships off. `SETTINGS: DEFAULT` restores all of it at any time.

- **`SWAY` is 30% slower**, 6.2 s to 8.86 s. Also Kim's call, from watching it.
  The old value was defended in a comment as "half the rate, so they never beat
  together", which had it backwards -- two periods in a 2:1 ratio realign every
  cycle, which is the definition of beating together. 8.86 against a 3.1 s
  breath is 2.857:1 and does not repeat in any span anybody watches.

- **`TOP EDGE` and `TOP DOME` now read `(LITTLE EFFECT)` under the shipped
  `SIDE COLOR: OUTLINE`,** and keep working. Measured: byte-identical at every
  level on 56 of the 67 sheets, because no shade multiplier lifts black and
  OUTLINE hands every invented face the sprite's outline, which on all 67 sheets
  is exactly `RGB(0,0,0)`. Eleven sheets do respond, `seel` by 35% of the
  figure, so locking the rows would be a lie in one direction and "no effect" a
  lie in the other.

### Retired, and kept

- **`HD SPRITE` and `SHAPE: CARVED` are no longer directions this mod is
  exploring.** Kim, who owns it: "por hora o HD e o CARVED sao ideias que eu nao
  quero mais explorar pq nao vi retorno nelas."

  Both still ship, both stay in the menu, and no code was deleted. A measured
  negative is a result, and removing it turns "we measured this and it did not
  pay" into "nobody tried". The reasons are on the record so nobody starts over
  from the attractive half of the numbers:

  `HD SPRITE` cannot pay off through this game's own renderer. Colour is applied
  by sorting every pixel into one of four shades, so detail INSIDE an original
  pixel is discarded on the way to the screen -- which is precisely and only
  what the enlargement invented. It also carried a disproportionate share of the
  cost: five of the ten unit-scale defects in this mod's history were reachable
  only through it, and so was 481 ms of freeze on the first walking step.

  `CARVED` loses to SLAB at this game's camera, measured: 216 upward-facing
  quads against 16 on `red`, and upward surface is surface the artist never
  drew. Under the shipped `SIDE COLOR: OUTLINE` that reaches 72% of the figure
  at the lowest camera rung. It cannot reconstruct a dent, so armpits and the
  gap between the legs do not survive.

  **The one reason CARVED's code stays is worth naming**: a SLAB is a thick card
  and means nothing outside this camera, while CARVED builds an actual volume.
  If this project ever goes somewhere the camera turns, that is the only
  starting point that exists.

### Fixed

- **The trailer now pins `HD SPRITE: OFF` like every other option.** It was the
  one setting the recorder did not fix, so it filmed whatever the recording
  machine's save held. The machine used had it on, which is the whole reason a
  shot froze for 481 ms and the recorder refused to publish -- a cost belonging
  to one option on one machine, read as a defect in the baseline.

### Added

- **`BLINK DETECT: OFF / ON`.** Finds the eyes in the sprite itself, for sheets
  this mod has no hand-measured entry for.

  **Kim** reported that this mod works well with **Wilds of Kanto**, which puts
  wild Pokemon in the overworld, but that the blinking does not. It does not,
  and the cause is the shape of the feature rather than a bug: `EYE_MARKS` is a
  hand-measured table keyed by SHEET BASE NAME, and it holds 56 front entries,
  every one of them a ROM character. Wilds of Kanto ships 1298 sheets named
  `001-normal` through `649-shiny`, so all 1298 fall through the lookup and every
  wild Pokemon stands there with its eyes open forever. A bigger hand table
  would have fixed those 1298 and nothing after them.

  What the detector looks for, in the terms the mesh builder already had: an
  island of the sheet's darkest tone, at most 6 texels and at most 2 wide, whose
  every neighbour is opaque and lighter -- which is both what separates an eye
  from the silhouette outline AND exactly the condition the closed-eye UV lookup
  needs to find skin to copy from. It has to sit in the upper 62% of the sheet's
  opaque rows, and it has to have an identical twin mirrored across the cell's
  own centre line, 2 to 4 columns of skin away. And then it refuses unless
  exactly one such pair exists on the frame.

  Measured against the hand table, which is the free accuracy test: over the 67
  ROM sheets it returns marks for 30 of the 56 that have an entry -- 19 the same
  set a person measured, 11 the same eyes with one texel more or fewer -- refuses
  the other 26, and never invents eyes. All 11 sheets with no entry (`poke_ball`,
  `boulder`, `clipboard`, `fossil`, `old_amber`, `paper`, `pokedex`, `snorlax`,
  `gambler_asleep`, `bike_shop_clerk`, `monster`) are refused. Zero false
  positives is not a target here, it is the condition for the feature existing:
  two pixels of body closing every few seconds is worse than no blink and much
  harder to notice as a bug.

  **It ships OFF, and the measurement is the reason.** On Pokemon art it is not
  that clean. It fires on 144 of the 649 normal-variant Wilds of Kanto sheets,
  and of 16 of those drawn at random and looked at, 10 landed on eyes, 2 clearly
  did not (Cacturne, Cacnea) and 4 could not be judged. The rules were measured
  against three-tone ROM art with one thick black outline; a Wilds of Kanto
  sheet carries 5 to 44
  tones, so black also turns up in leg gaps and shading and "the only island of
  the darkest tone" stops meaning "the eye". The ROM numbers do not transfer,
  and claiming they do would be worse than shipping the row off and letting the
  player judge.

  The hand table stays the authority: detection only runs where there is no
  entry, and only for the front view. A profile eye is a single mark with no
  mirror twin, so `EYE_SIDE_MARKS` keeps the side view to itself.

  A new in-game gate goes with it, `tools/ingame/probe_wilds.lua`. It swaps the
  clock around one `mesh()` call to put a sheet's eye in a known state, and
  compares the mesh's UVs at the closed instant against the open one. It needs
  Wilds of Kanto installed, so it is not part of the battery. It earned its
  keep on the first run: `blink_detect` was missing from the mesh cache key, so
  turning the option on worked or did nothing depending on whether the LRU had
  recycled that character's entry -- Colonel_Aureliano's v1.4.0 defect, one
  option later. Nothing offline could have seen it: the suite loads a fresh mod
  per test and its cache is always cold.

  Reported by **Kim**.

- **`V-GRID CHARS: OFF / ON`.** Draws the voxel wireframe over characters, which
  the Voxel Mod deliberately leaves off -- correctly, for how the game should
  look: a grid over a 16x16 sprite lands a line every couple of display pixels.
  This is a measuring tool rather than a look. With it on you can see where the
  mod actually placed geometry, which tells a slab from a carved hull at a
  glance. Off by default. Uses the host's own `Voxel3D.seams`, so the pass is
  put back the way it was found.

  Asked for by **Kim**, after the options submenu became the bench this mod is
  tested on.

- **`WHAT EACH ONE DOES`, in the game.** Every option has carried an
  explanation since the option system was written and nothing ever showed it.
  A row at the bottom of `CHARACTERS` opens a screen listing every option and
  what it changes. It appears only with Modern UI installed: the help is a full
  sentence, Modern UI wraps it, and the native 160x144 renderer would run it off
  the edge.

  Asked for by **Kim**.

- **`SETTINGS`, whole configurations at once.** Browse with left/right, press A
  to apply. `DEFAULT` restores what ships. `LIVED IN` is read off Kim's own save
  after he played with the menu until he stopped changing things and said those
  were the best defaults -- four of its choices are not the mod's defaults
  (`SIDE COLOR: OUTLINE`, `TOP EDGE: OFF`, `BREATH: NORMAL`, `FRONT SHAPE: MED`),
  which is exactly what makes it worth shipping: a taste somebody arrived at by
  looking. `STILL` stops all motion, for judging shape. `SHOWCASE` turns every
  motion on at a level that reads on video. None touch `HD SPRITE` or `DEMO FX`.

  Asked for by **Kim**.

### Fixed

- **The game no longer freezes on the first step in each direction.** With
  `HD SPRITE` on, the first time a character walked in a given direction the
  whole game stopped for about half a second, once per direction. This mod's
  own trailer refused to publish over it, naming single frames of 484 ms and
  478 ms in shot 4 -- and every one of those was ONE mesh.

  It was one function reading the same sheet over and over. `poseOffsetScan`
  measures how far the art shifts between the standing pose and the walking one
  by trying every candidate offset in a window and counting how much the two
  silhouettes overlap. On the ROM's 16 px cell that is 35 candidates over 256
  texels and costs 1.7 ms, which is why nobody ever saw it. On the HD sheet's
  64 px cell the window scales with the cell, so it is 425 candidates over 4096
  texels -- and every one of those candidates was asking `love.image` for the
  same pixels again. 1,136,155 pixel reads, each through a `pcall`, for a cell
  that holds 4,096 texels.

  Two things changed and neither of them changes a single vertex:

  - **the sheet is read once per frame, not once per question.** `frameTexel`
    now decodes each frame of the cell once into one byte per texel and answers
    from that. The answer never depended on anything else -- the decoded sheet,
    the cell, the layout and the outline tone are all fixed for the life of the
    mask -- so asking twice could never have given two answers;
  - **the overlap is counted 32 texels at a time.** Each row is packed into
    32-bit words, one bit per texel; a candidate offset becomes a shift, the
    overlap becomes a bitwise AND, and the score becomes a population count.

  The second half exists because of something worth knowing on its own:
  **`jit.status()` is FALSE inside LOVE 11.5 on Apple Silicon.** The game runs
  LuaJIT as a plain interpreter, while `luajit tests/voxel_chars_test.lua` runs
  with the compiler on. The same per-texel loop measured 3.8 ms under the suite
  and 38 ms under the game. Any optimisation judged by the suite's clock is
  worth about a tenth of what it looks like.

  Measured, offline, one cold build of the HD walking pose: **251 ms became 11
  to 16 ms**, and the pixel reads inside it 1,136,155 became 4,098. Measured in
  the game, on the machine that filmed the freeze: **the three walking poses
  cost 475 ms, 472 ms and 384 ms; they now cost 20 ms, 20 ms and 21 ms**, and
  the worst frame of the whole walk went from 482 ms to 28 ms. The trailer's
  freeze guard, which had been refusing to publish, now passes shot 4 with its
  worst frames at 39 to 51 ms -- the camera tipping over, which is a cost it
  already documented.

  `CARVED` carried the same defect in its own hull test, which asks `solid`
  seven times per voxel and re-read the sheet three times per ask: 4,380,066
  reads for one mesh. Front and back depend only on the column, the profile
  only on the depth slice, and the `CARVED+` recess only on the column, so each
  is now answered once per coordinate. **`CARVED` with `HD SPRITE` -- the case
  the trailer clocked at 1324 ms in game -- measured 1099 ms offline and now
  measures 142 ms**; plain `CARVED` on a ROM sheet went from 15 ms to 8 ms.
  What is left there is the cost the option's own help text already names --
  17024 quads against 104 -- and not a scan. It is still a hitch, and a player
  who turns both of those on will still feel the first build of each pose.

  Every mesh is byte for byte the one built before: 1830 meshes over all 67 ROM
  sheets in six option combinations, plus the HD sheet in `SLAB` and `CARVED`,
  hash identical before and after.

  Caught by this mod's own trailer, which refused to publish the recording and
  named the shot and the frame. **Kim** chose to have the cause fixed rather
  than the symptom worked around.

- **`V-GRID CHARS` now follows the world grid instead of competing with it.**
  Key `5` toggles the voxel wireframe; characters join it when this is on, and
  the row says `PRESS 5 FOR V-GRID` when it is not. Independent switches would
  have let characters wear seams in a world that has none, which reads as a
  rendering fault rather than a choice -- and the renderer could not honour it
  anyway, since the wireframe is a separate compiled shader bound once per pass
  from the host's own flag.

  Asked for by **Kim**.

- **`HD SPRITE` kept none of the character's colours, and now keeps all of
  them.** It rendered in grey beside NPCs that stayed in colour, which read like
  the extra resolution had broken something deep. It had not. In voxel mode a
  character is not coloured by the screen-space shader the flat game uses -- the
  3D canvas never runs through it -- so the host bakes the world palette into
  the texture instead, and this mod's swap was replacing that baked texture with
  a raw sheet read off disk. Every sheet in this game is three greys; the colour
  lives nowhere in the file.

  Reported by **Kim**, who asked to test the option in the game.

- **`HD SPRITE` stopped throwing two squares above a character's head, and
  four other options now do their whole job on it.** One audit of every
  constant the mod expresses in SHEET PIXELS found five that did not grow when
  the cell did. None of them fail on an enlarged sheet; they quietly do a
  quarter of what they say, which is why four earlier ones in the same family
  had to be found by somebody looking at a screen.

  - `BLINK` saved a copy of each eye quad before the mesh was scaled down, and
    wrote it back at draw time -- four times too far out, which is the two
    squares. It happened with `BLINK` turned OFF as well, on the first draw.
  - `GROUND SHADE` shaded the lowest six pixels of a sixty-four pixel cell
    instead of the lowest six of sixteen: a quarter of the height its own
    help text names. This one ships ON.
  - `STEP WEIGHT` leaned a quarter as far, so HIGH on an HD sheet was weaker
    than LOW on the sheet it was enlarged from.
  - The body anchors all reported the FEET band, the head included.
  - `AUTHORED REGIONS` put all three band boundaries inside the head.

  Reported by **Kim**, who saw the two squares while walking. The other four
  came out of auditing for the same shape of mistake afterwards, and out of the
  gate below, which was written because nobody was going to see them.

- **Options that cannot do anything now say so.** The four SLAB shaping rows
  (`TOP EDGE`, `FRONT SHAPE`, `TOP DOME`, `STEP WEIGHT`) do nothing under
  CARVED, and used to sit there looking adjustable, changing their value when
  pressed and having no effect. A row whose requirement is unmet now shows what
  to change instead of a value, and refuses to step.

  This matters most for whoever is testing: a row that changes and does nothing
  reads as a broken FEATURE rather than an empty combination.

  Asked for by **Kim**.

### Added, for whoever works on this

- **`tools/hd_equivalence.lua`: the enlarged sheet has to paint the same
  picture.** A character built from 16 px art and the same character built from
  an exact nearest-neighbour enlargement of it must come out identical. The
  enlargement adds no information, so any difference is the mod reacting to
  resolution, and a mod that reacts to resolution has a constant in the wrong
  unit. That is the whole class of defect above, stated as one invariant.

  Plain LuaJIT, two seconds, no LOVE, no display, no PNG decoder, no sprite on
  disk: it builds its own art in memory twice and hands the enlarged sheet to
  the mod through the same door `hdDataFor` uses. 333984 samples on one common
  world lattice across seven option sets, each compared by plane position, by
  which ORIGINAL sheet pixel its UV lands in, by interpolated shade and by
  band, plus the extreme anchors, the band spans and a clock sweep that has to
  catch the eye shut.

  Two things it deliberately does not treat as defects, both stated in the
  tool's own header: `FRONT SHAPE` and `TOP DOME` are resolution-ADAPTIVE by
  design (they normalise against the run's own width, so a 4 pixel run gets 4
  shade steps and its enlargement gets 16), and the `center` and `hand` anchors
  are unweighted means over vertices, which no scale factor can make invariant.

  Mutation tested by reintroducing each defect one at a time: all five above go
  red, and so do the four found earlier by hand (DEPTH, `BODY_SEARCH_LIMIT`,
  the eye mark blocks, the `poseOffset` scan window) and `CARVED+`'s recess
  depth. Ten for ten.

- **`tools/ingame/probe_walk.lua`: a gate for the black that appears while
  walking.** Every new SLAB face carries no art, so `SIDE COLOR: BODY` searches
  inward for a body texel and hands the face the OUTLINE -- black -- when the
  search fails. Whether it fails depends on the row, and the walking pose sits
  one row lower than the standing one, so a face can go black on one pose and
  come back on the next. That has been reported three times (**AngelusRole** in
  v1.4.2, **Kim** twice since) and the offline suite was green every time,
  because the defect is a UV landing on the wrong texel and the suite reads
  geometry.

  It photographs the character walking IN PLACE against a wall -- the host
  animates a blocked step without moving the cell -- and isolates the character
  by differencing against the same cell with `VOXEL CHARS: OFF`, so no part of
  the measurement needs to know where the character is standing. Inside that
  set it counts black under `OUTLINE` (the search never runs, so this is the
  yardstick) and under `BODY`, once per pose.

  Mutation tested against the two defects this family has actually shipped,
  restored one at a time: leaving `BODY_SEARCH_LIMIT` unscaled on the HD sheet
  drops the standing pose from 14.5% to 4.3%, and removing v1.4.2's `poseOffset`
  compensation drops the walking pose from 21.4% to 3.0%. Each breaks one pose
  and leaves the other alone, which is why the gate checks both.

### Fixed, for whoever works on this

- **`tools/ingame/clip.sh` could not film any option, and said the option did
  not exist.** The recorder checks that a key is real before recording, because
  "the option did nothing" is unfalsifiable from a video. That check reached the
  options submenu through `Screens.get`, which for an unregistered id falls back
  to `require("src.ui." .. id)` and throws -- and the throw went into a bare
  `pcall` and was dropped. After the screen was renamed to
  `VoxelCharactersOptions`, any copy still asking for `VoxelCharsMenu` answered
  "voxel_characters does not have that key" about every key the mod has: a wrong
  answer delivered with certainty, which is the one thing that check exists not
  to do.

  Both scans are now reported rather than merely consulted, and a scan that
  FAILED downgrades the verdict from "this key does not exist" to "I could not
  tell", naming the error. Both still refuse to record.

- **The en-US sweep went red on a file nobody wrote.** Agent worktrees land
  inside the mod as a full second copy of the repository, and the sweep's file
  walk found the copy and reported it as undeclared. Every commit was blocked
  until the worktree was deleted. `.claude` is pruned from the walk and ignored
  by git.

## [1.7.0] - 2026-08-11

**Characters are alive now, and you do not have to turn anything on to see it.**
Two things ship enabled in this release:

- **`BLINK: ON`.** Characters blink. The eye is found in the sprite itself and
  closed for a twelfth of a second, on a rhythm with a per-character phase, so a
  street full of people does not blink in unison.
- **`BREATH: SUBTLE`.** Every character breathes: the body scales a fraction of
  its height, pivoted at the feet, so it rises from the ground rather than
  floating. At `SUBTLE` the top of a head moves about a fifth of a pixel, which
  is meant to be felt rather than watched.

Those two are the release. Everything else here is a switch you can throw
yourself.

**One more thing changes by default, and it is a removal.** Three characters the
mod already treated as asleep have stopped leaning toward you as you walk past.
`gambler_asleep`, `sleeping_boy` and Snorlax each have a slow rhythm, deep
breathing and no sway in the mod's own table, and a sleeping character noticing a
passer-by contradicted that.

**Everything else is off until you turn it on**, per the house rule that a visual
change the community has not seen yet ships off: `SWAY`, `MOTION LAG`,
`FOOTFALL`, `ATTENTION` and `DEMO FX` start at
`OFF`, and `FIRST PERSON` starts at `CARD`.

`AUTHORED REGIONS` is the first option whose behaviour depends on material that
ships WITH the mod rather than being derived from your own ROM, so it deserves a
plain sentence: **it ships no artwork.** What it ships is a description of where
a character's head, body and feet are, measured off your own sprite, and the
only thing it changes is where `PART LAG` cuts the body. With it `OFF` the
character is divided into four equal slices of its cell, exactly as before.
`ON`, it is divided along the figure, and the feet begin where the legs
actually part. The mod's own tooling measured why that matters: a walking frame
sits a row lower in its cell than a standing one, so the old rule moved the neck
line mid-stride. The rest of this entry
is tooling, tests and the project's own language, plus one defect in shipped
behaviour that the tooling found.

### Added

- **`FOOTFALL: OFF / SUBTLE / NORMAL` squashes the solid on each footfall and
  stretches it at the top of the step**, so the weight transfer the walk cycle
  art already implies reaches the body without separating a single leg. The
  phase comes from DISTANCE travelled rather than from the sprite frame: the
  game walks 16 px per step, so every 16 px is a footfall, and that holds for
  the player, for a wandering NPC and for anyone on a bike, which changes how
  many frames a step takes and never how many pixels it has. The amplitude
  comes from smoothed velocity, so the effect is born and dies on its own
  instead of needing an "is walking" boolean that would snap on mid-scale.
  The levels are maximum squash in world pixels.

- **`ATTENTION: OFF / SUBTLE / CLEAR` leans a character toward the player when
  the player is close, and never turns it.** The levels are head displacement
  in world pixels, 0.5 and 1.0, against `SWAY: NORMAL` at 0.45. There is
  hysteresis on the way in and out, because a reaction that snaps at an exact
  radius reads as twitching rather than as attention.

  **It is a lean because it has to be.** The side faces of a solid carry 0.0%
  of the artist's art, since these characters were drawn from the front and
  never from the side, and the only reason nobody has seen that is that this
  game never turns a character. Turning one to look at the player would show
  the invented surface and nothing else.

- **`PART LAG: OFF / LOW / HIGH` delays the upper body behind the lower one**,
  so the head and hair arrive late instead of the whole character moving as one
  rigid piece. The levels are the delay in seconds, 0.08 and 0.16: under about
  0.05 nothing is readable at 60 fps, and past about 0.2 the head stops looking
  attached.

  **It needs something to delay, and the clip guard is what caught that.** With
  every other life option off the shear is constant, and a delayed constant is
  the same constant, so `PART LAG` only shows up on top of `MOTION LAG`, `SWAY`
  or `ATTENTION`. The clip tool refused to publish a side-by-side of it, which
  is how this was found rather than shipped.

  This is also the first thing here that needed the mesh to be addressable in
  regions. Body-wide inertia was a single matrix applied to the whole mesh;
  per-part motion needed vertical bands with their own state at draw time, cut
  only along rows that already carry a cap face, because the host draws
  characters with culling disabled and a cut anywhere else would expose the
  inside of the back wall.

- **`FIRST PERSON: CARD / SOLID` keeps characters solid through a first person
  blend instead of falling back to the flat card.** Since 1.3.0 this mod has
  handed back the card the moment the blend starts, which was a fix rather than
  laziness: **Colonel_Aureliano** reported black spikes, and the cause turned
  out to be proximity and not the camera. The shader pulls every vertex toward
  the eye, so on a solid the near corners cross the near plane before the far
  ones and a spike is what is left; a flat card survives because all of its
  vertices cross together. `SOLID` caps the pull instead of giving up the
  volume.

  **What it buys, measured, because this one is easy to oversell.** Across
  eight blend values, reproducing byte for byte over four runs, the effect
  grows through the transition, peaks at blend 0.74 at 5.9% of the frame, and
  is exactly zero by blend 0.83, where the host hides the player's own card as
  the blend completes. So this is not a solid body you can walk around in first
  person, and there is nothing to see at a settled first person view either
  way. It is worth the entry and the exit: your own body used to collapse to a
  flat card exactly when the camera came closest to it.

- **`DEMO FX: OFF / FIREBALL / BOLT` is a capability demo**, off by default and
  honest about what it is. The character throws a small effect from its hand
  each time a foot lands: `FIREBALL` travels and fades, `BOLT` flashes and is
  gone. It is not a Gen 1 feature, not a combat system, and it reaches no save
  data, battle, link play or encounter.

  It is built on two things that had to exist first. The mod now knows where a
  character's **hand** is, derived from the vertices the builder emitted rather
  than from a bounding box, and it knows the moment a **foot lands**, as an edge
  on the stride it was already counting. The effect uses both, so it leaves the
  right place at the right time instead of appearing in the middle of the body
  whenever a frame happens to pass.

### Fixed

- **The life channel animated in the camera's axis instead of the character's.**
  The mesh builders bake `Rx(corr)` into every vertex and the host cancels it,
  so post-multiplying our transform landed it in mesh space, tilted by the
  camera pitch. With `BREATH: SUBTLE`, which ships ON, the head rose 33% of its
  advertised amount at the default camera rung, 7% at the lowest and 93% at the
  highest, plus up to 0.079 px of fore and aft drift nobody asked for.
  `MOTION LAG` was worse: its `kz` term came out 82% vertical at the default
  rung, so "inertia" was largely bobbing. Fixed by conjugating the transform.

  No gate caught this because every life test asserted on the MATRIX and none
  composed it with the rotation baked into the vertices. That test exists now
  and measures world displacement at all four camera rungs.

### Added, for whoever works on this

- **`tools/bateria.sh` runs the whole battery in one command**, in the order
  that makes a failure mean something, with `--rapido` for the half that needs
  no game. A pre-commit hook runs the fast half. Its first full run found a
  gate that had been failing intermittently for reasons unrelated to the code.

- **`tools/mutantes.sh` runs declared mutations and reports which ones the
  suite fails to kill.** Its first run found a real hole: flipping the sign of
  the `MOTION LAG` term changes nothing that any of 603 checks look at, so the
  suite verified the magnitude of the lag and nothing about its direction.

- **`tools/render/card.sh` builds a before and after explainer image** with
  numbered callouts, from a recipe file. The before half can be rendered from a
  released tag, so a comparison in a release note is a measurement rather than
  an illustration. It refuses two halves that are pixel identical.

- **`tools/release.sh` builds and checks a release, and rehearses by default.**
  It exists because every release from 1.0.0 to 1.6.0 was invisible to the
  in-game updater: `modkit pack` produces a `.modpkg`, and the updater only
  considers an attachment whose name ends in `.zip`, discarding the whole
  release when it finds none. Thanks to **absol**, who hit the same thing in
  his fork and pointed at it.

- **`tools/so_comentarios.lua` proves a diff touched only comments**, by
  stripping them and comparing the code underneath.

- **`tools/fx_sfx.lua` generates the two sounds for the FX demo**, and
  `tools/fx_sfx_gate.sh` re-derives and measures them on every battery run.
  Generated rather than committed on purpose: a WAV in the repository can only
  be checked once, by whoever listened to it, and after that a gate can confirm
  the bytes have not changed and nothing else. Regenerating asks the question
  that matters instead, which is whether the sound is audible and inside the
  ceiling that keeps a demo effect from sitting on top of the game's music.
  Measured: fireball peaks at -10.6 dBFS and bolt at -10.1, against a -6
  ceiling and a silent control at -91.0.

  **The two files in `sfx/` are the first thing this mod ships that is not the
  player's own art**, and the README says so where a player will read it. They
  are versioned so the mod can play them without carrying a synthesiser, and
  the gate ties them to the generator byte for byte, so a hand-edited or
  re-encoded file stops matching rather than becoming a blob nobody re-examines.

  Playback is measured, not assumed. A recording stand-in for `love.audio`
  proves the contract: nothing at all when the option is off, exactly one sound
  per effect spawned, never twice in a frame despite the host drawing every
  character twice, and the sound landing in the same frame as the effect within
  a sixtieth of a second. A positive control runs first, so "zero calls" cannot
  be a broken recorder reporting zero.

- **`HD SPRITE: OFF / ON` draws characters from a higher-resolution sheet that
  ships with the mod, where one exists.** This is the first option in the mod's
  history that draws pixels **your ROM does not contain**, and it says so in its
  own help text.

  Where the sheet came from: an LLM was given the real 16×96 Red and returned a
  faithful enlargement. Measured against the original, the silhouette matches at
  IoU 0.989 to 1.000 and four of the six frames are identical, so it invented no
  shape. What it did invent is detail *inside* each original pixel — 39% of pixel
  blocks carry more than one tone internally. At 16×16 that detail does not
  survive; at 64×64 it does, which is the resolution the sheet ships at.

  `OFF` is the default and changes nothing. Only characters with a file in `hd/`
  are affected; today that is Red alone. The cost is worth knowing before turning
  it on: 17024 pieces of geometry per character against 1068.

- **`PART LAG` and `AUTHORED REGIONS` are built and do NOT ship.** They are in
  the code, they are not in the menu, and the reason is worth stating because it
  is the only feature this release measured and then withheld.

  `PART LAG` delays the upper body behind the lower one. At `HIGH` it reads as
  the body coming apart rather than as the head arriving late. At `LOW` it does
  not clear the clip tool's own guard at all: the two sides of the comparison
  differ from each other less than one side differs from itself, so the effect
  is smaller than the animation's own variation. Neither level was worth
  offering.

  `AUTHORED REGIONS` was the fix for the underlying cause -- the four bands are
  cut from the cell rather than from the figure, and a walking frame sits a row
  lower in its cell than a standing one -- and it is held with it, because it
  exists only to refine where `PART LAG` cuts.

- **A character preset format, for the laboratory.** A look is one line of text
  you can paste into a message and load back: `preset1 sheet=red head=3 body=1`.
  It does **not** contain colours, and that is deliberate. Every one of the 67
  character sheets in this game uses the same three tones, `#000000 #555555
  #aaaaaa`, so a colour picker would produce, for all but three of its values,
  shades this art has never contained. A preset instead chooses WHICH of the
  three existing tones each body part uses, which is the one kind of recolour
  the art's own system can absorb.

- **Characters can be composed from other characters' parts**, in the
  laboratory, with no shipped art at all: the hair rows of one sheet on the body
  of another. Every pixel is still from your own ROM, and the provenance report
  says so — a composed character still measures 100% artist pixels and 0%
  shipped ones.

- **A reason can travel with a choice.** The pairwise laboratory can record WHY
  a pick was made, alongside the pick, without breaking any of the 106 choices
  already recorded.

### Fixed

- **Three sleeping characters stopped watching you.** See the note at the top:
  this is the only change in this release that a player sees without turning
  something on.

### Changed

- **The trailer pins a time of day per shot, and moves the camera within a
  shot.** It was not reproducible before: the host's default follows the
  machine's wall clock, so the same shot list filmed morning and evening gave
  different footage.

- **The repository is en-US.** Roughly 3900 comment lines across `main.lua`,
  the test suite and the in-game gates were rewritten from Portuguese, with a
  mechanical gate proving no line of code moved with them. The project exists
  because of outside reports and pull requests, and a language barrier costs
  exactly the most valuable input it has.

- **The render harness was split** from one 2723 line file into modules, graded
  by output equality against a floor measured beforehand rather than by how
  tidy the result looks.

- **The provenance report splits three ways instead of two.** It used to
  separate your artist's pixels from surface the mod computes. It now reports a
  third number, `auth%`, for pixels that ship WITH the mod. It reads `0.0%` on
  every line, because this release ships none, and it is printed anyway: a
  number that only appears once it is non-zero teaches nobody where to look, and
  the release that ships the first one is exactly the release where somebody
  should already know.

- **The mod's own measuring tools could not see part of the mod.** The
  laboratory and every comparison card resolve file paths differently from the
  game, so a feature that worked perfectly in-game did nothing in the tools that
  judge features. Nothing a player could see was affected; everything used to
  judge what a player sees was.

## [1.6.0] - 2026-08-09

### Added

- **`FRONT SHAPE: OFF / LOW / MED / HIGH` steps the SLAB front face into shade
  toward each run's edges, for false roundness without a gradient.** The front
  face is flat: every pixel bakes the same shade, and on a typical overworld
  camera angle it is the largest surface the player actually sees, roughly
  three quarters of the pixels on screen. A continuous gradient was tried
  first, dark at the edges and bright in the middle, and it read as a bright
  stripe floating over the art rather than volume: hard edged pixel art and a
  smooth gradient fight each other. Stepping the shade into a fixed number of
  constant tones instead, the same way the source art already implies volume
  with a handful of tones, reads as intended.

  Each horizontal front run picks a shade per pixel from that pixel's
  distance to the run's own edges, quantized into three constant tones,
  mirrored around the run's own center. The center and half width used for
  that are both relative to the run's own bounds, never to an absolute
  screen coordinate, so a mirrored character keeps a mirrored shade with no
  east or west special case. Runs under 3 pixels wide have no middle pixel
  to distinguish from either edge, so nothing splits there: dividing would
  only add a quad with no possible step. The `BLINK` eye quad carved out of
  a front run is unaffected: it stays its own quad at the flat front shade,
  never stepped, and blinking keeps working in every pose that already
  blinks today.

  Default is OFF, so this release changes nothing for players who do not opt
  in. LOW is the strength measured against the silhouette gate: IoU 1.000
  against the flat card at pitch 0 on `red`, `blue`, `snorlax`, `poke_ball`
  and `nurse`, frames 0 through 5, with `red.png` frame 0 moving from 105 to
  259 quads, inside the mesh's 300 quad budget. HIGH is the same measured
  strength that already reads as heavier than intended on its own, kept
  available as a ceiling for players who want more contrast anyway.
  Splitting a run only changes its baked shade, never a vertex position, so
  the silhouette and the quad count are identical for any strength above
  zero; MED sits between the two measured strengths by construction, not a
  separate render pass.

  The mesh cache key now carries the selected strength, so switching
  `FRONT SHAPE` in the options menu changes what is on screen immediately
  instead of waiting on an unrelated cache invalidation.

- **`TOP DOME: OFF / LOW / HIGH` steps the SLAB top face into shade toward
  each run's edges, for a domed cap instead of a flat one.** At a typical
  overworld camera angle the top face is a quarter of the pixels the player
  sees, and it carries no art at all: it is colored by a body color search
  and comes out flat. The side faces never contribute at this angle (the
  card's tilt is a rotation around X, and a rotation around X exposes no
  face whose normal is in X). The top face is therefore the one invented
  surface left worth the effort, and it already comes out as one quad per
  pixel, so shading it by position inside its run costs zero extra geometry.
  As with `FRONT SHAPE`, a continuous gradient was tried first and read as a
  bright stripe floating over the art; this steps the shade into a fixed
  number of constant tones instead, quantized the same way the source art
  already implies volume.

  Each horizontal top run picks a shade per pixel from that pixel's distance
  to the run's own edges, mirrored around the run's own center, the same
  mechanism `FRONT SHAPE` uses on the front face. The center and half width
  are both relative to the run's own bounds, never to an absolute screen
  coordinate, so a mirrored character keeps a mirrored shade with no east or
  west special case. Runs under 3 pixels wide have no middle pixel to
  distinguish from either edge, so nothing splits there. `TOP EDGE` and
  `TOP DOME` both shade the same face without stepping on each other: `TOP
  DOME` steps the base shade `TOP EDGE` already produced, never replaces it,
  so turning one on never cancels the other.

  Default is OFF. LOW and HIGH are the two strengths measured against the
  silhouette gate: IoU 1.000 against the flat card at pitch 0 on `red`,
  `blue`, `snorlax`, `poke_ball` and `nurse`, frames 0 through 5, with the
  quad count identical to the option off at every strength, unlike `FRONT
  SHAPE`, which does add quads when it steps a front run: the top face was
  already emitted per pixel before this option existed, so there was never a
  run to split. Flicker between the standing and walking pose, the risk this
  measurement was meant to catch, did not appear: the outline width changes
  between poses mostly in the legs, which produce almost no top face, and
  the top faces concentrate on the head, which stays 95% stable between
  poses.

  The mesh cache key now carries the selected strength, the same fix `FRONT
  SHAPE` needed: without it, switching `TOP DOME` in the options menu would
  change nothing on screen until an unrelated cache eviction happened to
  clear the old mesh.

- **`STEP WEIGHT: OFF / LOW / HIGH` shears the SLAB mesh toward the camera
  on walking frames only, proportional to height, so the solid's weight
  trails the art's own step.** When the character walks, only the sprite
  art moves: the source art already drops a line on the walk frame, but the
  solid this mod builds stayed rigid, the same shape at the same height in
  both poses. This shears every vertex in Z by an amount proportional to
  its own height above the foot, on walking frames only: the foot stays
  put, the top of the mesh moves the most, and everything between scales
  in a straight line.

  The shear lands on Z on purpose, and that choice is what keeps it safe.
  At pitch 0, the camera the silhouette gate renders from, Z points
  straight at the camera, so shearing it does not move a single pixel of
  the silhouette. At the game's own overworld camera, which looks down
  from above, that same Z offset reads as vertical motion instead, adding
  a touch of bounce to the step. There is no X component at all, so the
  host's left/right mirror never sees this option. Default is OFF.

  Which frames count as walking is read from the same six frame bucket the
  mod's `CARVED` builder already uses (front, back and side standing,
  then front, back and side walking), not a hardcoded frame list: a sheet
  with fewer than six frames has no walking pose to begin with and this
  option is a no-op on it, and a frame index past 5 folds back into the
  standing bucket the same way `CARVED` already does, rather than being
  guessed at.

  LOW and HIGH are 0.25 and 0.5. The underlying shear is linear in
  strength by construction, one multiplication with no shading steps or
  quantization involved, so a strength halfway between two measured points
  produces exactly half the measured effect, not an estimate. HIGH (0.5)
  is the strength measured against the silhouette gate: IoU 1.000 against
  the flat card at pitch 0, sampled from -1.0 to +1.0 in half steps, well
  past the range exposed here, on `red`, `blue`, `snorlax`, `poke_ball` and
  `nurse`, frames 0 through 5. It is also the ceiling of the useful range:
  past it, the step starts reading as a crouch instead of a step, so
  nothing higher is offered. LOW (0.25)
  is exactly half that strength, inside the range that still reads as a
  step. Only the positive direction is exposed: a negative strength
  flattens the step instead of amplifying it, a different effect that is
  out of scope for this change.

  Calibrated honestly: measured on a 300 pixel test cell, the art alone
  already shifts the walking pose 8 pixels from the standing pose, and
  HIGH strength adds roughly 5 more. The character on screen during actual
  play is a small fraction of that test cell, so the real addition is on
  the order of a single pixel. This is a small amount of weight in the
  animation, not a change anyone should expect to see as a new look for
  the character.

  The mesh cache key now carries the selected strength, the same fix
  `FRONT SHAPE` and `TOP DOME` needed: without it, switching `STEP WEIGHT`
  in the options menu would change nothing on screen until an unrelated
  cache eviction happened to clear the old mesh. Quad count is unchanged
  at every strength: this moves vertices that already existed, it never
  adds a face.

- **A life channel: `BREATH`, `SWAY` and `MOTION LAG`.** All three shipped OFF
  in 1.6.0. `BREATH` was turned on deliberately afterwards and ships at `SUBTLE`
  from 1.7.0; this line said "each off by default" and stayed that way through a
  release that changed it, which is corrected here rather than quietly.
  Until now every character was a solid that stood perfectly still, and a room
  of them read as a diorama of statues. These three make the body do something.

  `BREATH: OFF / SUBTLE / NORMAL / STRONG` scales the body vertically from the
  feet. `SWAY: OFF / SUBTLE / NORMAL` shears it side to side at half the breath
  rate with its own phase, so the two never reach their extremes together.
  `MOTION LAG: OFF / SUBTLE / NORMAL` runs a spring per character that leans the
  body back while it moves and overshoots when it stops.

  **None of this writes a vertex.** The host builds a fresh transform matrix for
  every character every frame, and this mod multiplies a small local transform
  into it. That matters for two reasons. The mesh is created with the `static`
  usage hint and is shared by every instance of a sheet, so rewriting its
  vertices every frame would be both the misuse that hint exists to prevent and
  a guarantee that two identical NPCs move in lockstep. Working in the matrix
  avoids both: nothing is uploaded, and every instance gets its own transform
  for free.

  The algebra is what makes it legal. The host builds
  `T(px+8, y, py+8) . Rx(lean - pi/2) . [mirror] . T(-8,0,0)`, and a local
  `S(1,s,1)` commutes with both the mirror and that last translate, so
  post-multiplying puts the scale exactly where it belongs: before the lean,
  pivoted on the feet. Only column 2 of the matrix changes; the translation
  column is copied untouched, which is why the feet stay planted by
  construction rather than by care. The shadow matrix gets the same scale, so
  the body never separates from its own shadow.

  Each character keeps its own phase across frames, tracked by matching every
  draw to a remembered instance by cell and then by nearest neighbour. The phase
  advances with the **clock**, never with position. Deriving it from position
  was the first design and it is wrong: a walking character would breathe at
  double speed going one way and freeze going the other.

  A small table gives some sheets their own temperament: a sleeping gambler
  breathes slowly and does not sway, a swimmer sways more, a guard at attention
  barely moves. `poke_ball` and `boulder` are pinned to zero, because an item
  ball that breathes is the most obvious possible defect of the whole idea.

  Measured cost, Viridian City with 25 characters on screen, vsync off, warmed
  up and interleaved so warm-up drift cannot pass for effect: 0.166 ms against a
  ruler noise floor of 0.261 ms. The honest statement is not that it is cheap,
  but that this ruler cannot measure it.

  What this is **not**: per part secondary motion. One matrix transforms the
  whole mesh one way, so it cannot hold a bag back while the torso follows the
  step. `MOTION LAG` is the whole body carrying weight, not hair moving
  independently. That would need the mesh split into regions drawn with their
  own matrices, and it is not started.

- **A second patch point, and a capability probe that guards it.** The life
  channel needs to wrap `Voxel3D.draw`, which is more of the host's surface than
  this mod touched before. The probe now asks whether that function exists and
  is callable, the wrap is installed only if it does and only after the
  mandatory patch has committed, and a host without it loses the animation while
  everything else keeps working. The three animation rows do not even appear in
  the menu on such a host.

- **A `LIFE` row, read only, next to `STATUS`.** Reports `NO HOST`,
  `NO CHANNEL`, `REPLACED`, `FIRST PERSON`, `OFF`, or which of the three is on.
  Same reasoning as `STATUS`: a channel that depends on a second host function
  has more ways to be silently absent, so it says which one it is.

### Fixed

- **The game's own mod updater could never see any release of this mod.** The
  package was attached as `voxel_characters-<version>.modpkg`, which is what
  `modkit pack` names it, and the file genuinely is a zip inside. But
  `ModUpdate.pickZipAsset` (`src/mods/ModUpdate.lua:17-45`) only considers
  assets whose **name** ends in `.zip`, and `parseReleases` (`:155`) discards a
  release outright when it finds none. Every release from 1.0.0 to 1.6.0 was
  invisible to the in game updater, and everyone who wanted this mod had to
  download and import it by hand, which is a large part of why "how do I
  install this" is the most repeated question in the thread. **absol** worked
  it out after hitting the same thing on their own fork. The 1.6.0 release now
  carries `voxel_characters-1.6.0.zip`, verified by feeding the live GitHub
  response to the game's own parser, and `tools/release_check.sh` now asks the
  game that question instead of us assuming the answer.

  For the record, the other half of the report was not the problem: the tag may
  keep its `v`, because `stripV` (`src/mods/ModUpdate.lua:12-14`) removes a
  leading `v` or `V` before the semver check.

- **Pressing A on the `STATUS` or `LIFE` row closed the options menu.** The
  engine resolves A, Left and Right in one branch, in this order: call
  `activate` if the row has one, else cycle `step` if it has one, else treat A
  as CANCEL and pop the menu (`src/ui/OptionsMenu.lua:549-566`). A read only row
  offers `value` and neither of the other two, so it landed in the third case.
  A is also the first key anyone presses on a row they do not recognise, which
  is exactly the audience the `STATUS` row was built for. Both rows now carry an
  empty `activate`, so A leaves the cursor where it is. Found by an independent
  reading of the engine, not by any gate here: nothing in this mod's test suite
  presses a key in the real menu, and that is the first thing the next version
  fixes.

- **`MOTION LAG` was shearing the body nearly 45 degrees.** The level number was
  being used as a slope instead of a head displacement in pixels, because the
  divide by the 16 pixel cell height that `SWAY` already had was missing. At the
  old top level the head moved 11 world pixels, most of a tile, and the
  character read as falling over rather than walking. Caught by watching a video
  clip, after passing 465 offline checks and 8 in game checks that all asked
  whether something changed and never asked by how much. The suite now carries
  magnitude bounds, including an absolute ceiling no future level can exceed.

- **The instance tracker could lose a character and restart its phase.** The
  neighbour search covered eight cells while the match radius was 24 pixels, and
  24 pixels over 16 pixel cells reaches two cells, not one. In that gap an
  instance was not found and was reborn with a new phase, which is exactly the
  slipping the tracker exists to prevent. The search range is now derived from
  the radius so the two cannot drift apart again. Found by an independent review
  of the code, not by a test.

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
