-- Voxel Characters: characters as pixel slabs, without invading the Voxel Mod.
--
-- Dramatic Shape draws characters as flat cards. That is a deliberate choice
-- of its own; this mod only swaps the public function that is already
-- captured by field (`SpriteBillboards.mesh`) once the player picks a
-- thickness. The shadow and the ghost stay on the original alias.
--
-- DO NOT PATCH `shadowQuad`. This is not an economy, it is a requirement. The
-- player's occlusion silhouette (`VoxelScene.drawGhost`) draws that mesh with
-- the depth test INVERTED by `Voxel3D.beginGhost`, and Dramatic Shape's
-- author documents why in VoxelScene.lua:390-396: "a mesh carrying both
-- front and back faces would read its own back faces as 'behind something'
-- and repaint the figure on open ground, occluded or not". Our slab has
-- exactly front and back. Swapping shadowQuad for it paints the player as a
-- ghost in open ground and still smears in blotches from double blend.
--
-- The price of keeping the flat card on the sun pass is the self-shadow
-- fringe on the side and back faces (README, "Slab shadow" section). It is
-- the right side of the trade: subtle fringe against the player repainted
-- across the whole screen.

local mod = ...

local Semver = require("src.mods.Semver")
local Assets = require("src.render.Assets")

-- This id list is hand-maintained because the mod API only offers
-- mod.find(id); there is no way to enumerate every loaded mod, so a host's
-- id has to be known and asked for by name before its capability can be
-- probed at all. That is the one thing here that still needs manual upkeep
-- when a new lineage of the host appears. Once a host answers to one of
-- these ids, acceptance is decided entirely by capability (see probeHost
-- below), never by which id it used or what version it reports. List order
-- only breaks ties when more than one of these hosts is installed at once;
-- it is not a ranking of the hosts.
-- THE HOSTS WE CAN ATTACH TO, in the order we prefer them.
--
-- King of Spain, who wrote Dramatic Shape, has left, and the moderators put out
-- a list of forks in his place. Only one voxel mod should be enabled at a time,
-- so this order almost never decides anything -- but when two are enabled it
-- does, and it should prefer the ones with a maintainer.
--
-- The version range below is checked and then IGNORED if the API is present: a
-- fork with an untested version number still attaches, with a warning. That
-- decision predates this list and is what makes adding a fork a one-entry
-- change instead of a release.
local HOSTS = {
  {
    -- The performance fork, and the only one of these written for low-power
    -- handhelds. It keeps billboard characters, which is the thing this mod
    -- hooks, and its lib carries SpriteBillboards, Voxel3D and VoxelState.
    --
    -- Its id is lowercase, unlike the other three. That is not a typo here.
    --
    -- What it does NOT have, and this matters to one of our options: no first
    -- person and no third person, deliberately, as too heavy for the devices it
    -- targets. FIRST PERSON therefore has nothing to attach to on this host,
    -- which our capability probe already handles -- the row does not appear.
    id = "potato_voxel",
    name = "PotatoVoxel",
    supported = ">=1.4.0 <2.0.0",
  },
  {
    id = "BATTLE_ART_VOXEL_FORK",
    name = "Battle Art Voxel Fork",
    supported = ">=1.7.0 <2.0.0",
  },
  {
    id = "DRAMALESS_SHAPE",
    name = "Dramaless Shape Voxel Mod",
    supported = ">=1.5.0 <2.0.0",
  },
  {
    id = "DRAMATIC_SHAPE",
    name = "Dramatic Shape",
    supported = ">=1.5.0 <2.0.0",
  },
}
-- REFACTOR (main chunk locals): main.lua reached 199 locals against
-- LuaJIT's ceiling of 200 (LUAI_MAXVARS) because every menu option brought
-- along a handful of locals of its own at the top of the file (key,
-- values, labels, default, default index, the state variable, and four
-- functions: indexOf/read/set/row). Seven options later the budget had run
-- out and the next one did not fit: a COMPILE error, not a behavior one,
-- because the whole mod fails to load.
--
-- From now on there is ONE option description table (OPTIONS, right
-- below) and generic functions that operate on any entry of it
-- (optionIndexOf/readOption/setOption/makeOptionRow, further down), plus
-- ONE state local (optionState, a table indexed by the option's key) in
-- place of each option's dedicated state variable. Adding a new option is
-- adding an entry to this table: no new local in the main chunk.
--
-- Each entry uses the same { LABEL, value } pair format that STEP
-- WEIGHT already used on its own before this round (the `levels` field
-- below): it works both for numeric values with a separate label (FRONT
-- SHAPE: { "LOW", 0.12 }) and for strings (SIDE COLOR: { "BODY", "body" }),
-- with no special case. `defaultIndex` points to the default position
-- inside `levels` (TOP EDGE is the only one that does not start at
-- position 1: default ON, see the comment on that entry). `clears` says
-- what `setOption` clears when the value changes: "full" (DEPTH only,
-- which also invalidates `masks`), "mesh" (most of them, which only need
-- to rebuild the mesh), or omitted (BLINK, which never clears cache: it is
-- applied per mesh on every draw in applyBlinkUv, not baked into the
-- geometry).
local OPTIONS = {
  {
    key = "depth",
    label = "VOXEL CHARS",
    levels = {
      { "OFF", "off" }, { "1", 1 }, { "2", 2 },
      { "3", 3 }, { "5", 5 }, { "10", 10 },
    },
    defaultIndex = 4, -- position of 3
    help = "Extrudes overworld character sprites. Depth 1-5 stays inside the voxel pull budget; 10 may clip into walls.",
    clears = "full",
  },
  {
    key = "side_color",
    label = "SIDE COLOR",
    levels = { { "BODY", "body" }, { "OUTLINE", "outline" } },
    defaultIndex = 2,
    help = "Colors new side, top, and bottom faces from body pixels or keeps the original outline pixels.",
    clears = "mesh",
  },
  {
    key = "shape",
    label = "SHAPE",
    levels = {
      { "SLAB", "slab" }, { "CARVED", "carved" }, { "CARVED+", "carved_plus" },
    },
    defaultIndex = 1,
    -- THE THREE ARE NOT A QUALITY LADDER, and the menu had been suggesting they are.
    --
    -- Measured on the red frame 0: SLAB has 104 quads, of which 16 are top
    -- faces. CARVED has 1068, of which 216 are top faces. Thirteen times
    -- more upward-facing surface, and top surface is by definition surface
    -- the artist never drew. On this camera, which looks down from above,
    -- that is exactly the surface the player sees.
    --
    -- This is not a tuning note, it is the law that explains the three
    -- variable-depth attempts that already died here (relief by tone, map by
    -- AI, depth by line): every depth variation creates a step, every step
    -- exposes top, and top carries no art.
    --
    -- What CARVED buys in exchange is correct silhouette from ANY angle. In
    -- a game that rotates the camera that is everything; in this one, which
    -- never rotates in yaw, it is a benefit the camera never charges for. So
    -- it is neither the better mode nor the worse one: it is the
    -- camera-independent mode, and it is the only one of the two that
    -- produces a real volume, which is what would serve as the base for
    -- anything outside this game.
    help = "SLAB keeps the artist's front face flat and whole, which is what this game's camera looks at. CARVED builds real volume from three views: correct from any angle, but it trades the art for stair steps here. CARVED+ adds tone relief to CARVED.",
    clears = "mesh",
  },
  {
    key = "ground_shade",
    label = "GROUND SHADE",
    levels = { { "OFF", "off" }, { "ON", "on" } },
    defaultIndex = 2,
    help = "Adds the host-style contact shade to the lowest six pixels of the solid character mesh.",
    clears = "mesh",
  },
  {
    key = "blink",
    label = "BLINK",
    levels = { { "OFF", "off" }, { "ON", "on" } },
    -- KIM'S DECISION, 2026-08-09: on by default. The house rule is that every
    -- new visual change is born off, and it keeps holding for what is NEW.
    -- Blinking is not new: it shipped in v1.4.0, the community used it and
    -- liked it, and nobody reported it as bothersome. The conservative
    -- default exists so people who install are not surprised; once the
    -- feature has been seen and approved, the conservative choice becomes
    -- shipping what people would already choose.
    defaultIndex = 2,
    help = "Animates front-facing overworld eyes by swapping their UVs to nearby skin texels.",
  },
  {
    key = "blink_detect",
    label = "BLINK DETECT",
    requires = { key = "blink", value = "on", why = "NEEDS BLINK" },
    levels = { { "OFF", "off" }, { "ON", "on" } },
    -- OFF, and the measurement is the reason. Kim reported that blinking does
    -- not work under Wilds of Kanto; it does not, because EYE_MARKS knows 56
    -- ROM sheets by name and that mod ships 1298 sheets it has never heard of.
    -- `detectEyeMarks` (further down) finds the eyes in the pixels instead, and
    -- on the ROM's own art it never gets one wrong: 30 of 56 marked sheets
    -- found, zero invented across 67 sheets. On Pokemon art it is not that
    -- clean: it fires on 144 of the 649 normal-variant Wilds of Kanto sheets,
    -- and of 16 of those drawn at random and looked at, 10 landed on eyes, 2
    -- clearly did not (Cacturne, Cacnea) and 4 could not be judged. Nobody has
    -- judged this yet, so the house rule says it ships off. A wrong eye closes
    -- two pixels of body every few seconds, which is worse than no blink.
    defaultIndex = 1,
    help = "Finds the eyes in the sprite itself on sheets this mod has no hand-measured entry for, such as the Pokemon sheets added by Wilds of Kanto. Refuses unless it finds exactly one mirrored pair of small dark islands on skin. Never overrides a hand-measured sheet.",
    clears = "mesh",
  },
  {
    key = "grid_chars",
    label = "V-GRID CHARS",
    requires = { check = function() return gradeDoMundo() end,
                 why = "PRESS 5 FOR V-GRID" },
    -- A MEASURING TOOL, not a look. The host deliberately keeps the voxel
    -- wireframe off characters (VoxelScene.lua:1048): the seams are what make
    -- the WORLD read as built of voxels, and the people in it should read as
    -- drawn. That is a good call and this is not arguing with it.
    --
    -- It exists because with the grid on you can SEE where this mod actually
    -- put geometry -- a slab against a carved hull at a glance, or a face that
    -- should not be there. The submenu has become the bench this mod is tested
    -- on, and this is a bench instrument.
    --
    -- Needs the animation channel for the same reason the life options do: it
    -- rides the draw wrap, and without the wrap there is nowhere to stand.
    levels = { { "OFF", "off" }, { "ON", "on" } },
    defaultIndex = 2,
    help = "Draws the voxel wireframe over characters, which the host leaves off on purpose. A debugging aid: it shows where the mod actually placed geometry.",
  },
  {
    key = "top_edge",
    -- SLAB ONLY, and the code already said so in prose: CARVED and CARVED+
    -- build from the visual hull, with no continuous front run to step and no
    -- top run to shade. The row used to sit there looking adjustable and do
    -- nothing, which is the menu telling a lie.
    requires = { key = "shape", value = "slab", why = "NEEDS SHAPE: SLAB" },
    label = "TOP EDGE",
    levels = { { "OFF", "off" }, { "ON", "on" } },
    -- DECISION v1.4.2: OFF is not neutral. With SIDE COLOR: BODY, the top
    -- face of the highest row can pull the body color from below and paint
    -- a light cap above the dark outline, as on Red's hat. TOP EDGE on by
    -- default adds no effect: it removes that reading defect and keeps an
    -- adjustable dark edge for anyone who wants to go back to plain host
    -- shade.
    defaultIndex = 2, -- "on"
    help = "Darkens only exposed SLAB top faces for a false top-down edge.",
    clears = "mesh",
  },
  {
    key = "front_shape",
    -- SLAB ONLY, and the code already said so in prose: CARVED and CARVED+
    -- build from the visual hull, with no continuous front run to step and no
    -- top run to shade. The row used to sit there looking adjustable and do
    -- nothing, which is the menu telling a lie.
    requires = { key = "shape", value = "slab", why = "NEEDS SHAPE: SLAB" },
    label = "FRONT SHAPE",
    -- DECISION v1.6.0: the three levels are stepped shading strength on the
    -- front face, not polygon count. The geometry (vertex position, hence
    -- IoU and quad count) is identical for any strength > 0: emitFrontRun
    -- only uses the strength to scale each step's shade multiplier, never a
    -- vertex position. 0.12 is the value measured and validated by Kim (IoU
    -- 1.000 against the flat card on red, blue, snorlax, poke_ball and
    -- nurse, frames 0-5; 259 quads on red.png frame 0, within the budget of
    -- 300) and is the first level turned on. 0.22 was also measured and
    -- already "weighs too much" in Kim's reading, but it stays available as
    -- a ceiling for anyone who prefers more contrast. 0.17 (MED) is the
    -- midpoint between the two measured extremes: since the geometry does
    -- not depend on the magnitude of the strength, the two measured numbers
    -- already cover this third level by construction, with no need for an
    -- extra render round.
    levels = {
      { "OFF", "off" }, { "LOW", 0.12 }, { "MED", 0.17 }, { "HIGH", 0.22 },
    },
    defaultIndex = 4,
    help = "Steps the SLAB front face into three pixel aligned shade tones toward each run's edges, for false roundness without a gradient.",
    clears = "mesh",
  },
  {
    key = "top_dome",
    -- SLAB ONLY, and the code already said so in prose: CARVED and CARVED+
    -- build from the visual hull, with no continuous front run to step and no
    -- top run to shade. The row used to sit there looking adjustable and do
    -- nothing, which is the menu telling a lie.
    requires = { key = "shape", value = "slab", why = "NEEDS SHAPE: SLAB" },
    label = "TOP DOME",
    -- DECISION v1.6.0: TOP DOME follows the same mechanism as FRONT SHAPE
    -- (shade steps by position within the run, the strength only scales
    -- each step's multiplier, never a vertex position), but with two
    -- levels, not three: only 0.15 and 0.30 were measured (IoU 1.000
    -- against the flat card on red, blue, snorlax, poke_ball and nurse,
    -- frames 0-5; quad count identical to the option turned off at any
    -- strength) and the flicker between poses, the pre-registered risk,
    -- did not show up in the gate. Unlike FRONT SHAPE, there is no
    -- interpolated MED here: this round's spec only gave the two measured
    -- points, and a third level without measurement would be a guess.
    levels = { { "OFF", "off" }, { "LOW", 0.15 }, { "HIGH", 0.30 } },
    -- House rule: every new menu option starts with a conservative default.
    -- TOP DOME changes an established visual reading (the flat cap) and has
    -- not shipped yet, so OFF, like FRONT SHAPE.
    defaultIndex = 1,
    help = "Steps the SLAB top face into pixel aligned shade tones toward each run's edges, for a domed cap instead of a flat one.",
    clears = "mesh",
  },
  {
    key = "step_weight",
    -- SLAB ONLY, and the code already said so in prose: CARVED and CARVED+
    -- build from the visual hull, with no continuous front run to step and no
    -- top run to shade. The row used to sit there looking adjustable and do
    -- nothing, which is the menu telling a lie.
    requires = { key = "shape", value = "slab", why = "NEEDS SHAPE: SLAB" },
    label = "STEP WEIGHT",
    -- DECISION: STEP WEIGHT displaces a VERTEX (shear in Z), not shade, so
    -- unlike FRONT SHAPE/TOP DOME the magnitude changes real geometry, in
    -- the formula z = z + strength * (y / cellH). This formula is linear in
    -- the strength by construction: no step, no quantizer, just a
    -- multiplication. Kim measured the screen displacement on a 300px cell
    -- at three points (lean 0: +8px, art only; +0.5: +13px; -0.5: +3px) and
    -- the silhouette at pitch 0 (IoU 1.000) at FIVE points, -1.0 to +1.0,
    -- comfortably covering the range used here. 0.5 is both the measured
    -- ceiling and the ceiling Kim judged as the limit before the character
    -- starts to look like it is crouching instead of walking (his call, not
    -- contradicted by any new measurement: the linear formula gives no
    -- reason for a nonlinear turn between 0.25 and 0.5). 0.25 is exactly
    -- half that strength; the same linearity that guarantees half the
    -- measured displacement guarantees half the distance to any side
    -- effect, with no need for a new mesh to confirm it. Only the positive
    -- sign becomes a level: negative flattens the step, a different effect
    -- that is out of scope for this round.
    levels = { { "OFF", "off" }, { "LOW", 0.25 }, { "HIGH", 0.5 } },
    -- House rule again: STEP WEIGHT displaces a vertex for the first time
    -- in this branch (FRONT SHAPE and TOP DOME only touch shade), so the
    -- conservatism of the OFF default matters even more here.
    defaultIndex = 1,
    help = "Shears the SLAB mesh toward the camera on walking frames only, proportional to height, so the solid's weight trails the art's own step.",
    clears = "mesh",
  },
  -- ------------------------------------------------------------------ LIFE
  -- The three options below do NOT touch the mesh. They post-multiply the
  -- MATRIX the host builds per character per frame, inside our
  -- Voxel3D.draw wrap. That is why they have no `clears`: the cached
  -- geometry keeps being valid, and switching level takes effect on the
  -- next frame.
  --
  -- Why matrix and not vertex: the mesh is created with a "static" hint
  -- (Voxel3D.newMesh) and SHARED by every instance of the same sheet.
  -- Rewriting a vertex every frame would be the misuse that hint exists to
  -- prevent, and it would make two identical NPCs breathe in unison. The
  -- matrix arrives freshly allocated per instance (measured:
  -- tools/ingame/probe_draw.lua, eight properties, all passed), so it is
  -- the right channel.
  {
    key = "breath",
    label = "BREATH",
    -- Scales in Y around the FEET. The pivot is already at the feet by
    -- construction of the host's matrix, and S(1,s,1) commutes with the
    -- mirror and with the local T(-8,0,0), so post-multiplying the final
    -- matrix gives exactly "the body stretches upward from the ground"
    -- (checked in the algebra and confirmed by independent external
    -- review).
    --
    -- The numbers are a fraction of the height: the sheet is 16 px tall, so
    -- 0.010 displaces the top of the head by 0.16 world px.
    --
    -- SHIPS ON, at SUBTLE, and this comment used to say the opposite. It read
    -- "Default OFF per the house rule" while `defaultIndex` was 2, so the
    -- source contradicted itself and the 1.6.0 release note repeated the
    -- comment rather than the code. The house rule is real and this is a
    -- deliberate exception to it: breathing is what the life channel is FOR,
    -- and a mod whose headline feature is off by default has no headline.
    -- Blink ships on for the same reason, decided in the same commit.
    levels = {
      { "OFF", "off" }, { "SUBTLE", 0.010 }, { "NORMAL", 0.020 },
      { "STRONG", 0.035 },
    },
    -- KIM'S DECISION, 2026-08-09: on by default, at the LOWEST level.
    --
    -- This is the first time this mod ships movement without anyone asking
    -- for it, so it is worth recording what backs the choice. SUBTLE
    -- displaces the head by 0.16 world px, less than one screen pixel on
    -- the game's camera; the whole channel's cost stayed below the
    -- measuring rig's noise floor; and the effect disappears on its own on
    -- a host without the channel, without breaking anything. What it buys
    -- is the absence of the statue feeling, which is the reason this mod
    -- exists.
    --
    -- SUBTLE and not NORMAL on purpose: the right default for something the
    -- person did not choose is the smallest one that still makes a
    -- difference.
    defaultIndex = 2,
    help = "Breathes the solid by scaling it vertically from the feet, out of phase per character, so a room of NPCs stops reading as frozen.",
  },
  {
    key = "sway",
    label = "SWAY",
    -- Shear in X proportional to height: x' = x + k*(y/cellH). The feet
    -- stay pinned (y=0) and the head displaces k px. The sign is inverted
    -- when the sheet is mirrored, otherwise the sway would flip sideways
    -- along with the character.
    levels = { { "OFF", "off" }, { "SUBTLE", 0.20 }, { "NORMAL", 0.45 } },
    defaultIndex = 1,
    help = "Sways the solid side to side from the feet, slower than the breath and on its own phase, for idle weight shift.",
  },
  {
    key = "lag",
    label = "MOTION LAG",
    -- Inertia. A second-order spring per instance chases the character's
    -- velocity and shears the body in the OPPOSITE DIRECTION, proportional
    -- to height, with overshoot when it stops.
    --
    -- WHAT THIS IS NOT, and honesty matters here because the name is easy
    -- to misread: it is not secondary motion by part. A single matrix
    -- transforms the whole mesh one single way; it cannot hold the
    -- backpack steady while the torso follows the step. External review
    -- was direct on this point and is right. What comes out of this is the
    -- WHOLE BODY leaning from the feet, which reads as weight and inertia,
    -- not as hair flapping in the wind.
    --
    -- Real secondary motion requires a submesh per region (body, head,
    -- backpack) drawn with its own matrix. That is NOT done, and it is
    -- written this way in the roadmap so nobody thinks it is.
    -- The numbers are HEAD displacement in world pixels at walking speed,
    -- the same unit as SWAY. The spring overshoots by about 8%, so the
    -- real peak lands a bit above the chosen level.
    levels = { { "OFF", "off" }, { "SUBTLE", 0.6 }, { "NORMAL", 1.2 } },
    defaultIndex = 1,
    help = "Leans the whole solid back from its feet with a spring while it moves, and overshoots when it stops, so the body carries weight instead of sliding.",
  },
  {
    key = "footfall",
    label = "FOOTFALL",
    -- SQUASHES ON FOOTFALL IMPACT and stretches at the midpoint, keeping
    -- volume constant: the body lowers and widens when the foot hits, rises
    -- and thins when the step passes the top. It is the weight transfer the
    -- walk cycle art already implies, carried over to the solid without
    -- separating a single leg.
    --
    -- PHASE comes from DISTANCE traveled, not the sprite frame. The game
    -- walks 16 px per step, so every 16 px is a footfall, and this holds
    -- equally for the player, for an NPC wandering, and for anyone on a
    -- bike (which only changes how many frames the step takes, never how
    -- many pixels it has).
    --
    -- AMPLITUDE comes from smoothed velocity, so the effect is born and
    -- dies on its own when the character starts and stops walking. Without
    -- that it would need an "is walking" boolean, which would snap on and
    -- off mid-scale and show up as a jolt.
    --
    -- The numbers are the maximum squash in world pixels, the same unit as
    -- SWAY and MOTION LAG.
    levels = { { "OFF", "off" }, { "SUBTLE", 0.35 }, { "NORMAL", 0.7 } },
    defaultIndex = 1,
    help = "Squashes the solid on each footfall and stretches it at the top of the step, so the walk cycle's weight transfer reaches the body.",
  },
  {
    key = "attention",
    label = "ATTENTION",
    -- DECISION: the levels are LEAN, in world pixels at the head, toward
    -- whoever is watching. Not a turn.
    --
    -- NEVER ROTATE IN Y, and this is the rule the whole option is built
    -- around. The side faces of a slab carry 0.0% art, because the artist
    -- drew the character from the front and never from the side. The only
    -- reason nobody has seen that yet is that this game never turns a
    -- character. Turning one to "look at" the player would show the invented
    -- surface and nothing else, which is the opposite of noticing someone.
    --
    -- So attention is a LEAN, expressed through the same shear the life
    -- channel already uses, and the character keeps facing the way the game
    -- says it faces.
    --
    -- 0.5 and 1.0 pixels of head displacement. SWAY at its normal level is
    -- 0.45, so SUBTLE is about the size of a breath and CLEAR is twice it.
    -- Anything larger stops reading as attention and starts reading as the
    -- character falling toward the player.
    --
    -- OFF by default: new visual change, house rule.
    levels = { { "OFF", "off" }, { "SUBTLE", 0.5 }, { "CLEAR", 1.0 } },
    defaultIndex = 1,
    help = "Leans a character slightly toward the player when the player is close, without ever turning it.",
  },
  {
    key = "part_lag",
    -- Has nothing to delay on its own; its own help has said so since it was
    -- written. Held out of the menu today, so this only matters the day it
    -- comes back -- which is exactly when nobody will remember.
    requires = { anyOn = { "lag", "sway", "attention" },
                 why = "NEEDS MOTION LAG, SWAY OR ATTENTION" },
    held = true,  -- see registerOptionsRows: does not ship in 1.7.0
    label = "PART LAG",
    -- DECISION: the levels are DELAY, in seconds, between what the feet do and
    -- what the head does. Not amplitude: the shear is already x' = x + k*y, so
    -- the head ALREADY moves further than the feet. What a rigid body cannot
    -- do is arrive LATE, and that is the whole difference between a statue
    -- that leans and a person whose hair follows.
    --
    -- 0.08 and 0.16 seconds. Below about 0.05 nothing is readable at 60fps,
    -- and past about 0.2 the head stops looking attached.
    --
    -- OFF by default, because it is a new visual change and the house rule is
    -- that those ship off until the community has seen one and approved it.
    levels = { { "OFF", "off" }, { "LOW", 0.08 }, { "HIGH", 0.16 } },
    defaultIndex = 1,
    -- IT NEEDS SOMETHING TO DELAY, and that was found by the clip guard
    -- refusing to publish it: with every other life option off, the shear is
    -- constant, and a delayed constant is the same constant. PART LAG only
    -- shows up on top of MOTION LAG, SWAY or ATTENTION, which is obvious in
    -- hindsight and was not obvious when the option was written.
    help = "Delays the upper body behind the lower one, so the head and hair arrive late instead of moving as one rigid piece. Needs MOTION LAG, SWAY or ATTENTION on: it delays their movement, and has nothing to delay on its own.",
  },
  {
    key = "hd_sprite",
    label = "HD SPRITE",
    -- THE EXPERIMENT KIM ASKED FOR (roadmap T3.0). An LLM was given the real
    -- 16x96 sheet and returned a faithful 26x enlargement: silhouette IoU 0.989
    -- to 1.000 against the original, four of six frames identical, and only 28
    -- of 1536 pixels differing in tone once reduced back to 16x16.
    --
    -- So it invented no SHAPE. What it did invent is detail INSIDE each original
    -- pixel: 39% of pixel blocks carry more than one tone internally, up to five
    -- levels. Reduced to 16x16 that detail vanishes, which is why this option
    -- exists at 64x384 -- four blocks per original pixel is where it survives.
    --
    -- ON reads `hd/<sheet>.png` instead of the player's own sprite, so this is
    -- the first option that draws pixels the ROM does not contain. That is a
    -- deliberate experiment and not a slip: see T3.0. Only sheets with a file in
    -- `hd/` change at all; everyone else is untouched.
    --
    -- The cost is real and worth knowing before turning it on: 17024 quads per
    -- character against 1068, and a town holds about twenty five of them.
    levels = { { "OFF", "off" }, { "ON", "on" } },
    defaultIndex = 1,
    help = "Draws characters from a higher-resolution sheet shipped with the mod, where one exists, instead of from your own game's sprite. An experiment: the extra detail was invented by an LLM, not read from your ROM.",
  },
  {
    key = "authored_regions",
    held = true,  -- see registerOptionsRows: does not ship in 1.7.0
    label = "AUTHORED REGIONS",
    -- WHAT THIS CHANGES, and it changes nothing on its own: it only alters
    -- WHERE PART LAG cuts. With it off, the body is divided into four equal
    -- slices of the CELL. With it on, and only for a sheet that ships measured
    -- metadata, it is divided along the FIGURE, and the feet band begins where
    -- the legs actually part.
    --
    -- The defect it addresses was measured rather than imagined
    -- (tools/measure_regions.py): the walking frames of a sheet sit lower in
    -- the cell than the standing frames, so cutting the cell puts every
    -- boundary a row up the body mid-stride. The neck line moves during a walk
    -- for no reason a viewer could name.
    --
    -- OFF by default, and the reason is not only the house rule. This is the
    -- first option whose behaviour depends on material shipped WITH the mod
    -- rather than derived from the player's own ROM, and pure runtime has to
    -- stay reachable as the control. It ships no pixels: see
    -- docs/DISCLOSURE_DRAFT.md and authored/schema.lua.
    levels = { { "OFF", "off" }, { "ON", "on" } },
    defaultIndex = 1,
    help = "Lets PART LAG cut along measured body regions instead of four equal slices of the cell. Only affects sheets that ship region metadata, and only while PART LAG is on. Ships no artwork.",
  },
  {
    key = "first_person",
    label = "FIRST PERSON",
    levels = { { "CARD", "card" }, { "SOLID", "solid" } },
    defaultIndex = 1,
    -- WHY THIS EXISTS, AND WHY ONLY NOW.
    --
    -- Since v1.3.0 this mod has returned the flat card whenever
    -- FirstPerson.cardBlend() > 0. That was not laziness, it was a fix:
    -- Colonel_Aureliano reported black spikes with Dramatic Shape 1.7.0
    -- plus Kanto First Person, and the flat card does not have the defect.
    --
    -- Reading the host, the mechanism is this, and it is not "first
    -- person":
    --
    --   the shader moves EVERY VERTEX along its own ray toward the eye, by
    --   `pull` units (Voxel3D.lua:122-130);
    --   first person is step 6, and ANGLES_DEG[7] = 75 degrees, so
    --   VoxelScene.pull(rad 75) = 6 world units, with the tile worth 16;
    --   the near plane sits at max(1, |eye-focus| * 0.05), that is, 1 unit
    --   when eye and focus are together, which is the case here.
    --
    -- A vertex at distance d from the eye ends up at d - 6: it crosses the
    -- near plane at d < 7 and passes BEHIND the eye at d < 6. The flat card
    -- survives because all its vertices are at the same distance and cross
    -- together; on a solid the corners are at different distances, the
    -- front ones cross first, and what is left on screen is the spike.
    --
    -- SO THE DEFECT IS ONE OF PROXIMITY, NOT CAMERA. The catastrophic case
    -- is the player's own card during the transition, because the camera
    -- is entering their head and d goes to zero; the host only hides that
    -- card past blend > 0.9, so every entry and every exit passes through
    -- the broken range. An NPC one tile away is 16 units out and never
    -- gets close.
    --
    -- That is why turning off the solid for the whole camera was always
    -- too blunt, and why the fix lives in the draw wrap and not here:
    -- capping the `pull` we pass through removes the near plane crossing by
    -- construction, without giving up the volume. See fpPullSeguro.
    --
    -- Born as CARD per the house rule. That players have asked for it
    -- counts as a request, not as approval: nobody has seen it yet.
    help = "Keeps characters solid in first person instead of falling back to the flat card. Needs the host's draw channel.",
  },
  {
    key = "demo_fx",
    label = "DEMO FX",
    levels = { { "OFF", "off" }, { "FIREBALL", "fireball" }, { "BOLT", "bolt" } },
    defaultIndex = 1,
    -- A CAPABILITY DEMO, and the release note has to say so in those words.
    --
    -- It exists to show that this mod can own character effects with a
    -- position, a lifetime and a sound, rather than only passive body
    -- deformation. It is NOT Gen 1 authentic, it is not a combat system, and
    -- nothing it does reaches save data, battles, link play or an encounter.
    --
    -- Fired by a REAL EVENT from a REAL ANCHOR: one effect per footfall,
    -- leaving the character's hand. Both came from roadmap T1.2, which is why
    -- that was built first.
    --
    -- OFF by the house rule, and here the rule matters more than usual: this is
    -- the first thing the mod draws that is not the player's own art.
    help = "A capability demo, not a Gen 1 feature: the character throws a small effect from its hand on each footstep. Off by default.",
  },
}

local OPTION_BY_KEY = {}
for _, opt in ipairs(OPTIONS) do
  OPTION_BY_KEY[opt.key] = opt
end

-- The options that depend on the SECOND patch point (Voxel3D.draw). Without
-- that channel they do not show up in the menu: see registerOptionsRows.
-- FIRST PERSON belongs here even though it is not animation: what it
-- promises is the limited pull, which only exists if we can wrap
-- Voxel3D.draw. Offering SOLID on a host without that channel would be
-- offering the spikes back.
local LIFE_OPTION_KEYS = { breath = true, sway = true, lag = true,
  footfall = true, attention = true, part_lag = true, first_person = true,
  -- V-GRID CHARS rides the draw wrap like the rest of these: it toggles the
  -- host's seam uniform around our own draw, so without the wrap there is
  -- nowhere to stand and the row would promise what it cannot do.
  authored_regions = true, hd_sprite = true, grid_chars = true }

-- SIDE COLOR sentinel used by bodyTexelInFrame/blinkBodyTexel (further
-- below) to decide whether the body search comes into play. It stays as
-- its own constant, outside the generic option system, because those two
-- functions sit in the middle of mesh construction, not in the menu.
-- REFACTOR (main chunk locals, roadmap item 0): this used to be nineteen
-- separate chunk-level constants, DEFAULT_SIDE_COLOR through
-- BLINK_CLOSED_SECONDS, one `local` each. Same problem and same fix as the
-- OPTIONS/optionState refactor above (main.lua:53): every function gets
-- its OWN separate budget against LuaJIT's 200 chunk locals, so a constant
-- read by exactly one function costs nothing if it lives as a local inside
-- that function's body instead of out here. Fifteen of the nineteen moved
-- that way; follow the name to find it again:
--   TOP_EDGE_SHADE, SIDE_INSET, RUN_UV_INSET, FRONT_SHAPE_STEPS,
--     TOP_DOME_STEPS -> buildSlabMesh
--   PITCH_BUCKET -> quantizeCorrection and pitchKey (duplicated: it is
--     `math.pi / 180`, a unit conversion that cannot drift, not a tunable)
--   MAX_MESHES -> rememberMesh
--   AO_STRENGTH, AO_GROUND, AO_RISE -> shadeAtHeight
--   BODY_SEARCH_LIMIT -> bodyTexelInFrame
--   CARVED_PLUS_RECESS_STEPS -> buildCarvedMesh
--   POSE_OFFSET_DX_RANGE, POSE_OFFSET_DY_RANGE -> poseOffsetScan
--   BLINK_CLOSED_SECONDS -> blinkClosedForBase
-- The other four (SHARED.OBJ_SHADE, SHARED.DEFAULT_SIDE_COLOR, SHARED.DRAW_WINDOW_SIZE,
-- SHARED.LUMA_EPSILON) are each read by TWO OR MORE functions, so none of them has
-- a single home to move into; they stay here, gathered into one table
-- instead of four chunk locals. LIFE_CELL joins this same table further
-- down (main.lua, near the LIFE tuning block), where its own comment
-- lives, because it is shared by lifeCellKey, lifeInstance and
-- lifeDrawWrap the same way.
--
-- DECISION: Dramatic Shape's light comes from the southeast. Front and top
-- stay light, back and bottom darken by facing away from the light, and the
-- sides use a middle ground so the slab reads as volume without relying on
-- a real shadow. The front follows Voxel3D.FACE_SHADE.front = 0.90, not
-- 1.00. The sides stay symmetric at 0.78 on purpose: the host resolves the
-- frame before calling SpriteBillboards.mesh(def, frame) and applies the
-- mirror afterward on the matrix (VoxelScene.lua:234-241, 287-295). Since
-- the shade already comes baked into the vertex, different values for
-- east/west would swap sides on mirrored sheets. Read by both buildSlabMesh
-- and buildCarvedMesh.
--
-- DECISION v1.4.2, fine-tooth comb (item 1): STATUS decides by PROPORTION
-- over a sliding window of the last SHARED.DRAW_WINDOW_SIZE draw results, not by
-- an unbroken streak. A count of CONSECUTIVE failures is defeatable by
-- interleaving: if the player's sprite draws fine every frame while NPCs
-- with broken sheets fail interleaved on the same screen, every `ok` from
-- the player resets the streak before it reaches the limit, and STATUS
-- stays stuck at ACTIVE forever even with most characters falling back to
-- the flat card every frame. It escalates when HALF OR MORE of the window
-- is failures; a single bad sheet isolated among several good ones never
-- gets close to that (in the worst distribution within the window, 1 bad
-- sheet for every 4 good ones occupies at most 2 of the 8 slots), but
-- strict good/bad alternation (half the screen failing) escalates. Read by
-- pushDrawWindow and statusValue.
--
-- LUMA_EPSILON is read by frameTexel, eyeMarkTransfers and buildCarvedMesh.
local SHARED = {
  OBJ_SHADE = { front = 0.90, back = 0.68, side = 0.78, top = 1.0, bottom = 0.55 },
  DEFAULT_SIDE_COLOR = "body",
  DRAW_WINDOW_SIZE = 8,
  LUMA_EPSILON = 0.00001,
  -- The game's walking grid, in px. Read by lifeCellKey, lifeInstance and
  -- lifeDrawWrap (main.lua, LIFE section), which is why it lives here
  -- instead of as a local inside just one of them.
  LIFE_CELL = 16,
}

local EYE_MARKS = {
  agatha = { { 5, 7 }, { 6, 7 }, { 9, 7 }, { 10, 7 } },
  balding_guy = { { 6, 7 }, { 9, 7 } },
  beauty = { { 6, 7 }, { 9, 7 }, { 6, 8 }, { 9, 8 } },
  biker = { { 5, 6 }, { 6, 7 }, { 9, 7 }, { 10, 6 } },
  bird = { { 6, 7 }, { 9, 7 } },
  blue = { { 6, 7 }, { 9, 7 } },
  brunette_girl = { { 6, 7 }, { 9, 7 }, { 6, 8 }, { 9, 8 } },
  bruno = { { 5, 7 }, { 6, 7 }, { 9, 7 }, { 10, 7 } },
  captain = { { 6, 7 }, { 9, 7 } },
  channeler = { { 5, 7 }, { 6, 7 }, { 9, 7 }, { 10, 7 } },
  clerk = { { 5, 5 }, { 6, 5 }, { 9, 5 }, { 10, 5 } },
  cook = { { 6, 7 }, { 9, 7 } },
  cooltrainer_f = { { 6, 7 }, { 9, 7 }, { 6, 8 }, { 9, 8 } },
  cooltrainer_m = { { 6, 7 }, { 9, 7 } },
  daisy = { { 6, 7 }, { 9, 7 }, { 6, 8 }, { 9, 8 } },
  fairy = { { 5, 7 }, { 10, 7 } },
  fisher = { { 5, 5 }, { 6, 5 }, { 9, 5 }, { 10, 5 } },
  fishing_guru = { { 6, 7 }, { 9, 7 } },
  gambler = { { 6, 6 }, { 9, 6 } },
  gameboy_kid = { { 6, 7 }, { 9, 7 } },
  gentleman = { { 6, 7 }, { 9, 7 } },
  giovanni = { { 5, 6 }, { 6, 6 }, { 9, 6 }, { 10, 6 }, { 6, 7 }, { 9, 7 } },
  girl = { { 6, 6 }, { 9, 6 }, { 6, 7 }, { 9, 7 } },
  gramps = { { 5, 5 }, { 6, 5 }, { 9, 5 }, { 10, 5 } },
  granny = { { 5, 5 }, { 6, 5 }, { 9, 5 }, { 10, 5 } },
  guard = { { 6, 7 }, { 9, 7 } },
  gym_guide = { { 5, 6 }, { 6, 6 }, { 9, 6 }, { 10, 6 } },
  hiker = { { 6, 5 }, { 9, 5 } },
  koga = { { 5, 6 }, { 6, 6 }, { 9, 6 }, { 10, 6 }, { 6, 7 }, { 9, 7 } },
  lance = { { 6, 7 }, { 9, 7 } },
  link_receptionist = { { 6, 7 }, { 9, 7 }, { 6, 8 }, { 9, 8 } },
  little_boy = { { 6, 8 }, { 9, 8 }, { 6, 9 }, { 9, 9 } },
  little_girl = { { 6, 8 }, { 9, 8 }, { 6, 9 }, { 9, 9 } },
  lorelei = { { 5, 7 }, { 6, 7 }, { 9, 7 }, { 10, 7 } },
  middle_aged_man = { { 6, 6 }, { 9, 6 } },
  middle_aged_woman = { { 6, 6 }, { 9, 6 }, { 6, 7 }, { 9, 7 } },
  mom = { { 6, 7 }, { 9, 7 }, { 6, 8 }, { 9, 8 } },
  mr_fuji = { { 6, 7 }, { 9, 7 } },
  nurse = { { 6, 6 }, { 9, 6 }, { 6, 7 }, { 9, 7 } },
  oak = { { 6, 6 }, { 9, 6 }, { 6, 7 }, { 9, 7 } },
  red = { { 6, 7 }, { 9, 7 } },
  red_bike = { { 6, 6 }, { 9, 6 } },
  rocker = { { 6, 6 }, { 9, 6 } },
  rocket = { { 6, 7 }, { 9, 7 } },
  safari_zone_worker = { { 6, 7 }, { 9, 7 } },
  sailor = { { 5, 6 }, { 6, 7 }, { 9, 7 }, { 10, 6 } },
  scientist = { { 5, 5 }, { 6, 5 }, { 9, 5 }, { 10, 5 } },
  seel = { { 6, 6 }, { 9, 6 }, { 6, 7 }, { 9, 7 } },
  silph_president = { { 5, 3 }, { 6, 3 }, { 9, 3 }, { 10, 3 } },
  silph_worker_f = { { 6, 6 }, { 9, 6 }, { 6, 7 }, { 9, 7 } },
  silph_worker_m = { { 5, 7 }, { 6, 7 }, { 9, 7 }, { 10, 7 } },
  super_nerd = { { 6, 7 }, { 9, 7 } },
  swimmer = { { 5, 9 }, { 10, 9 } },
  waiter = { { 6, 7 }, { 9, 7 } },
  warden = { { 5, 3 }, { 6, 3 }, { 9, 3 }, { 10, 3 } },
  youngster = { { 6, 7 }, { 9, 7 } },
}

local EYE_SIDE_MARKS = {
  agatha = { { 5, 7 } },
  balding_guy = { { 5, 7 } },
  beauty = { { 5, 7 }, { 5, 8 } },
  biker = { { 6, 7 } },
  blue = { { 5, 7 } },
  brunette_girl = { { 5, 7 }, { 5, 8 } },
  bruno = { { 5, 6 } },
  captain = { { 5, 7 } },
  channeler = { { 5, 7 } },
  clerk = { { 6, 6 } },
  cook = { { 5, 7 } },
  cooltrainer_f = { { 4, 7 } },
  cooltrainer_m = { { 5, 7 } },
  daisy = { { 5, 6 }, { 5, 7 } },
  fishing_guru = { { 5, 7 } },
  gambler = { { 5, 6 } },
  gameboy_kid = { { 5, 7 } },
  gentleman = { { 5, 7 } },
  giovanni = { { 5, 8 } },
  girl = { { 5, 6 }, { 5, 7 } },
  gramps = { { 5, 7 } },
  guard = { { 5, 7 } },
  hiker = { { 5, 5 } },
  koga = { { 5, 7 } },
  lance = { { 5, 7 } },
  link_receptionist = { { 5, 6 }, { 5, 7 } },
  little_boy = { { 5, 8 }, { 5, 9 } },
  little_girl = { { 5, 8 }, { 5, 9 } },
  lorelei = { { 5, 6 } },
  middle_aged_man = { { 5, 6 } },
  middle_aged_woman = { { 5, 6 }, { 5, 7 } },
  mom = { { 5, 7 } },
  mr_fuji = { { 4, 7 } },
  nurse = { { 5, 6 }, { 5, 7 } },
  oak = { { 5, 7 } },
  red = { { 5, 7 } },
  red_bike = { { 6, 6 } },
  rocker = { { 5, 7 } },
  rocket = { { 5, 7 } },
  safari_zone_worker = { { 5, 7 } },
  sailor = { { 5, 6 } },
  scientist = { { 5, 7 } },
  silph_president = { { 6, 4 } },
  silph_worker_f = { { 5, 7 } },
  silph_worker_m = { { 5, 7 } },
  super_nerd = { { 5, 7 } },
  swimmer = { { 5, 10 } },
  waiter = { { 5, 7 } },
  warden = { { 5, 3 } },
  youngster = { { 5, 7 } },
}

-- Generated from OPTIONS (above): a new option gets `type = "choice"` and
-- the `choices`/`default` fields derived from `levels`/`defaultIndex` for
-- free, with no need to duplicate the table here.
do
  local schema = {}
  for _, opt in ipairs(OPTIONS) do
    schema[#schema + 1] = {
      key = opt.key,
      type = "choice",
      label = opt.label,
      choices = opt.levels,
      default = opt.levels[opt.defaultIndex][2],
      help = opt.help,
      -- Carried into the schema so the documentation gate can see it. A held
      -- option is still DEFINED -- the host stores it, the code reads it, the
      -- tests exercise it -- and only the menu row is withheld. Without this
      -- field the gate would keep demanding a README row for something a player
      -- cannot reach.
      held = opt.held,
    }
  end
  mod.options:define(schema)
end

local SpriteBillboards, Voxel3D, ImageCache, TerrainAtlas, hostLib
local VoxelState, FirstPerson, VoxelScene
local originalMesh
local meshes, masks = {}, {}
local meshOrder = {}
-- Resolved state for every option, indexed by key (opt.key). Replaces the
-- nine dedicated variables from before (depthValue, sideColorValue, ...):
-- see the REFACTOR above OPTIONS.
local optionState = {}
local optionsRegistered = false
local meshBlink = setmetatable({}, { __mode = "k" })

-- REGION BANDS, for per-part secondary motion (roadmap item 9).
--
-- Weak keys, like meshBlink above and for the same reason: the mesh is owned
-- by the host's cache and this table must not be what keeps it alive.
--
-- Four bands and not more. A 16 pixel character gives each band four pixels of
-- height, which is already near the floor of what can lag visibly, and every
-- extra band is another draw call per character per frame on a scene that
-- draws twenty five of them.
local meshBands = setmetatable({}, { __mode = "k" })

-- MEASURED REGION METADATA FOR ONE SHEET, or nil (roadmap T2.1 slice 3).
--
-- Read from authored/sheets/<base>.lua, which ships with the mod and contains
-- bounds produced by tools/measure_regions.py. Nothing here is a pixel: the
-- authored layer's pixel count is zero and the provenance metric reports it as
-- zero. See docs/DISCLOSURE_DRAFT.md.
--
-- OBJECTS NEVER COME BACK FROM THIS FUNCTION. A sheet whose `kind` is not
-- `living` returns nil even if it carries measurements, so an item ball cannot
-- become segmented merely because somebody described it. That is the same rule
-- the schema enforces on the data and `STILL_OBJECTS` enforces on life, stated
-- a third time at the point of use, because this is where getting it wrong
-- would show.
--
-- Failure is cached too, negatively, so a missing sheet costs one lookup rather
-- than one per mesh build.
local authoredCache = {}
local function authoredRegions(base)
  if not base then return nil end
  local hit = authoredCache[base]
  if hit ~= nil then return hit or nil end
  local dados = nil
  local caminho = (mod.path or ".") .. "/authored/sheets/" .. base .. ".lua"
  -- TWO READERS, and the second one exists because of a measured defect.
  --
  -- LOVE resolves a relative path against the GAME directory. In the real game
  -- that is the repo root, so this path resolves and the mod works. In the
  -- render harness the game directory is `tools/render`, so it does NOT, and
  -- `authprobe=1` reported `sheet=MISSING`: AUTHORED REGIONS would have
  -- silently done nothing in the laboratory, in every card and in every judge
  -- pair, while working perfectly in the game. A feature the ruler cannot see
  -- is a feature nobody can judge.
  --
  -- Mounting the repo root in the harness was the first attempt and LOVE 11
  -- refuses it: `mount` only accepts a path inside the save directory or the
  -- source. So the fallback lives here, reading the same relative path through
  -- plain Lua io, which resolves whenever the process was started from the repo
  -- root -- which is how every tool in this project is documented to run.
  --
  -- It is a read of a file this mod SHIPS, never of the player's data.
  local chunk
  if love and love.filesystem and love.filesystem.getInfo
     and love.filesystem.getInfo(caminho) then
    local okLoad, c = pcall(love.filesystem.load, caminho)
    if okLoad then chunk = c end
  else
    local f = io.open(caminho, "r")
    if f then
      local texto = f:read("*a")
      f:close()
      local okLoad, c = pcall(loadstring or load, texto, "@" .. caminho)
      if okLoad then chunk = c end
    end
  end
  do
    if chunk then
      local okRun, folha = pcall(chunk)
      -- `living` and measured, or nothing. Both halves matter: the kind keeps
      -- objects out, and the measurements are the only part this path uses.
      if okRun and type(folha) == "table" and folha.kind == "living"
         and type(folha.measured) == "table" then
        dados = folha.measured
      end
    end
  end
  authoredCache[base] = dados or false
  return dados
end
local REGION_BANDS = 4

-- THE FX DEMO (roadmap T2.3), one table instead of a dozen chunk locals.
--
-- A capability demo and nothing more: it shows that this mod can own character
-- effects with a position, a lifetime and a sound, not just passive body
-- deformation. It is NOT Gen 1 authentic and the release note has to say so.
--
-- Isolated by construction. It reads the anchors and events T1.2 built, draws
-- through the same `Voxel3D.draw` the bodies use, and touches no save data, no
-- battle, no link play and no encounter. Turning it off returns the previous
-- frame exactly, which the gate checks by counting draw calls rather than by
-- looking.
--
-- ONE TABLE, because `main.lua` has a chunk-local budget and exceeding it is a
-- compile error for every player. Two families, both deliberately cheap:
-- FIREBALL travels and fades, BOLT flashes in place and dies fast.
local FX = {
  vivos = {},          -- active effects, oldest first
  nascidos = 0,        -- cumulative spawns, so a gate can match sounds to them
  sons = {},           -- one source per family, created on first use
  malhas = {},         -- one mesh per family, built once and reused
  MAX = 4,             -- a bound, so a runaway trigger cannot allocate forever
  FAMILIAS = {
    fireball = { vida = 0.55, passo = 26, tam = 2.6, sobe = 3,
                 som = "fireball" },
    bolt     = { vida = 0.18, passo = 0,  tam = 1.5, sobe = 9,
                 som = "bolt" },
  },
}

-- ANIMATION EVENTS (roadmap T1.2 slice 2), a one-frame mailbox.
--
-- Three edges, each read off state the draw wrap already computes: `footfall`
-- when the stride index advances, `blink_closed` / `blink_open` when the
-- blink's own window opens and shuts, `attention_noticed` / `attention_lost`
-- when the hysteresis flips. Nothing is invented for the occasion, which is
-- the whole constraint: an event nobody can measure is a promise.
--
-- WHY A MAILBOX AND NOT A CALLBACK. There is no consumer yet. T2.3's effects
-- will be the first, and the roadmap holds a public API until two exist, so
-- this is the smallest thing that can be measured and later thrown away: a
-- list, emptied every time it is read.
--
-- The list is cleared by the READER, not by the writer, because the host draws
-- each character twice per frame (the water reflection) and PART LAG issues one
-- draw per band. Clearing on write would mean the last band's silence erased
-- the first band's footstep.
local eventosPendentes = {}
local function eventoNovo(nome)
  eventosPendentes[#eventosPendentes + 1] = nome
end

-- Blink needs no state of its own here. `applyBlinkUv` already keeps the
-- previous value in `meta.closed`, because that early return is what stops the
-- UV swap from being rewritten every frame, so the transition was already
-- being detected and only needed naming. It is per SHEET rather than per
-- instance: the timing is a function of the clock and the sheet's name, so
-- every character on that sheet blinks together.

-- NAMED ANCHORS (roadmap T1.2), one entry per mesh, weak-keyed like the rest.
--
-- Four points on the body, derived from the vertices the builder actually
-- emitted rather than from a bounding box: head, feet, centre and hand. They
-- exist so an effect can come out of a HAND instead of out of the middle of a
-- character, and so anything that wants to attach to a part has a name for it
-- rather than a guess.
--
-- Each anchor also records which BAND it belongs to, because the bands are the
-- only parts this mesh can address (they are what PART LAG cuts along). That is
-- what lets an anchor arrive late with the part it names instead of tracking
-- the body as one rigid piece.
local meshAnchors = setmetatable({}, { __mode = "k" })
local blinkVertexWarned = false
-- v1.4.2, fine-tooth comb: `patch()` builds everything in locals and only
-- commits these upvalues (SpriteBillboards and the others, installedMesh,
-- `patched`) after ALL the risky writes onto the host's table have
-- succeeded. A host whose table refuses writes (__newindex frozen) makes
-- pcall(patch, host) hold the error with no module upvalue ever touched;
-- without this, `SpriteBillboards` would end up set on its own and STATUS
-- would read REPLACED (no other function "stole" the mesh; ours simply
-- never got installed) instead of reflecting that the patch did not
-- complete. `statusValue` and `registerOptionsRows` check `patched`, never
-- `SpriteBillboards ~= nil`.
local patched = false
-- v1.4.2, TwoTracks: the function THIS mod installed in
-- SpriteBillboards.mesh, kept so the STATUS row can detect whether another
-- mod replaced it afterward (REPLACED). warnChainedMesh only catches
-- whoever patches BEFORE us.
local installedMesh
-- v1.4.2, TwoTracks: there are five paths that silently return the
-- original card (DEPTH: OFF, first person, mask that fails, mesh that
-- fails, exception in the outermost wrapper) and they are indistinguishable
-- from each other and from "the mod never patched anything". These
-- variables hold the result of the LAST draw for the STATUS row to report;
-- they are just assignment, zero cost per frame.
local lastDrawResult = "ok"
-- Sliding window: drawWindow[i] holds the failure TYPE (mask_failed,
-- build_failed or exception) of the i-th most recent result (modulo
-- SHARED.DRAW_WINDOW_SIZE), or nil when it was a success. drawWindowFailures and
-- drawWindowKindCounts are kept incrementally (without scanning the array
-- on every STATUS read). v1.4.2, fine-tooth comb (item 2): the STATUS
-- error label uses the DOMINANT cause in the window (drawWindowKindCounts),
-- not the most recent one: seven mask failures and one isolated exception,
-- more recent, on a different sheet, has to show MASK ERROR, not DRAW
-- ERROR. The label is this row's whole product.
local drawWindow = {}
local drawWindowPos = 0
local drawWindowFailures = 0
local drawWindowKindCounts = {}
local warnedDrawCauses = {}
local warnedReplacedMesh = false
-- Reason for each cached mesh failure, so that a bad sheet that already
-- failed once keeps entering the window (and stays logworthy, even if only
-- once) on every following call, not just the first: meshes[key] == false
-- only records "it failed", not why.
local meshFailureReasons = {}
-- LIFE. `originalDraw` is the host's Voxel3D.draw; `installedDraw` is
-- ours, for the LIFE row to detect who got replaced after us (same logic
-- as installedMesh). `drawPatched` only becomes true after the write has
-- succeeded, and only when the capability probe approved the channel: a
-- host without a usable Voxel3D.draw loses the animation and KEEPS the
-- rest of the mod working.
local originalDraw, installedDraw, drawPatched = nil, nil, false
-- Meshes THIS mod built. Weak key: when the LRU drops the mesh, the entry
-- disappears on its own. It is the only exact discriminator of "this is
-- one of our characters" inside the draw wrap, where terrain, grass,
-- shadow and the pokedex all pass through the same function.
local ourMeshes = setmetatable({}, { __mode = "k" })

-- Generic: operate on any entry of OPTIONS (opt.levels is an array of
-- { LABEL, value } pairs, opt.defaultIndex the default position in that
-- array). Replace each option's dedicated indexOf/readX pair.
local function optionIndexOf(opt, value)
  for i, level in ipairs(opt.levels) do
    if level[2] == value then return i end
  end
  return opt.defaultIndex
end

local function readOption(opt)
  local ok, value = pcall(mod.options.get, mod.options, opt.key)
  if ok then return opt.levels[optionIndexOf(opt, value)][2] end
  return opt.levels[opt.defaultIndex][2]
end

local function releaseMesh(mesh)
  if mesh and mesh ~= false and mesh.release then pcall(mesh.release, mesh) end
end

local function clearMeshCache()
  for _, mesh in pairs(meshes) do releaseMesh(mesh) end
  meshes, meshOrder = {}, {}
  meshFailureReasons = {}
end

local function clearCache()
  clearMeshCache()
  masks = {}
end

-- Generic: replaces the nine dedicated setX functions. `opt.clears`
-- decides what to clear when the value changes (see the field comment in
-- OPTIONS, above): "full" only for DEPTH (clearCache, which also drops
-- `masks`), "mesh" for most of them (clearMeshCache, releases the old
-- meshes right away instead of waiting for the LRU to recycle them, the
-- defect Colonel_Aureliano reported in v1.4.0 when the option changed in
-- the menu without changing anything on screen), and neither of the two
-- for BLINK.
local function setOption(opt, value)
  local nextValue = opt.levels[optionIndexOf(opt, value)][2]
  if optionState[opt.key] ~= nextValue then
    if opt.clears == "full" then
      clearCache()
    elseif opt.clears == "mesh" then
      clearMeshCache()
    end
  end
  optionState[opt.key] = nextValue
  return nextValue
end

for _, opt in ipairs(OPTIONS) do
  setOption(opt, readOption(opt))
end
Assets.register(clearCache)

local function writeOption(game, key, value)
  local id = mod.id
  local opts = game and game.save and game.save.options
  if opts then
    opts.modOptions = opts.modOptions or {}
    opts.modOptions[id] = opts.modOptions[id] or {}
    opts.modOptions[id][key] = value
  end
  local loader = game and game.mods
  if loader then
    loader.modOptions = loader.modOptions or {}
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id][key] = value
  end
  if loader and loader.events then
    loader.events:emit("mod.options_changed",
      { mod = id, key = key, value = value })
  end
end

-- Generic: replaces the nine dedicated rowX functions. Same shape each one
-- had (fixed id/label, value() reads the current level's label, step()
-- advances one level cyclically and goes through the usual
-- setOption/writeOption).
-- WHETHER AN OPTION CAN DO ANYTHING RIGHT NOW, and why not when it cannot.
--
-- Some of these options only mean something next to another one: the four SLAB
-- shaping rows do nothing under CARVED, and PART LAG has nothing to delay
-- unless something is moving. Until now they sat in the list looking
-- adjustable, changed their value when pressed, and had no effect -- which is
-- the menu telling a lie, and a bad one, because the person testing concludes
-- the FEATURE is broken rather than the combination being empty.
--
-- Kim asked for this after the submenu became the bench this mod is tested on.
-- The requirement is DATA on the option, not a branch here, so adding one is a
-- line next to the option it belongs to instead of an edit in two places.
-- IS THE HOST'S OWN WIREFRAME ON, the one key 5 toggles
-- (DramaticShapeVoxelMod/main.lua:553).
--
-- V-GRID CHARS RIDES IT rather than competing with it, which is what Kim asked
-- for: one key, one answer, the whole scene agreeing. Independent switches would
-- have let the characters wear seams in a world that has none, which reads as a
-- rendering fault rather than a choice.
--
-- It is also what the renderer can actually deliver. The wireframe is a separate
-- compiled shader variant, chosen once per pass from the host's own grid flag;
-- with the grid off the plain shader is bound and it has no seam uniform at all,
-- so asking for seams would silently do nothing. Better to say so in the row
-- than to offer a switch that works only sometimes and never explains why.
local function gradeDoMundo()
  local ok, VG = pcall(function() return hostLib and hostLib.require("VoxelGrid") end)
  if not (ok and type(VG) == "table" and type(VG.enabled) == "function") then
    return false
  end
  local ok2, ligada = pcall(VG.enabled)
  return ok2 and ligada and true or false
end

local function requisitoOk(opt)
  local req = opt.requires
  if not req then return true end
  if req.key then
    local atual = optionState[req.key] or readOption(OPTION_BY_KEY[req.key])
    if tostring(atual) ~= tostring(req.value) then return false, req.why end
  end
  -- A PREDICATE, for a requirement that is not another option's value. The
  -- world grid is the first: it belongs to the host and is toggled with key 5,
  -- so there is no key of ours to compare against.
  if req.check then
    local ok, resposta = pcall(req.check)
    if not (ok and resposta) then return false, req.why end
  end
  if req.anyOn then
    for _, k in ipairs(req.anyOn) do
      local atual = optionState[k] or readOption(OPTION_BY_KEY[k])
      if atual and tostring(atual) ~= "off" then return true end
    end
    return false, req.why
  end
  return true
end

local function makeOptionRow(opt)
  return {
    id = mod.id .. ":" .. opt.key,
    label = opt.label,
    -- Modern UI greys a row with `enabled = false` and skips it with the
    -- cursor; the native renderer ignores the field, which is why `step` also
    -- refuses below rather than trusting the presentation to prevent it.
    enabled = function() return (requisitoOk(opt)) end,
    value = function()
      local ok, porque = requisitoOk(opt)
      -- THE REASON GOES WHERE THE VALUE WAS, so it is readable on BOTH
      -- renderers and on a machine with no Modern UI to grey anything. A greyed
      -- row says "not now"; this says what to change.
      if not ok then return porque or "UNAVAILABLE" end
      local current = optionState[opt.key] or readOption(opt)
      return opt.levels[optionIndexOf(opt, current)][1]
    end,
    step = function(game, dir)
      if not requisitoOk(opt) then return false end
      local current = optionState[opt.key] or readOption(opt)
      local i = optionIndexOf(opt, current)
      i = ((i + (dir or 1) - 1) % #opt.levels) + 1
      local value = setOption(opt, opt.levels[i][2])
      writeOption(game, opt.key, value)
      return true
    end,
  }
end

-- v1.4.2: receives the table as a parameter, not through the module
-- upvalue, because patch() can only commit that upvalue AFTER all the
-- risky writes (main.lua, patch()) have succeeded; until then the
-- SpriteBillboards upvalue does not exist yet.
local function warnChainedMesh(spriteBillboards)
  if spriteBillboards.__voxelCharactersOriginal then return end
  if spriteBillboards.shadowQuad
      and spriteBillboards.mesh ~= spriteBillboards.shadowQuad then
    mod.log:warn("SpriteBillboards.mesh was already patched; chaining over %s",
      tostring(spriteBillboards.mesh))
  end
end

local function intField(def, ...)
  for i = 1, select("#", ...) do
    local v = tonumber(def and def[select(i, ...)])
    if v and v > 0 then return math.floor(v) end
  end
end

local function spriteLayout(def, sheetW, sheetH)
  local frames = intField(def, "frames")
  if not (frames and sheetW and sheetH and sheetW > 0 and sheetH > 0) then
    return nil
  end

  local frameW = intField(def, "frameW", "frameWidth", "cellW", "cellWidth",
                          "spriteW", "spriteWidth")
  local frameH = intField(def, "frameH", "frameHeight", "cellH", "cellHeight",
                          "spriteH", "spriteHeight")
  local columns = intField(def, "columns", "cols", "framesPerRow")

  if frameW or columns then
    frameW = frameW or (columns and math.floor(sheetW / columns))
    if not (frameW and frameW > 0 and frameW <= sheetW) then return nil end
    columns = columns or math.max(1, math.floor(sheetW / frameW))
    if columns < 1 then return nil end
    local rows = math.ceil(frames / columns)
    frameH = frameH or math.floor(sheetH / rows)
    if not (frameH and frameH > 0 and frameH <= sheetH) then return nil end
    if (columns - 1) * frameW + frameW > sheetW then return nil end
    if (rows - 1) * frameH + frameH > sheetH then return nil end
    return { frames = frames, w = frameW, h = frameH, columns = columns }
  end

  -- Without cell metadata, there are only two sheet layouts derivable
  -- without guessing: a vertical column like the vanilla engine, or a
  -- horizontal row. Sheets with padding or an ambiguous grid degrade to the
  -- original card.
  local vertical = (sheetH % frames == 0)
    and { frames = frames, w = sheetW, h = sheetH / frames, columns = 1 }
  local horizontal = (sheetW % frames == 0)
    and { frames = frames, w = sheetW / frames, h = sheetH, columns = frames }
  if frames == 1 and vertical then return vertical end
  if vertical and not horizontal then return vertical end
  if horizontal and not vertical then return horizontal end
  if vertical and horizontal then
    local vScore = math.abs(vertical.w - vertical.h)
    local hScore = math.abs(horizontal.w - horizontal.h)
    if vScore < hScore then return vertical end
    if hScore < vScore then return horizontal end
  end
  return nil
end

local function frameOrigin(layout, frame)
  local col = frame % layout.columns
  local row = math.floor(frame / layout.columns)
  local w, h = layout.w or layout.cellW, layout.h or layout.cellH
  return col * w, row * h
end

local function pixelAt(data, x, y)
  local ok, r, g, b, a = pcall(data.getPixel, data, x, y)
  if not ok then return nil end
  return r or 0, g or 0, b or 0, a or 0
end

local function luminance(r, g, b)
  return (r or 0) * 0.2126 + (g or 0) * 0.7152 + (b or 0) * 0.0722
end

-- THE HD SHEET FOR ONE CHARACTER, or nil (roadmap T3.0 experiment).
--
-- Read from `hd/<base>.png` inside the mod, which is why this is the first
-- option that draws pixels the player's ROM does not contain. Only sheets with a
-- file there change; every other character keeps coming from the ROM.
--
-- Cached both ways: a hit and a miss. A miss has to be cached too, or every
-- mesh build for every sheet without an HD file costs a filesystem probe.
local hdCache = {}
local function hdDataFor(base)
  if not base then return nil end
  local hit = hdCache[base]
  if hit ~= nil then return hit or nil end
  local dados = nil
  local caminho = (mod.path or ".") .. "/hd/" .. base .. ".png"
  if love and love.filesystem and love.filesystem.getInfo
     and love.filesystem.getInfo(caminho) then
    local ok, d = pcall(love.image.newImageData, caminho)
    if ok then dados = d end
  else
    -- Same fallback as the authored layer, and for the same measured reason:
    -- the render harness's game directory is tools/render, so a repo-relative
    -- path does not resolve there even though it does in the game.
    local f = io.open(caminho, "rb")
    if f then
      local bytes = f:read("*a"); f:close()
      local ok, d = pcall(function()
        return love.image.newImageData(
          love.filesystem.newFileData(bytes, base .. ".png"))
      end)
      if ok then dados = d end
    end
  end
  hdCache[base] = dados or false
  return dados
end

local hdTexCache = {}
-- The coloured HD texture the forSprite wrap built most recently for a sheet,
-- by base name. The draw-time swap reads this and never builds: at draw time
-- the palette the character stands under is not in reach, and guessing one
-- would put a character in the wrong world's colours.
local hdPronta = {}
-- THE PALETTE HAS TO BE BAKED IN, and finding that out cost a day.
--
-- In voxel mode a character is NOT coloured by the screen-space shader the flat
-- game uses -- the 3D canvas never runs through it. The host says so itself
-- (VoxelScene.lua:347): "the model's texture gets the palette baked in instead
-- (TerrainAtlas.forSprite)". So the texture the host hands to the draw is
-- already coloured, pixel by pixel, out of the world palette the character
-- stands under.
--
-- The first version of this loaded `hd/<base>.png` and handed it over RAW. The
-- sheet is three greys, like every sheet in the game, and the colour lives
-- nowhere in the file -- so the character rendered in GREY while every NPC
-- beside it stayed in colour. It read like the extra resolution had broken
-- something deep, and it had not: the swap was throwing the palette away.
--
-- `colors` is nil under RED++/trueColor, where a different bake supplies the
-- colour and there is nothing here to reproduce; the caller keeps the host's
-- own texture in that case rather than showing a grey one.
local function hdTextureFor(base, colors, chave)
  if not base then return nil end
  local k = base .. "#" .. tostring(chave or "cru")
  local hit = hdTexCache[k]
  if hit ~= nil then return hit or nil end
  local tex = nil
  local dados = hdDataFor(base)
  if dados and love.graphics then
    local ok, t = pcall(function()
      local fonte = dados
      if colors then
        -- Same function the host calls, so our sheet lands on exactly the
        -- colours the ROM sheet beside it does. Copying the thresholds by hand
        -- would drift the day the engine changes them.
        local TR = require("src.render.TileRenderer")
        local w, h = dados:getDimensions()
        local saida = love.image.newImageData(w, h)
        for y = 0, h - 1 do
          for x = 0, w - 1 do
            local r, g, b, a = dados:getPixel(x, y)
            r, g, b, a = TR.recolorSample(r, g, b, a, colors)
            saida:setPixel(x, y, r, g, b, a)
          end
        end
        fonte = saida
      end
      return love.graphics.newImage(fonte)
    end)
    if ok and t then
      -- NEAREST, always. The whole point is hard pixels; linear filtering would
      -- blur the tones back into the gradient the sheet was quantised out of.
      pcall(t.setFilter, t, "nearest", "nearest")
      tex = t
    end
  end
  hdTexCache[k] = tex or false
  return tex
end

local function hdTexturePronta(base)
  return base and hdPronta[base] or nil
end

local function maskFor(def)
  if not (def and def.image) then return nil end
  -- THE HD SHEET REPLACES THE ROM'S, when the option is on and a file exists.
  -- Everything downstream is unchanged: spriteLayout already derives the cell
  -- from the sheet size and the frame count, with no 16 hardcoded anywhere, so a
  -- 64 px cell needs no new code path -- only the scale back to one tile.
  -- The base name is taken apart here rather than through `spriteBaseName`,
  -- which is defined three hundred lines further down: reading it from up here
  -- got nil, the call threw, and `maskFor` runs inside a pcall -- so the mesh
  -- silently fell back and a test failed four hundred lines away with a nil
  -- vertex list. An upvalue that does not exist yet fails quietly, which is the
  -- worst way for it to fail.
  local base = tostring(def.image):match("([^/\\]+)%.%w+$")
    or tostring(def.image):match("([^/\\]+)$")
  local hd = (optionState.hd_sprite == "on") and hdDataFor(base) or nil
  local data = hd or ImageCache.get(def.image)
  if not data then return nil end
  local sheetW, sheetH = data:getDimensions()
  local layout = spriteLayout(def, sheetW, sheetH)
  if not layout then return nil end
  local frames = layout.frames
  -- THE HD FLAG IS IN THE KEY. Without it, toggling the option would keep
  -- returning the mask built from the other sheet: same image name, same frame
  -- count, and the dimensions do change here -- but relying on that would be
  -- luck, and the mesh cache below needs the flag anyway.
  local key = table.concat({
    def.image, sheetW, sheetH, frames, layout.w, layout.h, layout.columns,
    hd and "hd" or "rom",
  }, "#")
  if masks[key] ~= nil then return masks[key] or nil end

  local mask = {}
  local outlineLuma
  local minX, maxX, minY, maxY = layout.w, -1, layout.h, -1
  for f = 0, frames - 1 do
    local fx, fy = frameOrigin(layout, f)
    if fx + layout.w <= sheetW and fy + layout.h <= sheetH then
      for ly = 0, layout.h - 1 do
        for lx = 0, layout.w - 1 do
          local r, g, b, a = pixelAt(data, fx + lx, fy + ly)
          if r and (a or 0) >= 0.5 then
            mask[ly * layout.w + lx] = true
            local luma = luminance(r, g, b)
            if not outlineLuma or luma < outlineLuma then outlineLuma = luma end
            if lx < minX then minX = lx end
            if lx > maxX then maxX = lx end
            if ly < minY then minY = ly end
            if ly > maxY then maxY = ly end
          end
        end
      end
    end
  end

  if maxX < minX or maxY < minY then
    masks[key] = false
    return nil
  end

  local out = {
    mask = mask, minX = minX, maxX = maxX, minY = minY, maxY = maxY,
    sheetW = sheetW, sheetH = sheetH, frames = frames,
    cellW = layout.w, cellH = layout.h, columns = layout.columns,
    hd = hd and true or false,
    data = data, outlineLuma = outlineLuma,
  }
  masks[key] = out
  return out
end

-- The real lean is VoxelScene's `leanAngle()`, which gives precedence to
-- `VoxelScene.spriteLean` over `VoxelState.angle` (VoxelScene.lua:283-285).
-- Today only VR sets this field, to 75 degrees (VR.lua:281); reading only
-- `angle` would leave the body tilted by the difference inside the
-- headset.
local function leanCorrection()
  local a = 0
  local pinned
  if VoxelScene then
    local ok, value = pcall(function() return VoxelScene.spriteLean end)
    if ok then pinned = tonumber(value) end
  end
  if pinned then
    a = pinned
  elseif VoxelState then
    local ok, value = pcall(function() return VoxelState.angle end)
    if ok then a = tonumber(value) or 0 end
  end
  local b = 0
  if FirstPerson and FirstPerson.cardBlend then
    local ok, value = pcall(FirstPerson.cardBlend)
    if ok then b = math.max(0, math.min(1, tonumber(value) or 0)) end
  end
  return (math.pi / 2 - a) * (1 - b)
end

-- DECISION: the rung tween lasts 0.25 s; at 60 fps it generated around 15
-- distinct pitches, each with its own key. The 1 degree bucket reduces the
-- transition to 2 or 3 visible buckets with no perceptible displacement.
-- The cache stays deliberately small: 8 types x 6 frames already take up
-- 48 entries at a single pitch, and a tween crossing 2 or 3 buckets can ask
-- for 96 to 144 meshes. The LRU prevents unbounded growth, but it can
-- recycle meshes during tweens with many different NPCs on screen.
local function quantizeCorrection(angle)
  -- Moved from chunk scope (roadmap item 0: main chunk locals). Duplicated
  -- in pitchKey below rather than shared: this is `math.pi / 180`, a unit
  -- conversion that cannot drift, not a tunable that needs one source of
  -- truth.
  local PITCH_BUCKET = math.pi / 180
  return math.floor(((angle or 0) / PITCH_BUCKET) + 0.5) * PITCH_BUCKET
end

local function pitchKey(angle)
  local PITCH_BUCKET = math.pi / 180
  return tostring(math.floor(((angle or 0) / PITCH_BUCKET) + 0.5))
end

local function touchMeshKey(key)
  for i = #meshOrder, 1, -1 do
    if meshOrder[i] == key then
      table.remove(meshOrder, i)
      break
    end
  end
  meshOrder[#meshOrder + 1] = key
end

local function rememberMesh(key, mesh)
  -- Moved from chunk scope (roadmap item 0: main chunk locals): only read
  -- here.
  local MAX_MESHES = 64
  meshes[key] = mesh
  touchMeshKey(key)
  while #meshOrder > MAX_MESHES do
    local oldKey = table.remove(meshOrder, 1)
    local old = meshes[oldKey]
    meshes[oldKey] = nil
    releaseMesh(old)
  end
end

local function frameTexel(m, frame, lx, ly)
  if lx < 0 or lx >= m.cellW or ly < 0 or ly >= m.cellH then return false end
  frame = tonumber(frame) or 0
  if frame < 0 or frame >= m.frames then return false end
  local fx, fy = frameOrigin(m, frame)
  if fx + m.cellW > m.sheetW or fy + m.cellH > m.sheetH then return false end
  local r, g, b, a = pixelAt(m.data, fx + lx, fy + ly)
  if not r or (a or 0) < 0.5 then return false end
  local outline = m.outlineLuma
    and math.abs(luminance(r, g, b) - m.outlineLuma) <= SHARED.LUMA_EPSILON
  return true, outline
end

local function roleForFrame(frame, frames)
  frame = tonumber(frame) or 0
  if frame < 0 or frame >= frames then frame = 0 end
  if frame > 5 then frame = frame % 3 end
  return frame % 3
end

local function referenceFramesForRole(frame, frames, role)
  role = role or roleForFrame(frame, frames)
  if frames >= 6 then return role, role + 3 end
  if frames >= 3 then return role, nil end
  return tonumber(frame) or 0, nil
end

-- HOW MUCH BIGGER THIS SHEET IS THAN A TILE, or nil when it is not bigger.
--
-- `escalaParaTile` divides every vertex by this same factor to bring an
-- enlarged sheet back onto one tile, so every constant expressed in SHEET
-- PIXELS has to be multiplied by it or it silently does 1/k of its job. Six
-- places need the answer and each of them used to spell the predicate out
-- again; the day one of them was written slightly differently, the difference
-- would have been invisible, because a constant that is a quarter too small
-- still draws a picture.
--
-- The predicate has two halves and both are load-bearing. `m.hd` is what makes
-- the scaling OPT-IN: the suite legitimately builds 2x4 test sheets, and
-- inferring the scale from cell height alone multiplied those by eight (see
-- escalaParaTile). `cellH ~= 16` is what keeps an HD sheet that happens to be
-- tile sized out of a pointless multiply by one.
local function hdCellScale(m)
  if not (m and m.hd and m.cellH and m.cellH ~= 16) then return nil end
  return m.cellH / 16
end

local function bodyTexelInFrame(m, frameIndex, lx, ly, dx, dy, sideColor)
  -- Moved from chunk scope (roadmap item 0: main chunk locals): only read
  -- here. DECISION: four pixels covers the thick outlines of Gen 1 sprites
  -- without letting a search on custom art cross over into another part of
  -- the body.
  --
  -- FOUR SHEET PIXELS, so a sheet with a bigger cell needs proportionally more.
  -- This is what made the top of Red's head flicker black while walking with HD
  -- SPRITE on -- Kim's report, and the same symptom AngelusRole reported in
  -- v1.4.2 for the ordinary sheets. The cause is different and the fix there
  -- did not cover it: on a 64 px cell the outline is four pixels thick too, so
  -- a four step search never reaches body colour, gives up, and the top face
  -- takes the OUTLINE's black. It flickers rather than staying black because
  -- the walking pose sits one row lower, so some rows do find body and some do
  -- not.
  local BODY_SEARCH_LIMIT = 4
  local hdK = hdCellScale(m)
  if hdK then
    BODY_SEARCH_LIMIT = math.floor(4 * hdK + 0.5)
  end
  if sideColor ~= SHARED.DEFAULT_SIDE_COLOR then return lx, ly, true end
  local opaque, outline = frameTexel(m, frameIndex, lx, ly)
  if not (opaque and outline) then return lx, ly, opaque and not outline end
  for step = 1, BODY_SEARCH_LIMIT do
    local bx, by = lx + dx * step, ly + dy * step
    local bodyOpaque, bodyOutline = frameTexel(m, frameIndex, bx, by)
    if bodyOpaque and not bodyOutline then return bx, by, true end
  end
  return lx, ly, false
end

-- FIX for the top-flickering-while-walking defect (SLAB, v1.4.2): the
-- walking pose is the standing pose shifted down one row, a deliberate art
-- step (AngelusRole: "when a character's head is set to use the body
-- color, the top of the head flickers while walking"). verticalUv and
-- sideUv were reading the reference at the SAME coordinate (lx, ly) as the
-- current frame, so the top of the head in frame 3 resolved to frame 0's
-- texel one row lower, a different stripe of the hat. poseOffset measures,
-- by opaque mask overlap, how much the art shifts between two frames, so
-- the reference lookup fetches the physically corresponding texel, not
-- just the same index.
--
-- DECISION: deterministic tie-breaking is mandatory. Smaller |dx| + |dy|
-- first, then smaller dy, then smaller dx. Without an explicit total
-- order, symmetric sheets genuinely tie (test "poseOffset breaks ties
-- deterministically"), and the result would end up depending on the scan
-- order instead of the sheet's content; the cached mesh would change from
-- run to run, the worst possible bug here. `better` only swaps the best
-- candidate when it is strictly better by these rules, so the result does
-- not depend on how the dx/dy loops are walked.
--
-- DECISION v1.4.2, fine-tooth comb (item 3): precomputes `fromFrame`'s
-- opacity into a local array (flat, indexed by ly*cellW+lx) before the
-- candidate loop. frameTexel(m, fromFrame, lx, ly) does not depend on dx
-- or dy, but the scan was recomputing it for each of up to 35 candidates
-- (7 values of dy times 5 of dx); this cuts that half of the cost of the
-- first scan of each pair, without changing any result (same candidates,
-- same tie-break). It is the "trading flicker for stutter" risk the
-- original spec named, avoidable for free.
local function poseOffsetScan(m, fromFrame, toFrame)
  -- Moved from chunk scope (roadmap item 0: main chunk locals): only read
  -- here. DECISION v1.4.2: the poseOffset scan window. The step measured on
  -- red.png is one row; dy goes up to 3 for custom art sheets with a wider
  -- step, dx to 2 because there is no report of horizontal displacement and
  -- a bigger window would only cost O(cell^2) per extra candidate for no
  -- reason.
  local POSE_OFFSET_DX_RANGE = 2
  local POSE_OFFSET_DY_RANGE = 3
  local cellW, cellH = m.cellW, m.cellH
  -- THE WINDOW IS IN SHEET PIXELS, and on an enlarged sheet the step it is
  -- looking for is enlarged too. red.png steps ONE row between standing and
  -- walking; the same step on a 64 px sheet is FOUR, outside a window that
  -- reaches 3. The scan then returns the best match it could see instead of
  -- the true offset, and it does so silently -- there is no "not found".
  --
  -- Both of Kim's HD reports come out of that one wrong number. The eye marks
  -- are carried to the walking pose by this offset, so they land off the face
  -- and BLINK paints two black blocks beside the head -- "uns dois quadrados
  -- acima do personagem", only while walking, only sometimes. And the top and
  -- side faces fetch their stable colour through the same offset, so they read
  -- the wrong texel and come back as outline black -- the dots on the head that
  -- survived scaling BODY_SEARCH_LIMIT.
  --
  -- COST, because it is not free: the scan is O(cellW * cellH * window), so
  -- this is 425 candidates over 4096 pixels rather than 35 over 256. It is
  -- memoised per canonical frame pair per sheet (see poseOffset), so it happens
  -- once, not once per face.
  local hdK = hdCellScale(m)
  if hdK then
    POSE_OFFSET_DX_RANGE = math.floor(POSE_OFFSET_DX_RANGE * hdK + 0.5)
    POSE_OFFSET_DY_RANGE = math.floor(POSE_OFFSET_DY_RANGE * hdK + 0.5)
  end
  local fromOpaque = {}
  for ly = 0, cellH - 1 do
    local row = ly * cellW
    for lx = 0, cellW - 1 do
      fromOpaque[row + lx] = frameTexel(m, fromFrame, lx, ly)
    end
  end

  local bestDx, bestDy, bestScore = 0, 0, -1
  for dy = -POSE_OFFSET_DY_RANGE, POSE_OFFSET_DY_RANGE do
    for dx = -POSE_OFFSET_DX_RANGE, POSE_OFFSET_DX_RANGE do
      local score = 0
      for ly = 0, cellH - 1 do
        local row = ly * cellW
        for lx = 0, cellW - 1 do
          if fromOpaque[row + lx]
              and frameTexel(m, toFrame, lx + dx, ly + dy) then
            score = score + 1
          end
        end
      end
      local better = score > bestScore
      if not better and score == bestScore then
        local curTie = math.abs(dx) + math.abs(dy)
        local bestTie = math.abs(bestDx) + math.abs(bestDy)
        if curTie < bestTie then
          better = true
        elseif curTie == bestTie then
          if dy < bestDy then
            better = true
          elseif dy == bestDy and dx < bestDx then
            better = true
          end
        end
      end
      if better then
        bestDx, bestDy, bestScore = dx, dy, score
      end
    end
  end
  return bestDx, bestDy
end

local function poseOffset(m, fromFrame, toFrame)
  fromFrame = tonumber(fromFrame) or 0
  toFrame = tonumber(toFrame) or 0
  if fromFrame == toFrame then return 0, 0 end
  -- CARVED DECISION (v1.4.2): only compensates between frames of the SAME
  -- role (the same view: front, top or profile). CARVED reuses the front
  -- texture (role 0) to color the top at any rendered orientation and the
  -- profile texture (role 2) to color the side, so a wrong caller could ask
  -- for the overlap between the front mask and the profile one. That does
  -- not measure step displacement, it measures silhouette difference (the
  -- character in profile is narrower than from the front by nature of the
  -- art), and it would return a number that looks like a displacement but
  -- is actually noise. Every correct caller already compares pose.front
  -- with pose.front or pose.side with pose.side, so this branch should
  -- never fire in correct use; it stays as belt and suspenders against the
  -- next place that calls poseOffset with frames of different roles.
  if roleForFrame(fromFrame, m.frames) ~= roleForFrame(toFrame, m.frames) then
    return 0, 0
  end

  -- DECISION v1.4.2, fine-tooth comb (item 2): canonicalizes the pair
  -- before scanning, always from the smaller frame index to the larger,
  -- and negates when the request is in the opposite direction. A genuine
  -- score tie between +dy and -dy makes the "smaller dy" rule pick -1 in
  -- BOTH directions if each call scanned toward its own side
  -- (poseOffset(A,B) and poseOffset(B,A) are two independent scans, each
  -- applying the SAME "prefer negative dy" rule without knowing about the
  -- other), breaking poseOffset(A,B) == -poseOffset(B,A). This matters for
  -- real: eye compensation asks for poseOffset(refFrame, frame) and the
  -- geometry asks for poseOffset(frame, frameIndex), opposite directions
  -- of the same pair. By canonicalizing, there is only ONE scan per pair
  -- (memoized by lo:hi), never two independent ones, so the symmetry holds
  -- by construction, not by luck of the tie-break.
  local lo, hi, negate = fromFrame, toFrame, false
  if lo > hi then
    lo, hi, negate = hi, lo, true
  end

  m.poseOffsets = m.poseOffsets or {}
  local key = lo .. ":" .. hi
  local cached = m.poseOffsets[key]
  if not cached then
    if lo < 0 or lo >= m.frames or hi < 0 or hi >= m.frames then
      cached = { 0, 0 }
    else
      -- DECISION: the scan is O(cellW*cellH*window) and runs inside mesh
      -- construction; memoizing on `m` (the same object that already
      -- caches the mask) guarantees at most one scan per canonical pair
      -- per sheet, not one per face.
      local dx, dy = poseOffsetScan(m, lo, hi)
      cached = { dx, dy }
    end
    m.poseOffsets[key] = cached
  end
  if negate then
    return -cached[1], -cached[2]
  end
  return cached[1], cached[2]
end

local function spriteBaseName(path)
  if type(path) ~= "string" then return nil end
  local name = path:match("([^/\\]+)$") or path
  return (name:gsub("%.[^%.]*$", ""))
end

local function hashName(name)
  local h = 5381
  name = tostring(name or "")
  for i = 1, #name do
    h = (h * 33 + name:byte(i)) % 4294967296
  end
  return h
end

local function blinkTiming(baseName)
  local h = hashName(baseName)
  local period = 3 + (h % 3000) / 1000
  local phase = (math.floor(h / 3000) % 3000) / 1000
  return period, phase
end

local function blinkClosedForBase(baseName)
  -- Moved from chunk scope (roadmap item 0: main chunk locals): only read
  -- here.
  local BLINK_CLOSED_SECONDS = 0.12
  if not (love and love.timer and love.timer.getTime) then return false end
  local ok, now = pcall(love.timer.getTime)
  if not ok then return false end
  local period, phase = blinkTiming(baseName)
  return ((tonumber(now) or 0) + phase) % period < BLINK_CLOSED_SECONDS
end

local function blinkBodyTexel(m, frameIndex, lx, ly)
  local dirs = {
    { 0, 1 }, { -1, 0 }, { 1, 0 }, { 0, -1 },
  }
  for _, dir in ipairs(dirs) do
    local bx, by, found = bodyTexelInFrame(m, frameIndex, lx, ly, dir[1],
      dir[2], SHARED.DEFAULT_SIDE_COLOR)
    if found and (bx ~= lx or by ~= ly) then return bx, by end
  end
end

local function eyeTexelLuma(m, frameIndex, lx, ly)
  if lx < 0 or lx >= m.cellW or ly < 0 or ly >= m.cellH then return nil end
  local fx, fy = frameOrigin(m, frameIndex)
  local r, g, b, a = pixelAt(m.data, fx + lx, fy + ly)
  if not r or (a or 0) < 0.5 then return nil end
  return luminance(r, g, b)
end

-- FIX for the "only blinks when standing" defect (v1.4.2): the eye mark is
-- always the reference frame's (standing); for the walking pose, the
-- coordinate is the mark plus poseOffset, but it only counts if the tone
-- actually transfers. Without this, v1.4.1 closed the "eye" over skin when
-- frame 3 shifted down one row (CHANGELOG v1.4.1: "the face shifts
-- vertically on many sheets"), which is exactly the displacement
-- poseOffset measures.
local function eyeMarkTransfers(m, refFrame, rx, ry, walkFrame, wx, wy)
  local refLuma = eyeTexelLuma(m, refFrame, rx, ry)
  local walkLuma = eyeTexelLuma(m, walkFrame, wx, wy)
  if not (refLuma and walkLuma) then return false end
  return math.abs(refLuma - walkLuma) <= SHARED.LUMA_EPSILON
end

-- THE EYE FOUND BY MEASUREMENT, for the sheets no hand table knows.
--
-- Kim's report: this mod works with Wilds of Kanto, but the blinking does not.
-- The cause is not a bug, it is the shape of EYE_MARKS: it is keyed by SHEET
-- BASE NAME and it holds 56 front entries, all of them ROM characters. Wilds of
-- Kanto ships 1298 sheets named `001-normal` through `649-shiny`, so every wild
-- Pokemon falls through the lookup and stands there with its eyes open forever.
-- A bigger hand table would fix those 1298 and nothing after them.
--
-- WHAT AN EYE IS, in the only terms this mesh builder already has:
--   * a 4-connected island of the sheet's DARKEST tone -- that is exactly what
--     `frameTexel` already returns as `outline`, because `m.outlineLuma` is the
--     MINIMUM luma over the whole sheet;
--   * small: at most MAX_TEXELS texels, at most MAX_W wide and MAX_H tall;
--   * INTERIOR: every texel it touches is opaque and lighter. That single
--     condition is what separates an eye from the silhouette outline, and it is
--     also precisely the condition `blinkBodyTexel` needs to find a skin texel
--     to copy the closed UV from. A blob that passes here can always be closed;
--   * in the upper BAND of the sheet's opaque rows, so a belt buckle or the gap
--     between two feet cannot pass;
--   * MIRRORED: an identical island across the cell's own centre line, which is
--     the axis the host mirrors sprites about (VoxelScene resolves the frame and
--     applies the mirror on the matrix), separated by MIN_GAP..MAX_GAP columns
--     of skin. One eye alone is not a face.
--
-- AND THEN IT REFUSES unless exactly ONE such pair exists on the frame. That
-- last rule is the whole safety margin, and it is the one that carries the
-- measurement: over the 67 ROM sheets, this returns marks for 30 of the 56 that
-- have a hand entry -- 19 of them the same set the hand measured, 11 the same
-- eyes with one more or one fewer texel -- refuses the other 26, and never once
-- invents eyes: all 11 sheets with no entry (poke_ball, boulder, clipboard,
-- fossil, old_amber, paper, pokedex, snorlax, gambler_asleep, bike_shop_clerk,
-- monster) are refused. Zero false positives is not a target here, it is the
-- reason the feature can exist at all: two pixels of body closing every few
-- seconds is worse than no blink and much harder to notice as a bug.
--
-- ON POKEMON ART IT IS NOT THAT CLEAN, and that is why the option ships OFF.
-- It fires on 144 of the 649 normal-variant Wilds of Kanto sheets. Of a random
-- sample of 16 of those, looked at by eye at 20x, 10 landed on eyes, 2 clearly
-- did not (Cacturne, Cacnea) and 4 could not be judged. The rules above were
-- measured against three-tone ROM art with one thick black outline; a Pokemon
-- sheet carries 5 to 44 tones, so black turns up in leg gaps and shading too and
-- "the only island of the darkest tone" stops meaning "the eye". The numbers
-- from the ROM corpus do not transfer, and the honest thing is to let the
-- player judge rather than to claim they do.
--
-- Memoised on the mask, which is already cached per (sheet, cell, frame count)
-- the same way `poseOffsets` is, so this runs once per sheet and never per draw.
local function detectEyeMarks(m)
  if m.detectedEyes ~= nil then return m.detectedEyes or nil end
  m.detectedEyes = false
  -- Measured on the ROM corpus (see above): every one of these is the value
  -- where the false positive count over 67 sheets is zero and the hit count is
  -- highest. MAX_W = 1 costs three false positives; no vertical band at all
  -- costs one; MAX_GAP = 3 loses hits without buying safety.
  local MAX_TEXELS, MAX_W, MAX_H = 6, 2, 3
  local MIN_GAP, MAX_GAP = 2, 4
  -- The blob's top row, as a fraction of the sheet's opaque rows. 0.60 and 0.65
  -- both measure clean and 0.55 does not, so this sits in the middle of the
  -- plateau rather than on its edge.
  local BAND = 0.62
  local w, h = m.cellW, m.cellH
  if not (w and h and m.minY and m.maxY and m.maxY > m.minY) then return nil end
  local limitY = m.minY + (m.maxY - m.minY) * BAND
  local DIRS = { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }
  local seen, blobs = {}, {}
  for ly = 0, h - 1 do
    for lx = 0, w - 1 do
      local opaque, outline = frameTexel(m, 0, lx, ly)
      if opaque and outline and not seen[ly * w + lx] then
        seen[ly * w + lx] = true
        local body = { { lx, ly } }
        local minX, maxX, minY, maxY = lx, lx, ly, ly
        local i = 1
        while i <= #body do
          local px, py = body[i][1], body[i][2]
          i = i + 1
          for _, d in ipairs(DIRS) do
            local nx, ny = px + d[1], py + d[2]
            local key = ny * w + nx
            if nx >= 0 and nx < w and ny >= 0 and ny < h and not seen[key] then
              local nOpaque, nOutline = frameTexel(m, 0, nx, ny)
              if nOpaque and nOutline then
                seen[key] = true
                body[#body + 1] = { nx, ny }
                if nx < minX then minX = nx end
                if nx > maxX then maxX = nx end
                if ny < minY then minY = ny end
                if ny > maxY then maxY = ny end
              end
            end
          end
        end
        if #body <= MAX_TEXELS and maxX - minX + 1 <= MAX_W
          and maxY - minY + 1 <= MAX_H and minY <= limitY then
          -- INTERIOR AND ON SKIN. `outline` false on an opaque texel means its
          -- luma is above the sheet minimum, so "not outline" IS "lighter".
          local inside = {}
          for _, p in ipairs(body) do inside[p[2] * w + p[1]] = true end
          local island = true
          for _, p in ipairs(body) do
            for _, d in ipairs(DIRS) do
              local nx, ny = p[1] + d[1], p[2] + d[2]
              if not inside[ny * w + nx] then
                local nOpaque, nOutline = frameTexel(m, 0, nx, ny)
                if not nOpaque or nOutline then island = false break end
              end
            end
            if not island then break end
          end
          if island then
            blobs[#blobs + 1] = { body = body, minX = minX, maxX = maxX }
          end
        end
      end
    end
  end

  local found
  for a = 1, #blobs do
    for b = a + 1, #blobs do
      local left, right = blobs[a], blobs[b]
      if left.minX > right.minX then left, right = right, left end
      local gap = right.minX - left.maxX - 1
      if #left.body == #right.body and gap >= MIN_GAP and gap <= MAX_GAP then
        -- THE AXIS IS THE CELL'S OWN CENTRE LINE, `w - 1 - x`, and asking for
        -- it here is what makes this a mirror test and not just a shape test:
        -- two islands of the same shape sitting off to one side of the sprite
        -- are two marks that happen to match, not a face. The cell centre is
        -- the right line because it is the one the host mirrors a sprite about
        -- when it turns right (VoxelScene resolves the frame, then applies the
        -- mirror on the matrix), so it is the sheet's own axis of symmetry.
        local mirror = {}
        for _, p in ipairs(right.body) do mirror[p[2] * w + p[1]] = true end
        local same = true
        for _, p in ipairs(left.body) do
          if not mirror[p[2] * w + (w - 1 - p[1])] then same = false break end
        end
        if same then
          -- A second pair is a refusal, not a choice: on a sheet with two
          -- candidate faces there is no measurement that says which is the one.
          if found then return nil end
          found = {}
          for _, p in ipairs(left.body) do found[#found + 1] = { p[1], p[2] } end
          for _, p in ipairs(right.body) do found[#found + 1] = { p[1], p[2] } end
        end
      end
    end
  end
  m.detectedEyes = found or false
  return found
end

local function rowsForUv(rows, first, uv4)
  local out = {}
  for i = 0, 3 do
    local src = rows[first + i]
    out[i + 1] = { src[1], src[2], src[3], uv4[i * 2 + 1],
      uv4[i * 2 + 2], src[6] }
  end
  return out
end

local function setMeshVertex(mesh, index, row)
  if not (mesh and mesh.setVertex) then return false end
  local ok = pcall(mesh.setVertex, mesh, index, row)
  if ok then return true end
  return pcall(mesh.setVertex, mesh, index, row[1], row[2], row[3], row[4],
    row[5], row[6])
end

local function warnBlinkVertexFailure()
  if blinkVertexWarned then return end
  blinkVertexWarned = true
  mod.log:warn("could not update SLAB blink UVs; mesh.setVertex failed")
end

local function applyBlinkUv(mesh)
  local meta = meshBlink[mesh]
  if not meta then return end
  local closed = (optionState.blink or readOption(OPTION_BY_KEY.blink)) == "on"
    and blinkClosedForBase(meta.baseName)
  if meta.closed == closed then return end
  -- The blink edge was already here: this early return is what stops the UV
  -- swap from being rewritten every frame, so the line below it runs exactly
  -- when the eye changes state. The event is that transition, named. Guarded
  -- against the first call, where `meta.closed` is nil and the eye has not
  -- changed, it has only been observed for the first time.
  if meta.closed ~= nil then
    eventoNovo(closed and "blink_closed" or "blink_open")
  end
  meta.closed = closed
  for _, quad in ipairs(meta.quads) do
    local rows = closed and quad.closedRows or quad.openRows
    for i = 1, 4 do
      if not setMeshVertex(mesh, quad.first + i - 1, rows[i]) then
        warnBlinkVertexFailure()
      end
    end
  end
end

-- SIX SHEET PIXELS OFF THE GROUND, which is where the option's own help text
-- says the contact shade reaches: "the lowest six pixels".
--
-- `y` arrives in SHEET PIXELS, straight off the builder, so on a 64 px cell six
-- of them are six sixty-fourths of the body instead of six sixteenths: the
-- shade covered a QUARTER of the height it names, and GROUND SHADE ships ON, so
-- every HD character was drawn that way. `hdK` is the same factor
-- escalaParaTile will divide the vertices by afterwards; multiplying the rise
-- by it keeps the band at the same fraction of the figure, which is what
-- "the lowest six pixels" meant in the first place.
local function shadeAtHeight(shade, y, groundShade, hdK)
  -- Moved from chunk scope (roadmap item 0: main chunk locals): only read
  -- here.
  local AO_STRENGTH = 2.4
  local AO_GROUND = 0.12 * AO_STRENGTH
  local AO_RISE = 6 * (hdK or 1)
  if groundShade ~= "on" or y >= AO_RISE then return shade end
  local t = math.max(0, y) / AO_RISE
  return shade * (1 - AO_GROUND * (1 - t))
end

-- SCALING AN HD SHEET DOWN TO ONE TILE, and only when asked (roadmap T3.0).
--
-- The builders emit vertex coordinates in SHEET PIXELS, and the host's matrix
-- maps a 16 px cell onto one tile. Feed the same builders a 64 px cell and the
-- body comes out four tiles tall and fills the screen -- measured that way
-- first, which is how the factor got found rather than assumed.
--
-- IT IS OPT-IN, and the first version was not, which broke two checks. That
-- version inferred the scale from cell height, on the theory that a cell is
-- always sixteen units. It is not: the suite legitimately builds 2x4 sheets with
-- 2 frames to test one top face, and those got multiplied by eight. The lesson
-- is the same one this project keeps relearning -- a rule inferred from one
-- case is a rule that breaks the case nobody thought about.
--
-- So nothing is scaled unless `hdScale` was set, which only happens when the HD
-- sprite option is on. With it unset this function is not even called.
local function escalaParaTile(verts, m)
  -- Only an HD-sourced mask asks for this, and only when its cell really is
  -- bigger than a tile. Everything else returns untouched, which is what keeps
  -- the suite's deliberate 2x4 test sheets from being multiplied by eight.
  local hdK = hdCellScale(m)
  if not hdK then return verts end
  local k = 1 / hdK
  for i = 1, #verts do
    local v = verts[i]
    v[1], v[2], v[3] = v[1] * k, v[2] * k, v[3] * k
  end
  return verts
end

local function buildSlabMesh(def, frame, depth, correction, m, sideColor,
                             groundShade, baseName, topEdge, frontShape,
                             topDome, stepWeight)
  -- Moved from chunk scope (roadmap item 0: main chunk locals; see the
  -- REFACTOR comment above SHARED, main.lua). Every one of these five is
  -- only ever read inside this function, so it costs nothing here: this
  -- function's locals do not count against LuaJIT's 200 chunk locals.
  local TOP_EDGE_SHADE = 0.82
  -- Exposed SLAB faces sit at the real pixel boundary. The old inset was
  -- hiding z-fighting between internal faces that are no longer emitted now.
  local SIDE_INSET = 0
  local RUN_UV_INSET = 0.05
  -- DECISION v1.6.0: three shade steps is the same number of tones the
  -- artist already uses for volume in the source Gen 1 sprites. A continuous
  -- gradient was prototyped before and read as a bright stripe floating over
  -- the art, because hard-pixel art and smooth gradients fight each other;
  -- constant shade per pixel, quantized into these steps, is what matches
  -- the rest of the drawing.
  local FRONT_SHAPE_STEPS = 3
  -- Same reasoning as FRONT_SHAPE_STEPS: three tones is what the artist
  -- already uses for volume in the source Gen 1 sprites, and a step aligned
  -- to the pixel, not a continuous gradient (DECISION above
  -- FRONT_SHAPE_STEPS).
  local TOP_DOME_STEPS = 3
  m = m or maskFor(def)
  if not m then return nil end
  -- Read once: every constant below that is in SHEET PIXELS has to grow by
  -- this factor to survive escalaParaTile (see hdCellScale).
  local hdK = hdCellScale(m)
  frame = tonumber(frame) or 0
  if frame < 0 or frame >= m.frames then frame = 0 end
  local fx, fy = frameOrigin(m, frame)
  if fx + m.cellW > m.sheetW or fy + m.cellH > m.sheetH then return nil end
  local refFrameA, refFrameB = referenceFramesForRole(frame, m.frames)

  local z0, z1 = -depth, 0
  -- FIX for defect 2b (SLAB, v1.3.0): the Y axis had the same defect as X,
  -- and this round's spec claimed it did not. The host translates the card
  -- to ground height and pivots the lean there (VoxelScene.lua:287-295),
  -- so y = 0 in local space is the BOTTOM row of the cell, not the art's
  -- lowest opaque row. Anchoring on m.maxY sinks into the ground every
  -- sheet that has an empty footer: 8 of 67, poke_ball.png among them by 2
  -- pixels, which is the most common object event sprite in the game,
  -- along with snorlax, pokedex, fossil and old_amber. For the 59 sheets
  -- whose art touches ly = cellH-1 the formula is identical to the
  -- previous one, so this does not touch anyone who was already correct.
  local cellBottom = m.cellH - 1
  local verts, idx = {}, {}
  local c, s = math.cos(correction or 0), math.sin(correction or 0)

  -- FIX for defect 1 (SLAB, v1.3.0): `at` used to answer with `m.mask`,
  -- the union of opacity across ALL frames of the sheet (maskFor
  -- accumulates over the frames in main.lua:365-383). That works for
  -- front/back, which sample the current frame via rectUv and rely on the
  -- shader's alpha discard to cut out the pose; it does not work for
  -- top/bottom/side, whose UV resolves on purpose to a fixed opaque texel
  -- (verticalUv, sideUv) and is never discarded. SLAB was drawing the
  -- whole walking silhouette on every pose (Pikon: "It kinda looks like
  -- all Red's sprites are appearing at once when walking left to right").
  -- Now `at` queries the opacity of the CURRENT FRAME, not the union.
  local function at(lx, ly)
    if lx < m.minX or lx > m.maxX or ly < m.minY or ly > m.maxY then return false end
    return (frameTexel(m, frame, lx, ly))
  end

  local function uv(lx, ly)
    return (fx + lx + 0.5) / m.sheetW, (fy + ly + 0.5) / m.sheetH
  end

  local function bodyTexel(lx, ly, dx, dy)
    return bodyTexelInFrame(m, frame, lx, ly, dx, dy, sideColor)
  end

  local function topShade()
    if topEdge == "on" then return SHARED.OBJ_SHADE.top * TOP_EDGE_SHADE end
    return SHARED.OBJ_SHADE.top
  end

  -- TOP DOME FEATURE (v1.6.0): the top face already comes out as one quad
  -- per pixel (the `if not at(sx, ly - 1)` branch further below), so
  -- varying the shade by position within the run costs ZERO extra quads:
  -- it is just swapping the shade value that was already going into each
  -- quad, never adding a new quad. Same mechanism as FRONT SHAPE:
  -- TOP_DOME_STEPS constant tones, pixel aligned, chosen by distance to
  -- the run's edge, not a continuous gradient (that was already
  -- prototyped on the front face and read as a bright stripe floating
  -- over the art). `a` and `b` are the bounds of THIS row's horizontal run
  -- (lx, lx2 in the main loop), the same reference emitFrontRun uses for
  -- its own step: relative only to the run, never to an absolute screen
  -- coordinate, which guarantees the required symmetry in X (the run
  -- mirrors along with the character, and the shade mirrors along with
  -- it). `base` comes from topShade(), so TOP EDGE and TOP DOME coexist
  -- by construction: the dome's step is always a multiplier APPLIED ON TOP
  -- of TOP EDGE's base, never in place of it; turning one on does not
  -- cancel the other.
  local domoStep = tonumber(topDome) or 0
  local function topShadeDomo(sx, a, b)
    local base = topShade()
    -- Runs shorter than 3 pixels have no "middle" pixel distinct from the
    -- two edges: no step is possible, so they stay at the usual constant
    -- shade, same as the option turned off.
    if domoStep <= 0 or b - a < 2 then return base end
    local center = (a + b) / 2
    local half = (b - a) / 2
    local t = math.abs(sx - center) / half
    local level = math.floor(t * (TOP_DOME_STEPS - 0.001))
    return base * (1 - domoStep * level / (TOP_DOME_STEPS - 1))
  end

  local function sameUv(lx, ly)
    local u, v = uv(lx, ly)
    return { u, v, u, v, u, v, u, v }
  end

  local function sameFrameUv(frameIndex, lx, ly)
    local ffx, ffy = frameOrigin(m, frameIndex)
    local u = (ffx + lx + 0.5) / m.sheetW
    local v = (ffy + ly + 0.5) / m.sheetH
    return { u, v, u, v, u, v, u, v }
  end

  -- FIX for the top-flickering-while-walking defect (SLAB, v1.4.2): `lx,
  -- ly` is the face's coordinate in the CURRENT frame; `frameIndex` is the
  -- reference frame. Before reading the body at `frameIndex`, we
  -- compensate for the measured displacement between the two poses
  -- (poseOffset), otherwise the lookup lands on the same row of the wrong
  -- frame. If the compensated coordinate falls outside the cell or finds
  -- no opaque body in the reference frame, it degrades to the uncompensated
  -- coordinate (the pre-v1.4.2 behavior) before giving up on this reference
  -- frame; no face is left with an unresolved UV.
  local function sideUv(lx, ly, dx)
    local function tryFrame(frameIndex)
      if not frameIndex then return nil end
      local pdx, pdy = poseOffset(m, frame, frameIndex)
      local bx, by = bodyTexelInFrame(m, frameIndex, lx + pdx, ly + pdy, dx, 0,
        sideColor)
      if frameTexel(m, frameIndex, bx, by) then
        return sameFrameUv(frameIndex, bx, by)
      end
      bx, by = bodyTexelInFrame(m, frameIndex, lx, ly, dx, 0, sideColor)
      if frameTexel(m, frameIndex, bx, by) then
        return sameFrameUv(frameIndex, bx, by)
      end
    end
    return tryFrame(refFrameA) or tryFrame(refFrameB)
      or sameUv(bodyTexel(lx, ly, dx, 0))
  end

  local function verticalUv(lx, ly, dy)
    local function tryFrame(frameIndex)
      if not frameIndex then return nil end
      local pdx, pdy = poseOffset(m, frame, frameIndex)
      local bx, by = bodyTexelInFrame(m, frameIndex, lx + pdx, ly + pdy, 0, dy,
        sideColor)
      if frameTexel(m, frameIndex, bx, by) then
        return sameFrameUv(frameIndex, bx, by)
      end
      bx, by = bodyTexelInFrame(m, frameIndex, lx, ly, 0, dy, sideColor)
      if frameTexel(m, frameIndex, bx, by) then
        return sameFrameUv(frameIndex, bx, by)
      end
    end
    return tryFrame(refFrameA) or tryFrame(refFrameB)
      or sameUv(bodyTexel(lx, ly, 0, dy))
  end

  local function rectFrameUv(frameIndex, lx, ly, lx2, order)
    local ffx, ffy = frameOrigin(m, frameIndex)
    local u0 = (ffx + lx + RUN_UV_INSET) / m.sheetW
    local u1 = (ffx + lx2 + 1 - RUN_UV_INSET) / m.sheetW
    local v0 = (ffy + ly + RUN_UV_INSET) / m.sheetH
    local v1 = (ffy + ly + 1 - RUN_UV_INSET) / m.sheetH
    if order == "back" then
      return { u1, v1, u0, v1, u0, v0, u1, v0 }
    elseif order == "top" then
      return { u0, v0, u1, v0, u1, v1, u0, v1 }
    end
    return { u0, v1, u1, v1, u1, v0, u0, v0 }
  end

  local function rectUv(lx, ly, lx2, order)
    return rectFrameUv(frame, lx, ly, lx2, order)
  end

  -- FIX for the "only blinks when standing" defect (v1.4.2): the walking
  -- poses (3 and 5) now blink too. `refFrameA` (computed above) is already
  -- the current frame's role (0 front, 1 back, 2 profile); back never had
  -- an eye mark and stays without a blink. On the standing pose (frame ==
  -- refFrameA) the mark counts at its own coordinate, as always. On the
  -- walking pose, each mark only enters eyeLookup if the tone at (x+dx,
  -- y+dy) in the walking frame matches the tone at (x, y) in the
  -- reference frame; if ANY mark on the sheet fails to transfer, the whole
  -- sheet stays open-eyed on THIS pose, never half-closed. Decided here,
  -- measured sheet by sheet and pose by pose, never by a hand-written
  -- table.
  local blinkQuads = {}
  local canBlinkFrame = false
  local eyeLookup
  if refFrameA == 0 or refFrameA == 2 then
    local marks = refFrameA == 2 and EYE_SIDE_MARKS[baseName or ""]
      or EYE_MARKS[baseName or ""]
    -- THE MARKS ARE COORDINATES IN A 16x16 CELL, hand measured against the
    -- ROM's own art, and on a bigger cell they point somewhere else entirely:
    -- an eye at (6, 7) lands near the top left corner of a 64 px frame rather
    -- than on a face. BLINK would then close two pixels of forehead, and on the
    -- walking pose eyeMarkTransfers would compare the wrong tones, fail, and
    -- switch blinking off for the whole sheet.
    --
    -- One original pixel becomes a k by k block, which is exactly what it is
    -- after an enlargement: the mark still covers the same part of the face.
    if marks and hdCellScale(m) then
      local k = math.floor(hdCellScale(m) + 0.5)
      if k > 1 then
        local grandes = {}
        for _, eye in ipairs(marks) do
          for j = 0, k - 1 do
            for i = 0, k - 1 do
              grandes[#grandes + 1] = { eye[1] * k + i, eye[2] * k + j }
            end
          end
        end
        marks = grandes
      end
    end
    -- ONLY WHERE THE TABLE IS SILENT, and after the HD rescale on purpose. The
    -- hand table stays the authority: it was measured against the art by a
    -- person, the detector was measured against the hand table, and the second
    -- can never overrule the first. Detected marks come out of the sheet's OWN
    -- cell, at whatever size that cell is, so they must not go through the 16 px
    -- rescale above -- which is why this sits below it and not beside the
    -- lookup.
    --
    -- Front role only. A profile eye is a single mark with no mirror twin, so
    -- the pair rule this detector is built on has nothing to stand on there and
    -- EYE_SIDE_MARKS keeps the side view to itself.
    if not marks and refFrameA == 0 and m
      and (optionState.blink_detect
           or readOption(OPTION_BY_KEY.blink_detect)) == "on" then
      marks = detectEyeMarks(m)
    end
    if marks then
      if frame == refFrameA then
        eyeLookup = {}
        for _, eye in ipairs(marks) do
          eyeLookup[eye[2] .. ":" .. eye[1]] = true
        end
        canBlinkFrame = true
      else
        local pdx, pdy = poseOffset(m, refFrameA, frame)
        local candidate, allTransfer = {}, true
        for _, eye in ipairs(marks) do
          local wx, wy = eye[1] + pdx, eye[2] + pdy
          if eyeMarkTransfers(m, refFrameA, eye[1], eye[2], frame, wx, wy) then
            candidate[wy .. ":" .. wx] = true
          else
            allTransfer = false
            break
          end
        end
        if allTransfer then
          eyeLookup = candidate
          canBlinkFrame = true
        end
      end
    end
  end

  -- DECISION: SLAB also needs to fix the color classification of new faces
  -- by role, not by the current frame. The bug measured on red.png came
  -- from using the walk directly: 49/180 top face positions alternated
  -- between standing and walking, 14 of them in the hat region. The direct
  -- cause is row 0 of frame 3 being empty because the sprite shifts down a
  -- whole row. Top, bottom and sides use a fixed texel per pixel so they
  -- can search for body on the right axis without mixing columns of a run.

  -- STEP WEIGHT FEATURE (v1.6.0): shear in Z proportional to height, only
  -- on walking frames. In Z on purpose: at pitch 0, the compliance gate's
  -- camera, the Z axis points at the camera, so moving it does not change
  -- silhouette (Kim measured IoU 1.000 at -1.0, -0.5, 0, +0.5 and +1.0).
  -- On the game's camera, which looks down from above, that same Z
  -- displacement shows up vertically after the `correction` rotation `p()`
  -- already applied. Nothing in X: the host's mirror never sees this
  -- option.
  --
  -- "Walking frame" is derived from the same bucket carvedFrames already
  -- uses for CARVED (main.lua, function carvedFrames below), not the
  -- guessed literals 3, 4 and 5: a frame above 5 folds into a bucket of 3
  -- (frame % 3), same as roleForFrame, and only enters the "walking"
  -- bucket (position 3) when the sheet actually has six frames. That
  -- covers by construction the constraint "sheets with fewer frames have
  -- no walking pose": with m.frames < 6, bucketFrame never reaches 3
  -- within the valid frame range (already normalized to [0, m.frames) at
  -- the top of this function), so `andando` stays false and no 1 or
  -- 3-frame sheet overflows.
  --
  -- THE STRENGTH IS IN SHEET PIXELS, because it is added straight to `z`, and
  -- `escalaParaTile` divides z by the same factor it divides everything else
  -- by. Left unscaled, an HD character leaned a QUARTER as far as the same
  -- character at ROM resolution: the option was doing a quarter of its job
  -- rather than failing, which is the shape of every other constant in this
  -- file that had to grow with the cell. `y / m.cellH` on the other side of
  -- the multiplication is a FRACTION of the height and must not be touched.
  local stepWeightForce = (tonumber(stepWeight) or 0) * (hdK or 1)
  local bucketFrame = frame
  if bucketFrame > 5 then bucketFrame = bucketFrame % 3 end
  local andando = bucketFrame >= 3 and m.frames >= 6
  local stepWeightZ = andando and stepWeightForce or 0

  local function p(x, y, z)
    -- Exact zero when the option is off or the frame is not a walking one:
    -- adding 0.0 preserves the z value bit for bit, so the mesh stays
    -- identical to today's in both those cases.
    if stepWeightZ ~= 0 then z = z + stepWeightZ * (y / m.cellH) end
    -- Dramatic Shape's matrix tilts the card in X, pivoting at the feet.
    -- The solid mesh arrives counter-rotated at the same pivot; after the
    -- outer lean, the body ends up standing again.
    return { x, y * c - z * s, y * s + z * c, y }
  end

  local function quad(c1, c2, c3, c4, uv4, shade)
    local n = #verts / 4
    local first = #verts + 1
    local function add(corner, u, v)
      verts[#verts + 1] = {
        corner[1], corner[2], corner[3], u, v,
        shadeAtHeight(shade, corner[4], groundShade, hdK),
      }
    end
    add(c1, uv4[1], uv4[2])
    add(c2, uv4[3], uv4[4])
    add(c3, uv4[5], uv4[6])
    add(c4, uv4[7], uv4[8])
    Voxel3D.pushQuad(idx, n)
    return first
  end

  local function isEye(lx, ly)
    return eyeLookup and eyeLookup[ly .. ":" .. lx]
  end

  local function eyeClosedUv(lx, ly)
    local bx, by = blinkBodyTexel(m, frame, lx, ly)
    if bx then return sameUv(bx, by) end
  end

  local function addEyeQuad(first, openUv, closedUv)
    if not (canBlinkFrame and closedUv) then return end
    blinkQuads[#blinkQuads + 1] = {
      first = first,
      openRows = rowsForUv(verts, first, openUv),
      closedRows = rowsForUv(verts, first, closedUv),
    }
  end

  -- FIX for defect B (SLAB, v1.3.0): since `at()` started querying the
  -- current frame, side faces can be vertical runs when that preserves
  -- exactly the same UV and the same shade as the per-pixel quads.
  local function sameUvTable(a, b)
    if not (a and b) then return false end
    for i = 1, 8 do
      if a[i] ~= b[i] then return false end
    end
    return true
  end

  local sideRuns, finishedSideRuns = {}, {}

  local function sideRunKey(px, side)
    return side .. ":" .. px
  end

  local function finishSideRun(key)
    local run = sideRuns[key]
    if run then
      finishedSideRuns[#finishedSideRuns + 1] = run
      sideRuns[key] = nil
    end
  end

  local function addSideRun(px, ly, side, uv4)
    local key = sideRunKey(px, side)
    local sy = cellBottom - ly
    local run = sideRuns[key]
    if run and run.lastLy + 1 == ly and sameUvTable(run.uv4, uv4)
        and run.shade == SHARED.OBJ_SHADE.side then
      run.lastLy = ly
      run.minY = math.min(run.minY, sy)
      run.maxY = math.max(run.maxY, sy + 1)
      return
    end
    finishSideRun(key)
    sideRuns[key] = {
      px = px, side = side, lastLy = ly, minY = sy, maxY = sy + 1,
      uv4 = uv4, shade = SHARED.OBJ_SHADE.side,
    }
  end

  local function emitSideRun(run)
    if run.side == "left" then
      local x = run.px + SIDE_INSET
      quad(p(x, run.minY, z0), p(x, run.minY, z1),
           p(x, run.maxY, z1), p(x, run.maxY, z0),
           run.uv4, run.shade)
    else
      local x = run.px + 1 - SIDE_INSET
      quad(p(x, run.minY, z1), p(x, run.minY, z0),
           p(x, run.maxY, z0), p(x, run.maxY, z1),
           run.uv4, run.shade)
    end
  end

  -- DECISION: historically SLAB's left/right sides were per pixel because
  -- occupancy came from `m.mask` (the union of every frame) and only the
  -- shader's alpha discard cut out the pose on top. If they were runs, the
  -- side would leave a trail as the silhouette walked. Since v1.3.0,
  -- `at()` queries the current frame and the side is already born with the
  -- correct silhouette, so adjacent faces can be merged vertically when
  -- that is lossless: same X, same side, same shade and same resolved UV.
  -- Where the UV changes, we keep the quads separate. Front and back stay
  -- as horizontal runs with rectangular UV and a 0.05 texel inset.
  -- The community measured that 34/34 side silhouette pixels of red.png
  -- came out in the darkest tone, but one step inward only 16/34 were
  -- still outline. That is why BODY paints new faces with an interior
  -- texel, while front and back stay as the original art. Top/bottom are
  -- per pixel like the sides: when an outline pixel touches a vertical
  -- line of body, the new texel comes from that body instead of requiring
  -- the whole horizontal run to match. Starting in v1.2.2, this decision
  -- runs on fixed reference frames so SLAB does not flicker.
  -- FRONT SHAPE (v1.6.0): constant strength for the whole mesh, read once
  -- outside the loop. "off" becomes 0 (tonumber("off") == nil), the same
  -- branch as the usual single quad inside emitFrontRun; any strength > 0
  -- turns on the stepped scaling.
  local frontStep = tonumber(frontShape) or 0

  for ly = m.minY, m.maxY do
    local lx = m.minX
    while lx <= m.maxX do
      if at(lx, ly) then
        local lx2 = lx
        while lx2 + 1 <= m.maxX and at(lx2 + 1, ly) do lx2 = lx2 + 1 end

        -- FIX for defect 2 (SLAB, v1.3.0): X used to come out relative to
        -- the opaque bbox (`lx - m.minX`), not the sprite cell. The host
        -- anchors the card with Mat4.translate(px+8, y, py+8) followed by
        -- Mat4.translate(-8,0,0) (VoxelScene.lua:287-295): local space runs
        -- from x=0 to x=16 and the yaw/mirror pivot sits at x=8, the center
        -- of the CELL, not of the art's bbox. 40 of the 67 sheets have
        -- minX=1, so the whole art used to come out 1 pixel to the left of
        -- the card it replaces. X now uses raw lx.
        local x, y = lx, cellBottom - ly
        local w = lx2 - lx + 1
        -- FRONT SHAPE FEATURE (v1.6.0): pixel-aligned steps on the front
        -- face, in place of the usual constant shade, when the option is
        -- on. A continuous gradient was prototyped before this and read as
        -- a bright stripe floating over the art (hard-pixel art and smooth
        -- gradients fight each other); here every pixel of the run gets a
        -- CONSTANT shade, chosen among FRONT_SHAPE_STEPS levels by the
        -- distance to the run's edge, the same way the artist already
        -- builds volume in the source sprites.
        --
        -- FIX (fresh-eyes fine-tooth comb): `runCenter` and `runHalf` come
        -- from the WHOLE RUN (`lx`, `lx2`), never from the `a..b` segment
        -- `emitFrontRun` receives. An eye in the middle of the run cuts the
        -- CALL into pieces (the `isEye` loop right below), but does not cut
        -- the run: the eye pixel stays opaque and within `lx..lx2`.
        -- Measuring against the segment made each piece treat its own tip,
        -- glued to the eye, as if it were the silhouette's real edge, so
        -- that pixel came out in the same dark tone as the true edge: a
        -- dark ring around every eye, on any sheet with an eye mark
        -- (`EYE_MARKS`/`EYE_SIDE_MARKS`) and independent of the BLINK
        -- option, because the `isEye` cut never checks BLINK's state. `lx`
        -- and `lx2` mirror together like the rest of the run, so the
        -- required X symmetry stays guaranteed by construction: never an
        -- absolute screen coordinate, always the run's own bounds.
        local runCenter = (lx + lx2) / 2
        local runHalf = (lx2 - lx) / 2
        local function emitFrontRun(a, b)
          if a > b then return end
          -- No step is possible when the option is off OR the WHOLE RUN,
          -- not the segment, is shorter than 3 pixels: there is no
          -- "middle" pixel distinct from the two real edges. A short
          -- segment glued to an eye, inside a wide run, still needs the
          -- step: that is why the guard checks `lx2 - lx`, not `b - a`.
          if frontStep <= 0 or lx2 - lx < 2 then
            local rx, rw = a, b - a + 1
            quad(p(rx, y, z1), p(rx + rw, y, z1),
                 p(rx + rw, y + 1, z1), p(rx, y + 1, z1),
                 rectUv(a, ly, b), SHARED.OBJ_SHADE.front)
            return
          end
          for sx = a, b do
            local t = math.abs(sx - runCenter) / runHalf
            local level = math.floor(t * (FRONT_SHAPE_STEPS - 0.001))
            local sh = SHARED.OBJ_SHADE.front
              * (1 - frontStep * level / (FRONT_SHAPE_STEPS - 1))
            quad(p(sx, y, z1), p(sx + 1, y, z1),
                 p(sx + 1, y + 1, z1), p(sx, y + 1, z1),
                 rectUv(sx, ly, sx), sh)
          end
        end
        local cursor = lx
        for sx = lx, lx2 do
          if isEye(sx, ly) then
            emitFrontRun(cursor, sx - 1)
            local openUv = sameUv(sx, ly)
            local first = quad(p(sx, y, z1), p(sx + 1, y, z1),
              p(sx + 1, y + 1, z1), p(sx, y + 1, z1),
              openUv, SHARED.OBJ_SHADE.front)
            addEyeQuad(first, openUv, eyeClosedUv(sx, ly))
            cursor = sx + 1
          end
        end
        emitFrontRun(cursor, lx2)
        quad(p(x + w, y, z0), p(x, y, z0), p(x, y + 1, z0),
             p(x + w, y + 1, z0), rectUv(lx, ly, lx2, "back"),
             SHARED.OBJ_SHADE.back)
        for sx = lx, lx2 do
          if not at(sx, ly - 1) then
            quad(p(sx, y + 1 - SIDE_INSET, z0),
                 p(sx + 1, y + 1 - SIDE_INSET, z0),
                 p(sx + 1, y + 1 - SIDE_INSET, z1),
                 p(sx, y + 1 - SIDE_INSET, z1),
                 verticalUv(sx, ly, 1), topShadeDomo(sx, lx, lx2))
          end
          if not at(sx, ly + 1) then
            quad(p(sx, y + SIDE_INSET, z1),
                 p(sx + 1, y + SIDE_INSET, z1),
                 p(sx + 1, y + SIDE_INSET, z0),
                 p(sx, y + SIDE_INSET, z0),
                 verticalUv(sx, ly, -1), SHARED.OBJ_SHADE.bottom)
          end
          -- FIX v1.4.1: sides also need to be exposed faces. Within a
          -- horizontal run, a column's left side is coplanar with its
          -- neighbor's right side; with an inset, that still opened a gap
          -- between columns. We only emit the silhouette's outline.
          if not at(sx - 1, ly) then
            addSideRun(sx, ly, "left", sideUv(sx, ly, 1))
          end
          if not at(sx + 1, ly) then
            addSideRun(sx, ly, "right", sideUv(sx, ly, -1))
          end
        end
        lx = lx2 + 1
      else
        lx = lx + 1
      end
    end
  end

  local finalSideKeys = {}
  for key in pairs(sideRuns) do finalSideKeys[#finalSideKeys + 1] = key end
  table.sort(finalSideKeys)
  for _, key in ipairs(finalSideKeys) do finishSideRun(key) end
  for _, run in ipairs(finishedSideRuns) do emitSideRun(run) end

  -- REGIONS, for per-part secondary motion (roadmap item 9).
  --
  -- The mesh has to be addressable in bands so that hair can lag differently
  -- from feet. Three blockers were recorded against doing that, and all three
  -- come from the same wrong assumption, that a region means CUTTING the mesh:
  --
  --   cap faces: SLAB emits a top or bottom face only where the neighbouring
  --   row is empty, so a cut anywhere else exposes the inside of the back
  --   wall, because the host draws with culling disabled;
  --
  --   "the top N rows are a contiguous prefix" is false, because side faces
  --   accumulate in sideRuns and are emitted after the whole row scan;
  --
  --   the mesh is shared between every instance of a sheet in the frame.
  --
  -- Nothing is cut here. The quads are REORDERED so that every quad in a band
  -- is contiguous, and the index buffer is rebuilt to match. The set of quads
  -- is identical, every cap face is still exactly where it was, and the
  -- silhouette is unchanged: only the order in the buffer differs, and order
  -- carries no meaning in an indexed mesh.
  --
  -- That leaves the third blocker, which is real and is handled elsewhere: the
  -- ranges live on `ourMeshes`, beside the draw call, never on the mesh, so a
  -- mesh shared by five instances still gives each of them its own transform.
  local bandas, faixas = REGION_BANDS, nil
  do
    local quads = #verts / 4
    local porBanda = {}
    for b = 1, bandas do porBanda[b] = {} end
    -- MEASURED REGIONS, OR FOUR EQUAL SLICES OF THE CELL (roadmap T2.1 slice 3).
    --
    -- `regiao` is nil unless AUTHORED REGIONS is on AND this sheet ships
    -- measurements for this frame. Nil means the arithmetic below is exactly
    -- what it always was, which is what keeps the pure runtime path
    -- byte-identical rather than merely similar.
    local regiao = nil
    if optionState.authored_regions == "on" then
      local medidas = authoredRegions(baseName)
      regiao = medidas and medidas[frame] or nil
      -- A measurement that cannot be true of this cell is refused here rather
      -- than used. Stale metadata is the failure mode this whole slice invites,
      -- and silently cutting along a bound from a sprite that has since been
      -- re-imported would be worse than not cutting along anything.
      if regiao then
        -- THE MEASUREMENTS ARE ROWS OF THE SOURCE CELL, never of this one.
        -- tools/measure_regions.py reads the player's own 16 px sheet, so on a
        -- 64 px HD cell `top = 0, bottom = 15` describes the top QUARTER of the
        -- figure. Checking them against 64 would wave that through, and the cut
        -- below would then put every band boundary inside the head. Both the
        -- check and the lookup happen in the cell the numbers were measured in.
        local alt = (m.cellH or 16) / (hdK or 1)
        local ok = type(regiao.top) == "number" and type(regiao.bottom) == "number"
          and regiao.top >= 0 and regiao.bottom < alt and regiao.top < regiao.bottom
        if ok and regiao.footSplit then
          ok = regiao.footSplit > regiao.top and regiao.footSplit <= regiao.bottom
        end
        if not ok then regiao = nil end
      end
    end

    -- Head-first band for a sheet ROW, from the measured figure rather than
    -- from the cell. Local to this block, so it costs no chunk local.
    --
    -- The feet band starts where the legs actually part when that was
    -- measurable, and the rest of the figure divides evenly above it. Where it
    -- was not measurable -- the side standing pose has both feet together --
    -- the whole figure divides evenly, which is still the FIGURE and not the
    -- cell, so the bob no longer moves the boundaries.
    local function bandaMedida(ly)
      local topo, base = regiao.top, regiao.bottom
      if ly < topo then ly = topo elseif ly > base then ly = base end
      local corte = regiao.footSplit
      if corte then
        if ly >= corte then return bandas end
        local i = math.floor((ly - topo) / (corte - topo) * (bandas - 1)) + 1
        if i > bandas - 1 then i = bandas - 1 end
        return i
      end
      local i = math.floor((ly - topo) / (base - topo + 1) * bandas) + 1
      if i < 1 then i = 1 elseif i > bandas then i = bandas end
      return i
    end

    for q = 0, quads - 1 do
      -- The band comes from the quad's own centre in Y, so a quad that
      -- straddles a boundary lands wherever most of it is, and no quad ends up
      -- in two bands or in none.
      local y = 0
      for k = 1, 4 do y = y + verts[q * 4 + k][2] end
      y = y / 4
      local b
      if regiao then
        -- Back to a sheet row. The builder emits row `ly` at
        -- `y = cellH - 1 - ly` (see `cellBottom - ly` above), so a quad centred
        -- half a row lower inverts to `floor(cellH - y)`.
        --
        -- Divided by the HD factor so the row is a SOURCE row, the only kind
        -- the measurements know about. It would have been possible instead to
        -- multiply the bounds up and let the cut resolve at HD row precision,
        -- and that is worse: the boundary between two bands would then land a
        -- third of the way into a source row, which is precision the
        -- measurement does not have and nobody measured. Quantising the query
        -- instead makes the HD cut land exactly where the ROM cut lands.
        b = bandas
          - bandaMedida(math.floor(((m.cellH or 16) - y) / (hdK or 1))) + 1
      else
        b = math.floor(y / (m.cellH or 16) * bandas) + 1
      end
      if b < 1 then b = 1 elseif b > bandas then b = bandas end
      porBanda[b][#porBanda[b] + 1] = q
    end
    local novos, novoIdx, mapa = {}, {}, {}
    faixas = {}
    local escritos = 0
    -- HIGHEST BAND FIRST, which preserves the direction the row scan already
    -- emitted in: the builder walks the sheet from its top row down, and in
    -- mesh space the top of the sheet is the HIGH y.
    --
    -- This is not cosmetic. Two suite checks find "the front face" by taking
    -- the FIRST quad whose z is 0 and whose shade is the front constant, so
    -- reversing the vertical order handed them the foot quad where they
    -- expected the head quad, and they failed with a UV range from the wrong
    -- half of the sprite. They were right to fail: anything that reads the
    -- first quad of a kind is entitled to the order the builder always had.
    --
    -- Band 1 is therefore the HEAD and band `bandas` is the FEET, which is
    -- also the order a person describes a character in.
    for b = bandas, 1, -1 do
      local inicio = escritos
      for _, q in ipairs(porBanda[b]) do
        mapa[q] = escritos
        for k = 1, 4 do novos[#novos + 1] = verts[q * 4 + k] end
        Voxel3D.pushQuad(novoIdx, escritos)
        escritos = escritos + 1
      end
      -- Ranges are in VERTEX INDICES, which is what mesh:setDrawRange takes,
      -- and they are 1-based, which is what LOVE takes.
      -- Indexed from the head down, so faixas[1] is the head whichever way
      -- the loop above happens to run.
      faixas[bandas - b + 1] = { primeiro = inicio * 4 + 1,
                                 quantos = (escritos - inicio) * 4 }
    end
    -- The blink table names quads by their old position, so it moves too.
    -- Missing this would make the eye animate a quad somewhere else on the
    -- body, which is the kind of defect that only shows up on one sheet.
    for i, bq in ipairs(blinkQuads) do
      if bq.quad and mapa[bq.quad] then blinkQuads[i].quad = mapa[bq.quad] end
      if bq.first and mapa[math.floor((bq.first - 1) / 4)] then
        blinkQuads[i].first = mapa[math.floor((bq.first - 1) / 4)] * 4 + 1
      end
    end
    verts, idx = novos, novoIdx
  end

  local mesh = Voxel3D.newMesh(escalaParaTile(verts, m), idx)
  if mesh and #blinkQuads > 0 then
    -- THE SAVED ROWS ARE COPIES, and they were taken before the scaling.
    --
    -- `rowsForUv` copies the vertex POSITION as well as the UV, because
    -- `mesh:setVertex` writes a whole vertex and there is no partial write.
    -- Those copies were made while the eye quad was emitted, which is before
    -- `escalaParaTile` ran on the line above, so on a 64 px sheet they carry
    -- coordinates four times too large. The first `applyBlinkUv` then wrote
    -- them into the mesh and put the two eye quads out beyond the top of the
    -- head: this is one half of "uns dois quadrados acima do personagem" as
    -- Kim reported it. Scaling the copies by the same factor keeps a blink
    -- from moving anything but the UV, which is all a blink was ever meant to
    -- move.
    if hdK then
      for _, quadBlink in ipairs(blinkQuads) do
        for _, rows in ipairs({ quadBlink.openRows, quadBlink.closedRows }) do
          for i = 1, #rows do
            local row = rows[i]
            row[1], row[2], row[3] =
              row[1] / hdK, row[2] / hdK, row[3] / hdK
          end
        end
      end
    end
    -- `closed = false` from the start, not nil. The eye is emitted OPEN, so
    -- false is the truth about it, and saying so is what stops the first call
    -- with BLINK off from writing `openRows` back over a mesh that already
    -- holds them: `nil ~= false` made that write happen for every character on
    -- screen, once, with the option turned off. Harmless while the saved rows
    -- were right, and the delivery mechanism for the defect above while they
    -- were not.
    meshBlink[mesh] = { baseName = baseName, quads = blinkQuads, closed = false }
  end
  if mesh then meshBands[mesh] = faixas end

  -- The anchors, from the vertices as emitted (roadmap T1.2).
  --
  -- Measured off the real geometry, never guessed from the sheet's dimensions:
  --
  --   feet    the lowest point, centred across the width that touches it
  --   head    the highest point, centred the same way
  --   centre  the mean of every vertex, so it follows where the body's mass is
  --           rather than where the middle of the cell is
  --   hand    the vertex furthest from the centre line in x, which on a body
  --           with arms is the end of an arm and on a body without them is the
  --           widest point of the silhouette
  --
  -- HAND IS THE ONE WORTH BEING HONEST ABOUT. This mod has no rig and no region
  -- identity beyond the bands, so it cannot know an anatomical hand. What it
  -- can say, and what the gate checks, is that the point sits at the extreme of
  -- the silhouette rather than in the middle of the body. On a sheet whose arms
  -- are tucked in, that extreme is a shoulder or a hip, and calling it `hand`
  -- would be overclaiming, so the anchor also reports how far out it actually
  -- sits and the caller can decide whether that is an arm.
  if mesh then
    local n = #verts
    -- THE VERTICES HAVE ALREADY BEEN SCALED. `escalaParaTile` ran on the line
    -- that built the mesh, so an HD body that was 64 units tall is 16 units
    -- tall by the time it is read here -- but `m.cellH` still says 64. Dividing
    -- a 16-unit height by 64 put every anchor in the bottom quarter of the
    -- cell, so `head.band` came back as 4, the FEET band, on every HD sheet.
    -- Nothing consumes `band` yet, which is the only reason this was not a
    -- visible defect; it would have become one the day PART LAG asked an
    -- anchor which band it was in.
    local cellH = (m.cellH or 16) / (hdK or 1)

    -- IN CHARACTER SPACE, which means undoing what the builder just baked in.
    --
    -- Every vertex above went through `Rx(correction)`, and that rotation mixes
    -- y and z: on this body the head sits at y=14, z=0 as drawn and arrives in
    -- the vertex array at y=11.06, z=10.57. Reading the anchors straight off
    -- the vertices produced a "head" two thirds of the way down the body and a
    -- "hand" at the wrong height, and the caller then applied the same rotation
    -- a second time.
    --
    -- The inverse of Rx(c) is Rx(-c), so: y = y_m*c + z_m*s, z = -y_m*s + z_m*c.
    -- The anchors come out in the space a caller thinks in, the same space the
    -- builder started from, and composing them with a draw matrix is then the
    -- same operation the vertices themselves go through.
    local function paraPersonagem(v)
      return v[1], v[2] * c + v[3] * s, -v[2] * s + v[3] * c
    end

    local minY, maxY, somaX, somaY, somaZ = math.huge, -math.huge, 0, 0, 0
    for i = 1, n do
      local vx, vy, vz = paraPersonagem(verts[i])
      if vy < minY then minY = vy end
      if vy > maxY then maxY = vy end
      somaX, somaY, somaZ = somaX + vx, somaY + vy, somaZ + vz
    end
    local cx = somaX / n
    local function bandaDe(y)
      local b = math.floor(y / cellH * REGION_BANDS) + 1
      if b < 1 then b = 1 elseif b > REGION_BANDS then b = REGION_BANDS end
      -- faixas is indexed head-first, the same flip the band table applies.
      return REGION_BANDS - b + 1
    end
    -- HALF A SOURCE PIXEL, which is what 0.5 meant when the only cell was 16 px
    -- tall. On a scaled HD mesh a source pixel is 1/k units, so the plain 0.5
    -- gathered four times as thick a slab of vertices as it does at ROM
    -- resolution. It never crossed into the next source row (0.5 < 1), so this
    -- did not change an answer on any body measured here; it is a
    -- resolution-dependence in a function whose whole job is to name a fixed
    -- point on the body, and it is corrected rather than left to matter later.
    local tolExtremo = 0.5 / (hdK or 1)
    local function pontoNoExtremo(alvoY)
      local sx, sz, quantos = 0, 0, 0
      for i = 1, n do
        local vx, vy, vz = paraPersonagem(verts[i])
        if math.abs(vy - alvoY) < tolExtremo then
          sx, sz, quantos = sx + vx, sz + vz, quantos + 1
        end
      end
      if quantos == 0 then return cx, somaZ / n end
      return sx / quantos, sz / quantos
    end
    local pesX, pesZ = pontoNoExtremo(minY)
    local cabX, cabZ = pontoNoExtremo(maxY)
    -- THE HAND IS THE FURTHEST REACH, and it is looked for on the FRONT plane
    -- only. A side face at the same x belongs to the same arm but sits a depth
    -- away in z, and taking it would put the anchor inside the character's own
    -- thickness instead of on the surface an effect should leave from.
    local maoX, maoY, maoZ, maoDist = cx, somaY / n, 0, -1
    for i = 1, n do
      local vx, vy, vz = paraPersonagem(verts[i])
      local d = math.abs(vx - cx)
      if d > maoDist + 1e-9 or (math.abs(d - maoDist) < 1e-9 and vz > maoZ) then
        maoDist, maoX, maoY, maoZ = d, vx, vy, vz
      end
    end
    meshAnchors[mesh] = {
      feet   = { x = pesX, y = minY, z = pesZ, band = bandaDe(minY) },
      head   = { x = cabX, y = maxY, z = cabZ, band = bandaDe(maxY) },
      center = { x = cx, y = somaY / n, z = somaZ / n,
                 band = bandaDe(somaY / n) },
      hand   = { x = maoX, y = maoY, z = maoZ, band = bandaDe(maoY),
                 reach = maoDist },
    }
  end
  return mesh
end

local function frameBounds(m, frame)
  if frame < 0 or frame >= m.frames then return nil end
  local minX, maxX, minY, maxY = m.cellW, -1, m.cellH, -1
  for ly = 0, m.cellH - 1 do
    for lx = 0, m.cellW - 1 do
      if frameTexel(m, frame, lx, ly) then
        if lx < minX then minX = lx end
        if lx > maxX then maxX = lx end
        if ly < minY then minY = ly end
        if ly > maxY then maxY = ly end
      end
    end
  end
  if maxX < minX or maxY < minY then return nil end
  return { minX = minX, maxX = maxX, minY = minY, maxY = maxY }
end

local function carvedFrames(frame, frames)
  frame = tonumber(frame) or 0
  if frame < 0 or frame >= frames then frame = 0 end
  -- DECISION: Gen 1 sprites use buckets of three views: standing
  -- down/up/left and, when it exists, walking down/up/left. The audit
  -- counted 20/73 sprites with only three frames; they have all three
  -- views complete and should use CARVED. Frames above 5 explicitly fall
  -- into the bucket of three so a future frame does not silently become
  -- an invalid role.
  local bucketFrame = frame
  if bucketFrame > 5 then bucketFrame = bucketFrame % 3 end
  local pose = (bucketFrame >= 3 and frames >= 6) and 3 or 0
  local role = bucketFrame - pose
  return {
    front = pose,
    back = pose + 1,
    side = pose + 2,
    role = role,
  }
end

local function buildCarvedMesh(def, frame, depth, correction, m, sideColor, shape,
                               groundShade)
  -- Moved from chunk scope (roadmap item 0: main chunk locals): only read
  -- here.
  --
  -- TWO VOXEL COLUMNS, counted in SHEET pixels, so it scales with the cell for
  -- the same reason DEPTH and BODY_SEARCH_LIMIT do. Left alone, CARVED+'s
  -- recess on a 64 px sheet would be a quarter as deep as on the ROM's, which
  -- is the option quietly doing a quarter of its job rather than failing.
  -- Found by auditing for this shape of constant after Kim asked whether the
  -- OTHER options still apply correctly under HD -- not by anyone seeing it.
  local CARVED_PLUS_RECESS_STEPS = 2
  m = m or maskFor(def)
  if not (m and m.frames >= 3) then return nil end
  local hdK = hdCellScale(m)
  if hdK then
    CARVED_PLUS_RECESS_STEPS =
      math.floor(CARVED_PLUS_RECESS_STEPS * hdK + 0.5)
  end
  local pose = carvedFrames(frame, m.frames)
  if pose.back >= m.frames or pose.side >= m.frames then return nil end
  local carvedPlus = shape == "carved_plus"

  local frontBounds = frameBounds(m, pose.front)
  local backBounds = frameBounds(m, pose.back)
  local sideBounds = frameBounds(m, pose.side)
  if not (frontBounds and backBounds and sideBounds) then return nil end
  local widthFrame = pose.front
  local widthBounds = frontBounds
  local widthFrameA, widthFrameB = referenceFramesForRole(frame, m.frames,
    0)
  -- FIX for the top-flickering-while-walking defect, now in CARVED
  -- (v1.4.2): topUv has the same reference-frame lookup structure SLAB
  -- had, and the same defect (reads lx, ly at the current frame's
  -- coordinate, without compensating for the step). Compensation enters
  -- here, once per mesh, comparing pose.front (ALWAYS role 0, this
  -- sheet's front view) against the reference (also always role 0), never
  -- the raw `frame` the function receives: `frame` can be role 1 or role
  -- 2, and comparing the front mask against one of a different role would
  -- measure silhouette difference, not step displacement (poseOffset
  -- already refuses and returns 0,0 if the roles do not match, but the
  -- caller has to ask for the right comparison to begin with). Computed
  -- here, in texture space, before any per-role rotation in p(): the
  -- compensation never enters geometry space.
  local widthOffsetAX, widthOffsetAY = poseOffset(m, pose.front, widthFrameA)
  local widthOffsetBX, widthOffsetBY = 0, 0
  if widthFrameB then
    widthOffsetBX, widthOffsetBY = poseOffset(m, pose.front, widthFrameB)
  end

  local verts, idx = {}, {}
  local pitchC, pitchS = math.cos(correction or 0), math.sin(correction or 0)
  local cellBottom = m.cellH - 1
  local depthPixels = sideBounds.maxX - sideBounds.minX + 1
  local frontFrameA = 0
  local frontFrameB = m.frames >= 6 and 3 or nil
  local sideLineRecess = {}

  local function mirrorX(lx)
    -- FIX for defect A (CARVED, v1.3.0): the intersection mirror and the
    -- per-role rotation derive from the same cell axis.
    return (m.cellW - 1) - lx
  end

  local function frontXFor(lx)
    return lx
  end

  local function backXFor(lx)
    return mirrorX(lx)
  end

  local function frameLuma(frameIndex, lx, ly)
    if not frameIndex then return nil end
    if lx < 0 or lx >= m.cellW or ly < 0 or ly >= m.cellH then return nil end
    if frameIndex < 0 or frameIndex >= m.frames then return nil end
    local fx, fy = frameOrigin(m, frameIndex)
    local r, g, b, a = pixelAt(m.data, fx + lx, fy + ly)
    if not r or (a or 0) < 0.5 then return nil end
    return luminance(r, g, b)
  end

  local function maxRecessForLine(ly)
    if sideLineRecess[ly] ~= nil then return sideLineRecess[ly] end
    local farthest = -1
    for sx = sideBounds.minX, sideBounds.maxX do
      if frameTexel(m, pose.side, sx, ly) then
        farthest = math.max(farthest, sx - sideBounds.minX)
      end
    end
    local limit = math.max(0, math.min(CARVED_PLUS_RECESS_STEPS, farthest))
    sideLineRecess[ly] = limit
    return limit
  end

  local reliefMinLuma, reliefMaxLuma
  if carvedPlus then
    if m.reliefScanned then
      reliefMinLuma, reliefMaxLuma = m.reliefMinLuma, m.reliefMaxLuma
    else
      local function scanReliefFrame(frameIndex)
        if not frameIndex then return end
        for ly = 0, m.cellH - 1 do
          for lx = 0, m.cellW - 1 do
            local luma = frameLuma(frameIndex, lx, ly)
            if luma and not (m.outlineLuma
                and math.abs(luma - m.outlineLuma) <= SHARED.LUMA_EPSILON) then
              reliefMinLuma = reliefMinLuma and math.min(reliefMinLuma, luma) or luma
              reliefMaxLuma = reliefMaxLuma and math.max(reliefMaxLuma, luma) or luma
            end
          end
        end
      end
      scanReliefFrame(frontFrameA)
      scanReliefFrame(frontFrameB)
      if not reliefMinLuma then
        for ly = 0, m.cellH - 1 do
          for lx = 0, m.cellW - 1 do
            local luma = frameLuma(frontFrameA, lx, ly) or frameLuma(frontFrameB, lx, ly)
            if luma then
              reliefMinLuma = reliefMinLuma and math.min(reliefMinLuma, luma) or luma
              reliefMaxLuma = reliefMaxLuma and math.max(reliefMaxLuma, luma) or luma
            end
          end
        end
      end
      m.reliefScanned = true
      m.reliefMinLuma, m.reliefMaxLuma = reliefMinLuma, reliefMaxLuma
    end
  end

  -- DECISION: side frame 2 is the character looking left. On Gen 1 sheets
  -- that left edge is the face. That is why the leftmost opaque column of
  -- the side view sits at z = 0, and the following columns walk toward
  -- negative z, toward the back of the head. On red.png the measured torso
  -- is 14 columns from the front and 11 from the side; the side's full
  -- opaque box has 13 columns because it includes pixels outside the
  -- torso. In both cases, depth comes from the art, not from a slab
  -- slider.
  --
  -- DECISION: v1.2.1 added the back silhouette to the intersection. Since
  -- front and back are opposite views, the back view's X column enters
  -- mirrored; without that mirror the hull loses almost everything on
  -- asymmetric sprites. The axis cannot come from the sheet's global
  -- bbox: Kim measured 12/40 six-frame sheets where the side view widens
  -- that bbox (biker 0..15 versus front 1..14; bird 0..15 versus 2..13;
  -- brunette_girl and cooltrainer_f 1..15 versus 2..13), clipping 3% to 8%
  -- of legitimate voxels on 7/8 audited sprites. It also cannot diverge
  -- from the axis used by the per-role rotation: since v1.3.0 the geometry
  -- is anchored to the cell, so the front/back texture mirror uses the
  -- same cell axis to avoid leaking outside the card on asymmetric
  -- sheets. On role 1 that mirror cannot flip the hull's logical space a
  -- second time: p() already transforms lx into m.cellW - x to present the
  -- back view. Mirroring here too would validate opacity on one column and
  -- draw on another.
  --
  -- DECISION: CARVED+ recesses the front surface by tone in only 2 steps.
  -- red.png has 3 opaque body tones besides the outline; more steps would
  -- only fake a precision the art does not have. The same art uses tone
  -- both for outline and for volume: where the artist darkened just to
  -- separate the hat from the forehead, the relief turns into a groove.
  -- That is why it is its own step, not the default. The recess is also
  -- limited by each side line's real depth: at least one layer always
  -- remains, because a thin sprite from an external mod cannot turn into a
  -- hole going through the character.
  local function solid(lx, ly, sx)
    if lx < widthBounds.minX or lx > widthBounds.maxX then return false end
    if ly < widthBounds.minY or ly > widthBounds.maxY then return false end
    if sx < sideBounds.minX or sx > sideBounds.maxX then return false end
    local frontX = frontXFor(lx)
    if not frameTexel(m, pose.front, frontX, ly) then return false end
    if not frameTexel(m, pose.back, backXFor(lx), ly) then return false end
    if not frameTexel(m, pose.side, sx, ly) then return false end
    if carvedPlus and reliefMinLuma and reliefMaxLuma
        and reliefMaxLuma > reliefMinLuma + SHARED.LUMA_EPSILON then
      local luma = frameLuma(frontFrameA, frontX, ly)
        or frameLuma(frontFrameB, frontX, ly)
      if luma then
        local dark = (reliefMaxLuma - luma) / (reliefMaxLuma - reliefMinLuma)
        local recess = math.max(0, math.min(maxRecessForLine(ly),
          math.floor(dark * CARVED_PLUS_RECESS_STEPS + 0.5)))
        if (sx - sideBounds.minX) < recess then return false end
      end
    end
    return true
  end

  local function uvFor(frameIndex, lx, ly)
    local fx, fy = frameOrigin(m, frameIndex)
    return (fx + lx + 0.5) / m.sheetW, (fy + ly + 0.5) / m.sheetH
  end

  local function sameUv(frameIndex, lx, ly)
    local u, v = uvFor(frameIndex, lx, ly)
    return { u, v, u, v, u, v, u, v }
  end

  local function opaqueFrame(preferred, fallback, lx, ly)
    if frameTexel(m, preferred, lx, ly) then return preferred end
    if fallback and frameTexel(m, fallback, lx, ly) then return fallback end
    return preferred
  end

  local function bodyTexel(frameIndex, lx, ly, dx, dy)
    return bodyTexelInFrame(m, frameIndex, lx, ly, dx, dy, sideColor)
  end

  local sideFrameA, sideFrameB = referenceFramesForRole(frame, m.frames, 2)
  -- v1.4.2: same logic as widthOffsetA/B above, but for the side. pose.side
  -- is ALWAYS role 2 (this sheet's profile view), same as sideFrameA/B;
  -- the comparison stays profile-against-profile, never
  -- front-against-profile.
  local sideOffsetAX, sideOffsetAY = poseOffset(m, pose.side, sideFrameA)
  local sideOffsetBX, sideOffsetBY = 0, 0
  if sideFrameB then
    sideOffsetBX, sideOffsetBY = poseOffset(m, pose.side, sideFrameB)
  end

  local function sideUv(sx, ly)
    local middle = (sideBounds.minX + sideBounds.maxX) / 2
    local dx = sx <= middle and 1 or -1
    -- DECISION: the side shell has to have a stable classification across
    -- frames. On red.png, 161/378 side positions alternated body/outline
    -- because the mesh came from the combined silhouette, but the color
    -- search only looked at the current frame. We search once among the
    -- sheet's side views and fix the first opaque texel found; that way
    -- walking does not swap red for black at the same face position.
    --
    -- v1.4.2: `sx, ly` compensated by the displacement between pose.side
    -- and the reference frame before reading the body, with the same
    -- degradation as topUv: compensated, then uncompensated, then the
    -- usual fallbacks.
    local function tryFrame(sideFrame, pdx, pdy)
      if not sideFrame then return nil end
      local bx, by = bodyTexel(sideFrame, sx + pdx, ly + pdy, dx, 0)
      if frameTexel(m, sideFrame, bx, by) then
        return sameUv(sideFrame, bx, by)
      end
      bx, by = bodyTexel(sideFrame, sx, ly, dx, 0)
      if frameTexel(m, sideFrame, bx, by) then
        return sameUv(sideFrame, bx, by)
      end
    end
    local uv = tryFrame(sideFrameA, sideOffsetAX, sideOffsetAY)
      or tryFrame(sideFrameB, sideOffsetBX, sideOffsetBY)
    if uv then return uv end
    return sameUv(pose.side, sx, ly)
  end

  local function topUv(lx, ly, dy)
    -- DECISION: top/bottom need fixed classification like the sides. The
    -- bug measured on red.png came from using the current frame: 49/180
    -- top face positions alternated standing/walking, 14 of them in the
    -- hat's top 6 rows. The direct cause is row 0 existing in frame 0
    -- (".....######.....") and disappearing in frame 3, because the whole
    -- sprite shifts down a row while walking. Trying the reference view and
    -- only falling back to the walking one fixes the face's color to the
    -- same logical texel wherever there is opacity.
    --
    -- v1.4.2: `lx, ly` compensated by the displacement between pose.front
    -- and the reference frame (widthOffsetA/B, computed once above) before
    -- reading the body; if the compensated coordinate falls outside the
    -- cell or finds no opaque body in the reference frame, it degrades to
    -- the uncompensated coordinate before falling into the fallbacks that
    -- already existed.
    local function tryFrame(frameIndex, pdx, pdy)
      if not frameIndex then return nil end
      local bx, by = bodyTexel(frameIndex, lx + pdx, ly + pdy, 0, dy)
      if frameTexel(m, frameIndex, bx, by) then
        return sameUv(frameIndex, bx, by)
      end
      bx, by = bodyTexel(frameIndex, lx, ly, 0, dy)
      if frameTexel(m, frameIndex, bx, by) then
        return sameUv(frameIndex, bx, by)
      end
    end
    local uv = tryFrame(widthFrameA, widthOffsetAX, widthOffsetAY)
      or tryFrame(widthFrameB, widthOffsetBX, widthOffsetBY)
    if uv then return uv end
    return sameUv(widthFrame, lx, ly)
  end

  local function p(x, y, z)
    local ox, oz = x, z
    if pose.role == 1 then
      ox, oz = m.cellW - x, -depthPixels - z
    elseif pose.role == 2 then
      -- DECISION: the side role also needs to compensate for the pivot.
      -- Without this, red.png measured on the real main.lua went from Y
      -- [0, 13] at the front to Y [-14, 0] at the side: the positive z
      -- entered the lean's counter-rotation as vertical displacement and
      -- half the directions sank into the ground. The compensation keeps
      -- the volume at non-positive z, like front and back. Since v1.3.0 X
      -- also preserves the cell's padding; that is why the axis coming
      -- from the side view adds sideBounds.minX back, while the depth axis
      -- rotates around the cell's width.
      ox, oz = sideBounds.minX - z, x - m.cellW
    end
    return { ox, y * pitchC - oz * pitchS, y * pitchS + oz * pitchC, y }
  end

  local function quad(c1, c2, c3, c4, uv4, shade)
    local n = #verts / 4
    local function add(corner, u, v)
      verts[#verts + 1] = {
        corner[1], corner[2], corner[3], u, v,
        shadeAtHeight(shade, corner[4], groundShade, hdK),
      }
    end
    add(c1, uv4[1], uv4[2])
    add(c2, uv4[3], uv4[4])
    add(c3, uv4[5], uv4[6])
    add(c4, uv4[7], uv4[8])
    Voxel3D.pushQuad(idx, n)
  end

  for ly = m.minY, m.maxY do
    for lx = widthBounds.minX, widthBounds.maxX do
      for sx = sideBounds.minX, sideBounds.maxX do
        if solid(lx, ly, sx) then
          local x0, x1 = lx, lx + 1
          local y0, y1 = cellBottom - ly, cellBottom - ly + 1
          local z0 = -(sx - sideBounds.minX)
          local z1 = z0 - 1

          if not solid(lx, ly, sx - 1) then
            quad(p(x0, y0, z0), p(x1, y0, z0), p(x1, y1, z0),
                 p(x0, y1, z0), sameUv(opaqueFrame(pose.front, widthFrame, lx, ly), lx, ly),
                 SHARED.OBJ_SHADE.front)
          end
          if not solid(lx, ly, sx + 1) then
            quad(p(x1, y0, z1), p(x0, y0, z1), p(x0, y1, z1),
                 p(x1, y1, z1), sameUv(opaqueFrame(pose.back, widthFrame, lx, ly), lx, ly),
                 SHARED.OBJ_SHADE.back)
          end
          if not solid(lx - 1, ly, sx) then
            quad(p(x0, y0, z1), p(x0, y0, z0), p(x0, y1, z0),
                 p(x0, y1, z1), sideUv(sx, ly), SHARED.OBJ_SHADE.side)
          end
          if not solid(lx + 1, ly, sx) then
            quad(p(x1, y0, z0), p(x1, y0, z1), p(x1, y1, z1),
                 p(x1, y1, z0), sideUv(sx, ly), SHARED.OBJ_SHADE.side)
          end
          if not solid(lx, ly - 1, sx) then
            quad(p(x0, y1, z1), p(x1, y1, z1), p(x1, y1, z0),
                 p(x0, y1, z0), topUv(lx, ly, 1), SHARED.OBJ_SHADE.top)
          end
          if not solid(lx, ly + 1, sx) then
            quad(p(x0, y0, z0), p(x1, y0, z0), p(x1, y0, z1),
                 p(x0, y0, z1), topUv(lx, ly, -1), SHARED.OBJ_SHADE.bottom)
          end
        end
      end
    end
  end

  return Voxel3D.newMesh(escalaParaTile(verts, m), idx)
end

local function buildSelectedMesh(def, frame, depth, correction, m, sideColor, shape,
                                 groundShade, baseName, topEdge, frontShape,
                                 topDome, stepWeight)
  if shape == "carved" or shape == "carved_plus" then
    local ok, mesh = pcall(buildCarvedMesh, def, frame, depth, correction, m,
      sideColor, shape, groundShade)
    if ok and mesh then return mesh end
  end
  return buildSlabMesh(def, frame, depth, correction, m, sideColor, groundShade,
    baseName, topEdge, frontShape, topDome, stepWeight)
end

-- FRONT SHAPE, TOP DOME and STEP WEIGHT, like TOP EDGE, only exist for
-- SLAB: CARVED/CARVED+ build from the visual voxel hull, without the
-- continuous front run emitFrontRun steps, without the top run topShadeDomo
-- reads, and without the `p()` that applies STEP WEIGHT's shear. Outside
-- SLAB, the key ignores the strength on purpose, so it does not duplicate
-- identical meshes just because the menu switched level.
local function cacheKey(def, frame, depth, correction, layout, sideColor, shape,
                        groundShade, topEdge, frontShape, topDome, stepWeight)
  local depthPart = (shape == "carved" or shape == "carved_plus") and "art"
    or tostring(depth)
  local topEdgePart = shape == "slab" and tostring(topEdge or "") or ""
  local frontShapePart = shape == "slab" and tostring(frontShape or "") or ""
  -- The key MUST include the dome's strength, same pattern as FRONT SHAPE:
  -- without this, touching the menu changes nothing on screen until the
  -- LRU happens to recycle it, exactly the defect Colonel_Aureliano
  -- reported in v1.4.0.
  local topDomePart = shape == "slab" and tostring(topDome or "") or ""
  -- Same requirement from this round's spec ("the cache key needs to
  -- include the strength"), same reason as TOP DOME right above.
  local stepWeightPart = shape == "slab" and tostring(stepWeight or "") or ""
  -- AUTHORED REGIONS CHANGES THE VERTEX ORDER, so it has to be in the key for
  -- the same reason TOP DOME and STEP WEIGHT are. Without it, toggling the
  -- option would leave every already-built mesh cut the old way until the LRU
  -- happened to recycle it: the menu would appear to do nothing, which is
  -- exactly the defect Colonel_Aureliano reported in v1.4.0.
  --
  -- Read from optionState rather than passed in, because it is not one of the
  -- things buildSlabMesh's caller resolves, and threading a thirteenth
  -- parameter through for a boolean is how signatures rot.
  local authoredPart = tostring(optionState.authored_regions or "")
  -- HD changes every vertex in the mesh, so it belongs in the key for exactly
  -- the reason TOP DOME and STEP WEIGHT do: without it, toggling the option
  -- leaves already-built characters as they were until the LRU happens to evict
  -- them, and the menu appears to do nothing.
  -- BLINK DETECT CUTS THE FRONT RUN, so it changes the vertex list and belongs
  -- here for exactly the reason AUTHORED REGIONS and HD SPRITE do. It was left
  -- out of the first version and the in-game gate caught it: `clears = "mesh"`
  -- empties the cache on the menu edge, but a mesh the game rebuilds a frame
  -- later at the old key is indistinguishable from one built at the new one, so
  -- whether the eyes appeared depended on whether the LRU had recycled that
  -- entry -- the option worked or did nothing depending on how many characters
  -- were on screen. Colonel_Aureliano's v1.4.0 defect, one option later.
  local blinkDetectPart = tostring(optionState.blink_detect or "")
  local hdPart = tostring(optionState.hd_sprite or "")
  return table.concat({
    tostring(def and def.image or ""),
    tostring(def and def.frames or ""),
    tostring(frame or 0),
    depthPart,
    tostring(sideColor or ""),
    tostring(shape or ""),
    tostring(groundShade or ""),
    topEdgePart,
    frontShapePart,
    topDomePart,
    stepWeightPart,
    authoredPart,
    blinkDetectPart,
    hdPart,
    tostring(layout and layout.cellW or ""),
    tostring(layout and layout.cellH or ""),
    tostring(layout and layout.columns or ""),
    pitchKey(correction),
  }, "#")
end

-- FIX for defect 3 (SLAB and CARVED, v1.3.0; runs before either of the
-- two gets chosen): the host's shader moves every vertex toward the eye
-- when FirstPerson.cardBlend() > 0 (Voxel3D.lua:122-130, sent at
-- :1296-1307). On a flat card that is projectively stable; on a solid
-- volume, each corner moves in a different direction, and combined with
-- the first-person camera, which sits at the sprite's head with a short
-- near plane (FirstPerson.lua:63-75, Voxel3D.lua:518-519), it crosses the
-- near plane and produces black spikes (Colonel_Aureliano, Dramatic Shape
-- 1.7.0 + Kanto First Person, a manifest conflict field cleaned by hand).
-- This mod's contract is explicit: every failure path falls back to the
-- original flat card, never a body with spikes. In a pcall like
-- leanCorrection already does (main.lua:418-421), because FirstPerson may
-- not exist in every supported host version; absence = zero blend =
-- current behavior. We do not try to compensate for rotateY: the host also
-- swaps the requested frame for a continuous apparent direction in first
-- person (VoxelScene.lua:234-241) and documents the first-person card as a
-- cylindrical billboard; a solid should not inherit that contract. This
-- does not become a menu option: it is not an aesthetic choice, it is the
-- clean-failure contract.
local function firstPersonCardActive()
  if not (FirstPerson and FirstPerson.cardBlend) then return false end
  local ok, blend = pcall(FirstPerson.cardBlend)
  return ok and tonumber(blend) ~= nil and tonumber(blend) > 0
end

local originalMeshWarned = false

local function warnOriginalMeshFailure(reason)
  if originalMeshWarned then return end
  originalMeshWarned = true
  mod.log:warn(
    "dropped a character billboard because the original mesh call failed: %s",
    tostring(reason))
end

-- FIX for the "a third-party mod takes down voxel mode for the whole
-- game" defect (v1.4.2): the host
-- (DramaticShapeVoxelMod/lib/SpriteBillboards.lua:65) does `def.image ..
-- "#" .. frame` with no type guard; a nil `frame` coming from ANY entity
-- mod throws there. The host is called by VoxelScene.lua:368, inside the
-- draw loop, with no pcall; the exception rises up to Pipelines.lua, which
-- marks the whole mod as broken for the entire session (AngelusRole: had
-- to disable Wilds of Kanto for our mod to start working again). A single
-- entity with a bad pose, a single frame, turns off voxel mode for the
-- whole game until restart. None of our paths that call the original may
-- let that exception escape; that is why EVERY caller of `originalMesh`
-- goes through here, never calls `originalMesh` directly.
local function safeOriginal(def, frame)
  local ok, mesh = pcall(originalMesh, def, frame)
  if ok then return mesh end
  warnOriginalMeshFailure(mesh)
  return nil
end

-- v1.4.2, fine-tooth comb (items 1 and 2): pushes a result into the
-- sliding window. `kind` is nil for success, or the failure type
-- (mask_failed, build_failed, exception) for failure. Keeps
-- drawWindowFailures and drawWindowKindCounts correct without scanning the
-- array: if the slot being overwritten was a failure, it removes it from
-- both counts before writing the new value on top.
local function pushDrawWindow(kind)
  local slot = (drawWindowPos % SHARED.DRAW_WINDOW_SIZE) + 1
  local old = drawWindow[slot]
  if old then
    drawWindowFailures = drawWindowFailures - 1
    drawWindowKindCounts[old] = drawWindowKindCounts[old] - 1
  end
  drawWindow[slot] = kind
  if kind then
    drawWindowFailures = drawWindowFailures + 1
    drawWindowKindCounts[kind] = (drawWindowKindCounts[kind] or 0) + 1
  end
  drawWindowPos = drawWindowPos + 1
end

-- v1.4.2, TwoTracks: records a successful draw (or an intentional path,
-- DEPTH: OFF or first person) in the window.
local function recordDrawResult(kind)
  lastDrawResult = kind
  pushDrawWindow(nil)
end

-- v1.4.2, TwoTracks: records a draw failure in the window and logs the
-- cause, once per DISTINCT cause (key = type + message), never per frame.
-- Different causes (two sheets broken in different ways) each log once;
-- the SAME cause repeating (the same bad sheet every time) logs only
-- once.
local function recordDrawFailure(kind, message)
  lastDrawResult = kind
  pushDrawWindow(kind)
  local causeKey = kind .. ": " .. tostring(message)
  if not warnedDrawCauses[causeKey] then
    warnedDrawCauses[causeKey] = true
    mod.log:warn("voxel mesh %s: %s", kind, tostring(message))
  end
end

-- v1.4.2, fine-tooth comb (item 2): the window's DOMINANT cause, not the
-- most recent one. Only swaps the best candidate when the count is
-- strictly greater, so a tie breaks by the fixed order below
-- (deterministic), never by the order the failures arrived in.
local function dominantFailureKind()
  -- Moved from chunk scope (roadmap item 0: main chunk locals): only read
  -- here.
  local DRAW_FAILURE_KIND_PRIORITY = { "mask_failed", "build_failed", "exception" }
  local bestKind, bestCount = nil, 0
  for _, kind in ipairs(DRAW_FAILURE_KIND_PRIORITY) do
    local count = drawWindowKindCounts[kind] or 0
    if count > bestCount then
      bestKind, bestCount = kind, count
    end
  end
  return bestKind
end

local function warnReplacedMesh()
  if warnedReplacedMesh then return end
  warnedReplacedMesh = true
  mod.log:warn("SpriteBillboards.mesh is no longer the function this mod " ..
    "installed; another mod replaced it after patching")
end

-- v1.4.2, AngelusRole/Tyler Durden/TwoTracks: the STATUS row exists
-- because none of the three reports had a way to know, just by looking at
-- the game, why characters were not drawing as voxel. Precedence order
-- (Kim): NO HOST and REPLACED first, they are patch states and apply to
-- every draw; DEPTH: OFF and first person by live state read, because
-- they are uniform choices that apply to the whole frame, not per sprite;
-- only then the failure proportion in the sliding window of the last
-- SHARED.DRAW_WINDOW_SIZE draws, which only escalates to an error when HALF OR
-- MORE of the window is failures (item C: a single bad sheet, isolated or
-- interleaved with good sheets, cannot leave STATUS stuck at error).
local function statusValue()
  -- Moved from chunk scope (roadmap item 0: main chunk locals): only read
  -- here.
  local STATUS_FAILURE_LABELS = {
    mask_failed = "MASK ERROR",
    build_failed = "BUILD ERROR",
    exception = "DRAW ERROR",
  }
  -- v1.4.2, fine-tooth comb: `patched`, never `SpriteBillboards ~= nil`. A
  -- patch that started but did not finish (host table refused a write)
  -- never gets to mark `patched`, so this still reads NO HOST instead of
  -- REPLACED, even if `SpriteBillboards` had been set too early in an
  -- earlier version of this code.
  if not patched then return "NO HOST" end
  if SpriteBillboards.mesh ~= installedMesh then
    warnReplacedMesh()
    return "REPLACED"
  end
  if (optionState.depth or readOption(OPTION_BY_KEY.depth)) == "off" then return "OFF" end
  -- Intentional, not a defect: in CARD we return the original card on
  -- purpose in first person (see the first_person option and
  -- fpPullSeguro). In SOLID none of this happens and the row must not lie
  -- by saying it did.
  if firstPersonCardActive() then
    local fp = optionState.first_person or readOption(OPTION_BY_KEY.first_person)
    if fp ~= "solid" or installedDraw == nil then return "FIRST PERSON" end
  end
  if drawWindowFailures * 2 >= SHARED.DRAW_WINDOW_SIZE then
    return STATUS_FAILURE_LABELS[dominantFailureKind()] or "ACTIVE"
  end
  return "ACTIVE"
end

-- AN EMPTY `activate` IS NOT DECORATION, it is the fix for a real defect.
--
-- OptionsMenu:update (src/ui/OptionsMenu.lua:549-566) handles A, left and
-- right in the same branch, and picks what to do in this order: if the
-- row has `activate`, call it; else, if it has `step`, cycle it; ELSE, if
-- it was A, treat it as CANCEL and POP THE MENU. A read-only row, with
-- `value` and neither of the other two, falls into that third case:
-- pressing A over STATUS closed the whole options screen, as if the
-- player had chosen to exit.
--
-- And A is the key a person presses first when they want to understand a
-- row they do not recognize, which is exactly the situation the STATUS
-- row was created for. An `activate` that does nothing keeps the cursor
-- where it was, which is the right behavior for a row that only informs.
--
-- Found by independent review reading the engine, not by a test of ours:
-- no gate here presses a key in the actual menu. See the tooling step for
-- the next version.
local function readOnlyRow(id, label, value)
  return {
    id = mod.id .. ":" .. id,
    label = label,
    value = value,
    activate = function() end,
  }
end

local function statusRow()
  return readOnlyRow("status", "STATUS", statusValue)
end

local warnedReplacedDraw = false

-- Same idea as the STATUS row, for the new channel. The three reports
-- that motivated STATUS (AngelusRole, TwoTracks, Tyler Durden) had in
-- common that there was no way to know, just by looking at the game, why
-- nothing was happening. A channel that depends on a SECOND point in the
-- host has even more ways to not happen, so it is born saying which one
-- it is at.
local function lifeStatusValue()
  if not patched then return "NO HOST" end
  if not drawPatched then return "NO CHANNEL" end
  if Voxel3D.draw ~= installedDraw then
    if not warnedReplacedDraw then
      warnedReplacedDraw = true
      mod.log:warn("Voxel3D.draw is no longer the function this mod " ..
        "installed; another mod replaced it after patching")
    end
    return "REPLACED"
  end
  if firstPersonCardActive() then
    local fp = optionState.first_person or readOption(OPTION_BY_KEY.first_person)
    if fp ~= "solid" then return "FIRST PERSON" end
  end
  local on = {}
  if optionState.breath ~= "off" then on[#on + 1] = "BREATH" end
  if optionState.sway ~= "off" then on[#on + 1] = "SWAY" end
  if optionState.lag ~= "off" then on[#on + 1] = "LAG" end
  if optionState.footfall ~= "off" then on[#on + 1] = "STEP" end
  if #on == 0 then return "OFF" end
  return table.concat(on, "+")
end

local function lifeStatusRow()
  return readOnlyRow("life", "LIFE", lifeStatusValue)
end

-- ====================================================== CAMERA PRESET

-- The current rung in degrees, the way the host measures it (0 lays the
-- card flat on the ground, 90 raises it). Returns nil when there is no way
-- to know, and then the row says so instead of guessing.
local function cameraRung()
  if not VoxelState then return nil end
  local ok, value = pcall(function() return VoxelState.angle end)
  if not ok then return nil end
  local rad = tonumber(value)
  if not rad then return nil end
  return math.deg(rad)
end

local function presetParaAgora()
  -- Moved from chunk scope (roadmap item 0: main chunk locals): only read
  -- here.
  --
  -- MEASURED, not chosen. The harness rendered the red frame 0 at every
  -- host camera rung against every menu thickness, and counted what
  -- fraction of the drawn pixels come from the artist's art (front and back
  -- faces) versus surface this mod invented (top, sides, bottom):
  --
  --                 rung 15   rung 35   rung 50   rung 75
  --     depth  1     76.3      88.4      92.8      97.6
  --     depth  2     62.2      80.0      86.9      95.5
  --     depth  3     52.4      73.4      81.6      93.3
  --     depth  5     40.1      62.9      73.8      89.1
  --     depth 10     26.0      49.6      62.1      81.0
  --
  -- The criterion was not invented: it is what IS ALREADY THE DEFAULT. rung
  -- 35 with depth 3 gives 73.4% art, and that is the configuration the
  -- community has seen, used and approved. So for every rung the
  -- recommendation is the largest thickness that still stays at that level.
  -- Out comes 1, 3, 5, 10, and the monotonicity is a consequence of the
  -- table, not a rounding of ours.
  --
  -- THE INTERESTING RESULT: with these thicknesses the composition stays
  -- nearly constant at every rung (art between 73 and 81%). A more level
  -- camera looks more toward the top, and the preset compensates for
  -- exactly that by removing thickness. That is why it does NOT touch FRONT
  -- SHAPE or TOP DOME: once the thickness is right, the ratio between the
  -- front face and the top one is already the same everywhere, so there is
  -- no measured reason to vary the shading along with it.
  --
  -- And the reverse also holds: at rung 75 you can use the menu's MAXIMUM
  -- thickness and still have more art on screen than today's default
  -- configuration has. Anyone playing at that camera is leaving volume on
  -- the table without knowing it.
  local CAMERA_PRESET = {
    { rung = 15, depth = 1 },
    { rung = 35, depth = 3 },
    { rung = 50, depth = 5 },
    { rung = 75, depth = 10 },
  }
  local graus = cameraRung()
  if not graus then return nil end
  local melhor, distancia = nil, math.huge
  for _, entrada in ipairs(CAMERA_PRESET) do
    local d = math.abs(entrada.rung - graus)
    if d < distancia then melhor, distancia = entrada, d end
  end
  return melhor, graus
end

-- An ACTION row, not a cycling one. Pressing A applies it; left and right
-- do nothing. It is deliberate that it is not automatic: the mod changing
-- someone's choice on its own every time the person switches camera is
-- the same family of defect as A on a read-only row closing the menu,
-- that is, doing what nobody asked for. Here the person asks, sees the
-- value change in the VOXEL CHARS row right below, and the save stores
-- what they chose.
local function cameraPresetRow()
  return {
    id = mod.id .. ":camera_preset",
    label = "CAMERA FIT",
    value = function()
      local entrada, graus = presetParaAgora()
      if not entrada then return "NO CAMERA" end
      local atual = optionState.depth
      if atual == entrada.depth then
        return string.format("OK AT %d", math.floor(graus + 0.5))
      end
      return string.format("SET DEPTH %d", entrada.depth)
    end,
    activate = function(game)
      local entrada = presetParaAgora()
      if not entrada then return end
      local opt = OPTION_BY_KEY.depth
      local valor = setOption(opt, entrada.depth)
      writeOption(game, opt.key, valor)
    end,
  }
end

-- WHOLE SETTINGS AT ONCE, because a menu with twenty one rows is a menu nobody
-- reconfigures twice. Cycle the name with left/right, press A to apply.
--
-- LIVED IN IS NOT INVENTED. It is read off Kim's own save, after he played with
-- the menu until he stopped changing things and said those were the best
-- defaults. Four of its choices are not the mod's defaults -- SIDE COLOR:
-- OUTLINE, TOP EDGE: OFF, BREATH: NORMAL, FRONT SHAPE: MED -- and that
-- disagreement is exactly what makes it worth shipping: it is a taste somebody
-- arrived at by looking, not a table somebody reasoned out.
--
-- The other two are for a JOB rather than a taste, which is why they are not
-- "more" and "less" of the same thing:
--   STILL      nothing moves. For judging shape, and for any comparison where
--              motion would swamp the thing being compared -- the clip tool's
--              own guard fails on animated scenes for exactly that reason.
--   SHOWCASE   every motion on at a level that reads on video without looking
--              like a puppet. For recording, not for playing.
--
-- Applying one writes every key it names, so a preset always lands you in a
-- KNOWN state rather than merging with whatever was set before. Keys it does
-- not name are left alone on purpose: HD SPRITE and DEMO FX are experiments,
-- and a preset that silently switched an experiment on would be a preset
-- nobody trusts.
local SETTINGS_PRESETS = {
  { nome = "DEFAULT", valores = nil },
  { nome = "LIVED IN", valores = {
      depth = 3, side_color = "outline", shape = "slab", ground_shade = "on",
      blink = "on", top_edge = "off", front_shape = 0.17, top_dome = "off",
      step_weight = 0.25, breath = 0.020, sway = 0.20, lag = "off",
      footfall = 0.35, attention = "off", first_person = "card",
    } },
  { nome = "STILL", valores = {
      breath = "off", sway = "off", lag = "off", footfall = "off",
      attention = "off", grid_chars = "off",
    } },
  { nome = "SHOWCASE", valores = {
      depth = 3, side_color = "body", shape = "slab", ground_shade = "on",
      blink = "on", top_edge = "on", front_shape = 0.17, top_dome = "off",
      step_weight = 0.25, breath = 0.020, sway = 0.20, lag = 0.6,
      footfall = 0.35, attention = 0.5, first_person = "solid",
    } },
}

local presetEscolhido = 1

local function settingsPresetRow()
  return {
    id = mod.id .. ":settings_preset",
    label = "SETTINGS",
    value = function()
      return SETTINGS_PRESETS[presetEscolhido].nome
    end,
    -- Left and right BROWSE, A APPLIES. Deliberately not "changing the value
    -- applies it": cycling past SHOWCASE on the way to STILL would otherwise
    -- rewrite every option twice on the way, and the person is only looking.
    step = function(_, dir)
      presetEscolhido = ((presetEscolhido + (dir or 1) - 1) % #SETTINGS_PRESETS) + 1
      return true
    end,
    activate = function(game)
      local escolha = SETTINGS_PRESETS[presetEscolhido]
      for _, opt in ipairs(OPTIONS) do
        local alvo
        if escolha.valores == nil then
          -- DEFAULT means the option's OWN declared default, read from the
          -- same table the menu builds itself from, so it cannot drift.
          alvo = opt.levels[opt.defaultIndex][2]
        else
          alvo = escolha.valores[opt.key]
        end
        if alvo ~= nil then
          local valor = setOption(opt, alvo)
          writeOption(game, opt.key, valor)
        end
      end
    end,
  }
end

-- v1.4.2: ALWAYS registered, with or without a host (Colonel_Aureliano
-- lost twenty minutes on a clean reinstall, and Angelus thought it was
-- Wilds of Kanto, because without a host the row would not even show up).
-- Without a host, only the STATUS row (saying NO HOST); with a host,
-- STATUS on top and the usual rows after, in the same order.
-- THE ROWS THAT LIVE INSIDE OUR OWN SCREEN.
--
-- Split out so both callers build the same list: the submenu shows it, and the
-- in-game menu gate can still count what a player can reach.
local function ourRows()
  local out = {}
  out[#out + 1] = statusRow()
  if patched then
    out[#out + 1] = lifeStatusRow()
    out[#out + 1] = cameraPresetRow()
    out[#out + 1] = settingsPresetRow()
    for _, opt in ipairs(OPTIONS) do
      -- The three life options only show up when the channel exists. A
      -- menu that offers BREATH on a host without a replaceable
      -- Voxel3D.draw promises what it cannot deliver, and that is
      -- exactly the experience the STATUS row was created to end.
      -- `held` KEEPS AN OPTION OUT OF THE MENU WITHOUT DELETING IT.
      --
      -- Kim looked at PART LAG on 2026-08-12 and said HIGH looks bad; LOW was
      -- then measured and does not clear the clip guard at all -- the sides
      -- differ from each other LESS than one side differs from itself, so the
      -- effect is smaller than the animation's own variation. An option whose
      -- only two levels are "looks wrong" and "invisible" is not a choice, it
      -- is a trap, so it does not ship.
      --
      -- Held rather than deleted, and that is deliberate. The code, the gates
      -- and the measurements around it are intact and cost a player nothing;
      -- deleting them would throw away a measured negative, which is a result.
      -- One word here brings it back.
      if not opt.held and not (LIFE_OPTION_KEYS[opt.key] and not drawPatched) then
        out[#out + 1] = makeOptionRow(opt)
      end
    end
  end
  return out
end

-- WHAT EACH OPTION DOES, IN THE GAME, which is where somebody wonders.
--
-- Every option has carried a `help` sentence since the option system was
-- written, and until now NOTHING SHOWED IT: it fed the documentation gate and
-- the README and stopped there. The player looking at a row called FRONT SHAPE
-- had no way to find out what it changes without leaving the game.
--
-- WHY A SCREEN AND NOT A TOOLTIP, since a tooltip is what was asked for. Modern
-- UI has one -- press SELECT and a description card opens -- but it is private
-- to Modern UI's OWN options screen: the handler requires
-- `screenId == "ManagerState"`, and the shared presenter it draws mod screens
-- with never reads a description or a footer from the row
-- (gen1_modern_ui/main.lua:3070). There is no field to fill in. Checked rather
-- than assumed, because filling in a field would have been the better answer.
--
-- Drawing our own card over Modern UI's panel was the alternative and it is
-- the bad one: we would be guessing at another mod's layout, in a mod we do not
-- ship, and it would look foreign the day that mod changed its theme.
--
-- A SCREEN IS SAFE ON BOTH, which answers the other half of the request -- Kim
-- asked to hide the tooltip without Modern UI "because it could break". A card
-- drawn over a 160x144 layout could. A screen of its own cannot: it is the same
-- shape as the submenu that opens it, and the native renderer already draws
-- exactly that. So it shows for everybody, and nobody gets a second-class menu.
local function helpRows()
  local out = {}
  for _, opt in ipairs(OPTIONS) do
    if not opt.held then
      -- The label is the row, the sentence is the value. On Modern UI the value
      -- column carries it; on the native renderer it lands on the row's second
      -- line, which is where the option's own value normally goes.
      local texto = opt.help or ""
      out[#out + 1] = {
        id = "voxel_characters:help_" .. opt.key,
        label = opt.label,
        value = function() return texto end,
      }
    end
  end
  return out
end

-- ONE ROW IN THE SHARED MENU, and everything else behind it.
--
-- This mod had grown to twenty rows in a list it shares with the game and with
-- every other mod. Kim asked for them gathered, and he is right for a second
-- reason he did not have to give: a submenu is where the host status can be
-- stated in full, which is the first thing anybody debugging this needs and the
-- last thing that fits on a shared list.
--
-- The pattern is PotatoVoxel's, at its main.lua:1047 -- register a screen, add a
-- row that pushes it. Borrowed rather than invented because it is already proven
-- against this engine, and the engine protects it: a mod screen that throws
-- degrades to the builtin instead of dead-ending the player
-- (src/ui/Screens.lua:46).
--
-- The screen reuses the game's own OptionsMenu and then swaps its row list for
-- ours. No drawing code, no input handling, and it inherits every future fix to
-- that menu. `self.rows` is a plain field on the instance (OptionsMenu.lua:539),
-- which is what makes the swap a two-line screen instead of a UI rewrite.
local function registerOptionsRows()
  if optionsRegistered then return end
  optionsRegistered = true
  -- GUARDED, because `mod.content` is not guaranteed to be there. The test
  -- harness's stub mod has no content registry at all, and neither would an
  -- older host: reaching for it directly threw at load time and took the whole
  -- mod down with it -- every option gone, not just the submenu.
  --
  -- A mod that dies because its NICE-TO-HAVE menu could not register is a mod
  -- that punishes the player for the engine's age. Without the registry the
  -- rows simply stay on the shared list, which is where they were until today.
  local temTela = false
  -- BOTH failure paths say something. The first version only logged when the
  -- register CALL threw, so a missing registry fell through silently and the
  -- rows quietly stayed on the shared list -- which looks exactly like the
  -- submenu never being written. The in-game gate caught it; the log did not.
  if not (mod.content and mod.content.screens and mod.content.screens.register) then
    mod.log:warn("no screen registry on this host (content=%s screens=%s); "
      .. "the options stay on the main list",
      tostring(mod.content ~= nil),
      tostring(mod.content and mod.content.screens ~= nil))
  end
  if mod.content and mod.content.screens and mod.content.screens.register then
    local ok, porque = pcall(function()
      -- THE NAME ENDS IN "Options" ON PURPOSE, and it is a contract with
      -- another mod rather than a style choice.
      --
      -- Modern UI restyles the whole game, and it adapts MOD option screens
      -- too -- but it recognises them semantically, by shape plus a name
      -- ending in `Options` or `Settings` (gen1_modern_ui/main.lua:2506,
      -- isOptionRowsScreen). Its author wrote that rule specifically so mods
      -- would not each need a special case, and named the reason: without it
      -- "their native 160x144 renderer" stays visible while the rest of the
      -- game is modern.
      --
      -- This screen used to be `VoxelCharsMenu`. It ended in "Menu", so it
      -- fell outside the rule and would have been the one un-restyled corner
      -- of a player's game. A five letter rename buys the whole design.
      -- Same suffix rule as the submenu, so Modern UI styles this one too.
      pcall(function()
        mod.content.screens:register("VoxelCharactersHelpOptions", {
          new = function(g)
            local ajuda = require("src.ui.OptionsMenu").new(g)
            ajuda.rows = helpRows()
            ajuda.index = 1
            ajuda.title = "WHAT EACH ONE DOES"
            return ajuda
          end,
        })
      end)
      mod.content.screens:register("VoxelCharactersOptions", {
        new = function(game)
          local tela = require("src.ui.OptionsMenu").new(game)
          local linhas = ourRows()
          -- ONLY WHERE THE TEXT CAN BE READ, which is Kim's condition and it
          -- turned out to be the right one for a reason neither of us had.
          --
          -- The help screen puts a whole sentence in the value column. Modern
          -- UI wraps it across as many lines as it needs. The native renderer
          -- draws one line inside a 160x144 box and would run it off the edge
          -- -- not a crash, just unreadable, which is worse than absent.
          --
          -- Matching on the id is admittedly brittle against a fork, so it
          -- matches any enabled mod whose id mentions a modern ui rather than
          -- one exact string. The failure is soft either way: no row.
          local moderno = false
          local carregados = game and game.mods and game.mods.mods
          if type(carregados) == "table" then
            for id, entrada in pairs(carregados) do
              if type(id) == "string" and id:lower():match("modern.?ui")
                and not (type(entrada) == "table" and entrada.enabled == false) then
                moderno = true
                break
              end
            end
          end
          -- LAST, not first. The rows above are what somebody came here to
          -- change; this one is what they read once and then never again.
          if moderno then
            linhas[#linhas + 1] = {
              id = "voxel_characters:help",
              label = "WHAT EACH ONE DOES",
              value = function() return "" end,
              activate = function(g)
                require("src.ui.Screens").push(g, "VoxelCharactersHelpOptions")
              end,
            }
          end
          tela.rows = linhas
          tela.index = 1
          -- Modern UI puts `state.title` above the panel and falls back to a
          -- table of known screen ids (gen1_modern_ui/main.lua:297); ours is not
          -- in that table, so without this the panel is headed "OPTIONS" -- true
          -- but useless next to the game's own OPTIONS the player just left.
          -- The native renderer draws no heading at all and ignores this.
          tela.title = "CHARACTERS"
          return tela
        end,
      })
    end)
    temTela = ok
    if not ok then
      mod.log:warn("could not register the CHARACTERS screen: %s; "
        .. "the options stay on the main list", tostring(porque))
    end
  end
  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    if temTela then
      out[#out + 1] = {
        id = "voxel_chars_menu",
        -- NOT "VOXEL CHARS": that is already the DEPTH option's label, and two
        -- rows with the same name in one menu is a puzzle for the player. The
        -- gate caught the collision, which is the only reason it is not shipping.
        label = "CHARACTERS",
        value = function() return statusValue() end,
        activate = function(g)
          require("src.ui.Screens").push(g, "VoxelCharactersOptions")
        end,
      }
    else
      -- No screen to open, so the rows go where they always went. One row that
      -- opens nothing would be worse than twenty that work.
      for _, r in ipairs(ourRows()) do out[#out + 1] = r end
    end
    return out
  end)

  mod.events:on("mod.options_changed", function(payload)
    if not (payload and payload.mod == mod.id) then return end
    local opt = OPTION_BY_KEY[payload.key]
    if opt then setOption(opt, payload.value) end
  end)

  -- ------------------------------------------------------- the shortcut
  -- BACKSLASH OPENS THE SUBMENU FROM THE OVERWORLD, so that testing an option
  -- costs one key instead of START, several DOWNs, A, several more DOWNs, A.
  -- That is the whole reason it exists: the submenu made the options tidier to
  -- read and slightly slower to reach, and this pays that back.
  --
  -- WHY BACKSLASH. Backtick is the engine's dev console (Game.lua:573). The
  -- function keys are worse than they look: f1, f2, f5 and f10 are taken, and
  -- macOS eats most of the rest as media keys before LOVE ever sees them.
  -- Backslash is bound by nothing here and intercepted by nothing above.
  --
  -- WRAPPING `love.keypressed` IS THIS CODEBASE'S OWN PATTERN, not something
  -- invented here: its test drivers chain the handler the same way
  -- (tests/drivers/touch_layout_bug633_test.lua:87). There is no input hook to
  -- use instead -- the engine exposes exactly one hook, `ui.options.rows`.
  if temTela and type(love) == "table" and not love.__voxelCharactersKeys then
    local anterior = love.keypressed
    love.__voxelCharactersKeys = true
    love.keypressed = function(key, ...)
      -- ONLY FROM THE OVERWORLD, and this is the guard that matters. Pushing a
      -- menu on top of a battle, a dialog or another menu is how a debug
      -- shortcut turns into a corrupted save. If anything at all is already on
      -- the stack above the overworld, the key is not ours.
      if key == "\\" then
        -- THE RETURN VALUE OF THE pcall IS THE POINT, not just whether it
        -- threw. The first version tested only `ok`, which is true whenever the
        -- body ran WITHOUT opening anything -- so every backslash anywhere,
        -- naming a save file included, got swallowed and never reached the
        -- engine. A shortcut that eats a key it declined to handle is worse
        -- than no shortcut.
        local ok, abriu = pcall(function()
          -- `src.core.Game` is the engine's singleton, the same table main.lua
          -- holds as a file-local (main.lua:226), so this is the live game and
          -- not a second copy.
          local g = require("src.core.Game")
          if g and g.stack and g.overworld and g.stack:top() == g.overworld then
            require("src.ui.Screens").push(g, "VoxelCharactersOptions")
            return true
          end
          return false
        end)
        if ok and abriu then return end
      end
      if anterior then return anterior(key, ...) end
    end
  end
end

-- ========================================================================
-- LIFE: matrix animation, one instance at a time
-- ========================================================================
--
-- WHAT THIS SECTION DOES, IN ONE SENTENCE: the host builds a new world
-- matrix for every character every frame; we post-multiply that matrix by
-- a small LOCAL transform (scale in Y, shear in X and in Z) and return it.
-- No vertex is written, no mesh is duplicated.
--
-- WHY THIS IS CORRECT, and not a trick. The host's chain is
--
--     M = T(px+8, y, py+8) . Rx(lean - pi/2) . [S(-1,1,1)] . T(-8,0,0)
--
-- (row-major, translation in the 4th column; VoxelScene.billboardMatrix).
-- I want to inject the transform BEFORE the rotation, in the card's local
-- space, so the effect is "stretches upward from the ground" and not
-- "stretches toward the camera". Post-multiplying puts the transform in
-- the most local spot of all, after the T(-8,0,0). This is equivalent
-- because:
--
--   S(1,s,1) commutes with T(-8,0,0)   (a scale only in Y, a translation
--                                        only in X: orthogonal axes)
--   S(1,s,1) commutes with S(-1,1,1)   (two diagonals)
--
-- so M . S = T . Rx . S(-1,1,1) . S(1,s,1) . T(-8,0,0), which is exactly
-- where I wanted the scale. The shear H (x' = x + kx.y, z' = z + kz.y)
-- also commutes with T(-8,0,0), but NOT with the mirror: that is why kx is
-- negated when m[1] < 0, otherwise the sway would flip sideways along with
-- the character.
--
-- THE PIVOT IS THE FEET. The mesh has y=0 at the ground (the host itself
-- documents "its feet at local y = 0 land on y"), so scaling y around zero
-- keeps the foot planted and raises the head, and shearing proportional to
-- y does not drag the foot. That is what makes this read as a body and not
-- a sticker sliding around.

-- REFACTOR (main chunk locals, roadmap item 0): this used to be eleven
-- separate chunk-level constants, BREATH_PERIOD through LIFE_PERSONALITY,
-- one `local` each (same fix as the OPTIONS/optionState refactor, see
-- main.lua:53: a function's own locals do not count against the chunk's
-- 200). Nine of the eleven moved to a local inside the single function
-- that reads them, comment and value both unchanged:
--   BREATH_PERIOD, SWAY_PERIOD, LIFE_PERSONALITY -> lifeDrawWrap
--   LAG_STIFFNESS, LAG_DAMPING, LAG_REFERENCE_SPEED -> lifeAdvance
--   LIFE_MATCH_RADIUS, LIFE_MATCH_CELLS -> lifeInstance
--   LIFE_FORGET_SECONDS, LIFE_MAX_INSTANCES -> lifeForget
-- LIFE_CELL is the odd one out: it is read by THREE functions
-- (lifeCellKey, lifeInstance, lifeDrawWrap), so it moved into SHARED
-- instead (main.lua, near OBJ_SHADE) as SHARED.LIFE_CELL, the same table
-- that already holds the other constants shared by more than one function.

-- Instance tracker.
--
-- WHY IT EXISTS, and is not just a hash of position: if the animation's
-- phase were f(position), a walking character changes position every
-- frame and the phase slips along with it (external review called this
-- "phase slipping", and it is right: it would breathe at superspeed
-- walking one direction and freeze walking the other). The phase has to
-- advance with TIME and only with time.
--
-- So we match every draw with a known instance by proximity, and carry
-- the phase from one frame to the next. Without this there is no
-- secondary motion at all: a spring needs state.
local lifeInstances = {}
local lifeCount = 0

local function lifeCellKey(sheet, px, py)
  return sheet .. "\1" .. math.floor(px / SHARED.LIFE_CELL) ..
    "\1" .. math.floor(py / SHARED.LIFE_CELL)
end

-- Initial phase for a new instance. Deterministic (the same sheet in the
-- same spot comes back with the same phase after switching maps and
-- returning) and well spread out: the constants are irrational on
-- purpose, because px and py are multiples of 16 and any simple rational
-- factor would line up neighboring instances on the same phase, which is
-- exactly the robot choir we are trying to avoid.
local function lifeSeedPhase(px, py)
  local v = px * 0.6180339887 + py * 0.4142135624
  return v - math.floor(v)
end

local function lifeForget(now)
  -- Moved from chunk scope (roadmap item 0: main chunk locals): only read
  -- here.
  local LIFE_FORGET_SECONDS = 2  -- without showing up, the instance is forgotten
  local LIFE_MAX_INSTANCES = 512
  if lifeCount <= LIFE_MAX_INSTANCES then return end
  for key, inst in pairs(lifeInstances) do
    if now - inst.seen > LIFE_FORGET_SECONDS then
      lifeInstances[key] = nil
      lifeCount = lifeCount - 1
    end
  end
end

-- Returns this draw's instance, creating one if it is the first time.
--
-- Three attempts, in this order:
--   1. exact cell. Covers the normal case (standing) AND the reflected
--      copy in the water, which the host draws through the SAME function
--      in the same frame with the same matrix: it lands on the same
--      instance and does not become a second person.
--   2. the eight neighboring cells, same sheet, within the radius. This is
--      the character that just crossed a cell boundary while walking.
--   3. a new instance.
local function lifeInstance(sheet, px, py, now)
  -- Moved from chunk scope (roadmap item 0: main chunk locals): only read
  -- here. px: how far an instance may have walked.
  local LIFE_MATCH_RADIUS = 24
  -- DERIVED, never hand-written. The neighbor scan needs to reach EVERY cell
  -- that could contain a point within the radius, and that relation is
  -- geometric: a 24 px radius over 16 px cells reaches TWO cells, not one
  -- (px' = 15 is in cell 0, px = 32 in cell 2, and the distance between them
  -- is 17, well within 24).
  --
  -- The first version only scanned the eight adjacent cells with the radius
  -- at 24, and independent review caught it: in that gap the instance was
  -- not found and was reborn with a new phase, which is exactly the phase
  -- slipping this tracker exists to prevent. Deriving the cell reach from
  -- the radius makes the two numbers unable to diverge anymore.
  local LIFE_MATCH_CELLS = math.ceil(LIFE_MATCH_RADIUS / 16)
  local key = lifeCellKey(sheet, px, py)
  local inst = lifeInstances[key]
  if not inst then
    local best, bestKey, bestDist = nil, nil, LIFE_MATCH_RADIUS * LIFE_MATCH_RADIUS
    for dx = -LIFE_MATCH_CELLS, LIFE_MATCH_CELLS do
      for dy = -LIFE_MATCH_CELLS, LIFE_MATCH_CELLS do
        if dx ~= 0 or dy ~= 0 then
          local k = lifeCellKey(sheet, px + dx * SHARED.LIFE_CELL, py + dy * SHARED.LIFE_CELL)
          local c = lifeInstances[k]
          -- `c.seen < now` prevents stealing an instance that was ALREADY
          -- seen this frame: that is a different person, not this one.
          if c and c.seen < now then
            local ddx, ddy = px - c.px, py - c.py
            local d = ddx * ddx + ddy * ddy
            if d < bestDist then best, bestKey, bestDist = c, k, d end
          end
        end
      end
    end
    if best then
      lifeInstances[bestKey] = nil
      inst = best
    else
      inst = {
        phase = lifeSeedPhase(px, py),
        px = px, py = py,
        lagX = 0, lagVX = 0, lagZ = 0, lagVZ = 0,
        -- total distance already traveled, in world pixels. This is where
        -- the FOOTFALL phase comes from: the game walks 16 px per step, so
        -- every 16 px traveled is a footfall, with no need to read any
        -- frame.
        andado = 0, velocidade = 0,
        seen = now,
      }
      lifeCount = lifeCount + 1
      lifeForget(now)
    end
    lifeInstances[key] = inst
  end
  return inst
end

-- Advances the instance up to `now`. Idempotent within the same frame: the
-- second call (the water reflection) has dt = 0 and touches nothing. That
-- is what frees this code from needing to know where a frame begins and
-- ends.
local function lifeAdvance(inst, px, py, now, rate)
  -- Moved from chunk scope (roadmap item 0: main chunk locals): only read
  -- here.
  local LAG_STIFFNESS = 90       -- secondary motion's spring
  local LAG_DAMPING = 12         -- below critical: overshoots and comes back
  local LAG_REFERENCE_SPEED = 60 -- px/s of a normal walk (16 px / 16 frames)
  local dt = now - inst.seen
  if dt <= 0 then return end
  -- A huge dt means the instance disappeared and came back (map switch,
  -- menu open, game paused). Carrying the spring forward with it would
  -- blow it up.
  if dt > 0.25 then dt = 1 / 60 end

  inst.phase = (inst.phase + dt * rate) % 1

  -- Speed in px/s from the actual displacement. It is the only honest
  -- source: the mod does not see the NPC's walking state, only where it
  -- was and where it is.
  local dx, dz = px - inst.px, py - inst.py
  local vx, vz = dx / dt, dz / dt
  inst.px, inst.py = px, py

  -- Distance traveled and smoothed speed. Distance gives the footfall's
  -- PHASE; speed gives the AMPLITUDE, and that is what makes the effect
  -- disappear on its own when the character stops, with no need for an
  -- "is walking?" boolean that would snap on and off.
  inst.andado = (inst.andado or 0) + math.sqrt(dx * dx + dz * dz)

  -- FOOTFALL AS AN EDGE (roadmap T1.2 slice 2).
  --
  -- The amplitude already uses `cos(andado / LIFE_CELL * 2pi)`, which peaks at
  -- +1 once per cell walked. The impact is therefore the moment `andado`
  -- crosses a multiple of the cell, and that is a STRIDE INDEX changing rather
  -- than a condition being true: a condition would hold for several frames and
  -- fire several times for one step.
  --
  -- Recorded here, before the band loop and before anything draws, so the
  -- water reflection's second call and PART LAG's one-call-per-band both see a
  -- stride index that has already advanced and emit nothing.
  local passada = math.floor(inst.andado / SHARED.LIFE_CELL)
  if inst.passada and passada > inst.passada then
    eventoNovo("footfall")
    -- A ONE-SHOT OF ITS OWN for the FX demo, rather than reading the mailbox.
    -- The mailbox is emptied by whoever READS it, and the demo is not its
    -- owner: an internal consumer that drained it would starve the external
    -- one, and one that read without draining would see every past footstep
    -- again on every frame. Measured: that spawned an effect per frame and no
    -- effect ever appeared to expire.
    inst.fxPendente = true
  end
  inst.passada = passada
  local vel = math.sqrt(vx * vx + vz * vz) / LAG_REFERENCE_SPEED
  if vel > 1 then vel = 1 end
  -- Smooths so the amplitude does not flicker when a frame moves 0 px due
  -- to rounding, which happens on every footfall.
  inst.velocidade = (inst.velocidade or 0) + (vel - (inst.velocidade or 0)) * 0.25

  -- Second-order spring chasing the negative of the velocity: the body
  -- lags behind while accelerating, and overshoots when the character
  -- stops.
  local alvoX = -vx / LAG_REFERENCE_SPEED
  local alvoZ = -vz / LAG_REFERENCE_SPEED
  inst.lagVX = inst.lagVX +
    (LAG_STIFFNESS * (alvoX - inst.lagX) - LAG_DAMPING * inst.lagVX) * dt
  inst.lagVZ = inst.lagVZ +
    (LAG_STIFFNESS * (alvoZ - inst.lagZ) - LAG_DAMPING * inst.lagVZ) * dt
  inst.lagX = inst.lagX + inst.lagVX * dt
  inst.lagZ = inst.lagZ + inst.lagVZ * dt

  inst.seen = now
end

-- Post-multiplies `m` (row-major, 16 numbers) by the local transform
--
--     L = S(1, s, 1) . H(kx, kz)     with H: x' = x + kx.y,  z' = z + kz.y
--
-- and returns a NEW table. New, not an in-place mutation, even though we
-- have verified the host allocates the matrix on every call: if a future
-- host recycled a scratch matrix, mutating would accumulate the effect
-- every frame until it blew up, and that failure mode is too expensive
-- for what it saves.
-- Post-multiplies `m` by the LOCAL transform
--
--     L = [ sx  kx  0  8-8sx ]      scale in X pivoted at the cell's CENTER
--         [ 0   s   0  0     ]      scale in Y pivoted at the FEET
--         [ 0   kz  1  0     ]      shear proportional to height
--         [ 0   0   0  1     ]
--
-- and returns a NEW table.
--
-- WHY X IS DIFFERENT FROM THE OTHERS. Scale in Y and shear COMMUTE with
-- the host's local T(-8,0,0), so post-multiplying already puts them in the
-- right place. Scale in X does NOT commute: S(sx,1,1) . T(-8,0,0) scales
-- the -8 along with it, and the character would fatten to only one side,
-- from the sheet's left edge instead of its own axis. That is why X enters
-- as T(8,0,0) . S(sx,1,1) . T(-8,0,0), which is what produces the (8 -
-- 8sx) term in column 4.
--
-- Checked on paper: the local point (8, 0, z), the center of the foot,
-- ends up at col4 + 8.col1 with and without the scale. The foot stays
-- planted and the body fattens to both sides, which is the only way to
-- squash without the character sliding.
--
-- Written out flat, with no loop over indices, because this is the mod's
-- hottest path: it runs once per character per draw, twice per frame
-- each.
local function lifeApply(m, s, kx, kz, sx, corr)
  local out = {
    m[1], m[2], m[3], m[4],
    m[5], m[6], m[7], m[8],
    m[9], m[10], m[11], m[12],
    m[13], m[14], m[15], m[16],
  }
  -- THE TRANSFORM IS CONJUGATED BY THE TILT CORRECTION, and without this
  -- it operates on the wrong axis. This was a defect in production.
  --
  -- The builder returns the vertex already counter-rotated: `p()` applies
  -- Rx(corr) with corr = pi/2 minus the camera angle, and the host undoes
  -- it with Rx(angle - pi/2). Net, the character ends up standing. But
  -- post-multiplying here puts our transform in the MESH's space, which is
  -- rotated by the pitch, not in the character's space. The world then
  -- sees Rx(t)*L*Rx(-t) instead of L.
  --
  -- Measured: with BREATH SUBTLE the head rose by 16*eps*cos^2(corr)
  -- instead of 16*eps. At the default rung (35) that is 33% of what was
  -- promised; at rung 15 only 7% is left. And a Z drift of 16*eps*sin*cos
  -- appeared, up to 0.079 px, pushing the body backward without anyone
  -- asking. MOTION LAG was the worst: the kz term turned 82% vertical at
  -- the default rung, so "inertia" was largely the body rising and
  -- falling.
  --
  -- No gate caught it because every life test asserted on the MATRIX and
  -- none composed the matrix with the rotation baked into the vertex. The
  -- missing test exists now and measures displacement IN THE WORLD at the
  -- four rungs.
  --
  -- Fix: post-multiply L' = Rx(corr) * L * Rx(-corr), which makes the
  -- world see exactly L. With corr = 0 this collapses into L and the old
  -- behavior returns identically, which is correct when there is no tilt.
  --
  -- L, in the character's coordinates (x shears by y, y scales, z shears
  -- by y), and the conjugation expanded term by term:
  --
  --   L  = [ 1 kx 0 ; 0 s 0 ; 0 kz 1 ]
  --   L' = [ 1        kx*c                 kx*n              ]
  --        [ 0   s*c*c + n*n - kz*n*c   s*n*c - kz*n*n - n*c ]
  --        [ 0   s*n*c + kz*c*c - c*n   s*n*n + kz*n*c + c*c ]
  local c, n = 1, 0
  if corr and corr ~= 0 then c, n = math.cos(corr), math.sin(corr) end

  local a12, a13 = kx * c, kx * n
  local a22 = s * c * c + n * n - kz * n * c
  local a23 = s * n * c - kz * n * n - n * c
  local a32 = s * n * c + kz * c * c - c * n
  local a33 = s * n * n + kz * n * c + c * c

  -- out[coluna j] = m * (coluna j de L')
  local m1, m2, m3 = m[1], m[2], m[3]
  local m5, m6, m7 = m[5], m[6], m[7]
  local m9, m10, m11 = m[9], m[10], m[11]
  local m13, m14, m15 = m[13], m[14], m[15]

  out[2] = m1 * a12 + m2 * a22 + m3 * a32
  out[6] = m5 * a12 + m6 * a22 + m7 * a32
  out[10] = m9 * a12 + m10 * a22 + m11 * a32
  out[14] = m13 * a12 + m14 * a22 + m15 * a32

  out[3] = m1 * a13 + m2 * a23 + m3 * a33
  out[7] = m5 * a13 + m6 * a23 + m7 * a33
  out[11] = m9 * a13 + m10 * a23 + m11 * a33
  out[15] = m13 * a13 + m14 * a23 + m15 * a33

  if sx and sx ~= 1 then
    local recuo = 8 - 8 * sx
    out[1] = m[1] * sx
    out[5] = m[5] * sx
    out[9] = m[9] * sx
    out[13] = m[13] * sx
    out[4] = m[4] + m[1] * recuo
    out[8] = m[8] + m[5] * recuo
    out[12] = m[12] + m[9] * recuo
    out[16] = m[16] + m[13] * recuo
  end
  return out
end

-- ------------------------------------------------------------ the wrap
-- Reads the draw's identity from the matrix itself. Measured in game
-- (tools/ingame/probe_draw.lua): m[4] carries px, or px+16 when mirrored,
-- in which case m[1] = -1; m[12] carries py+8. These are WORLD
-- coordinates, immune to the camera (P8) and to the tilt rung (P6).
--
-- When m[1] is not +-1, the host is mixing in first-person yaw
-- (billboardMatrix, cardBlend > 0 branch) and px stops being recoverable.
-- There this mod already returns the flat card on purpose, so the
-- animation drops out too.
-- THE FIX. `pull` is a depth bias: the shader pushes every vertex toward
-- the eye by that distance. Too close, and this throws the vertex behind
-- the eye and what shows up is a black spike.
--
-- So we do not turn off the volume, we hand over a pull the distance can
-- take. Erring low is safe by construction: a smaller pull only means
-- less depth bias, and the bias's reason to exist (not fighting in z with
-- terrain FAR away) does not apply to something glued to the camera.
local function fpPullSeguro(model, pull)
  -- Moved from chunk scope (roadmap item 0: main chunk locals): only read
  -- here.
  --
  -- Conservative character radius from the matrix's anchor: half a cell in
  -- x and z, plus the maximum depth the menu offers. Used to ask about the
  -- CLOSEST vertex instead of the center, which is what decides whether any
  -- corner crosses the near plane.
  local FP_RAIO = 14
  -- Margin above the near plane (1 unit when eye and focus are together).
  -- Two is the smallest number that still leaves room for breath and
  -- inertia to move the body after this math, since they touch the matrix
  -- and not the pull.
  local FP_FOLGA = 2
  if type(pull) ~= "number" or pull <= 0 then return pull end
  local eye = Voxel3D and Voxel3D.eye
  if type(eye) ~= "table" then return pull end
  local ex, ey, ez = eye[1], eye[2], eye[3]
  if type(ex) ~= "number" or type(ey) ~= "number" or type(ez) ~= "number" then
    return pull
  end
  local dx = ex - (model[4] or 0)
  local dy = ey - (model[8] or 0)
  local dz = ez - (model[12] or 0)
  local d = math.sqrt(dx * dx + dy * dy + dz * dz) - FP_RAIO
  local teto = d - FP_FOLGA
  if teto < 0 then teto = 0 end
  return math.min(pull, teto)
end

-- WHAT MAY BREATHE, SWAY, LAG AND SQUASH.
--
-- Reported by Pikon: the town map lying on the table in the rival's house
-- sways. He is right that it should not, and right about the rule too, which
-- Kim confirmed: people and Pokemon move, objects do not. A swaying map reads
-- as a bug even to someone who cannot name what is wrong, because maps on
-- tables do not breathe.
--
-- THE LIST IS OF OBJECTS, NOT OF CHARACTERS, and that direction is the whole
-- design. Measuring every sheet's frame count (its height over 16, see
-- RomExtractor.lua:481) splits them almost along the line we want: 58 sheets
-- have 3 or 6 frames and are all characters, 9 have one frame. But two of
-- those nine are alive and merely still, `snorlax` and `gambler_asleep`, and a
-- sleeping Snorlax that breathes is exactly the reading we want.
--
-- So the rule is not "animate what walks", it is "hold still what is furniture",
-- and anything unknown is treated as alive. That default is the one that
-- survives other mods: overworld_wild_spawns registers hundreds of Pokemon
-- sprites we have never seen, and a Pokemon should breathe. A list of
-- characters would freeze them all; a list of objects lets them through.
--
-- The names come from the ROM and cannot grow, and the offline suite asserts
-- the classification over the real sheet names, so a wrong entry fails a test
-- instead of sitting in a table nobody rereads.
--
-- Note what this does NOT explain, because the difference matters: Pikon also
-- noticed the pokeballs on Oak's table do not sway. That is not this rule at
-- work. Those pokeballs are map art, not object events, so they never reach
-- SpriteBillboards.mesh and were never ours to animate.
local function lifeAlive(info)
  -- Moved from chunk scope (roadmap item 0: main chunk locals): only read
  -- here.
  local STILL_OBJECTS = {
    boulder = true, clipboard = true, fossil = true, old_amber = true,
    paper = true, poke_ball = true, pokedex = true,
  }
  if not info then return false end
  return not STILL_OBJECTS[info.base]
end

local function lifeDrawCore(mesh, texture, model, pull, sunModel)
  -- THE TEXTURE HAS TO TRAVEL WITH THE GEOMETRY (roadmap T3.0).
  --
  -- UVs are normalised -- `(frameOrigin + lx) / sheetW` -- so an HD-built mesh
  -- samples the same FRACTIONAL positions either way and would look correct
  -- against the ROM sheet too, just with the ROM's tones. Swapping the texture
  -- is what makes the extra tones visible at all, which is the entire point of
  -- the experiment.
  --
  -- Done first, before any of the early returns below, so every path that draws
  -- this mesh draws it with the sheet it was built from. Putting it after them
  -- would leave the still, the reflection and the fallback paths sampling the
  -- other sheet.
  -- ONLY WHEN A COLOURED ONE IS ALREADY BUILT. The forSprite wrap below builds
  -- and caches it against the palette the character stands under; this swap
  -- cannot know that palette, so it never bakes one itself. If the wrap never
  -- ran -- an old host, or a colour mode that skips it -- the host's own
  -- texture stays, and HD simply does not apply. A grey character would be a
  -- worse answer than no change at all.
  if optionState.hd_sprite == "on" then
    local info = ourMeshes[mesh]
    local tex = info and info.base and hdTexturePronta(info.base)
    if tex then texture = tex end
  end

  -- Moved from chunk scope (roadmap item 0: main chunk locals): only read
  -- here. Amplitudes and rhythms. Seconds and fraction of cell height.
  local BREATH_PERIOD = 3.1      -- calm breathing of a standing adult
  -- 8.86 IS 6.2 / 0.7: Kim asked for a sway 30% slower than it was, watching it
  -- in the game. It used to be 6.2, exactly twice the breath period, which the
  -- old comment defended as "half the rate, so they never beat together" -- and
  -- that reasoning was backwards. Two periods in a 2:1 ratio realign every
  -- single cycle, which is the definition of beating together; 8.86 against 3.1
  -- is 2.857:1 and does not repeat in any span anybody watches.
  local SWAY_PERIOD = 8.86
  -- PER-SHEET PERSONALITY (roadmap step 7). Multipliers on top of what the
  -- menu chose: rate, breath amplitude, sway amplitude. Absent from the
  -- table = 1, 1, 1. Same shape as EYE_MARKS, which already has 112 entries
  -- and proved that a hand-written table ages well in this mod.
  --
  -- This does NOT invent new movement: it only says that a sitting old man
  -- breathes slowly and barely sways, and that a swimmer standing in water
  -- sways more than a guard at attention. No new pixel was drawn for this.
  local LIFE_PERSONALITY = {
    -- sleeping or sitting: slow and nearly still
    -- ASLEEP, AND THEREFORE NOT WATCHING. `attention = 0` here is not a taste
    -- call: this table already says these two are asleep -- a slow rate, deep
    -- breathing, no sway at all -- and a sleeping character leaning toward a
    -- passing player is the same class of wrongness as a breathing item ball.
    -- Derived from what the row already claims rather than chosen.
    gambler_asleep   = { rate = 0.45, breath = 1.35, sway = 0.0, attention = 0 },
    sleeping_boy     = { rate = 0.45, breath = 1.35, sway = 0.0, attention = 0 },
    -- standing at attention: normal rate, no sway
    guard            = { rate = 1.00, breath = 0.80, sway = 0.15 },
    officer_jenny    = { rate = 1.00, breath = 0.80, sway = 0.20 },
    scientist        = { rate = 1.05, breath = 0.85, sway = 0.30 },
    -- in the water or standing for a long time: more sway
    swimmer          = { rate = 1.15, breath = 1.10, sway = 1.60 },
    fisher           = { rate = 0.85, breath = 1.05, sway = 1.25 },
    -- children and restless people: fast and short
    youngster        = { rate = 1.30, breath = 0.90, sway = 1.20 },
    girl             = { rate = 1.25, breath = 0.90, sway = 1.15 },
    little_girl      = { rate = 1.40, breath = 0.85, sway = 1.30 },
    -- carrying weight
    super_nerd       = { rate = 0.90, breath = 1.15, sway = 0.75 },
    gambler          = { rate = 0.95, breath = 1.10, sway = 0.85 },
    -- OBJECTS. An item ball does not breathe. Without this entry, the
    -- poke_ball on the ground would end up pulsing, which is the most
    -- obvious defect this feature could possibly have.
    poke_ball        = { rate = 1, breath = 0, sway = 0, lag = 0 },
    boulder          = { rate = 1, breath = 0, sway = 0, lag = 0 },
    -- Snorlax, whose entire characterisation is being asleep. Same reasoning.
    snorlax          = { rate = 0.40, breath = 1.60, sway = 0.0, attention = 0 },
  }
  local info = ourMeshes[mesh]
  if not info or type(model) ~= "table" then
    return originalDraw(mesh, texture, model, pull, sunModel)
  end

  -- Before any early return, because this is not animation: it is the
  -- condition for the solid to be allowed to exist in first person, and it
  -- applies even with every life option turned off.
  local fp = optionState.first_person or readOption(OPTION_BY_KEY.first_person)
  if fp == "solid" and firstPersonCardActive() then
    pull = fpPullSeguro(model, pull)
  end

  local breath = optionState.breath
  local sway = optionState.sway
  local lag = optionState.lag
  local footfall = optionState.footfall
  if breath == "off" and sway == "off" and lag == "off"
    and footfall == "off" and (optionState.attention or "off") == "off" then
    return originalDraw(mesh, texture, model, pull, sunModel)
  end
  -- After the first-person pull clamp on purpose: that one is about not
  -- drawing garbage and applies to everything we draw, including objects.
  -- This one is about what is alive.
  if not lifeAlive(info) then
    return originalDraw(mesh, texture, model, pull, sunModel)
  end

  local m1 = model[1]
  local espelhado = m1 < 0
  if math.abs(math.abs(m1) - 1) > 1e-6 then
    return originalDraw(mesh, texture, model, pull, sunModel)
  end

  -- Same care as blinking (blinkClosedForBase): the clock comes from the
  -- host, and a host without love.timer must not bring down the draw.
  -- Without a clock there is no animation, and the character comes out as
  -- it always did.
  if not (love and love.timer and love.timer.getTime) then
    return originalDraw(mesh, texture, model, pull, sunModel)
  end
  local okNow, now = pcall(love.timer.getTime)
  if not okNow or type(now) ~= "number" then
    return originalDraw(mesh, texture, model, pull, sunModel)
  end

  local px = espelhado and (model[4] - SHARED.LIFE_CELL) or model[4]
  local py = model[12] - 8
  local pessoa = LIFE_PERSONALITY[info.base]
  local rate = pessoa and pessoa.rate or 1
  local inst = lifeInstance(info.base, px, py, now)
  lifeAdvance(inst, px, py, now, rate / BREATH_PERIOD)

  local s, kx, kz = 1, 0, 0
  if breath ~= "off" then
    local amp = breath * (pessoa and pessoa.breath or 1)
    s = 1 + amp * math.sin(inst.phase * 2 * math.pi)
  end
  if sway ~= "off" then
    local amp = sway * (pessoa and pessoa.sway or 1)
    -- Half the breath rate and a quarter turn out of phase: the two never
    -- reach the extreme together, which is what would make the character
    -- look like a metronome instead of a person.
    local a = (inst.phase * BREATH_PERIOD / SWAY_PERIOD + 0.25) * 2 * math.pi
    kx = amp * math.sin(a) / SHARED.LIFE_CELL
  end
  if lag ~= "off" then
    -- DIVIDING BY SHARED.LIFE_CELL, same as SWAY right above, and the reason is
    -- written here because missing it slipped past every numeric gate.
    --
    -- `amp` is HEAD displacement in world pixels. The shear is x' = x +
    -- k*y with y up to 16, so k has to be amp/16. Without the division,
    -- `amp` turned into the SLOPE: at level 0.70 the head moved 0.70*16 =
    -- 11 px, nearly a whole tile, and the character did not read as
    -- walking with weight, it read as falling sideways. The eight in-game
    -- checks passed anyway, because
    -- they all asked "did it change?" and none asked "by how much?". What
    -- caught it was watching the clip.
    local amp = lag * (pessoa and pessoa.lag or 1) / SHARED.LIFE_CELL
    kx = kx + amp * inst.lagX
    kz = kz + amp * inst.lagZ
  end
  local sx = 1
  if footfall ~= "off" then
    local amp = footfall * (pessoa and pessoa.footfall or 1) / SHARED.LIFE_CELL
    -- cosine of the footfall's phase: +1 on impact, -1 at the top of the
    -- step. One full cycle per cell walked.
    local pulso = math.cos((inst.andado / SHARED.LIFE_CELL) * 2 * math.pi)
    local achata = amp * (inst.velocidade or 0) * pulso
    s = s - achata
    -- Volume preserved: what disappears in height shows up in width.
    -- Without this the character just shrinks, which reads as sinking into
    -- the ground instead of stepping.
    sx = 1 + achata
  end

  -- The shear in X lives in the card's space, which the mirror has
  -- already flipped. Without negating here, sway and lag would swap sides
  -- every time the character turned to face the other way, and the jump
  -- would be visible.
  if espelhado then kx = -kx end

  -- The SAME correction the builder baked into the vertex, quantized the
  -- same way: if the two diverge, the conjugation does not cancel and a
  -- residue is left over.
  -- ATTENTION (roadmap item 10): a character notices the player.
  --
  -- HYSTERESIS, and it is the whole difference between attention and
  -- twitching. With one distance threshold, a player standing exactly on it
  -- makes every nearby character flick in and out of leaning once per frame.
  -- Two thresholds, and a character that has noticed you keeps noticing until
  -- you are meaningfully further away.
  --
  -- The lean also EASES rather than snapping, using the same instance clock
  -- everything else here uses, so noticing takes about a third of a second.
  local attention = optionState.attention
  if attention ~= "off" then
    local eye = Voxel3D and Voxel3D.eye
    if type(eye) == "table" then
      local dx = (eye[1] or 0) - (model[4] or 0)
      local dy = (eye[2] or 0) - (model[8] or 0)
      local dz = (eye[3] or 0) - (model[12] or 0)
      local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
      local PERTO, LONGE = 34, 46
      local notou = inst.notou
      if not notou and dist < PERTO then notou = true
      elseif notou and dist > LONGE then notou = false end
      -- ATTENTION AS AN EDGE. `notou` is already a hysteresis with two
      -- thresholds, so the transition is a genuine event rather than a
      -- threshold being crossed back and forth on noise.
      --
      -- NIL COUNTS AS "HAS NOT NOTICED", which is what the line above already
      -- assumes: `if not notou and dist < PERTO` treats an unset instance as
      -- oblivious. Guarding against nil instead would swallow the first
      -- transition, so a character that is already standing next to the player
      -- when it first draws would never announce that it noticed. Found by the
      -- gate, which put the eye right on top of the character.
      if notou ~= (inst.notou or false) then
        eventoNovo(notou and "attention_noticed" or "attention_lost")
      end
      inst.notou = notou
      -- Ease toward 0 or 1 at a fixed rate per second, so the speed of
      -- noticing does not depend on frame rate.
      local alvo = notou and 1 or 0
      local passo = math.min(1, (now - (inst.attT or now)) * 3)
      inst.att = (inst.att or 0) + (alvo - (inst.att or 0)) * passo
      inst.attT = now
      if inst.att > 0.001 then
        -- Toward the eye in X, expressed as head displacement, then divided
        -- by the cell height for the same reason SWAY and MOTION LAG are:
        -- the shear is x' = x + k*y with y up to 16, so k is amp/16. Missing
        -- that division is the defect that sheared a body 45 degrees and
        -- passed 465 checks.
        local dirX = dx > 0 and 1 or -1
        -- PER-SHEET TEMPERAMENT, the sixth axis (roadmap T2.4 question 2).
        --
        -- The personality table already scales rate, breath, sway, MOTION LAG
        -- and FOOTFALL per sheet. ATTENTION was the one life axis it did not
        -- reach, so every character noticed the player with exactly the same
        -- eagerness, including the ones the same table describes as asleep.
        --
        -- The default is 1, so nothing changes for any sheet that does not set
        -- it: this is a multiplier on an existing amplitude and not a new
        -- behaviour.
        local att = pessoa and pessoa.attention or 1
        kx = kx + attention * att * inst.att * dirX / SHARED.LIFE_CELL
      end
    end
  end

  local corr = quantizeCorrection(leanCorrection())

  -- PER-PART SECONDARY MOTION (roadmap item 9).
  --
  -- What a rigid body cannot do is arrive LATE. The shear already makes the
  -- head travel further than the feet, because x' = x + k*y; what it cannot
  -- express is the head still catching up after the feet have stopped.
  --
  -- So each instance keeps a short history of its own shear, and each band
  -- reads a different point in it: the feet read now, the head reads
  -- `atraso` seconds ago. One draw call per band, each with its own matrix.
  --
  -- The history lives on the INSTANCE and not on the mesh, which is the third
  -- blocker recorded against this feature: the mesh is shared by every
  -- character using that sheet, so anything per-character has to live beside
  -- the draw call.
  local partLag = optionState.part_lag
  local faixas = meshBands[mesh]
  if partLag ~= "off" and faixas and #faixas > 1 and mesh.setDrawRange then
    inst.hist = inst.hist or {}
    local h = inst.hist
    h[#h + 1] = { t = now, kx = kx, kz = kz }
    -- Trim to what the longest delay can possibly need, plus a margin. An
    -- unbounded history on twenty five characters is a leak that only shows
    -- up after ten minutes of walking.
    while #h > 2 and h[1].t < now - (partLag * 2 + 0.5) do table.remove(h, 1) end

    local function shearEm(quando)
      -- Walk back to the newest sample at or before `quando`. Linear, but the
      -- list is a couple of dozen entries at 60fps and the walk starts from
      -- the end, so it stops almost immediately.
      for i = #h, 1, -1 do
        if h[i].t <= quando then return h[i].kx, h[i].kz end
      end
      return h[1].kx, h[1].kz
    end

    local ok = true
    for b = 1, #faixas do
      local faixa = faixas[b]
      if faixa.quantos > 0 then
        -- Band 1 is the head and gets the full delay; the last band is the
        -- feet and gets none. Linear in between, which is what a chain of
        -- equal segments settles into anyway.
        local fracao = (#faixas - b) / (#faixas - 1)
        local bkx, bkz = shearEm(now - partLag * fracao)
        if espelhado then bkx = -bkx end
        local mb = lifeApply(model, s, bkx, bkz, sx, corr)
        local sb = sunModel and lifeApply(sunModel, s, bkx, 0, sx, corr) or nil
        if not pcall(mesh.setDrawRange, mesh, faixa.primeiro, faixa.quantos) then
          ok = false
          break
        end
        originalDraw(mesh, texture, mb, pull, sb)
      end
    end
    -- THE RANGE IS STICKY ON THE MESH OBJECT, and the mesh is shared between
    -- every instance of this sheet in the frame. Leaving a range set would
    -- draw the next character as one band of itself. This is the one real
    -- hazard that survived from the old blocker list.
    pcall(mesh.setDrawRange, mesh)
    if ok then return end
    -- A host whose mesh will not take a draw range falls through to the
    -- single-matrix path below, which is what every version until now did.
  end

  local novo = lifeApply(model, s, kx, kz, sx, corr)
  -- The shadow receives the SAME scale. Without this the body breathes and
  -- the shadow stays still, and the character detaches from its own
  -- shadow. The shear in Z stays out: the shadow's matrix already flattens
  -- z (casterMatrix ends in S(1,1,0)) and reintroducing depth there would
  -- have no meaning.
  local novoSol = sunModel and lifeApply(sunModel, s, kx, 0, sx, corr) or nil
  local resultado = originalDraw(mesh, texture, novo, pull, novoSol)

  -- THE FX DEMO (roadmap T2.3), after the body and never instead of it.
  --
  -- Spawn is driven by a REAL EVENT and positioned from a REAL ANCHOR: a
  -- footfall fires one effect from the character's hand. Both of those came
  -- from T1.2 and neither is invented here, which is the point of having built
  -- them first.
  --
  -- Only on the FIRST draw of a frame for this instance. The host draws every
  -- character twice for the water reflection and PART LAG issues one call per
  -- band, so advancing the effects on every call would run their lifetimes at
  -- up to eight times speed and spawn several per step.
  local demo = optionState.demo_fx
  if demo and demo ~= "off" and inst.fxQuadro ~= now then
    inst.fxQuadro = now
    local fam = FX.FAMILIAS[demo]
    local ancoras = meshAnchors[mesh]
    if fam and ancoras then
      if inst.fxPendente and #FX.vivos < FX.MAX then
        inst.fxPendente = false
        FX.nascidos = FX.nascidos + 1

        -- THE SOUND, on the same line as the effect it belongs to.
        --
        -- Spawn and play happen in one place so they cannot drift apart. The
        -- gate's tolerance is a single frame, and the only way to be sure of
        -- that is for there to be no second code path with its own idea of when
        -- a footstep happened.
        --
        -- Guarded like every other host capability in this file. A host with no
        -- audio, or a build where love.audio is absent, loses the sound and
        -- keeps the effect, rather than raising inside the draw path, which is
        -- the worst possible place for it. The source is created once per
        -- family and remembered, including the failure, so a missing file is
        -- not retried on every footstep.
        if love and love.audio and love.audio.newSource and fam.som then
          if FX.sons[fam.som] == nil then
            local ok, fonte = pcall(love.audio.newSource,
              (mod.path or ".") .. "/sfx/" .. fam.som .. ".wav", "static")
            FX.sons[fam.som] = (ok and fonte) or false
          end
          local fonte = FX.sons[fam.som]
          if fonte then pcall(function() fonte:play() end) end
        end

        local a = ancoras.hand
        -- CARRIES THE RESOLVED FAMILY, not the option's name.
        --
        -- It used to store `demo` and look the family up again when retiring,
        -- which quietly made the off path guarded in THREE places: the option
        -- check, the family lookup at spawn, and that second lookup. Three
        -- guards sound safer and are worse, because a gate cannot prove any of
        -- them: defeating one or two changed nothing observable, so the off
        -- path passed whether or not it worked. One guard that a test can break
        -- is worth more than three nobody can.
        FX.vivos[#FX.vivos + 1] = {
          f = fam, nasceu = now,
          x = (model[4] or 0) + a.x - 8, y = a.y, z = (model[12] or 0),
        }
      end
      -- Advance and retire. An effect that never dies is a leak that looks
      -- like a feature for the first ten seconds, so the age check runs before
      -- anything is drawn and the list is rebuilt rather than patched.
      local vivos = {}
      for _, e in ipairs(FX.vivos) do
        local idade = now - e.nasceu
        local f = e.f
        if f and idade < f.vida then
          vivos[#vivos + 1] = e
          local t = idade / f.vida
          local m = {
            f.tam * (1 - t * 0.6), 0, 0, e.x + f.passo * t,
            0, f.tam * (1 - t * 0.6), 0, e.y + f.sobe * t,
            0, 0, f.tam * (1 - t * 0.6), e.z,
            0, 0, 0, 1,
          }
          -- Reuses the character's own mesh as the effect's shape. A demo does
          -- not need art of its own to prove the channel works, and shipping
          -- art here would break the mod's promise for a prototype.
          originalDraw(mesh, texture, m, pull, nil)
        end
      end
      FX.vivos = vivos
    end
  end
  return resultado
end

-- THE WIREFRAME ON CHARACTERS, wrapped around the core rather than threaded
-- through it: the core has nine places where it hands off to the host, and a
-- flag that has to be set before each and cleared after each is a flag that
-- will be forgotten at the tenth.
--
-- THE HOST TURNS THIS OFF ON PURPOSE and says why (VoxelScene.lua:1048): the
-- seams are what make the WORLD read as built out of voxels, and the people in
-- it are the one thing that should read as drawn -- a grid over a 16x16 sprite
-- lands a line every couple of display pixels and turns a face into a mesh.
-- That is a taste call about how the game should look, and it is a good one.
--
-- This option is not arguing with it. It is a MEASURING TOOL: with the grid on
-- you can see where the mod actually put geometry, which is the fastest way to
-- tell a slab from a carved hull, or to see a face that should not be there.
-- Kim asked for it after the submenu turned into the bench this mod is tested
-- on. Off by default, and it says so in its own help.
--
-- `Voxel3D.seams` is the host's own API for exactly this, so the pass is put
-- back the way it was found rather than left dirty for whatever draws next.
local function lifeDrawWrap(mesh, texture, model, pull, sunModel)
  local liga = optionState.grid_chars == "on"
    and ourMeshes[mesh] ~= nil
    and Voxel3D and type(Voxel3D.seams) == "function"
    -- Checked here too, not only in the menu: the key can be pressed while the
    -- option is already on, and a row's requirement is read when somebody looks
    -- at the menu rather than every frame.
    and gradeDoMundo()
  if not liga then
    return lifeDrawCore(mesh, texture, model, pull, sunModel)
  end
  pcall(Voxel3D.seams, true)
  local ok, resultado = pcall(lifeDrawCore, mesh, texture, model, pull, sunModel)
  pcall(Voxel3D.seams, false)
  if not ok then error(resultado, 0) end
  return resultado
end

local function voxelMesh(def, frame)
  local depth = optionState.depth or readOption(OPTION_BY_KEY.depth)
  if depth == "off" then
    recordDrawResult("off")
    return safeOriginal(def, frame)
  end
  -- In first person the solid only comes out if TWO things are true: the
  -- person asked for it, and the draw channel exists to cap the pull.
  -- Without the channel, installedDraw stays nil and SOLID would promise
  -- exactly the spikes v1.3.0 fixed; the option does not even show up in
  -- the menu on that host, but an old save can carry the value, so the
  -- check is here and not in the menu.
  if firstPersonCardActive() then
    local fp = optionState.first_person or readOption(OPTION_BY_KEY.first_person)
    if fp ~= "solid" or installedDraw == nil then
      recordDrawResult("first_person")
      return safeOriginal(def, frame)
    end
  end
  local sideColor = optionState.side_color or readOption(OPTION_BY_KEY.side_color)
  local shape = optionState.shape or readOption(OPTION_BY_KEY.shape)
  local groundShade = optionState.ground_shade or readOption(OPTION_BY_KEY.ground_shade)
  local topEdge = optionState.top_edge or readOption(OPTION_BY_KEY.top_edge)
  local frontShape = optionState.front_shape or readOption(OPTION_BY_KEY.front_shape)
  local topDome = optionState.top_dome or readOption(OPTION_BY_KEY.top_dome)
  local stepWeight = optionState.step_weight or readOption(OPTION_BY_KEY.step_weight)
  local correction = quantizeCorrection(leanCorrection())
  local okMask, m = pcall(maskFor, def)
  if not (okMask and m) then
    recordDrawFailure("mask_failed",
      okMask and "maskFor found no usable mask for this sprite" or m)
    return safeOriginal(def, frame)
  end
  -- DEPTH IS IN SHEET PIXELS, so a bigger cell needs a bigger number for the
  -- SAME thickness. Missing this is what made the HD character read as PAPER --
  -- Kim's word for it, and the right one.
  --
  -- The slab's thickness is `depth` sheet pixels, and escalaParaTile then
  -- divides EVERY axis by cellH/16 to bring a 64 px figure down to one tile.
  -- Width and height are in sheet pixels too, so they survive that intact; the
  -- thickness does not, because it never grew with the sheet. DEPTH 3 became
  -- three quarters of a pixel: a figurine instead of a filled biscuit.
  --
  -- CARVED does not go through here and never had the bug: it measures its own
  -- thickness off the silhouette (`depthPixels`), which is in sheet pixels and
  -- grows with the sheet on its own. `depth` reaches buildCarvedMesh and is
  -- unused. That is exactly why the report named SLAB.
  local hdK = hdCellScale(m)
  if hdK then
    depth = depth * hdK
  end
  local baseName = spriteBaseName(def and def.image)
  local key = cacheKey(def, frame, depth, correction, m, sideColor, shape,
    groundShade, topEdge, frontShape, topDome, stepWeight)
  if meshes[key] ~= nil then
    touchMeshKey(key)
  else
    local ok, mesh = pcall(buildSelectedMesh, def, frame, depth, correction,
      m, sideColor, shape, groundShade, baseName, topEdge, frontShape, topDome,
      stepWeight)
    if ok and mesh then
      meshFailureReasons[key] = nil
    else
      meshFailureReasons[key] = (not ok) and mesh
        or "buildSelectedMesh returned no mesh for this sprite"
    end
    rememberMesh(key, (ok and mesh) or false)
  end
  local mesh = meshes[key]
  if mesh then
    recordDrawResult("ok")
    applyBlinkUv(mesh)
    -- Marks the mesh as OURS and stores the sheet. This is what the
    -- Voxel3D.draw wrap uses to know that draw is a character from this
    -- mod and not terrain, grass, shadow or the pokedex, which pass
    -- through the same function.
    --
    -- Only on the FIRST time. The mesh is cached by (sheet, frame,
    -- options), so base and frame never change for the same mesh object;
    -- reassigning on every cache hit would allocate a table per character
    -- per frame without changing anything inside it.
    if ourMeshes[mesh] == nil then
      ourMeshes[mesh] = { base = baseName, frame = frame,
                          frames = (def and def.frames) or 1 }
    end
    return mesh
  end
  -- Records again on every call, even when `mesh` came from cache
  -- (meshes[key] == false from an earlier failure): without this, only
  -- the FIRST attempt would enter the sliding window, and a sheet that
  -- always fails would look like it had only failed once.
  recordDrawFailure("build_failed", meshFailureReasons[key])
  return safeOriginal(def, frame)
end

-- v1.4.2, fine-tooth comb (blocking): atomic patch. Everything built in
-- locals first; the TWO writes to the host's table (the only ones that
-- can throw, if that table refuses a write) run before any module upvalue
-- commit. If either one throws, the exception rises to the caller's
-- pcall(patch, host) and NO module upvalue was touched (not
-- SpriteBillboards, not installedMesh, not `patched`), so the next
-- statusValue() still reads NO HOST. Without this, SpriteBillboards could
-- end up set on its own by an earlier successful write and STATUS would
-- read REPLACED for a replacement that never happened.
--
-- v1.4.2, fine-tooth comb (item 1): the two writes are not a single
-- transaction; a host whose __newindex only protects the (already
-- existing) `mesh` key and allows a new key (the most plausible way to
-- defend a public API without locking out extension) lets the FIRST write
-- through and the second one throw. Without undoing the first,
-- __voxelCharactersOriginal stays written into the host's table forever,
-- even though the patch never actually took, which contradicts the
-- README ("does not modify the Voxel Mod"). If the second one throws, the
-- first is undone: if __voxelCharactersOriginal already existed before (a
-- real repatch), the previous value comes back; if it did not exist, it
-- goes back to nil, exactly as it was.
local function patch(host)
  local handle = host.handle
  local V = handle.exports.lib
  local spriteBillboards = host.modules.SpriteBillboards
  local voxel3D = host.modules.Voxel3D
  local imageCache = host.modules.ImageCache
  local okVoxel, voxel = pcall(V.require, "VoxelState")
  local voxelState = okVoxel and voxel or nil
  local okFirst, first = pcall(V.require, "FirstPerson")
  local firstPerson = okFirst and first or nil
  local okScene, scene = pcall(V.require, "VoxelScene")
  local voxelScene = okScene and scene or nil

  warnChainedMesh(spriteBillboards)
  local previousOriginal = spriteBillboards.__voxelCharactersOriginal
  local original = previousOriginal or spriteBillboards.mesh
  local installed = function(def, frame)
    local ok, mesh = pcall(voxelMesh, def, frame)
    if ok then return mesh end
    recordDrawFailure("exception", mesh)
    return safeOriginal(def, frame)
  end
  -- Risky writes. No upvalue commit until both have succeeded.
  spriteBillboards.__voxelCharactersOriginal = original
  local okMesh, meshErr = pcall(function()
    spriteBillboards.mesh = installed
  end)
  if not okMesh then
    -- Undoes the first write: `spriteBillboards[k] = v` never invokes
    -- __newindex for a key that already has a raw value (the one we just
    -- wrote), so this assignment goes straight through rawset even on a
    -- table whose __newindex blocks new keys, with no need for an
    -- explicit `rawset` builtin. In a pcall because undoing is
    -- best-effort: the error that matters to the caller is the second
    -- write's, not the rollback's.
    pcall(function()
      spriteBillboards.__voxelCharactersOriginal = previousOriginal
    end)
    error(meshErr, 0)
  end

  -- Commit: only gets here if the two writes above did not throw.
  Voxel3D = voxel3D
  ImageCache = imageCache
  -- Kept so anything below can reach a host module we did not know we needed at
  -- attach time. VoxelGrid is the first: V-GRID CHARS asks it whether the
  -- world's own wireframe is on, and only rides along when it is.
  hostLib = V
  SpriteBillboards = spriteBillboards
  VoxelState = voxelState
  FirstPerson = firstPerson
  VoxelScene = voxelScene
  originalMesh = original
  installedMesh = installed
  patched = true
  registerOptionsRows()
  mod.log:info("patched %s character billboards", host.name)

  -- ----------------------------------------------- the palette for HD SPRITE
  -- OPTIONAL, like the animation patch below, and for the same reason: it is
  -- one more piece of host surface, and losing it costs one option rather than
  -- the mod.
  --
  -- This is where the host bakes a character's world palette into its texture
  -- (VoxelScene.lua:358 and :404), because the 3D canvas never runs through the
  -- screen-space shader the flat game colours sprites with. Wrapping it HERE,
  -- rather than swapping the texture at draw time, is what lets an HD sheet be
  -- coloured at all: this is the one place that knows which palette applies.
  --
  -- It also fixes the ghost and the shadow for free -- both call the same
  -- function -- which a draw-time swap would have had to chase one by one.
  pcall(function()
    local okAtlas, atlas = pcall(V.require, "TerrainAtlas")
    if not (okAtlas and type(atlas) == "table" and atlas.forSprite) then return end
    if atlas.__voxelCharactersForSprite then return end
    local anterior = atlas.forSprite
    atlas.__voxelCharactersForSprite = anterior
    local ok = pcall(function()
      atlas.forSprite = function(caminho, colors)
        if optionState.hd_sprite == "on" then
          local base = spriteBaseName(caminho)
          if base and hdDataFor(base) then
            -- Key by the palette, not just the sheet: one character walks
            -- through several world palettes in a session and each needs its
            -- own bake, exactly as the host's own cache does it.
            local chave = ""
            if colors then
              for i = 1, 4 do
                local c = colors[i]
                chave = chave .. (c and (c[1] .. "," .. c[2] .. "," .. c[3]) or "-") .. ";"
              end
            end
            local tex = hdTextureFor(base, colors, chave)
            if tex then
              hdPronta[base] = tex
              return tex
            end
          end
        end
        return anterior(caminho, colors)
      end
    end)
    if not ok then
      pcall(function() atlas.__voxelCharactersForSprite = nil end)
      return
    end
    TerrainAtlas = atlas
    mod.log:info("patched %s sprite palette, so HD SPRITE keeps its colours",
      host.name)
  end)

  -- SECOND PATCH POINT, and it is OPTIONAL on purpose.
  --
  -- The animation channel needs to wrap Voxel3D.draw. That is more host
  -- surface than this mod had before, and more surface means more chance
  -- for a future fork to break us: between October and now the original
  -- repository went dark twice and three lineages were born versioning in
  -- incompatible ways. That is why this whole patch sits AFTER the commit
  -- above and in its own pcall: if it fails, the mod loses the animation
  -- and keeps drawing solids normally, which is the main product. The
  -- opposite (losing the mod because of a decoration) would be
  -- unacceptable.
  --
  -- The capability probe has already rejected hosts without a usable
  -- Voxel3D.draw (probeHost, OPTIONAL_CAPABILITIES), so getting here
  -- without the capability means an old host, and the absence is silent
  -- by choice: whoever runs a host without the channel sees LIFE: NO
  -- CHANNEL on the options screen and knows why.
  if host.caps and host.caps.drawWrap then
    local okDraw, drawErr = pcall(function()
      local previous = voxel3D.draw
      if previous ~= installedDraw then originalDraw = previous end
      installedDraw = lifeDrawWrap
      voxel3D.draw = lifeDrawWrap
    end)
    if okDraw then
      drawPatched = true
      mod.log:info("patched %s character draw for the life channel", host.name)
    else
      originalDraw, installedDraw, drawPatched = nil, nil, false
      mod.log:warn("could not patch %s character draw; the mod works, but " ..
        "BREATH, SWAY and MOTION LAG stay off: %s", host.name, tostring(drawErr))
    end
  end
end

local function hostIds()
  local ids = {}
  for i, host in ipairs(HOSTS) do ids[i] = host.id end
  return table.concat(ids, ", ")
end

-- DECISION v1.4.2: decide by capability, not by version number. Measured
-- before this change: "banana" (an unreadable version) was ACCEPTED and
-- "1.3.1" (a readable version, but out of range, with the whole API
-- present) was REJECTED, the opposite of what makes sense. There are
-- three host lineages versioning independently and chaotically (1.6.2.ST
-- with a suffix Semver cannot read; v1.68 which parses as 1.68.0 and so
-- ends up "greater" than 1.7.6; and a release's manifest possibly stating
-- one version while the code itself states another). A version gate over
-- this gets it wrong again with every new release, and every mistake
-- costs a whole version where the mod does nothing for whoever migrated.
-- From now on the version never rejects a host: it is just information,
-- always logged, and a warning when it is out of the known range.

-- ROADMAP STEP 2. OPTIONAL capabilities: their absence does NOT reject
-- the host, it only turns off the feature that depends on it.
--
-- This is the price of touching more than one point of the host, and the
-- price has to be paid here, not at the site of the accident. v1.4.2's
-- probe already proved the idea's worth: it is the reason v1.5.0 survived
-- the original repository going dark twice and the community splitting
-- into three lineages. A new feature that depends on more host API has to
-- come in through the same door, otherwise the first change from a fork
-- takes the whole mod down with it.
--
-- Every capability is a question only the host can answer, answered by
-- reading and never by version number.
local function probeCapabilities(modules)
  return {
    -- Life channel: requires Voxel3D.draw to exist as a function
    -- replaceable by FIELD. There is no way to verify by reading that the
    -- call sites resolve the field at call time (on the three living
    -- lineages, all 32 do), but it is possible to require the minimum:
    -- that the field exists and is callable. The rest is covered by the
    -- pcall around the write.
    drawWrap = type(modules.Voxel3D) == "table"
      and type(modules.Voxel3D.draw) == "function",
  }
end

-- Capability probe: a host is usable when exports.lib exists and returns
-- the three required modules, and SpriteBillboards.mesh is a function.
-- The three optional ones (VoxelState, FirstPerson, VoxelScene) stay
-- optional, handled in patch(). pcall on every require because a host
-- that passes the id check but is missing one of the required modules (or
-- whose require blows up) has to be rejected cleanly, without taking down
-- the whole mod's loading (same class of defect as round 2).
local function probeHost(handle)
  -- Moved from chunk scope (roadmap item 0: main chunk locals): only read
  -- here.
  local REQUIRED_MODULES = { "Voxel3D", "ImageCache", "SpriteBillboards" }
  if not (handle.exports and handle.exports.lib) then
    return nil, "exports.lib is missing"
  end
  local V = handle.exports.lib
  local modules = {}
  for _, name in ipairs(REQUIRED_MODULES) do
    local ok, required = pcall(V.require, name)
    if not ok or required == nil then
      return nil, name .. " is missing"
    end
    modules[name] = required
  end
  if type(modules.SpriteBillboards.mesh) ~= "function" then
    return nil, "SpriteBillboards.mesh is not a function"
  end
  return modules, nil, probeCapabilities(modules)
end

local function findHost()
  local rejected = {}
  for _, host in ipairs(HOSTS) do
    local handle = mod.find(host.id)
    if not handle then
      rejected[#rejected + 1] = host.id .. ": not found"
    else
      local modules, why, caps = probeHost(handle)
      if modules then
        local okVersion, versionWhy = Semver.satisfies(handle.version, host.supported)
        if not okVersion then
          mod.log:warn(
            "found %s %s (%s) with an untested version (checked against %s: %s); " ..
            "continuing because the required API is present",
            host.name, tostring(handle.version), host.id, host.supported,
            tostring(versionWhy or "does not satisfy the range"))
        end
        return {
          id = host.id,
          name = host.name,
          supported = host.supported,
          handle = handle,
          modules = modules,
          caps = caps,
        }
      end
      rejected[#rejected + 1] = ("%s: found %s but %s")
        :format(host.id, tostring(handle.version), why)
    end
  end
  return nil, table.concat(rejected, "; ")
end

local host, hostRejects = findHost()
if not host then
  mod.log:warn("could not find usable Voxel Characters host; checked %s: %s",
    hostIds(), hostRejects)
  registerOptionsRows()
  return
end

local handle = host.handle
mod.log:info("found %s %s (%s)", host.name, tostring(handle.version), host.id)

local ok, err = pcall(patch, host)
if not ok then
  mod.log:warn("could not patch %s character billboards: %s", host.name, tostring(err))
  registerOptionsRows()
end

-- NAMED ANCHORS, the read side (roadmap T1.2).
--
-- Deliberately the smallest surface that answers the question an effect asks:
-- "where is this character's hand right now". Given one of our meshes it
-- returns the four anchors in CHARACTER space, each with the band it belongs
-- to; the caller composes them with whatever transform the frame is using, the
-- same one the draw wrap applies to that band.
--
-- Not a public API yet. The roadmap is explicit that a presentation API waits
-- for two real consumers, and today there are none: this exists so the gate can
-- measure the anchors and so T2.3's effects have something to attach to. Kept
-- as one function on the mod table rather than a namespace for exactly that
-- reason, and because main.lua's chunk-local budget is a real constraint.
function mod._anchors(mesh)
  return meshAnchors[mesh]
end

-- ANIMATION EVENTS, the read side (roadmap T1.2 slice 2).
--
-- Returns the edges that arrived since the last read, and empties the mailbox.
-- Reader-clears rather than writer-clears on purpose: the host draws each
-- character twice per frame and PART LAG issues one draw per band, so clearing
-- on write would let the last band's silence erase the first band's footstep.
--
-- Not a public API, for the same reason `_anchors` is not: there is no consumer
-- until T2.3 has an effect to fire, and the roadmap holds a presentation API
-- until two exist.
-- Named `_animEvents` and not `_events`: the mod handle already carries an
-- `events` namespace for the host's own event bus, and the offline suite keeps
-- registered handlers on `mod._events`. Colliding with either would have been
-- silent in production and loud only in the suite, which is where it surfaced.
function mod._animEvents()
  if #eventosPendentes == 0 then return eventosPendentes end
  local saida = eventosPendentes
  eventosPendentes = {}
  return saida
end

-- HOW MANY EFFECTS ARE ALIVE (roadmap T2.3), a test hook and not an API.
--
-- Exists because the first gate for the FX demo inferred liveness from the
-- NUMBER OF DRAW CALLS in a frame, and that turned out to be too coarse to
-- prove anything: with both off-guards deliberately defeated, the OFF run still
-- passed, because spawns are rare and the driver was not sampling the frames
-- where an effect happened to be alive. A gate that cannot fail on a broken off
-- path is not guarding the off path.
--
-- Counting the live list directly removes the sampling question entirely: an
-- effect that exists is counted whether or not a draw call landed on the frame
-- the test looked at.
--
-- Internal, like `_anchors` and `_animEvents`, for the same reason: the roadmap
-- holds a public presentation API until two real consumers exist.
function mod._fxVivos()
  return #FX.vivos
end

-- HOW MANY EFFECTS HAVE EVER SPAWNED (roadmap T2.3 slice 4), a test hook.
--
-- The audio gate matches one sound to one effect, and it has to count against
-- SPAWNS rather than against footfalls: the cap can refuse a spawn, and a sound
-- played for a refused effect would be a noise with nothing behind it.
function mod._fxNascidos()
  return FX.nascidos
end

-- THE BAND RANGES PART LAG WILL CUT ALONG (roadmap T2.1 slice 3).
--
-- Internal test hook, not public API, same as the four above. It is what lets
-- the region path be checked without a person looking at a screen: the gate
-- builds one mesh with AUTHORED REGIONS off and one with it on, reads the
-- boundaries out of both, and compares them against the measured sheet.
--
-- It returns the ranges as they are stored, in VERTEX indices, head first.
-- Deriving the row each boundary falls on is the caller's job, because that
-- conversion belongs next to whatever is asking rather than in here.
function mod._bands(mesh)
  return meshBands[mesh]
end

-- Whether a sheet's measured metadata is reachable at all, and what it says.
-- Exists so a gate can tell "the regions did nothing because the option is
-- off" apart from "the regions did nothing because the file never loaded",
-- which otherwise look identical from outside and are very different problems.
function mod._authoredRegions(base)
  return authoredRegions(base)
end
