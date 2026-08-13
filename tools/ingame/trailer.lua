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

  -- THE REAL CLOCK, taken here and never let go, because the recording pins
  -- the one everything else reads (see A GAME CLOCK below). Every wall-time
  -- measurement in this file goes through RELOGIO so the cost of a frame stays
  -- measurable after the clock the mod animates on stops being the wall's.
  local RELOGIO = (love.timer and love.timer.getTime) or os.clock

  -- THE BUILD QUEUE, which is what "the scene is still loading" actually is.
  -- ChunkMesher builds the terrain in a coroutine on a per-frame time budget
  -- (ChunkMesher.lua:1034, 0.012 to 0.030 s a frame), so a fresh map arrives
  -- over MANY frames and the only thing that knows when it is done is
  -- `ChunkMesher.pending()` (ChunkMesher.lua:1024), the length of its job
  -- list. The host's own shot scripts poll exactly this
  -- (DramaticShapeVoxelMod/tests/tp_shots.lua:41-52) and so does this file now.
  local okCM, ChunkMesher = pcall(lib.require, "ChunkMesher")
  if not (okCM and type(ChunkMesher) == "table"
          and type(ChunkMesher.pending) == "function") then
    -- CANNOT TELL IS NOT THE SAME AS READY, and it refuses for the same reason
    -- clip.lua refuses an option it could not find in the mod's own list: a
    -- recording nobody could prove was settled is exactly the unfalsifiable
    -- artifact these guards exist to stop. Named, not silent.
    log("REFUSED: host sem ChunkMesher.pending, nao da para provar que a cena "
      .. "terminou de carregar. Sem isso o trailer publica o terreno nascendo "
      .. "no meio do plano e ninguem descobre antes de assistir.")
    return
  end

  -- Median and a high percentile over a sample of frame times. The mean is the
  -- wrong statistic here: one 300 ms hitch in 180 frames moves it by 1.7 ms and
  -- hides itself, while the median says what the shot normally costs and the
  -- 90th says how bad its bad frames are. Sorts in place.
  local function mediana(t)
    if #t == 0 then return nil end
    table.sort(t)
    return t[math.ceil(#t / 2)]
  end
  local function alto(t, p)
    if #t == 0 then return nil end
    return t[math.max(1, math.min(#t, math.ceil(#t * p)))]
  end

  -- TIME OF DAY, per shot.
  --
  -- Two things are wrong with leaving it alone, and pinning it fixes both.
  --
  -- The trailer was NOT REPRODUCIBLE. The host's default is "sync", which
  -- follows the machine's wall clock, so the same shot list filmed in the
  -- morning and in the evening produces different footage. A comparison
  -- between two recordings, which is how the clip guard works, would have been
  -- measuring the hour.
  --
  -- And every shot looked the same. "Variety in time of day" is on the roadmap
  -- as missing; it turns out to be one call, because DayNight.setting is an
  -- ordinary ModSetting and the host itself sets it programmatically.
  --
  -- IT IS RESTORED AT THE END, including on the way out through an error.
  -- setIndex WRITES TO THE SAVE (game.save.options.modOptions), so a trailer
  -- run that forgot would leave the player's own game pinned to dusk, and the
  -- player would have no idea why.
  local okDN, DayNight = pcall(lib.require, "DayNight")
  local HORA = { sync = 1, day = 2, night = 3, dusk = 4, dawn = 5, cycle = 6 }
  local horaOriginal = nil
  if okDN and DayNight and DayNight.setting then
    local ok, i = pcall(function() return DayNight.setting:read() end)
    if ok and i then horaOriginal = i end
  else
    log("host sem DayNight: os planos vao usar a hora que estiver")
  end

  -- VC_TRAILER_HORA forces every shot to one hour. It exists to make the
  -- setting PROVABLE: film the whole list twice, once as day and once as
  -- night, and the frames must differ. Without it, "the hour arrived" and "the
  -- hour was ignored" produce the same log line, which is the failure shape
  -- this project keeps paying for.
  local HORA_FORCADA = os.getenv("VC_TRAILER_HORA")

  local function porHora(nome)
    nome = HORA_FORCADA or nome
    if not (okDN and DayNight and DayNight.setting and nome) then return end
    local i = HORA[nome]
    if not i then log("hora desconhecida: %s", tostring(nome)); return end
    pcall(function() DayNight.setting:setIndex(i, game) end)
  end

  -- ZOOM, so a shot can hold on one face.
  --
  -- Item 4 lists "a shot that holds on one face long enough to read the blink"
  -- as missing, and it stayed missing because the shot list only ever chose a
  -- camera RUNG, which is an angle and not a distance. The host has a
  -- distance: `CamControl.zoomBy(notches)`, where POSITIVE PULLS OUT, so
  -- closing in is a negative count.
  --
  -- Restored to the starting distance at the end of each shot rather than at
  -- the end of the run, because the next shot's framing is written assuming
  -- the default and a leftover zoom would silently reframe everything after
  -- it.
  local okCam, CamControl = pcall(lib.require, "CamControl")
  local function porZoom(n)
    if not (okCam and CamControl and CamControl.zoomBy and n and n ~= 0) then
      return false
    end
    return (pcall(CamControl.zoomBy, n)) and true or false
  end

  -- NOTHING ON SCREEN THAT IS SOMEBODY ELSE'S.
  --
  -- Item 4 lists this last: the trailer is published as this mod's, and other
  -- installed mods put their own work in the frame. `overworld_wild_spawns`
  -- puts Pokemon in the overworld and `gen1_modern_ui` changes the menu, so a
  -- viewer cannot tell which of the three mods they are looking at, and we
  -- would be showing somebody else's work without saying so.
  --
  -- Two are NOT disabled and must never be: DramaticShapeVoxelMod is the host
  -- this mod patches, so without it there is nothing to film, and
  -- voxel_characters is the subject.
  --
  -- Restored at the end. Turning a player's mods off and leaving them off is
  -- exactly the kind of thing that gets a mod uninstalled.
  local ESSENCIAIS = { DRAMATIC_SHAPE = true, voxel_characters = true,
                       dramatic_shape_voxel = true }
  local desligados = {}
  local function soNossos()
    local L = game.mods
    if not (L and L.setEnabled and L.mods) then
      log("nao consegui alcancar o loader: outros mods podem aparecer")
      return
    end
    for id, m in pairs(L.mods) do
      if not ESSENCIAIS[id] and m.enabled ~= false then
        if pcall(L.setEnabled, L, id, false) then
          desligados[#desligados + 1] = id
        end
      end
    end
    if #desligados > 0 then
      log("desligados para a gravacao: %s", table.concat(desligados, ", "))
    else
      log("nenhum outro mod ativo, ou o loader nao deixou desligar")
    end
  end
  local function restauraMods()
    local L = game.mods
    if not (L and L.setEnabled) then return end
    for _, id in ipairs(desligados) do pcall(L.setEnabled, L, id, true) end
    if #desligados > 0 then
      log("mods restaurados: %s", table.concat(desligados, ", "))
    end
  end

  local function restauraHora()
    if horaOriginal and okDN and DayNight and DayNight.setting then
      pcall(function() DayNight.setting:setIndex(horaOriginal, game) end)
      log("hora restaurada para o indice %d", horaOriginal)
    end
  end

  -- THE SHOT LIBRARY, shared with every other tool that films (roadmap 21.3).
  -- Locations and camera setups live in planos.lua so that a feature filmed
  -- today and the same feature filmed in March are framed the same way, and so
  -- that a bad landing spot is fixed once instead of in every list that copied
  -- it.
  local P = dofile("mods/voxel_characters/tools/ingame/planos.lua")
  local DEGRAU = {}
  for k, v in pairs(P.DEGRAUS) do DEGRAU[k] = v end
  DEGRAU.primeira = FPLEVEL

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
    { mapa = "PALLET_TOWN", x = 5, y = 6, dir = "down", degrau = "plano",
      degrauFim = "medio", seg = 5,
      legenda = "Dramatic Shape tips the world over" },
    { mapa = "PALLET_TOWN", x = 5, y = 6, dir = "down", degrau = "alto",
      seg = 5, legenda = "Voxel Characters gives a body to whoever walks in it" },
    { mapa = "VIRIDIAN_CITY", x = 17, y = 17, dir = "down", degrau = "alto",
      degrauFim = "empe", anda = true, seg = 6, hora = "dusk",
      legenda = "A whole city, and not one flat card" },
    { mapa = "CERULEAN_POKECENTER", x = 3, y = 4, dir = "up", degrau = "medio",
      seg = 5, opcoes = { breath = 0.035 },
      legenda = "They breathe, each at their own pace" },
    -- CLOSE, and long. The blink is a 0.12 s event on a period of seconds, so
    -- a four second wide shot can miss it entirely and a viewer who does see it
    -- has no idea what they saw. Six seconds close in is enough to catch two.
    { mapa = "CERULEAN_POKECENTER", x = 3, y = 4, dir = "up", degrau = "empe",
      seg = 6, zoom = -3, opcoes = { blink = "on" },
      legenda = "And they blink" },
    { mapa = "ROUTE_1", x = 10, y = 20, dir = "down", degrau = "alto",
      anda = true, seg = 6, hora = "dawn", opcoes = { footfall = 0.7, lag = 0.6 },
      legenda = "The step carries weight, and the body takes a moment to follow" },
    { mapa = "VIRIDIAN_CITY", x = 17, y = 17, dir = "down", degrau = "empe",
      seg = 4, hora = "dusk", opcoes = { front_shape = 0.17, top_dome = 0.15 },
      legenda = "Shading that suggests volume without inventing geometry" },
    -- FIRST PERSON IN A PAIR, and not in a single shot. Kim watched it and said
    -- he didn't see a difference, and he was right: a single shot alone shows the
    -- result without showing what changed, and in first person the difference is
    -- precisely the thickness, which only exists through comparison. Same place,
    -- same direction, same step, only the option changes between the two.
    -- Both halves of the pair pin the SAME hour, said out loud rather than
    -- left to the default. The pair's whole job is that only the option
    -- differs between the two shots, and time of day is now something that
    -- can differ.
    { mapa = "CERULEAN_POKECENTER", x = 3, y = 4, dir = "right",
      degrau = "primeira", seg = 4, hora = "day",
      opcoes = { first_person = "card" },
      legenda = "In first person we used to fall back to the flat card" },
    { mapa = "CERULEAN_POKECENTER", x = 3, y = 4, dir = "right",
      degrau = "primeira", seg = 5, hora = "day",
      opcoes = { first_person = "solid" },
      legenda = "Now the body stays" },
    { mapa = "PALLET_TOWN", x = 5, y = 6, dir = "down", degrau = "alto",
      seg = 4, hora = "night", legenda = "Voxel Characters" },
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

  -- A GAME CLOCK, AND WHY THE TRAILER LOOKED LIKE IT RAN AT LOW FRAME RATE.
  --
  -- Under a driver the game does NOT advance on the wall clock. main.lua:415
  -- calls `Game:update(1 / 60)` once per driver resume, deliberately, so a
  -- script observes and acts exactly once per logic step. So one recorded
  -- frame is worth PASSO sixtieths of a second of GAME time, always, and the
  -- assembled video's time axis is game time.
  --
  -- The mod's life channels are not on that axis. BREATH, SWAY, MOTION LAG,
  -- FOOTFALL and BLINK all read `love.timer.getTime()` directly (main.lua:1819
  -- and :4687) and advance by the WALL time between draws. Everything else in
  -- the frame -- the walk, the camera tween, the host -- is on the fixed step.
  --
  -- The two only agree if the recording happens to run at exactly 30 frames a
  -- second, which it never does, because `love.graphics.captureScreenshot`
  -- reads back the frame and encodes a PNG. MEASURED HERE, over the whole shot
  -- list, before this fix: a capture-carrying frame took between 32 ms and
  -- 188 ms depending on the shot, against 8.7 to 13.6 ms for the frames with
  -- no capture. So the animation clock ran between 1.2x and 5.9x faster than
  -- the video it was being recorded into, at a rate that CHANGED FROM SHOT TO
  -- SHOT. Fast enough and it strobes: at 5.9x the breath cycle is sampled six
  -- times over, and BLINK -- 0.12 s closed, main.lua:1817 -- lands inside a
  -- single frame interval, so the "And they blink" shot could miss the blink
  -- entirely or show it as one 1/30 s flash. That is what "the trailer shows
  -- things in low fps" was. It was never the renderer: the same measurement
  -- says the game itself draws these scenes in 8.7 to 13.6 ms, 73 to 116 fps.
  --
  -- So the recording pins the clock those channels read to the axis the video
  -- is assembled on: one sixtieth per game frame, counted, not measured. The
  -- trailer is not real time and never was -- it already teleports, forces the
  -- hour and turns other mods off -- so the honest thing is for its clock to
  -- be the recording's, not the recorder's.
  --
  -- It is RESTORED at the end, including on the way out, for the same reason
  -- the hour is: this writes into the running game.
  --
  -- The invariant that makes it work is PASSO * FPS == 60, checked rather than
  -- trusted. Raise FPS to 60 and leave PASSO at 2 and every shot silently
  -- plays at double speed while the life channels stay at one; there is no
  -- symptom to see until someone watches, which is the failure shape this
  -- whole file is being taught to refuse.
  if PASSO * FPS ~= 60 then
    log("REFUSED: PASSO %d times FPS %d is %d, not the 60 logic steps a second "
      .. "the driver runs at (main.lua:415). One of the two is in the wrong "
      .. "unit and every shot would play at %.2fx speed.",
      PASSO, FPS, PASSO * FPS, PASSO * FPS / 60)
    return
  end
  local TIQUE = 1 / 60
  local quadroDoJogo = 0
  -- AHEAD OF THE BOOT, never behind it. The mod remembers when it last saw
  -- each character and drops any frame whose clock is not ahead of that
  -- (main.lua:4304, `if dt <= 0 then return end`), and `seen` is only written
  -- on a frame that counted. A clock that started behind the wall would
  -- therefore freeze every character already on screen, permanently, and the
  -- symptom would be "the life options stopped working" rather than anything
  -- to do with a clock. LOVE's clock starts at zero with the process, so a
  -- thousand seconds is past any boot, and the max() holds even if it is not.
  local INICIO_RELOGIO = math.max(1000, RELOGIO() + 1)
  local function agora() return INICIO_RELOGIO + quadroDoJogo * TIQUE end
  local function passo(n)
    for _ = 1, (n or 1) do
      quadroDoJogo = quadroDoJogo + 1
      coroutine.yield()
    end
  end
  local function restauraRelogio()
    if love.timer then love.timer.getTime = RELOGIO end
  end
  if love.timer then love.timer.getTime = agora end

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

  -- WAITING FOR THE SCENE INSTEAD OF WAITING FOR A NUMBER.
  --
  -- Kim: "the character walks outside and the voxel environment is still
  -- loading". It was doing exactly that. The old settle was `U.wait(70)`, a
  -- fixed count with no relationship to anything the host does, and MEASURED
  -- over the shot list it was not enough: six of eleven shots took their first
  -- frame with the terrain still being built -- five jobs still queued on the
  -- Viridian City walk, three in the Pokemon centre, two in Pallet.
  --
  -- WHAT THAT LOOKS LIKE, filmed with this wait taken back out: shot 4 opens
  -- on the FLAT GAME under the caption "A whole city, and not one flat card",
  -- and tips over into the voxel city part way through. The host is doing the
  -- right thing -- it holds the camera flat rather than tilt over an empty
  -- stage (VoxelState.lua:158-161) -- so the cost of recording early is not a
  -- half-built world, it is the shot arriving late, in the middle of itself.
  --
  -- Terrain arrives over many frames on purpose. ChunkMesher runs each build in
  -- a coroutine under a per-frame time budget (ChunkMesher.lua:1034), so it
  -- cannot be hurried, only waited for -- and waiting is free here, because the
  -- trailer is not real time. A shot that begins a second later costs nothing;
  -- a shot that begins too early costs the shot.
  --
  -- FOUR CONDITIONS, and each one is a different way for a scene to be busy:
  --
  --   * the build queue is empty (ChunkMesher.pending(), ChunkMesher.lua:1024).
  --     Voxel.ready alone is NOT enough: it goes true on the current map's
  --     body-only mesh while the border ring and the neighbouring maps are
  --     still cooking, which is precisely the pop-in at the edge of frame;
  --   * Voxel.ready, for the current map's own terrain;
  --   * Voxel.t >= 1, the camera rung's tween finished;
  --   * FirstPerson.blend stopped moving. The first-person rungs fly the
  --     camera into the head over several frames and that motion is NOT the
  --     rung tween. Measured: shot 9, first person, had an empty build queue
  --     and still opened at 29 dB against a 54 dB floor -- it was the blend.
  --     Read as "stopped changing" rather than compared against a target so
  --     that a rung this list does not use today cannot deadlock it.
  --
  -- With the pipeline OFF (the flat rung, level 0) the queue is not pumped at
  -- all -- main.lua:239 returns before pump() when the mode is inactive -- so
  -- pending() would sit frozen at whatever it was and this would spin until the
  -- cap. There is also nothing 3D on screen to pop in. So the flat rung waits
  -- for the tween and nothing else.
  local okFP, FirstPerson = pcall(lib.require, "FirstPerson")
  if not okFP then FirstPerson = nil end

  -- The cap is a refusal, not a timeout to be ignored: a scene that never
  -- settles is a shot nobody should publish, and the run says which one.
  local LIMITE_CENA = 900
  -- FIVE POLLS IN A ROW, not one. `ChunkMesher.pending()` can read zero for a
  -- single frame in the gap between a map change dequeuing its old jobs
  -- (ChunkMesher.lua:1158 and :1217 only mark the entry stale) and
  -- VoxelScene.prefetch queueing the replacements on the next frame. One poll
  -- can land exactly there, and it would land there most often on the shots
  -- that change map, which are the ones that need the wait.
  local ESTAVEL = 5
  -- The tail after the queue is empty, for the shadow map: it redraws on its
  -- own pass when its signature changes (ShadowMap.lua:423) and that is not
  -- in the mesher's queue, so nothing here can observe it directly. THIS IS
  -- THE ONE NUMBER IN THIS FILE THAT IS NOT MEASURED. It is not invented
  -- either: it is what the host's own shot scripts wait after the same queue
  -- (DramaticShapeVoxelMod/tests/fp_shots.lua:51, tp_shots.lua:51), and this
  -- has no better claim to the number than they do. Measured, at least, is
  -- that nothing re-enters the queue during it: every shot of the list reports
  -- an empty queue at its first captured frame.
  local RABO = 40

  local function cenaPronta()
    if not (VoxelState.active and VoxelState.active()) then
      return (VoxelState.t or 1) >= 1
    end
    return ChunkMesher.pending() == 0
      and VoxelState.ready and (VoxelState.t or 1) >= 1
  end

  -- Returns how many frames it waited, what the queue held when it started,
  -- and whether the scene was actually settled when it gave up waiting.
  local function esperaCena()
    local fila = ChunkMesher.pending()
    local esperou, seguidos, anterior = 0, 0, nil
    while esperou < LIMITE_CENA do
      local b = FirstPerson and FirstPerson.blend or 0
      if cenaPronta() and b == anterior then
        seguidos = seguidos + 1
      else
        seguidos = 0
      end
      anterior = b
      if seguidos >= ESTAVEL then break end
      passo(1)
      esperou = esperou + 1
    end
    local ok = seguidos >= ESTAVEL
    passo(RABO)
    return esperou, fila, ok
  end

  soNossos()

  local n = 0
  local cortes = {}
  local recusas = {}
  local function recusa(indice, fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    recusas[#recusas + 1] = string.format("REFUSED plano %d: %s", indice,
      ok and s or tostring(fmt))
    log("%s", recusas[#recusas])
  end

  for indice, p in ipairs(PLANOS) do
    for k, v in pairs(BASE) do opcao(k, v) end
    for k, v in pairs(p.opcoes or {}) do opcao(k, v) end
    local marcoOpcoes = quadroDoJogo

    local nivelInicio = DEGRAU[p.degrau] or 4
    local nivelFim = p.degrauFim and (DEGRAU[p.degrauFim] or 4) or nil
    -- BUILT AT THE RUNG THE SHOT ENDS AT, not the one it starts at.
    --
    -- The flat rung builds no terrain at all: shot 2 opens flat and tips over
    -- a quarter of the way in, so the whole map used to be meshed DURING the
    -- shot that shows the world tipping. The host hides the worst of it (it
    -- holds the tween at flat until the current map's mesh lands,
    -- VoxelState.lua:158-161) but the border ring and the neighbours keep
    -- cooking behind the tilt.
    --
    -- Meshing at the highest rung the shot will reach and then dropping back
    -- to the rung it opens on leaves the geometry cached -- going flat does not
    -- evict, the live set is unchanged -- so the tip is instant and nothing is
    -- built while the camera is recording. It changes no framing: the same
    -- rungs, in the same order, with the build moved in front of the shot.
    local nivelQuente = math.max(nivelInicio, nivelFim or nivelInicio)
    pcall(Pipelines.setLevel, "voxel", nivelQuente)
    -- AFTER the options, never before. DayNight.forceSync is called from every
    -- path that can act under the FULL preset, including the manager's
    -- options_changed hook, and this loop changes options on every shot. Set
    -- the hour first and it would be reset to "sync" before a single frame was
    -- recorded, which would look exactly like the setting not working.
    porHora(p.hora or "day")
    local zoomAplicado = p.zoom and porZoom(p.zoom) and p.zoom or nil
    local _, px, py = Pouso.escolher(game, p.mapa, p.x, p.y)
    U.teleport(game, p.mapa, px, py, p.dir)
    -- Two frames before asking the queue anything: VoxelScene.prefetch
    -- requests the new map's builds on the frame after the map changes, and
    -- polling in between reads the zero that sits in the gap.
    passo(4)
    local esperou, fila, cenaOk = esperaCena()
    if nivelQuente ~= nivelInicio then
      pcall(Pipelines.setLevel, "voxel", nivelInicio)
      local e2, _, ok2 = esperaCena()
      esperou, cenaOk = esperou + e2, cenaOk and ok2
    end
    -- AND THE OPTION HAS TO HAVE LANDED TOO, which is a different wait from the
    -- terrain's and the only one of the two that was ever right. DEPTH clears
    -- the masks as well as the mesh, and clip.lua measured that rebuild
    -- directly off captured frames: byte for byte identical 48 ticks after the
    -- change, clearly different by 68. This loop writes DEPTH on every shot, so
    -- every shot pays it. The old fixed `U.wait(70)` was, by accident, almost
    -- exactly this number -- which is why the option changes did land and only
    -- the terrain did not.
    local ESPERA_OPCAO = 75
    while quadroDoJogo - marcoOpcoes < ESPERA_OPCAO do passo(1) end
    if not cenaOk then
      recusa(indice, "the scene never settled. After %d frames the build queue "
        .. "still held %d job(s) (it started at %d). Recording here films the "
        .. "terrain arriving, which is the pop-in this wait exists to remove.",
        esperou, ChunkMesher.pending(), fila)
    end

    local quadros = p.seg * FPS
    local inicio = n + 1
    local andando = p.dir
    legenda = p.legenda

    -- WHAT THE SCENE LOOKED LIKE AT THE MOMENT THE FIRST FRAME WAS TAKEN.
    -- Read here and printed with the shot, because "the terrain was still
    -- building" and "the terrain was there" produce the same footage on a
    -- machine fast enough and different footage on any other, and until this
    -- line existed the difference was only ever discovered by watching.
    local pendenteNoInicio = ChunkMesher.pending()
    local prontoNoInicio = VoxelState.ready
    local tweenNoInicio = VoxelState.t
    local comCaptura, semCaptura = {}, {}
    local animInicio, animFim, realInicio, realFim
    -- WHERE the expensive frames are, not only how many. A hitch in the first
    -- second of a shot is a scene still warming up and the settle can absorb
    -- it; the same hitch in the middle is the game doing it while somebody
    -- plays, and no amount of waiting will move it.
    local estourosOnde = {}

    -- CAMERA MOVEMENT INSIDE A SHOT, when the shot asks for it.
    --
    -- `Pipelines.setLevel` takes an integer rung and floors it, so at first
    -- glance changing it mid shot should produce a jump. It does not: the host
    -- TWEENS. VoxelState keeps `Voxel.angle = from + (goal - from) * ease(t)`
    -- and update() eases toward the goal every frame, so setting a new rung is
    -- handing the camera a destination, not a new position.
    --
    -- So `degrauFim` costs one call and gets the thing item 4 listed as
    -- missing: a shot that moves instead of a shot that is a still frame.
    -- It fires a quarter of the way in, so the shot arrives settled, moves,
    -- and settles again before the cut.
    local moverEm = p.degrauFim and math.floor(quadros * 0.25) or nil
    for i = 1, quadros do
      -- The caption fades in and out within the shot. Appearing all at once together with the
      -- cut makes the eye read both things at the same time and read neither.
      local t = i / quadros
      legendaAlpha = math.min(1, math.min(t, 1 - t) * 6)
      if moverEm and i == moverEm then
        pcall(Pipelines.setLevel, "voxel", DEGRAU[p.degrauFim] or 4)
      end
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
      -- WHAT A FRAME COSTS, split between the frame that carries the capture
      -- and the frames that do not. They are not the same number and only one
      -- of them says anything about the mod: `captureScreenshot` reads the
      -- backbuffer back and encodes a PNG at the end of the frame it was asked
      -- on, which is a cost the trailer pays and a player never does. The
      -- capture-free frames are the honest render cost, and they are the ones
      -- the shot's verdict is measured on.
      local t0 = RELOGIO()
      -- BOTH CLOCKS, read at the same instant of the same frame: the one the
      -- mod animates on and the one the machine is actually on. The shot's
      -- verdict is the first against the video; the second is printed beside
      -- it so the log says how far apart they would have been.
      --
      -- THROUGH `love.timer.getTime` AND NOT THROUGH `agora` DIRECTLY, which
      -- is the difference between a gate and a tautology. Calling the local
      -- would measure the counter this file keeps and would report a perfect
      -- 1.00x even with the pin removed -- the mod would be back on the wall
      -- clock and the guard would say nothing. Read through the global and the
      -- guard reads exactly what the mod reads, whatever that turns out to be.
      if i == 1 then animInicio, realInicio = love.timer.getTime(), t0 end
      if i == quadros then animFim, realFim = love.timer.getTime(), t0 end
      love.graphics.captureScreenshot(string.format("vc_trailer_%05d.png", n))
      passo(1)
      local t1 = RELOGIO()
      comCaptura[#comCaptura + 1] = (t1 - t0) * 1000
      for _ = 2, PASSO do
        passo(1)
        local t2 = RELOGIO()
        local ms = (t2 - t1) * 1000
        semCaptura[#semCaptura + 1] = ms
        if ms > 1000 / FPS then
          estourosOnde[#estourosOnde + 1] = string.format("%d:%.0fms", i, ms)
        end
        t1 = t2
      end
    end
    if p.anda then
      for _, d in ipairs({ "up", "down", "left", "right" }) do
        game.input.state[d] = false
      end
    end
    legendaAlpha = 0
    if zoomAplicado then porZoom(-zoomAplicado) end
    cortes[#cortes + 1] = string.format("%d:%d:%s", inicio, n, p.degrau)
    log("plano %d/%d  %-22s %-9s %ds  quadros %d a %d",
        indice, #PLANOS, p.mapa, p.degrau, p.seg, inicio, n)

    local videoSeg = math.max(1e-6, (quadros - 1) / FPS)
    local animSeg = (animFim or 0) - (animInicio or 0)
    local realSeg = (realFim or 0) - (realInicio or 0)
    local custo = mediana(semCaptura)
    local custoAlto = alto(semCaptura, 0.9)
    local ORCAMENTO = 1000 / FPS
    local estouros = #estourosOnde
    log("plano %d  scene: queue %d to %d, waited %d frame(s) + %d tail, "
      .. "ready=%s tween=%.2f",
      indice, fila, pendenteNoInicio, esperou, RABO,
      tostring(prontoNoInicio), tweenNoInicio or -1)
    log("plano %d  clock: animation %.2fs over %.2fs of video (%.2fx); "
      .. "the wall ran %.2fs (%.2fx)",
      indice, animSeg, videoSeg, animSeg / videoSeg, realSeg,
      realSeg / videoSeg)
    log("plano %d  cost: render %.1fms median, %.1fms p90 (%.0f fps); "
      .. "capture adds %.1fms; %d of %d frames over %.1fms%s",
      indice, custo or -1, custoAlto or -1,
      1000 / math.max(0.001, custo or 0.001),
      (mediana(comCaptura) or 0) - (custo or 0),
      estouros, #semCaptura, ORCAMENTO,
      estouros > 0 and ("  at " .. table.concat(estourosOnde, " ")) or "")

    -- THE ANIMATION HAS TO HAVE RUN AT THE SPEED THE VIDEO PLAYS IT.
    --
    -- One per cent, and it is a tolerance and not a taste: the pinned clock
    -- advances exactly PASSO sixtieths per recorded frame, so a healthy shot
    -- lands on 1.0000x and only floating point can move it. What this catches
    -- is the whole class of ways that stops being true -- a yield that does not
    -- go through passo(), a wait inside the recording loop, FPS and PASSO
    -- edited apart, the pin removed -- each of which plays the mod's life
    -- channels at a speed the video does not run at. MEASURED, both sides:
    -- with the pin, every shot of the list reports 1.00x; without it, the same
    -- shots measured 1.2x to 5.9x, and it was the 5.9x one that looked like a
    -- slideshow.
    if math.abs(animSeg / videoSeg - 1) > 0.01 then
      recusa(indice, "the animation clock ran %.2fx the video's own rate "
        .. "(%.2fs of animation across %.2fs of footage). Everything the mod "
        .. "animates -- breath, blink, sway, lag, footfall -- plays at that "
        .. "speed in the finished file.", animSeg / videoSeg, animSeg, videoSeg)
    end

    -- AND THE MACHINE HAS TO BE ABLE TO DRAW IT AT THE RATE THE VIDEO CLAIMS.
    --
    -- The budget is the video's own frame, 1000/FPS ms, and it is not a number
    -- anyone picked: the file shows FPS distinct frames a second, so a frame
    -- the game cannot draw in that long is a frame the video oversells.
    -- Measured on the frames that carry NO capture, because the PNG readback
    -- is a cost the trailer pays and a player never does -- it ran 22 to
    -- 181 ms a frame here, and counting it would refuse every shot for the
    -- recorder's own expense.
    --
    -- TWO WAYS TO BE TOO EXPENSIVE, and they need two rules because the first
    -- version of this guard had one and MISSED THE REAL CASE. It compared the
    -- shot's MEDIAN frame against the budget. Turning HD SPRITE and CARVED on
    -- for the whole list -- 17024 quads a character against SLAB's 104 -- did
    -- not move the median at all (8.7 to 9.9 ms, against 8.6 to 9.1 with them
    -- off) and the gate passed the recording. What those options cost is not
    -- sustained load, it is a BUILD HITCH: the same run had single frames of
    -- 1324 ms and 1393 ms. A player feels a second and a half of freeze; the
    -- video does not show it at all, because the recording advances on the game
    -- clock and simply waits for the frame. That is exactly the lie this guard
    -- exists to stop, and an average cannot see it.
    --
    -- SUSTAINED: the median frame against the video's own frame. MEASURED,
    -- both sides: 8.6 to 9.1 ms across the shot list as it stands, against a
    -- 33.3 ms budget; a shot given 30 ms of deliberate extra work a frame
    -- measured 39.4 ms and was refused.
    --
    -- A FREEZE: any single frame past three times the budget, 100 ms here.
    -- MEASURED, both sides, over the whole list: the worst frame of a healthy
    -- shot is 58 ms, and it is not noise -- it is the camera tipping over in
    -- shot 2, three frames of 33 to 58 ms right after the rung changes, which
    -- is a real cost and a small one. The freezes are an order of magnitude
    -- past that: 484 ms and 478 ms in shot 4, 1324 and 1393 ms under HD. The
    -- threshold sits in the empty band between 58 and 478.
    --
    -- The count of frames over budget is printed with each shot, WITH THE
    -- FRAME NUMBERS, but it is not itself a refusal: six frames of 34 to 37 ms
    -- in the middle of a walk and one frame of 484 ms are the same count and
    -- are not the same thing, and a rule that cannot tell them apart is a rule
    -- someone waives.
    if custo and custo > ORCAMENTO then
      recusa(indice, "the scene needs %.1fms a frame and the video gives it "
        .. "%.1f, so a player would see %.1f fps where the file claims %d. The "
        .. "capture is excluded from that number. Make the shot cheaper or "
        .. "drop the video's frame rate; do not publish it at %d.",
        custo, ORCAMENTO, 1000 / custo, FPS, FPS)
    end
    local pior = alto(semCaptura, 1.0)
    if pior and pior > 3 * ORCAMENTO then
      recusa(indice, "the game froze for %.0fms inside this shot (frames over "
        .. "budget: %s). The finished video will not show it -- the recording "
        .. "advances on the game clock and waits -- but a player gets the "
        .. "freeze, and a trailer that is smooth only for the recorder is the "
        .. "thing this guard exists to refuse.",
        pior, table.concat(estourosOnde, " "))
    end
  end

  legenda = nil
  love.draw = desenhoOriginal
  restauraRelogio()
  restauraHora()
  restauraMods()
  log("cortes: %s", table.concat(cortes, " "))
  -- THE VERDICT IS THE LAST THING AND IT IS NOT PROSE. trailer.sh refuses to
  -- assemble anything when a refusal is present, so this line has to be
  -- greppable and has to come out even when every shot was fine -- a run that
  -- printed nothing would be indistinguishable from a run whose guards never
  -- executed, which is the empty green this project keeps paying for.
  if #recusas > 0 then
    -- The refusals themselves were printed as they happened, in shot order,
    -- and are not repeated here: trailer.sh greps the log for them and would
    -- print each one twice.
    log("TRAILER SHOTS REFUSED: %d of %d", #recusas, #PLANOS)
  else
    log("TRAILER SHOTS OK: %d shots settled, on clock and within budget",
      #PLANOS)
  end
  log("end, %d frames a %d fps, %.1f s", n, FPS, n / FPS)
end
