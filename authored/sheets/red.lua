-- ASH, measured against the real sprite (roadmap T2.1, slices 1 and 2).
--
-- `red` is Ash: the sheet is named for the player character's Japanese-release
-- name, which is what the ROM calls him, and every tool here uses the sheet
-- name rather than the character's.
--
-- WHAT THIS IS NOT. It is not an art pack, and it ships no pixels: `overlays`
-- is empty, so this sheet's authored pixel count is zero and the provenance
-- metric reports it as zero. Nothing in the mod loads this file.
--
-- SLICE 1 NAMED THE REGIONS AND REFUSED TO SAY WHERE THEY WERE, on the grounds
-- that pixel bounds written before anything can check them are invented
-- numbers. `tools/measure_regions.py` is the thing that can check them, and the
-- `measured` block below is its output rather than anybody's estimate. It runs
-- offline in the battery, so a bound that stops matching the sprite fails on
-- the next commit instead of at some later render.
--
-- THE ONE FINDING WORTH READING BEFORE THE NUMBERS. The walking frames sit ONE
-- ROW LOWER than the standing frames. That is the sprite's own bob, and it
-- matters here more than anywhere else, because `PART LAG` cuts the body into
-- bands with `math.floor(y / cellH * REGION_BANDS)`, measured from the cell and
-- not from the figure. Every band boundary therefore lands one row too high on
-- every walking frame. That is not a defect this slice fixes; it is the exact
-- reason the roadmap wants authored regions at all, now with a number on it.

return {
  kind = "living",

  -- WHICH regions this sheet has. Where they are lives in `measured`, and only
  -- for the ones that can be read off the pixels without interpreting a shape.
  regions = {
    head = true,
    hair = true,
    body = true,
    feet = true,
  },

  -- Measured by tools/measure_regions.py, which reads this character's sheet
  -- out of the player's own imported sprite cache. The path is named there
  -- and deliberately not here: modkit's MK301 refuses any shipped Lua that
  -- points at that tree, and it is right to, because a distributed mod has
  -- no business doing so. This file ships; the tool does not need to.
  -- DO NOT HAND-EDIT: the gate re-measures and fails on any disagreement, so a
  -- hand-written number here does not survive the next battery.
  --
  --   top/bottom/left/right   the opaque bounding box, in cell rows and columns
  --   lightFreeBottom         last row from the top with no light tone in it
  --   footSplit               lowest row whose silhouette is two separate runs
  --   bob                     rows below the standing frame this frame sits
  --
  -- footSplit is `nil` on frames 2 and 4 and that is a measurement, not a gap:
  -- the side standing pose has both feet together, and the back walking pose
  -- shows one foot. A number there would be an invention.
  measured = {
    [0] = { top = 0, bottom = 15, left = 1, right = 14, lightFreeBottom = 3, footSplit = 15, bob = 0 },
    [1] = { top = 0, bottom = 15, left = 1, right = 14, lightFreeBottom = 5, footSplit = 15, bob = 0 },
    [2] = { top = 0, bottom = 15, left = 1, right = 13, lightFreeBottom = 2, footSplit = nil, bob = 0 },
    [3] = { top = 1, bottom = 15, left = 1, right = 14, lightFreeBottom = 4, footSplit = 14, bob = 1 },
    [4] = { top = 1, bottom = 15, left = 1, right = 14, lightFreeBottom = 6, footSplit = nil, bob = 1 },
    [5] = { top = 1, bottom = 15, left = 1, right = 13, lightFreeBottom = 3, footSplit = 15, bob = 1 },
  },

  -- WHICH FRAMES `lightFreeBottom` MAY BE READ AS THE CAP, and this distinction
  -- is the whole reason the field is named for what it measures instead of what
  -- it means.
  --
  -- Where there is a face, the rows above it are the cap crown. Where there is
  -- not, the same measurement runs down past the head to the first light pixels,
  -- which are his hands: frame 1 reports 5 and frame 4 reports 6, and neither is
  -- a cap. The number is still a fact on those frames; it is just not this
  -- region.
  --
  -- The discriminator is measured rather than eyeballed. `capReadable` asks
  -- whether the first light pixels sit in the central half of the cell, which
  -- is where a face is and where a pair of hands is not. This list was
  -- originally the two front frames, written from reading the sprite by eye;
  -- the measurement says the two SIDE frames resolve as well, because the face
  -- in profile still lands inside the middle. Widened to follow the evidence.
  hairFrames = { 0, 2, 3, 5 },

  -- How strongly the life channel should read on this sheet, 0 to 1. 1 means
  -- "the defaults are right for him". It exists so a future sheet can say it is
  -- stiffer or livelier than average WITHOUT anyone editing the mod's amplitude
  -- constants, which are shared by everyone.
  responsiveness = 1.0,

  -- EMPTY ON PURPOSE. The first authored pixel is a decision Kim has not made
  -- and this slice does not make for him. An empty list is a valid state, it
  -- keeps the authored pixel count at zero, and it means the day something is
  -- added here the diff is exactly the thing that changed.
  overlays = {},

  -- NO BAG, and its absence is a finding rather than an omission.
  --
  -- The roadmap's motivating example for authored regions is letting `PART LAG`
  -- "cut along a bag strap instead" of in equal bands. On this sheet there is no
  -- bag strap to cut along. The front and side views show none at all. The back
  -- views do have a mid-tone block across the shoulders, at rows 10 to 12, which
  -- could be a pack or could be the back of his shirt, and at sixteen pixels
  -- square nothing in the image decides between them.
  --
  -- So `bag` is not declared. Declaring it and guessing bounds would put an
  -- invented number in a file whose whole purpose is that its numbers are
  -- measured, and the narrower claim is reversible: if Kim says the block is a
  -- pack, it becomes a region with his word as the source, recorded as such.
  note = "Ash. Bounds measured, not estimated. No bag on this sheet. "
      .. "Ships no authored pixels.",
}
