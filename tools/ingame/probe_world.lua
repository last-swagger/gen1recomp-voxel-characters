-- CAN THE HARNESS LAND AND DRIVE THE PLAYER AT ALL, ON WHICHEVER GAME BOOTED?
--
--   bash mods/voxel_characters/tools/ingame/gold.sh
--
-- or by hand, once the landing is chosen:
--
--   VC_MAP=PLAYERS_HOUSE_2F VC_X=3 VC_Y=3 POKEPORT_VERSION=gold \
--     POKEPORT_DRIVER=mods/voxel_characters/tools/ingame/probe_world.lua love .
--   VC_MAP=REDS_HOUSE_2F VC_X=4 VC_Y=4 POKEPORT_VERSION=blue \
--     POKEPORT_DRIVER=mods/voxel_characters/tools/ingame/probe_world.lua love .
--
-- gold.sh is what arranges for the mod to be attached on a Gen 2 game before
-- this boots; on Gen 1 nothing has to be arranged.
--
-- WHY THIS EXISTS. Every other in-game probe here measures pixels, and every
-- one of them takes for granted that it can already put the player somewhere
-- and make it walk. On Gen 1 that is `U.teleport` plus `game.overworld`.
-- Neither name exists on Gold, so the whole measuring layer stops at the door,
-- and the host matrix (tools/ingame/hosts.sh) is the only thing that can say
-- anything at all about Gen 2 -- and all it can say is "the mod attached",
-- which is the first sentence and not the paragraph.
--
-- It is not that the old path fails loudly. Measured on Gold 2026-08-17 it
-- returns success at every step: `U.teleport` pushes a Gen 1 state onto Gold's
-- stack without erroring, Gold reads a non-empty stack as "a menu is open",
-- and the player then does not move at all -- holding `down` for 80 frames
-- moved the cell 3,3 -> 3,3. A pixel probe pointed at that would have
-- photographed a frozen character and measured it happily.
--
-- SIX CHECKS, and half of them exist so a green cannot be empty:
--
--   G1 exactly one world backend claimed this game, and it carries every
--      member this gate is about to call. The boot map is reported and NOT
--      asserted: Gold boots into a room and Gen 1 sits on the title screen
--      with no map at all, and requiring one here would fail Blue for being
--      Blue -- the per-game assumption this whole slice exists to remove;
--   G2 landing controls where the player is. Two landings, on two different
--      cells, because Gold BOOTS into PLAYERS_HOUSE_2F 3,3 -- exactly where
--      this gate wants to stand -- so a single landing is satisfied by a
--      `land` that does nothing at all. Confirmed by mutation: with the
--      adapter's landing stubbed out to return true without calling setMap,
--      the second landing still read "ok" and only the first one caught it;
--   G3 the mod is attached WHILE the world is being driven. Without this the
--      gate goes green on a boot where voxel_characters never loaded, and
--      "the harness can drive Gold" would then say nothing about this mod;
--   G4 a held direction walks the player to the far end of the corridor and
--      stops there -- on the exact cell the MAP said was the last landable one
--      that way, not on whatever cell the run happened to reach;
--   G5 the walk is repeatable and reversible: back to the other end of the
--      corridor (again a cell the map predicted), then forward again onto the
--      same cell as the first run. A script, a warp or a nudge that moved the
--      player for some other reason breaks that even when G4 came out right;
--   G6 the control, and the reason G4 is falsifiable at all. The direction is
--      held against the wall for four more steps' worth of frames and the cell
--      must not move. Without it G4 passes on any implementation where the
--      cell counter free-runs while a key is down.
--
-- WHAT IS PINNED, AND WHY EACH ONE.
--
--   * the landing map and cell come from the environment with NO default. A
--     default here is a cell inherited from whichever game the author had
--     open, and this gate exists precisely because the two games do not share
--     one. A run that was not told where to stand fails rather than guesses;
--   * the mod set. gold.sh leaves only voxel_characters and the Gen 2 voxel
--     host enabled and writes every other installed mod out as false. Not
--     tidiness: another mod on this machine wraps Gold's World.step, and the
--     first run of this gate was made with the ordinary set;
--   * the corridor. The direction, how far it runs and where it ends are all
--     MEASURED off the map that was landed on, never written down here. A
--     written-down direction would be a second per-game constant and it would
--     go stale the first time a map changed;
--   * the map script is waited out before anything is read off the player. A
--     map load runs a setup script on both games, and a cell read underneath
--     one is a cell read while somebody else is driving.
--
-- WHAT THIS GATE DELIBERATELY DOES NOT SEE: whether the character is DRAWN,
-- what it looks like, and whether the voxel host does anything beyond
-- attaching. Those need the pixel probes, and pointing them at Gold is the
-- slice after this one.

