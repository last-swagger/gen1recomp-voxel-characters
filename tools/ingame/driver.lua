-- In-game gate for Voxel Characters.
--
-- The offline harness (tools/render/) measures geometry and color in two seconds, but
-- it loads the mod with the host MOCKED. By construction it never shows the real
-- sun (the host does p.rgb * vShade * sunlight * dayTint and the harness only has
-- vShade), nor the character against the world, nor the real scale (the harness uses
-- cells of 240 to 320 px and the game draws at a fraction of that), nor movement.
--
-- It does not replace the harness: the harness catches regressions fast, this one answers
-- "is it any good".
--
-- THIS USES tests/drivers/util.lua, the utility that the project's own 240
-- drivers use. I wrote this file twice from scratch before looking,
-- and both versions failed because of things util.lua already solves.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  dofile("mods/voxel_characters/tools/ingame/erro.lua")()
  local n = 0

  -- Without a TTY, LOVE's stdout is BLOCK buffered and a process that doesn't exit
  -- never flushes. An empty log doesn't distinguish "nothing happened" from "hasn't
  -- finished", and I've already drawn the wrong conclusion from this more than once.
  io.stdout:setvbuf("line")

  -- VSYNC OFF, AND THIS IS THE LINE THAT MAKES THE GATE WORK BY ITSELF.
  --
  -- With vsync on and the window occluded (the normal case when this runs from a
  -- shell, behind the editor), love.graphics.present() waits for a flip that the
  -- macOS compositor doesn't schedule while nobody is looking. The entire
  -- love.run loop stops: measured at 5 frames in 90 seconds. The symptom is
  -- indistinguishable from "stuck at the launcher" (zero photos, empty log) and that's
  -- why this gate spent days looking broken. The PROJECT'S OWN drivers
  -- (tests/drivers/zoom_test.lua) hang the same way without this: it wasn't
  -- our code.
  if love.window and love.window.setVSync then pcall(love.window.setVSync, 0) end

  -- PHOTO: love.graphics.captureScreenshot, NOT U.shot.
  --
  -- Both exist and are different code paths. U.shot uses
  -- game.capturePath and writes with io.open to a path RELATIVE to the working
  -- directory; captureScreenshot writes to LOVE's save directory. I already
  -- had a driver working with the latter and broke everything by "improving"
  -- to match the project's pattern without checking that the new mechanism worked
  -- in this environment. Adopting the house structure was right; adopting along with it
  -- a mechanism I hadn't proven, was not.
  local function foto(nome)
    n = n + 1
    local caminho = string.format("vc_%02d_%s.png", n, nome)
    love.graphics.captureScreenshot(caminho)
    U.wait(8)  -- the capture only lands on disk at the end of the frame
    U.log("foto " .. caminho)
  end

  U.log("VC driver: comecando")

  -- REACHING THE WORLD: U.teleport, not hammering "a".
  --
  -- The previous version of this file waited up to 900 frames and then mashed
  -- "a" three hundred times hoping to get through title and menu, and it failed with
  -- ZERO photos and an empty log. Two things were wrong and both were
  -- measured:
  --
  -- 1. POKEPORT_GAME and POKEPORT_SLOT are DEAD LETTERS here. They're only read
  --    in LaunchOptions.resolve (main.lua:359), which comes AFTER the
  --    `if scripted then ... return end` (main.lua:313-330). With
  --    POKEPORT_DRIVER set, control never gets there. The version that boots
  --    comes from POKEPORT_VERSION (main.lua:304), default "red". On this machine
  --    red is NOT ready (missing assets/generated/audio/programs.bin and
  --    assets/generated/trade/game_boy.png), so the boot fell into the importer
  --    and sat waiting for a ROM nobody was going to drag in: the driver never even
  --    got created. What fixes this is run.sh, exporting POKEPORT_VERSION.
  --
  -- 2. U.teleport is the house standard: 212 of the project's 240 drivers use it, and
  --    only 8 use the key-press path. It clears the stack and pushes
  --    OverworldController directly, so there's no title screen to get through.
  -- AND THE DESTINATION IS VALIDATED. U.teleport doesn't validate anything: if the requested cell is
  -- a sign, table, wall or NPC, the player lands on top of it and the photo comes out with them
  -- in a place nobody can stand. It was Kim who spotted this in the photos
  -- before I did. See tools/ingame/pouso.lua.
  local Pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")
  local MAPA, X, Y, RAIO = Pouso.escolher(game,
    os.getenv("VC_MAP") or "VIRIDIAN_CITY",
    tonumber(os.getenv("VC_X")) or 17,
    tonumber(os.getenv("VC_Y")) or 17)
  U.teleport(game, MAPA, X, Y, "down")
  U.wait(30)
  if RAIO == nil then
    U.log("VC driver: AVISO, nenhuma celula boa perto do ponto pedido")
  elseif RAIO > 0 then
    U.log(string.format("VC driver: pouso deslocado %d celula(s) para (%d,%d)",
      RAIO, X, Y))
  end

  if not (game.overworld and game.stack:top() == game.overworld) then
    U.log("VC driver: teleport para " .. MAPA .. " NAO chegou ao mundo")
    foto("preso_fora_do_mundo")
    return
  end
  U.log("VC driver: no mundo, mapa " .. MAPA)

  -- Turn on a mod option by code, to compare with and without anyone
  -- navigating the menu. VC_OPT="front_shape=0.12". The mod persists the option in the save and
  -- reacts to the mod.options_changed event, so writing and emitting is the same
  -- path the menu uses.
  local opt = os.getenv("VC_OPT")
  if opt and opt ~= "" then
    local chave, valor = opt:match("^([%w_]+)=(.+)$")
    if chave then
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
      -- The bus is game.mods.events, not game.mods (src/mods/Loader.lua:595
      -- and :1059). Writing the option to the save WITHOUT emitting changes nothing on screen,
      -- because the mesh is already cached: that's how I produced an A/B with
      -- byte-for-byte identical images and nearly presented it as a comparison.
      local emitiu = false
      if game.mods and game.mods.events
        and type(game.mods.events.emit) == "function" then
        emitiu = pcall(game.mods.events.emit, game.mods.events,
          "mod.options_changed",
          { mod = "voxel_characters", key = chave, value = valor })
      end
      -- READ IT BACK, and don't trust the emit. `pcall(emit)` returns true
      -- when the bus accepted the message, EVEN WHEN there is no
      -- listener at all, meaning when voxel_characters isn't even loaded.
      -- This guard exists to prevent an A/B with two identical sides, and the
      -- way it was, it attested that the message went out, not that it arrived.
      --
      -- The STATUS row reads the state of the mod ITSELF, so it is the response of
      -- whoever received it. Without it, nothing here distinguishes "applied" from "ignored".
      local chegou, status = false, nil
      local rows = {}
      local okRows = pcall(function()
        game.mods.hooks:run("ui.options.rows", {}, rows)
      end)
      if okRows then
        for _, r in ipairs(rows) do
          if r.id and tostring(r.id):find(chave, 1, true) and r.value then
            local okv, v = pcall(r.value, {})
            if okv then chegou, status = true, tostring(v) end
          end
        end
      end
      U.log("VC driver: opcao " .. chave .. "=" .. valor ..
        (emitiu and " (evento emitido)" or " (FALHOU o evento: A/B nao vale)")
        .. (chegou and (" (o mod le: " .. tostring(status) .. ")")
            or " (NAO CONSEGUI LER DE VOLTA do mod)"))
      if not emitiu then
        U.log("VC driver: ABORTANDO, um A/B sem efeito e pior que nenhum")
        foto("opcao_sem_efeito")
        return
      end
      U.wait(30)
    end
  end

  foto("no_mundo")

  -- The host's eight camera steps. The "3" key cycles the voxel pipeline:
  -- it's registered with hotkey = "3" in DramaticShapeVoxelMod/main.lua:155,
  -- over VoxelState.ANGLES_DEG = { 0, 35, 15, 35, 50, 75, 75, 75 }.
  for i = 1, 7 do
    U.tap(game, "3")
    U.wait(20)
    foto(string.format("camera%d", i))
  end
  U.log("VC driver: angulos cobertos")

  -- FIRST PERSON, both modes, and why it needs its own
  -- handling even though it's within the "3" key cycle.
  --
  -- Step 6 of HOTKEY_ORDER is already 1ST, so camera5 above is already first
  -- person. But with the default (FIRST PERSON = CARD) that photo shows the flat
  -- card, which is the old behavior, and the gate counted the photo without ever
  -- looking at the new mode. Two photos of the SAME step, one in each mode, is what
  -- makes the difference visible to whoever opens the folder.
  --
  -- Via Pipelines and not via key: the key cycle depends on where the save
  -- stopped, and the gate can't depend on that to reach a specific step.
  do
    local ok = pcall(function()
      require("src.render.Pipelines").setLevel("voxel", 6)
    end)
    if ok then
      U.wait(120)  -- the step tweens and first person has a blend on top
      for _, modo in ipairs({ "card", "solid" }) do
        local o = game.save and game.save.options
        if o then
          o.modOptions = o.modOptions or {}
          o.modOptions.voxel_characters = o.modOptions.voxel_characters or {}
          o.modOptions.voxel_characters.first_person = modo
        end
        if game.mods and game.mods.modOptions then
          game.mods.modOptions.voxel_characters =
            game.mods.modOptions.voxel_characters or {}
          game.mods.modOptions.voxel_characters.first_person = modo
        end
        pcall(function()
          game.mods.events:emit("mod.options_changed",
            { mod = "voxel_characters", key = "first_person", value = modo })
        end)
        U.wait(25)
        foto("primeira_" .. modo)
      end
      pcall(function()
        require("src.render.Pipelines").setLevel("voxel", 4)
      end)
      U.wait(60)
      U.log("VC driver: primeira pessoa coberta nos dois modos")
    else
      U.log("VC driver: sem Pipelines, primeira pessoa nao coberta")
    end
  end

  -- Walking. It's the one thing a still harness image can't judge.
  for i = 1, 6 do
    U.hold(game, "down", 8)
    if i % 2 == 0 then foto(string.format("andando%d", i)) end
  end

  -- NEGATIVE CONTROL: is OUR character present in any of these photos?
  --
  -- Until now this gate said GATE OK by counting FILES. Turning off the whole mod
  -- would leave it green: the driver runs to the end, writes the photos, and nobody
  -- looks at a single pixel. A gate like that measures that the game opened, not that the mod did anything.
  --
  -- The control is turning the mod on and off at the SAME position and SAME camera and
  -- comparing. It photographs both states to disk so whoever opens the folder can
  -- look, and prints the number so run.sh can fail the gate.
  do
    local function opta(valor)
      local o = game.save and game.save.options
      if o then
        o.modOptions = o.modOptions or {}
        o.modOptions.voxel_characters = o.modOptions.voxel_characters or {}
        o.modOptions.voxel_characters.depth = valor
      end
      if game.mods and game.mods.modOptions then
        game.mods.modOptions.voxel_characters =
          game.mods.modOptions.voxel_characters or {}
        game.mods.modOptions.voxel_characters.depth = valor
      end
      pcall(function()
        game.mods.events:emit("mod.options_changed",
          { mod = "voxel_characters", key = "depth", value = valor })
      end)
      U.wait(20)
    end

    local function pega()
      local pronto
      love.graphics.captureScreenshot(function(img) pronto = img end)
      for _ = 1, 120 do
        coroutine.yield()
        if pronto then return pronto end
      end
      return nil
    end

    local function difere(a, b)
      if not (a and b) or a:getWidth() ~= b:getWidth() then return -1, 0 end
      local d, n = 0, 0
      for y = 0, a:getHeight() - 1, 3 do
        for x = 0, a:getWidth() - 1, 3 do
          n = n + 1
          local ar, ag, ab = a:getPixel(x, y)
          local br, bg, bb = b:getPixel(x, y)
          if math.abs(ar - br) + math.abs(ag - bg) + math.abs(ab - bb) > 0.02 then
            d = d + 1
          end
        end
      end
      return d, n
    end

    -- THE FLOOR COMES FROM THE SAME RUN. Two photos with the mod ON, without changing
    -- anything between them, measure how much the scene moves on its own: day cycle, NPC
    -- wandering, everything that isn't the mod.
    --
    -- Without this the threshold was a fraction I picked (one five-hundredth), and
    -- when deliberately neutralizing the mod the measurement came out 175 of 87552 against a
    -- threshold of exactly 175: it passed by a hair, by chance. A threshold chosen
    -- by guessing doesn't separate signal from noise, it just looks like it does.
    opta(3)
    local com1 = pega()
    U.wait(20)
    local com2 = pega(); foto("controle_com_mod")
    opta("off")
    local sem = pega(); foto("controle_sem_mod")
    opta(3)

    local piso = difere(com1, com2)
    local dif, amostras = difere(com1, sem)
    U.log(string.format("VC driver: controle piso %d, mod ligado contra "
      .. "desligado %d, de %d amostras", piso, dif, amostras))
  end

  U.log("VC driver: fim, " .. n .. " fotos")
  U.wait(20)
end
