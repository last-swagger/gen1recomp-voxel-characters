-- TRAILER, recorded from inside the game itself.
--
-- A list of PLANOS: each one picks map, position, camera step, mod options,
-- whether the character walks, how long it lasts, and what the caption says.
-- The driver runs the list and records the whole sequence numbered; trailer.sh assembles it.
--
-- WHY FROM INSIDE THE GAME, and not capturing the screen from outside: the camera step,
-- the time of day, the position and the options become DATA instead of gesture. A trailer
-- recorded by hand doesn't get redone when a feature changes; this one gets redone by running
-- it again, and that's why it counts as a tool and not just as a video.
--
-- The SCRIPT tells the mod's story in the order it happened: the world
-- tips over, the characters gain a body, the body gains life, and at the end the camera
-- enters the player's head. Each shot exists to show ONE thing, because
-- a shot that shows two things shows none.
--
-- Usage:
--   POKEPORT_VERSION=blue POKEPORT_DRIVER=.../trailer.lua love .
--   VC_TRAILER_SEGUNDOS=12  cuts everything proportionally, to test quickly

return function(game)
  local U = dofile("tests/drivers/util.lua")
  dofile("mods/voxel_characters/tools/ingame/erro.lua")()
  io.stdout:setvbuf("line")
  if love.window and love.window.setVSync then pcall(love.window.setVSync, 0) end

  local function log(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    print("[trailer] " .. (ok and s or tostring(fmt)))
  end

  local function opcao(chave, valor)
    local o = game.save and game.save.options
    if o then
      o.modOptions = o.modOptions or {}
      o.modOptions.voxel_characters = o.modOptions.voxel_characters or {}
      o.modOptions.voxel_characters[chave] = valor
    end
    if game.mods and game.mods.modOptions then
      game.mods.modOptions.voxel_characters =
        game.mods.modOptions.voxel_characters or {}
      game.mods.modOptions.voxel_characters[chave] = valor
    end
    pcall(function()
      game.mods.events:emit("mod.options_changed",
        { mod = "voxel_characters", key = chave, value = valor })
    end)
  end

  local lib
  for _, f in ipairs({
    function() return game.mods.exports.DRAMATIC_SHAPE.lib end,
    function() return game.mods:find("DRAMATIC_SHAPE").exports.lib end,
    function() return game.mods.find("DRAMATIC_SHAPE").exports.lib end,
  }) do
    local ok, v = pcall(f)
    if ok and type(v) == "table" and v.require then lib = v break end
  end
  if not lib then log("sem a lib do host, nao da para dirigir a camera"); return end
  local okVS, VoxelState = pcall(lib.require, "VoxelState")
  if not okVS then log("host sem VoxelState"); return end
  local Pipelines = require("src.render.Pipelines")
  local FPLEVEL = VoxelState.FP_LEVEL or 6

  -- The steps by NAME, so the script doesn't carry a magic number. The host's
  -- ladder is ANGLES_DEG = {0, 35, 15, 35, 50, 75, 75, 75}, indexed by
  -- level + 1, so level 0 is the flat game and 5 is the most upright.
  local DEGRAU = { plano = 0, baixo = 2, medio = 3, alto = 4, empe = 5,
                   primeira = FPLEVEL }

  local BASE = {
    depth = 3, shape = "slab", side_color = "body", ground_shade = "off",
    blink = "on", top_edge = "on", front_shape = "off", top_dome = "off",
    step_weight = "off", breath = 0.010, sway = "off", lag = "off",
    footfall = "off", first_person = "card",
  }

  -- THE SCRIPT. Editing here means editing the trailer.
  local PLANOS = {
    { mapa = "PALLET_TOWN", x = 5, y = 6, dir = "down", degrau = "plano",
      seg = 4, legenda = "Pokemon Red, exactly as it has always been" },
    { mapa = "PALLET_TOWN", x = 5, y = 6, dir = "down", degrau = "medio",
      seg = 5, legenda = "Dramatic Shape tips the world over" },
    { mapa = "PALLET_TOWN", x = 5, y = 6, dir = "down", degrau = "alto",
      seg = 5, legenda = "Voxel Characters gives a body to whoever walks in it" },
    { mapa = "VIRIDIAN_CITY", x = 17, y = 17, dir = "down", degrau = "alto",
      anda = true, seg = 6, legenda = "A whole city, and not one flat card" },
    { mapa = "CERULEAN_POKECENTER", x = 3, y = 4, dir = "up", degrau = "medio",
      seg = 5, opcoes = { breath = 0.035 },
      legenda = "They breathe, each at their own pace" },
    { mapa = "CERULEAN_POKECENTER", x = 3, y = 4, dir = "up", degrau = "empe",
      seg = 4, opcoes = { blink = "on" }, legenda = "And they blink" },
    { mapa = "ROUTE_1", x = 10, y = 20, dir = "down", degrau = "alto",
      anda = true, seg = 6, opcoes = { footfall = 0.7, lag = 0.6 },
      legenda = "The step carries weight, and the body takes a moment to follow" },
    { mapa = "VIRIDIAN_CITY", x = 17, y = 17, dir = "down", degrau = "empe",
      seg = 4, opcoes = { front_shape = 0.17, top_dome = 0.15 },
      legenda = "Shading that suggests volume without inventing geometry" },
    -- FIRST PERSON IN A PAIR, and not in a single shot. Kim watched it and said
    -- he didn't see a difference, and he was right: a single shot alone shows the
    -- result without showing what changed, and in first person the difference is
    -- precisely the thickness, which only exists through comparison. Same place,
    -- same direction, same step, only the option changes between the two.
    { mapa = "CERULEAN_POKECENTER", x = 3, y = 4, dir = "right",
      degrau = "primeira", seg = 4, opcoes = { first_person = "card" },
      legenda = "In first person we used to fall back to the flat card" },
    { mapa = "CERULEAN_POKECENTER", x = 3, y = 4, dir = "right",
      degrau = "primeira", seg = 5, opcoes = { first_person = "solid" },
      legenda = "Now the body stays" },
    { mapa = "PALLET_TOWN", x = 5, y = 6, dir = "down", degrau = "alto",
      seg = 4, legenda = "Voxel Characters" },
  }

  -- Scales the whole script when you just want to check the plumbing.
  local ALVO = tonumber(os.getenv("VC_TRAILER_SEGUNDOS") or "")
  if ALVO then
    local soma = 0
    for _, p in ipairs(PLANOS) do soma = soma + p.seg end
    for _, p in ipairs(PLANOS) do
      p.seg = math.max(1, math.floor(p.seg * ALVO / soma + 0.5))
    end
  end

  -- 30 video frames per second, capturing one game frame and skipping the
  -- next. Thirty is enough to read movement and it cuts disk space and
  -- assembly time in half, which at 1500 files stops being a detail.
  local PASSO, FPS = 2, 30

  local legenda, legendaAlpha = nil, 0
  local fonte = love.graphics.newFont(20)
  local desenhoOriginal = love.draw
  love.draw = function()
    desenhoOriginal()
    if not legenda or legendaAlpha <= 0 then return end
    local w, h = love.graphics.getDimensions()
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setFont(fonte)
    local tw = fonte:getWidth(legenda)
    local x, y = (w - tw) / 2, h - 86
    -- Lower third, no box: a black box in a Game Boy game reads as
    -- game interface and not as video caption. A shadow solves legibility
    -- over any background without competing with the art.
    love.graphics.setColor(0, 0, 0, 0.75 * legendaAlpha)
    love.graphics.print(legenda, x + 2, y + 2)
    love.graphics.setColor(1, 1, 1, legendaAlpha)
    love.graphics.print(legenda, x, y)
    love.graphics.pop()
  end

  local Pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")

  -- WALKING WITHOUT HITTING THE WALL.
  --
  -- Kim watched and noticed: in the shots where the character walks, it reaches
  -- the wall and keeps pushing, and that reads as amateur because it reads as
  -- someone forgetting the controller is held down. The cause was silly: the shot held
  -- one direction the whole time without ever asking if it could keep going.
  --
  -- Now it asks, and it asks the same judge the rest of the harness uses
  -- (Pouso.recusa, which consults the engine about boundary, collision, sign, door and
  -- NPC). When the next cell refuses, the direction reverses. The result is a
  -- back and forth within the space that exists, which is what a trailer wants
  -- anyway: continuous movement, no wall.
  local OPOSTO = { up = "down", down = "up", left = "right", right = "left" }
  local DELTA = { up = { 0, -1 }, down = { 0, 1 },
                  left = { -1, 0 }, right = { 1, 0 } }

  local function podeSeguir(dir)
    local ow = game.overworld
    if not (ow and ow.map and ow.player) then return true end
    local d = DELTA[dir]
    if not d then return true end
    local cx = (ow.player.cellX or 0) + d[1]
    local cy = (ow.player.cellY or 0) + d[2]
    return Pouso.recusa(ow.map, ow, cx, cy) == nil
  end

  local n = 0
  local cortes = {}

  for indice, p in ipairs(PLANOS) do
    for k, v in pairs(BASE) do opcao(k, v) end
    for k, v in pairs(p.opcoes or {}) do opcao(k, v) end

    pcall(Pipelines.setLevel, "voxel", DEGRAU[p.degrau] or 4)
    local _, px, py = Pouso.escolher(game, p.mapa, p.x, p.y)
    U.teleport(game, p.mapa, px, py, p.dir)
    -- Settle before recording: the step does a tween, the mesh rebuilds and the
    -- teleport has one frame of old world. Recording over that puts a
    -- jump at the start of each shot, and the cut is already the jump.
    U.wait(70)

    local quadros = p.seg * FPS
    local inicio = n + 1
    local andando = p.dir
    legenda = p.legenda
    for i = 1, quadros do
      -- The caption fades in and out within the shot. Appearing all at once together with the
      -- cut makes the eye read both things at the same time and read neither.
      local t = i / quadros
      legendaAlpha = math.min(1, math.min(t, 1 - t) * 6)
      if p.anda then
        -- Only reverses when the next cell refuses AND the character is already
        -- stopped in it; asking mid step would return the cell it
        -- left from and the direction would keep swapping every frame.
        if not podeSeguir(andando) then
          game.input.state[andando] = false
          andando = OPOSTO[andando] or andando
        end
        table.insert(game.input.pressQueue, andando)
        game.input.state[andando] = true
      end
      n = n + 1
      love.graphics.captureScreenshot(string.format("vc_trailer_%05d.png", n))
      for _ = 1, PASSO do coroutine.yield() end
    end
    if p.anda then
      for _, d in ipairs({ "up", "down", "left", "right" }) do
        game.input.state[d] = false
      end
    end
    legendaAlpha = 0
    cortes[#cortes + 1] = string.format("%d:%d:%s", inicio, n, p.degrau)
    log("plano %d/%d  %-22s %-9s %ds  quadros %d a %d",
        indice, #PLANOS, p.mapa, p.degrau, p.seg, inicio, n)
  end

  legenda = nil
  love.draw = desenhoOriginal
  log("cortes: %s", table.concat(cortes, " "))
  log("fim, %d quadros a %d fps, %.1f s", n, FPS, n / FPS)
end
