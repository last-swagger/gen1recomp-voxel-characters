-- ONE LANDING SURFACE FOR BOTH GAMES, PICKED BY CAPABILITY.
--
--   local W = dofile("mods/voxel_characters/tools/ingame/world.lua")
--   local w = W.of(game)          -- nil when nothing here can drive this game
--   w:land("PLAYERS_HOUSE_2F", 3, 3, "down")
--   local cx, cy = w:cell()
--
-- WHY THIS EXISTS, AND WHAT IT COST TO FIND OUT.
--
-- Every probe in this directory reaches the player through two names that only
-- Gen 1 has: `U.teleport` (tests/drivers/util.lua) and `game.overworld`. Input
-- is not the problem -- `game.input.pressQueue` and `game.input.state` are the
-- same object on both games, which is why the core's own ~90 Gold drivers use
-- them unchanged. The WORLD is the problem, and the two are disjoint:
--
--                       Gen 1                     Gold
--   the overworld       game.overworld, a state   game.world, not a state
--                       pushed on game.stack      at all; an EMPTY stack is
--                                                 free roam
--   landing             stack:push(OverworldState, world:setMap(id,x,y,f)
--                       id, x, y, facing)
--   the player's cell   overworld.player.cellX    world.player.cellX
--   a script is up      transitioning / runner    world:busy()
--
-- MEASURED ON GOLD, 2026-08-17, with today's harness pointed at it. Not one of
-- these three throws, which is the whole reason this file exists rather than a
-- bug report:
--
--   1. `game.overworld` is nil, so every probe's "did I reach the world" test
--      (`game.overworld and game.stack:top() == game.overworld`) is nil and
--      the probe aborts having measured nothing;
--   2. `MapLoader.load(game.data, "PLAYERS_HOUSE_2F")` fails with "attempt to
--      index field 'maps' (a nil value)" -- Gold keeps its maps somewhere
--      else -- and tools/ingame/pouso.lua swallows that and returns radius 0,
--      which is its code for "the cell you asked for is fine". It answered
--      radius 0 for cell 0,0 of PLAYERS_HOUSE_2F, which is a wall. The landing
--      validator had quietly become a rubber stamp;
--   3. `U.teleport` returns without error, having pushed a GEN 1
--      OverworldController onto Gold's stack. Gold reads a non-empty stack as
--      "a menu is open", so the player then froze: holding `down` for 80
--      frames moved the cell 3,3 -> 3,3.
--
-- A crash would have been kinder than any of those.
--
-- WHY CAPABILITY AND NEVER A GAME NAME. This project's founding rule, and it
-- has already survived a 309-commit engine jump: a backend is chosen by
-- probing for the members it is about to call, never by asking which game is
-- booted. `POKEPORT_GAME == "gold"` is a fact about today's build; "this
-- object has a setMap and a player" is a fact about what the code can do, and
-- it stays true through a rename, a fork, or a third generation nobody has
-- written yet. `name` below is for the log line and for nothing else -- no
-- branch anywhere may read it.
--
-- AMBIGUITY IS LOUD. If two backends both answer, `of` returns nil and says
-- so rather than taking the first. A game that grew a second landing surface
-- is a game where the harness would be measuring one of them by accident, and
-- accidentally-right is the failure mode this whole directory is built to
-- avoid.
--
-- WHAT IS NOT IN HERE, ON PURPOSE. Input: `game.input` is already shared, and
-- wrapping it would invent a difference that does not exist. Frames: nothing
-- here yields, so it can be called from outside a coroutine and so a caller
-- can never be surprised by a hidden wait. `land` returns as soon as the game
-- has accepted the request; letting frames pass afterwards is the caller's
-- job, exactly as it already is after `U.teleport`.

local W = {}

