-- Picks where the driver can drop the player without them showing up on top of
-- nothing at all.
--
-- THE BUG THIS FIXES. `U.teleport(game, mapa, x, y, dir)` empties the
-- stack and pushes the OverworldController to those coordinates WITHOUT VALIDATING ANYTHING
-- (tests/drivers/util.lua:85-90). If the cell is a sign, a table, a
-- wall, or an NPC, the player lands there and stays. Kim saw this in the
-- gate screenshots before I did: "the ash is standing on top of a place it wasn't supposed to be".
-- The screenshots were right; the driver was the one that was wrong.
--
-- The game already knows how to answer this question. None of these checks were invented
-- here, they're all things the engine itself already consults:
--
--   map:inBounds(cx, cy)              Map.lua:216   inside the map bounds
--   map:isWalkableCell(cx, cy)        Map.lua:220   the same check that Collision uses
--   map:signAtCell(cx, cy)            Map.lua:287   sign. this was the one in the screenshot
--   map:warpAtCell(cx, cy)            Map.lua:283   registered door
--   map:isWarpTileCell(cx, cy)        Map.lua:261   tile that triggers the door
--   map:warpPadOrHoleAt(cx, cy)       Map.lua:268   teleport pad, hole
--   overworld:npcAtCell(cx, cy)       OverworldController.lua:1721   who's there
--
-- THE MAP COMES THROUGH tools/ingame/world.lua, NOT FROM MapLoader DIRECTLY,
-- and this is the correction that made the file honest on a second game.
-- MapLoader is Gen 1's: on Gold `MapLoader.load(game.data, id)` fails with
-- "attempt to index field 'maps' (a nil value)", and the version of `escolher`
-- below that swallowed that returned radius 0 -- its code for "the cell you
-- asked for is already fine". Measured on Gold 2026-08-17: it said radius 0
-- for cell 0,0 of PLAYERS_HOUSE_2F, which is a wall. Every one of the seven
-- checks had silently become a no-op and the function still reported success,
-- which is the exact failure this file was written to stop, one generation
-- further along. A map that cannot be loaded now comes back as radius nil with
-- a reason, so it reads as "I could not check" rather than as "it is fine".
--
-- Warp and hole are left out because landing on top of them switches maps on the
-- first frame and the driver loses the map it asked for. `npcAtCell` is better than
-- sweeping `npcs` by hand: it also catches the NPC that is ENTERING the cell
-- (targetX/targetY), which is half a step away from becoming an overlap.
--
-- Twenty-odd drivers in the project itself do some version of this, each one
-- their own way, and none of them cover all seven checks. This one does.

local Pouso = {}

-- The adapter is loaded once and kept. `dofile` recompiles the file on every
-- call, and `escolher` is called inside loops (tools/ingame/trailer.lua walks a
-- list of stations through it), so the naive version re-read the same file off
-- disk once per station.
local World
local function adapter()
  if World == nil then
    local ok, mod = pcall(dofile, "mods/voxel_characters/tools/ingame/world.lua")
    World = (ok and mod) or false
  end
  return World or nil
end

-- Growing rings around the requested cell (Chebyshev distance). The search
-- returns the first good cell, so it's always the closest one to what the
-- caller wanted: if the requested cell already works, that's the one that comes out, and nothing changes
-- where it was already right.
local function anel(raio)
  if raio == 0 then return { { 0, 0 } } end
  local pontos = {}
  for d = -raio, raio do
    pontos[#pontos + 1] = { d, -raio }
    pontos[#pontos + 1] = { d, raio }
  end
  for d = -raio + 1, raio - 1 do
    pontos[#pontos + 1] = { -raio, d }
    pontos[#pontos + 1] = { raio, d }
  end
  return pontos
end

-- Each method wrapped in pcall: a map from a game version that lacks one of
-- them can't take down the whole driver. Absence counts as "doesn't block", which
-- is the safe side: worst case we fall back to the old behavior instead
-- of not landing anywhere at all.
local function chama(obj, metodo, ...)
  if type(obj) ~= "table" or type(obj[metodo]) ~= "function" then return nil end
  local ok, r = pcall(obj[metodo], obj, ...)
  return ok and r or nil
end

-- Why this cell does NOT work, or nil when it does.
function Pouso.recusa(map, ow, cx, cy)
  if not map then return "sem mapa" end
  if chama(map, "inBounds", cx, cy) == false then return "fora do mapa" end
  if chama(map, "isWalkableCell", cx, cy) ~= true then return "nao da para andar" end
  if chama(map, "signAtCell", cx, cy) then return "placa" end
  if chama(map, "warpAtCell", cx, cy) then return "porta" end
  if chama(map, "isWarpTileCell", cx, cy) then return "tile de porta" end
  if chama(map, "warpPadOrHoleAt", cx, cy) then return "plataforma ou buraco" end
  if ow and chama(ow, "npcAtCell", cx, cy) then return "tem alguem" end
  return nil
end

-- Returns map, x, y, radius, why. `radius` is how many cells the search had to
-- walk (0 = the requested cell already worked), or nil when nothing was found
-- OR nothing could be checked -- and `why` is which of those two it was.
--
-- Loads the map WITHOUT teleporting first, through the world adapter: on Gen 1
-- that is the same MapLoader call OverworldController:setMap makes
-- (OverworldController.lua:320) and the result stays cached, so the next
-- teleport reuses it; on Gold it is World:connectionMap, which is how the
-- engine itself gets a map's collision without moving the player. The first
-- version of this teleported to the bad spot just to be able to read the map and then
-- teleported again, which showed up on screen as a flicker.
function Pouso.escolher(game, mapa, x, y, raioMax)
  local W = adapter()
  local w = W and W.of(game) or nil
  if not w then
    return mapa, x, y, nil, "no world adapter answered for this game, so "
      .. "nothing about this cell was checked"
  end
  local map = w:loadMap(mapa)
  if not map then
    return mapa, x, y, nil, "could not load " .. tostring(mapa)
      .. ", so nothing about this cell was checked"
  end

  -- The world is only used to query NPCs, and only when we're already on THIS
  -- map; on a different map the NPC list belongs to another place and would answer
  -- about people who aren't there.
  local ow = (w:mapId() == mapa) and w or nil

  for raio = 0, (raioMax or 8) do
    for _, p in ipairs(anel(raio)) do
      local cx, cy = x + p[1], y + p[2]
      if not Pouso.recusa(map, ow, cx, cy) then return mapa, cx, cy, raio end
    end
  end
  -- No good cell nearby. Returns the original request and signals it via nil:
  -- surfacing the problem is better than hiding it in some random spot.
  return mapa, x, y, nil, "no cell within " .. tostring(raioMax or 8)
    .. " of " .. x .. "," .. y .. " passes every check"
end

return Pouso
