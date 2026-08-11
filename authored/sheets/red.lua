-- ASH, the one living fixture (roadmap T2.1, slice 1).
--
-- `red` is Ash: the sheet is named for the player character's Japanese-release
-- name, which is what the ROM calls him, and every tool here uses the sheet
-- name rather than the character's.
--
-- WHAT THIS IS NOT. It is not an art pack, and it ships no pixels: `overlays`
-- is deliberately empty, so this sheet's authored pixel count is zero and the
-- provenance metric reports it as zero. Nothing in the mod loads this file.
--
-- WHAT IT IS FOR. One real sheet, described in the schema's own vocabulary, so
-- that the schema is exercised by something rather than only by its own tests.
-- Ash is the right first sheet because he is the one the creator item (T2.2)
-- starts from and the one Kim looks at most.
--
-- THE REGIONS ARE DECLARED AND UNMEASURED, and that is deliberate. Writing
-- pixel bounds now would be inventing numbers before anything can check them:
-- the honest first version says WHICH regions this sheet has, which is a claim
-- the schema can validate, and leaves WHERE they are to the slice that can
-- measure it against the real sprite. `PART LAG` cuts in four bands found from
-- cap rows today; the payoff of this table is letting it cut along the bag
-- strap instead, and a made-up strap row would be worse than none.

return {
  kind = "living",

  regions = {
    head = true,
    hair = true,   -- the cap, which on this sheet is not separable from head
                   -- at every frame; the measuring slice has to say so
    body = true,
    bag = true,    -- the reason this table is worth having
    feet = true,
  },

  -- How strongly the life channel should read on this sheet, 0 to 1. 1 means
  -- "the defaults are right for him". It exists so a future sheet can say it
  -- is stiffer or livelier than average WITHOUT anyone editing the mod's
  -- amplitude constants, which are shared by everyone.
  responsiveness = 1.0,

  -- EMPTY ON PURPOSE. The first authored pixel is a decision Kim has not made
  -- and this slice does not make for him. An empty list is a valid state, it
  -- keeps the authored pixel count at zero, and it means the day something is
  -- added here the diff is exactly the thing that changed.
  overlays = {},

  note = "Ash. Regions named, not measured. Ships no authored pixels.",
}