-- The lists the overworld draws and updates its actors from. Both games spell
-- them the same -- `entities`, `npcs`, `ghosts` -- which is the only reason
-- this is one function and not two; the ones that are missing are simply left
-- out, so a game with two of the three is handled without being asked which
-- game it is. Used by the probes that have to empty a room before measuring
-- it, and it is the same surgery the host performs on itself when a runtime
-- object is dropped.
local function actorLists(obj)
  local out = {}
  if type(obj) ~= "table" then return out end
  for _, key in ipairs({ "entities", "npcs", "ghosts" }) do
    if type(obj[key]) == "table" then out[#out + 1] = obj[key] end
  end
  return out
end

-- Each backend lists, in `detect`, every member it is about to call. That is
-- the whole contract: a backend may only claim a game whose surface it has
-- actually checked for.
local BACKENDS = {
  {
    -- Gold and anything else whose overworld is an object rather than a state.
    name = "gen2 world object",
    detect = function(game)
      local w = type(game) == "table" and game.world
      return type(w) == "table"
        and type(w.setMap) == "function"
        and type(w.busy) == "function"
        and type(w.connectionMap) == "function"
        and type(w.player) == "table"
        and type(game.stack) == "table"
    end,
    build = function(game)
      local self = {}

      local function world() return game.world end

      function self:player() return world().player end

      -- No nil guard on the player here, unlike the Gen 1 backend below, and
      -- the difference is real rather than an oversight: this world builds its
      -- player in World.new and cannot be detected before that, while Gen 1's
      -- overworld state exists from boot with no player until something lands
      -- on it. Measured: G1 of tools/ingame/probe_world.lua reports cell 3,3 on
      -- Gold at boot and cell nil,nil on Blue.
      function self:cell()
        local p = world().player
        return p.cellX, p.cellY
      end

      function self:moving()
        local p = world().player
        return p.moving and true or false
      end

      function self:map() return world().map end

      function self:mapId()
        local m = world().map
        return m and m.id
      end

      function self:land(mapId, cx, cy, facing)
        local ok = world():setMap(mapId, cx, cy, facing or "down")
        return ok and true or false
      end

      -- The LIVE map when it is the one being asked about, because that is the
      -- object collision really runs against; anything else through the
      -- engine's own cached builder, which is how World itself gets a
      -- neighbour's collision without moving the player.
      function self:loadMap(mapId)
        local w = world()
        if w.map and w.map.id == mapId then return w.map end
        local ok, m = pcall(w.connectionMap, w, mapId)
        return (ok and m) or nil
      end

      function self:busy() return world():busy() and true or false end

      -- Gold's own free-roam test (src/core/Game2.lua:pipelineGate): the world
      -- is not a state, so an EMPTY stack is free roam and anything on the
      -- stack is a screen sitting over it.
      function self:inWorld()
        return world().map ~= nil and game.stack:top() == nil
      end

      function self:npcAtCell(cx, cy)
        local w = world()
        if type(w.npcAtCell) ~= "function" then return nil end
        local ok, npc = pcall(w.npcAtCell, w, cx, cy)
        return ok and npc or nil
      end

      function self:actors() return actorLists(world()) end

      return self
    end,
  },
  {
    -- Gen 1: the overworld is a state module, and it is both the class the
    -- stack is pushed with and the live instance the fields are read off.
    name = "gen1 overworld state",
    detect = function(game)
      return type(game) == "table"
        and type(game.overworld) == "table"
        and type(game.stack) == "table"
        and type(game.stack.push) == "function"
        and type(game.stack.pop) == "function"
    end,
    build = function(game)
      local self = {}

      local function ow() return game.overworld end

      function self:player() return ow().player end

      function self:cell()
        local p = ow().player
        if not p then return nil, nil end
        return p.cellX, p.cellY
      end

      function self:moving()
        local p = ow().player
        return (p and p.moving) and true or false
      end

      function self:map() return ow().map end

      function self:mapId()
        local m = ow().map
        return m and m.id
      end

      -- U.teleport's body, minus the `require`: the class to push is the one
      -- the game is already holding, so this cannot land a state from a
      -- different tree than the one running.
      function self:land(mapId, cx, cy, facing)
        while game.stack:top() do game.stack:pop() end
        local ok = pcall(game.stack.push, game.stack, ow(),
          mapId, cx, cy, facing or "down")
        return ok and true or false
      end

      function self:loadMap(mapId)
        local live = ow().map
        if live and live.id == mapId then return live end
        local okReq, MapLoader = pcall(require, "src.world.MapLoader")
        if not (okReq and MapLoader and MapLoader.load) then return nil end
        local ok, m = pcall(MapLoader.load, game.data, mapId)
        return (ok and m) or nil
      end

      -- Gen 1 has no single `busy`. These are the two fields the engine's own
      -- idle test reads (Zoom.gateOK, src/render/Zoom.lua:104): a map
      -- transition in flight, or a script runner with something to say.
      function self:busy()
        local o = ow()
        if o.transitioning then return true end
        local r = o.runner
        if r and type(r.isRunning) == "function" and r:isRunning() then
          return true
        end
        return false
      end

      function self:inWorld()
        return game.stack:top() == ow() and ow().map ~= nil
      end

      function self:npcAtCell(cx, cy)
        local o = ow()
        if type(o.npcAtCell) ~= "function" then return nil end
        local ok, npc = pcall(o.npcAtCell, o, cx, cy)
        return ok and npc or nil
      end

      function self:actors() return actorLists(ow()) end

      return self
    end,
  },
}

-- The backend for this game, or nil and the reason. Never guesses.
function W.of(game)
  local matched = {}
  for _, b in ipairs(BACKENDS) do
    local ok, answer = pcall(b.detect, game)
    if ok and answer then matched[#matched + 1] = b end
  end
  if #matched == 0 then
    return nil, "no world backend recognised this game: it has neither a world "
      .. "object with setMap/busy/player nor an overworld state on a stack"
  end
  if #matched > 1 then
    local names = {}
    for _, b in ipairs(matched) do names[#names + 1] = b.name end
    return nil, "more than one world backend claims this game (" ..
      table.concat(names, ", ") .. "); refusing to pick, because measuring "
      .. "through the wrong one would still look like it worked"
  end
  local w = matched[1].build(game)
  w.name = matched[1].name
  return w
end

-- Is this cell a wall? Both Map classes answer `isWalkableCell`, and a map
-- that cannot answer at all is treated as a wall: a probe that needs a wall
-- for its control must not be handed a cell nobody vouched for.
function W.wall(map, cx, cy)
  if type(map) ~= "table" or type(map.isWalkableCell) ~= "function" then
    return true
  end
  local ok, walkable = pcall(map.isWalkableCell, map, cx, cy)
  return not (ok and walkable == true)
end

return W
