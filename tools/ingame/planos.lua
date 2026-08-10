-- THE SHOT LIBRARY: named places and camera setups, shared by every tool that
-- films (roadmap item 21.3).
--
-- WHY THIS EXISTS. The trailer's shot list carried its own map names, tile
-- coordinates and camera rungs inline, and the clip tool carried a different
-- set of its own. So a feature filmed today and the same feature filmed in
-- March are framed differently for no reason anyone chose, and comparing two
-- recordings of a release means comparing two framings as well.
--
-- Naming them fixes that and does one more thing: a landing spot that turns
-- out to be bad, a wall the character keeps walking into, a room where an NPC
-- stands in front of the subject, gets fixed ONCE here instead of in every
-- shot list that copied it.
--
-- Each entry says what it is FOR, because the next person choosing a shot is
-- choosing by intent and not by coordinates.

local P = {}

P.LOCAIS = {
  -- The opening. Pallet Town from the player's own doorstep: the most
  -- recognisable frame in the game, and the one where "exactly as it has
  -- always been" is a claim a viewer can check.
  abertura = {
    mapa = "PALLET_TOWN", x = 5, y = 6, dir = "down",
    para = "the opening, and any before-and-after of the world tipping over",
  },
  -- A town with buildings, fences and several NPCs at once. This is the shot
  -- that has to carry "a whole city, and not one flat card", so it needs
  -- depth in the scene and other people in frame.
  cidade = {
    mapa = "VIRIDIAN_CITY", x = 17, y = 17, dir = "down", anda = true,
    para = "crowds, and anything that has to be seen on more than one body",
  },
  -- Indoors, bright, and with NPCs who stand still. The life channel is a
  -- half-pixel effect, so it needs a place where nothing else moves; a
  -- Pokemon centre is the brightest room in the game and its staff do not
  -- wander.
  interior = {
    mapa = "CERULEAN_POKECENTER", x = 3, y = 4, dir = "up",
    para = "breath, blink, attention: small effects that need a still scene",
  },
  -- Open road with tall grass and a long clear walk. The one place a
  -- character can walk for six seconds without meeting a wall, which is what
  -- the step options need.
  estrada = {
    mapa = "ROUTE_1", x = 10, y = 20, dir = "down", anda = true,
    para = "walking: footfall, motion lag, step weight, part lag",
  },
  -- An empty room. ZERO object events, which is why the in-game gates use it:
  -- with nobody else on screen the measurement floor sits at zero.
  vazio = {
    mapa = "REDS_HOUSE_2F", x = 3, y = 4, dir = "down",
    para = "measurement, not footage: the only place with a floor of zero",
  },
}

-- The camera rungs by NAME, so no shot list carries a magic number. The host's
-- ladder is ANGLES_DEG = {0, 35, 15, 35, 50, 75, 75, 75}, indexed by level+1,
-- so level 0 is the flat game and 5 is the most upright. FP_LEVEL is the
-- first-person rung and is read from the host rather than written here,
-- because it is the one that has moved between host versions.
P.DEGRAUS = { plano = 0, baixo = 2, medio = 3, alto = 4, empe = 5 }

-- Camera setups, as a rung plus a zoom in notches. Zoom is signed the way the
-- host signs it: POSITIVE PULLS OUT, so closing in is negative.
P.CAMERAS = {
  jogo    = { degrau = "plano", zoom = 0,
              para = "the game as it ships, for a before shot" },
  padrao  = { degrau = "alto", zoom = 0,
              para = "the default view: what most players actually see" },
  baixa   = { degrau = "medio", zoom = 0,
              para = "a shallower angle, where top faces matter least" },
  retrato = { degrau = "empe", zoom = -3,
              para = "close on one face: blink, attention, anything small" },
  larga   = { degrau = "alto", zoom = 2,
              para = "wide, for crowds and for showing a whole street" },
}

-- Resolves a named location and camera into the flat table a shot list wants,
-- so a shot can say `P.plano("interior", "retrato")` and get everything.
-- Extra fields override, because a shot list still needs to say how long it
-- runs and what its caption is.
function P.plano(local_, camera, extra)
  local L = P.LOCAIS[local_]
  local C = P.CAMERAS[camera]
  if not L then error("unknown location: " .. tostring(local_), 2) end
  if not C then error("unknown camera: " .. tostring(camera), 2) end
  local p = {}
  for k, v in pairs(L) do p[k] = v end
  for k, v in pairs(C) do p[k] = v end
  p.para = nil            -- documentation, not a shot field
  for k, v in pairs(extra or {}) do p[k] = v end
  return p
end

return P
