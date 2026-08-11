-- THE OBJECT FIXTURE, which exists to be refused (roadmap T2.1, slice 1).
--
-- An item ball is not alive, and the roadmap asks for one object sheet in the
-- first pass for exactly one reason: so that a rule cannot accidentally make an
-- item ball or a boulder breathe. That is not a hypothetical. `main.lua` pins
-- `boulder`, `clipboard`, `fossil`, `old_amber`, `paper`, `poke_ball` and
-- `pokedex` to zero life BY HAND, in `STILL_OBJECTS`, because a general rule
-- made them pulse and a pulsing item ball on the ground was, in the comment's
-- own words, the most obviously wrong thing the mod could do.
--
-- So this file declares the minimum a sheet can declare, and the gate then
-- proves three things about it:
--
--   1. it validates, because "object" is a legitimate thing to be;
--   2. adding ANY living field to it -- regions, responsiveness, deformation --
--      is refused by the schema rather than ignored;
--   3. its kind agrees with `STILL_OBJECTS` in the mod's own source, so the
--      authored layer and the runtime cannot drift into disagreeing about what
--      is alive. If someone deletes poke_ball from that list, this fixture goes
--      red, which is the correct reaction to the mod deciding an item ball
--      breathes.
--
-- The third one is what makes this a fixture rather than a comment.

return {
  kind = "object",

  -- No regions. No responsiveness. No deformation. Not because they are
  -- unknown, but because they are meaningless here, and the schema refuses
  -- them on an object rather than accepting and disregarding them.

  overlays = {},

  note = "An item ball. Not alive; see STILL_OBJECTS in main.lua.",
}