local ADAPTER = "mods/voxel_characters/tools/ingame/world.lua"
local POUSO = "mods/voxel_characters/tools/ingame/pouso.lua"

-- The shortest walk this gate will accept. One cell could be a turn-in-place
-- -- the first press of a new direction only turns the character, on both
-- games -- and a gate that cannot tell those apart is not measuring a walk.
-- Two still fits in the smallest room either game has.
local STEPS = 2

-- Four steps' worth of frames. Gen 2 walks a cell in 16 (measured: the cell
-- changes on frame 17 of a held direction) and Gen 1 has its own number, so
-- this is a ceiling for "a step should have happened by now", never a
-- multiplier anything is derived from.
local STEP_BUDGET = 120

-- How long a map's setup script may run before the gate calls it a hang. The
-- Gold rooms this lands in run a MAPCALLBACK_NEWMAP on entry.
local SCRIPT_BUDGET = 600

return function(game)
  local function log(f, ...) print("[world] " .. string.format(f, ...)) end
  dofile("mods/voxel_characters/tools/ingame/erro.lua")()
  io.stdout:setvbuf("line")
  -- The same vsync release every other driver here takes: with the window
  -- occluded, love.graphics.present waits for a flip the macOS compositor does
  -- not schedule while nobody is looking, and the whole run reads as a hang.
  if love.window and love.window.setVSync then pcall(love.window.setVSync, 0) end

  local verdicts, allOk = {}, true
  local function verdict(name, ok, detail)
    if not ok then allOk = false end
    verdicts[#verdicts + 1] = { name = name, ok = ok }
    log("%s  %s  %s", name, ok and "PASSED" or "FAILED", detail or "")
  end
  local function finish()
    log("")
    for _, v in ipairs(verdicts) do
      log("%-3s %s", v.name, v.ok and "PASSED" or "FAILED")
    end
    log("VERDICT: %s",
      allOk and "THE HARNESS CAN DRIVE THIS GAME" or "READ ABOVE")
    for _ = 1, 10 do coroutine.yield() end
  end
  local function wait(n)
    for _ = 1, n do coroutine.yield() end
  end

  -- Input is the one thing the two games already share: `pressQueue` and
  -- `state` are the same object on both, which is why the core's own Gold
  -- drivers use them unchanged. Held one frame at a time here rather than
  -- through U.hold, because the cell has to be read between frames.
  local DIRS = { "up", "down", "left", "right" }
  local function release()
    for _, d in ipairs(DIRS) do game.input.state[d] = false end
  end
  local function press(d)
    release()
    table.insert(game.input.pressQueue, d)
    game.input.state[d] = true
  end

  -- Nothing below has a default: see the header. The landing is the one thing
  -- that cannot be derived from the game, so it has to be handed in.
  local MAP = os.getenv("VC_MAP")
  local X = tonumber(os.getenv("VC_X") or "")
  local Y = tonumber(os.getenv("VC_Y") or "")
  if not (MAP and X and Y) then
    verdict("G1", false, "no landing was given: set VC_MAP, VC_X and VC_Y. "
      .. "This gate refuses to pick a cell for you, because the cell is the "
      .. "one thing the two games do not share")
    return finish()
  end

  -- ------------------------------------------------------------------ G1
  local World = dofile(ADAPTER)
  local w, whyNot = World.of(game)
  if not w then
    verdict("G1", false, tostring(whyNot))
    return finish()
  end
  -- Every member this gate is about to call, checked once here rather than
  -- discovered as a nil-index halfway through a walk.
  --
  -- The boot map is REPORTED, not asserted, and the difference is the whole
  -- reason G1 says so little. Gold boots straight into PLAYERS_HOUSE_2F under
  -- POKEPORT_DRIVER; Gen 1 sits on the title screen with no map at all until
  -- something lands. Requiring a live map here would fail Blue for being Blue,
  -- which is exactly the kind of per-game assumption this whole slice is
  -- removing.
  local NEEDED = { "land", "cell", "mapId", "map", "loadMap", "busy",
                   "inWorld", "moving", "player", "npcAtCell" }
  local missing = {}
  for _, m in ipairs(NEEDED) do
    if type(w[m]) ~= "function" then missing[#missing + 1] = m end
  end
  verdict("G1", #missing == 0, string.format(
    "backend %s; on boot it reports map %s, cell %s,%s%s", w.name,
    tostring(w:mapId()), tostring(select(1, w:cell())),
    tostring(select(2, w:cell())),
    #missing > 0 and (". Missing: " .. table.concat(missing, ", ")) or ""))
  if #missing > 0 then return finish() end

  -- ------------------------------------------------------------------ G2
  -- The landing cell is validated before it is used, the way every driver here
  -- does it: an unvalidated teleport drops the player on a sign or a table and
  -- leaves them there. tools/ingame/pouso.lua explains each check and now
  -- takes its map through the same adapter, so it answers on both games.
  local DELTA = { { "down", 0, 1 }, { "up", 0, -1 },
                  { "left", -1, 0 }, { "right", 1, 0 } }
  local Pouso = dofile(POUSO)
  local map = w:loadMap(MAP)
  local _, lx, ly, radius, why = Pouso.escolher(game, MAP, X, Y)
  if radius == nil then
    verdict("G2", false, string.format("the landing check could not vouch for "
      .. "%s %d,%d: %s", MAP, X, Y, tostring(why)))
    return finish()
  end

  -- Land, let the map's setup script run out, and report where we ended up.
  local scriptFrames = 0
  local function landOn(cx, cy)
    if not w:land(MAP, cx, cy, "down") then return false, "the game refused" end
    wait(30)
    local n = 0
    while w:busy() and n < SCRIPT_BUDGET do
      n = n + 1
      coroutine.yield()
    end
    scriptFrames = scriptFrames + n
    local ax, ay = w:cell()
    if not w:inWorld() then return false, "not in the overworld afterwards" end
    if w:mapId() ~= MAP then return false, "ended on " .. tostring(w:mapId()) end
    if w:busy() then return false, "still busy after " .. n .. " frames" end
    if ax ~= cx or ay ~= cy then
      return false, string.format("asked for %d,%d and got %d,%d", cx, cy, ax, ay)
    end
    return true
  end

  -- A SECOND CELL, AND IT IS THE HALF THAT MAKES THIS CHECK FALSIFIABLE.
  --
  -- Gold boots straight into PLAYERS_HOUSE_2F 3,3 under POKEPORT_DRIVER, which
  -- is exactly where this gate wants to stand. So "the player is on the cell I
  -- asked for" is satisfied by a `land` that does NOTHING AT ALL -- the player
  -- was already there. Verified: with the adapter's landing stubbed out to
  -- return true without calling setMap, the one-landing version of this check
  -- passed. Landing on a different cell and then coming back is what turns it
  -- back into a measurement, and it costs two map loads.
  local altX, altY
  for raio = 1, 4 do
    for _, d in ipairs(DELTA) do
      local cx, cy = lx + d[2] * raio, ly + d[3] * raio
      if not altX and not Pouso.recusa(map, nil, cx, cy) then
        altX, altY = cx, cy
      end
    end
  end
  if not altX then
    verdict("G2", false, string.format("no second landable cell within 4 of "
      .. "%s %d,%d, so a landing that did nothing could not be told from one "
      .. "that worked", MAP, lx, ly))
    return finish()
  end

  local okA, whyA = landOn(altX, altY)
  local okB, whyB = landOn(lx, ly)
  local cx0, cy0 = w:cell()
  verdict("G2", okA and okB, string.format(
    "landed on %s %d,%d then back on %d,%d%s: %s, %s; now at %d,%d, in the "
    .. "overworld: %s, %d frame(s) of map script", MAP, altX, altY, lx, ly,
    radius > 0 and string.format(" (the landing check moved the requested "
      .. "%d,%d by %d cell(s))", X, Y, radius) or "",
    okA and "ok" or tostring(whyA), okB and "ok" or tostring(whyB),
    cx0, cy0, tostring(w:inWorld()), scriptFrames))
  if not (okA and okB) then return finish() end

  -- ------------------------------------------------------------------ G3
  -- Read out of the mod itself, not out of the loader's status: a mod that
  -- loaded fine and found no host looks identical from outside, which is the
  -- failure tools/ingame/probe_hosts.lua exists for.
  local function attached()
    local loader = game and game.mods
    local exports = loader and loader.exports and loader.exports.voxel_characters
    if type(exports) ~= "table" or type(exports.hostReport) ~= "function" then
      return false, "no hostReport export: the mod did not load on this game"
    end
    local ok, rep = pcall(exports.hostReport)
    if not (ok and type(rep) == "table") then
      return false, "hostReport threw: " .. tostring(rep)
    end
    return rep.patched == true, string.format(
      "host=%s hostVersion=%s patched=%s draw=%s atlas=%s why=%s",
      tostring(rep.host), tostring(rep.hostVersion), tostring(rep.patched),
      tostring(rep.drawPatched), tostring(rep.atlasPatched), tostring(rep.why))
  end
  local ok3, why3 = attached()
  verdict("G3", ok3, tostring(why3))

  -- --------------------------------------------------------------- G4/G5/G6
  -- THE CORRIDOR, measured off the map rather than written down.
  --
  -- The landed cell has to sit inside a straight run of landable cells with a
  -- WALL at both ends. Then a held direction walks to one end and stops there,
  -- and the resting cell is a number the map already knew -- which is what
  -- makes "the player moved by the expected amount" a real assertion instead
  -- of a restatement of whatever happened.
  --
  -- WHY WALL TO WALL AND NOT ONE STEP AT A TIME, which is what the first
  -- version of this gate did and it was wrong on Gold in a way worth writing
  -- down. Gold CHAINS steps with no idle frame between them: measured on
  -- PLAYERS_HOUSE_2F, the cell goes 3,3 -> 3,4 on frame 17 with `moving`
  -- already true again and `progress` already back to 0, so the next step had
  -- begun on the very frame the last one landed. A probe that reacts to the
  -- cell changing by releasing the key is one frame too late by construction,
  -- and its "one step" is always two cells. Waiting for a wall has no such
  -- race: the wall is where the engine itself decides to stop.
  --
  -- `Pouso.recusa` rather than plain walkability for the cells in between,
  -- because a warp tile is walkable and would take the player out of the map
  -- mid-run, and a sign is walkable and would open a text box.
  local BACK = { down = "up", up = "down", left = "right", right = "left" }

  -- How many landable cells lie in this direction before something stops the
  -- player, and whether the thing that stops them is a wall. Anything that is
  -- not a wall (a warp, a sign, somebody standing there) is refused: those
  -- stop the RUN somewhere the map cannot predict.
  local function reach(dx, dy)
    local n = 0
    while n < 12 do
      local cx, cy = cx0 + dx * (n + 1), cy0 + dy * (n + 1)
      if Pouso.recusa(map, nil, cx, cy) then
        return n, World.wall(map, cx, cy)
      end
      n = n + 1
    end
    return n, false
  end

  local dir, ddx, ddy, fwd, back
  for _, d in ipairs(DELTA) do
    local ahead, aheadWalled = reach(d[2], d[3])
    local behind, behindWalled = reach(-d[2], -d[3])
    -- Two cells ahead at least: one step could be a turn-in-place on either
    -- game, and a gate that cannot tell those apart is not measuring a walk.
    if ahead >= STEPS and aheadWalled and behindWalled
      and (not fwd or ahead > fwd) then
      dir, ddx, ddy, fwd, back = d[1], d[2], d[3], ahead, behind
    end
  end
  if not dir then
    verdict("G4", false, string.format("no direction out of %s %d,%d lies in a "
      .. "corridor of landable cells with a wall at both ends and at least %d "
      .. "cell(s) ahead, so there is nowhere to walk that the map can predict "
      .. "the end of", MAP, cx0, cy0, STEPS))
    return finish()
  end
  log("corridor: %s, %d cell(s) ahead and %d behind, walls at both ends",
    dir, fwd, back)

  -- Hold a direction until the player has stopped moving and the cell has been
  -- unchanged for SETTLE frames WITH THE KEY STILL DOWN. That is what "walked
  -- into a wall" looks like from outside, and it cannot be confused with the
  -- gap between two steps: a step is 16 frames on Gold and the settle window
  -- is longer than one.
  local SETTLE = 20
  local RUN_BUDGET = 600
  local function runUntilBlocked(d)
    local frames, still = 0, 0
    local lx, ly = w:cell()
    while frames < RUN_BUDGET do
      press(d)
      frames = frames + 1
      coroutine.yield()
      local nx, ny = w:cell()
      if nx == lx and ny == ly and not w:moving() then
        still = still + 1
        if still >= SETTLE then break end
      else
        still, lx, ly = 0, nx, ny
      end
    end
    release()
    local settle = 0
    while w:moving() and settle < STEP_BUDGET do
      settle = settle + 1
      coroutine.yield()
    end
    return frames
  end

  local fwdFrames = runUntilBlocked(dir)
  local cx1, cy1 = w:cell()
  local wantX, wantY = cx0 + ddx * fwd, cy0 + ddy * fwd
  verdict("G4", cx1 == wantX and cy1 == wantY and w:mapId() == MAP,
    string.format("held %s from %d,%d until the wall stopped it, %d frame(s): "
      .. "now at %d,%d and the map says the last landable cell that way is "
      .. "%d,%d; still on %s", dir, cx0, cy0, fwdFrames, cx1, cy1,
      wantX, wantY, tostring(w:mapId())))

  -- ------------------------------------------------------------------ G6
  -- The control, and the only check here that can fail on a game where holding
  -- a key moves the counter on its own. The player is already against the wall
  -- and the same direction is held for four steps' worth of frames.
  local wallMoved = false
  for _ = 1, STEP_BUDGET do
    press(dir)
    coroutine.yield()
    local nx, ny = w:cell()
    if nx ~= cx1 or ny ~= cy1 then wallMoved = true end
  end
  release()
  wait(20)
  local wx, wy = w:cell()
  verdict("G6", not wallMoved and wx == cx1 and wy == cy1, string.format(
    "kept pushing %s into the wall at %d,%d for %d more frames; the cell must "
    .. "not move and it is now %d,%d", dir, cx1, cy1, STEP_BUDGET, wx, wy))

  -- ------------------------------------------------------------------ G5
  -- Back to the other end of the corridor, then forward again. The return leg
  -- lands on a cell the map predicted too, and the second forward run has to
  -- land on exactly the cell the first one did: a walk that is repeatable is a
  -- walk, and a walk that is not is something else moving the player.
  local backFrames = runUntilBlocked(BACK[dir])
  local cx2, cy2 = w:cell()
  local backX, backY = cx0 - ddx * back, cy0 - ddy * back
  local againFrames = runUntilBlocked(dir)
  local cx3, cy3 = w:cell()
  verdict("G5", cx2 == backX and cy2 == backY and cx3 == cx1 and cy3 == cy1
    and w:mapId() == MAP, string.format(
    "walked %s to the other end in %d frame(s): %d,%d, and the map says %d,%d; "
    .. "then %s again in %d frame(s): %d,%d, against the %d,%d of the first "
    .. "run; still on %s", BACK[dir], backFrames, cx2, cy2, backX, backY,
    dir, againFrames, cx3, cy3, cx1, cy1, tostring(w:mapId())))

  finish()
end
