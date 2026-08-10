-- Records the frames of a side-by-side clip: the same place, the same camera,
-- the same number of frames, once with the option off and once with it on.
-- clip.sh is what assembles the video, with ffmpeg.
--
-- WHY THIS EXISTS: BREATH, SWAY and MOTION LAG only mean anything over TIME.
-- A still photo judges none of the three, and until now the only way to show
-- the effect to someone was asking them to open the game. A three-second
-- clip solves that, and it is also what the community can see in a Discord
-- message.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  dofile("mods/voxel_characters/tools/ingame/erro.lua")()
  io.stdout:setvbuf("line")
  -- Without this the loop runs at less than one frame per second with the
  -- window occluded, and recording 200 frames would take minutes. See tools/ingame/driver.lua.
  if love.window and love.window.setVSync then pcall(love.window.setVSync, 0) end

  local function log(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    print("[clip] " .. (ok and s or tostring(fmt)))
  end

  -- TWO ARBITRARY SIDES, not just off against on.
  --
  -- VC_CLIP_OPT="breath=0.020"            left OFF, right 0.020
  -- VC_CLIP_OPT="breath=0.010:0.035"      left 0.010, right 0.035
  --
  -- The second form exists for the choice loop: judging between two
  -- candidates is easier and more reliable than judging one alone, and it is
  -- the only way for the viewer's preference to become usable signal.
  -- Comparing against OFF answers "does it do anything?"; comparing two
  -- levels answers "which one?", which is the question left over once the
  -- feature already exists.
  local OPT = os.getenv("VC_CLIP_OPT") or "breath=0.020"
  local CHAVE, RESTO = OPT:match("^([%w_]+)=(.+)$")
  if not CHAVE then log("opcao ilegivel: %s", OPT); return end
  local ESQ, DIR = RESTO:match("^([^:]+):(.+)$")
  if not ESQ then ESQ, DIR = "off", RESTO end
  local VALOR = DIR
  local VAL_ESQ = tonumber(ESQ) or ESQ
  local NUM = tonumber(DIR) or DIR
  local QUADROS = tonumber(os.getenv("VC_CLIP_FRAMES")) or 96
  local PASSO = tonumber(os.getenv("VC_CLIP_STEP")) or 2  -- captura 1 em cada N
  local ZOOM = tonumber(os.getenv("VC_CLIP_ZOOM")) or 0

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
    local ok = game.mods and game.mods.events
      and pcall(game.mods.events.emit, game.mods.events, "mod.options_changed",
        { mod = "voxel_characters", key = chave, value = valor })
    if not ok then log("AVISO: a troca de %s NAO foi emitida", chave) end
    return ok
  end

  -- LANDING SPOT. See tools/ingame/pouso.lua: U.teleport does not validate
  -- anything, which is why the player used to land on top of signs and tables in the gate's photos.
  local pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")
  local mapa, x, y = pouso.escolher(game,
    os.getenv("VC_MAP") or "OAKS_LAB",
    tonumber(os.getenv("VC_X")) or 5,
    tonumber(os.getenv("VC_Y")) or 10)
  U.teleport(game, mapa, x, y, os.getenv("VC_FACING") or "down")
  U.wait(60)
  if not (game.overworld and game.stack:top() == game.overworld) then
    log("nao cheguei ao mundo"); return
  end
  log("mapa %s em (%d,%d)", mapa, x, y)

  -- CAMERA STEP, and first person is one of them.
  --
  -- Until now every clip came out on whatever step the save had, which had
  -- already rescaled pixel counts between runs in this project and, worse,
  -- left FIRST PERSON with NO clip at all: players asked for the feature and
  -- there was no way to show it side by side.
  --
  -- Through the same door the host uses, and not through VoxelState.setLevel:
  -- the step is owned by the engine's Pipelines, and Voxel.update rewrites
  -- Voxel.level from it every frame (VoxelState.lua:180). Calling the wrong
  -- one does not error, it just does nothing, and the symptom looks like the
  -- camera does not exist.
  local DEGRAUS = { off = 0, baixo = 2, medio = 3, alto = 4, empe = 5,
                    primeira = 6, terceira = 7 }
  local pedido = os.getenv("VC_CLIP_DEGRAU")
  if pedido and pedido ~= "" then
    local nivel = DEGRAUS[pedido] or tonumber(pedido)
    if not nivel then
      log("VC_CLIP_DEGRAU=%s nao existe; use %s ou um numero", pedido,
          "off/baixo/medio/alto/empe/primeira/terceira")
      return
    end
    local ok = pcall(function()
      require("src.render.Pipelines").setLevel("voxel", nivel)
    end)
    if not ok then log("nao consegui trocar o degrau de camera"); return end
    -- The step tweens and first person still has the blend on top of it.
    -- Recording before it settles puts the CAMERA's motion inside the clip,
    -- and the eye reads that as the effect we are trying to show.
    U.wait(120)
    log("degrau de camera: %s (nivel %d)", pedido, nivel)
  end

  -- WHY INDOORS AND NOT ON THE STREET. Outside, the sky has a day cycle, and
  -- since the two sides are recorded one after the other, the background
  -- gradient shifts between them: whoever looks at the side by side sees a
  -- different sky before seeing the character breathe, and the difference
  -- that matters falls into the background. Inside the lab there is no sky,
  -- and there are still enough people standing still to show each one breathes on its own phase.
  --
  -- ZOOM ZERO BY DEFAULT. Forcing zoom in the game pulls the camera to a low
  -- angle and the frame turns into wall and floor. What zooms in is the CROP
  -- in clip.sh, afterward, over what the game already drew: the character
  -- stays near the center because the camera follows it, so cropping the
  -- center is enough and does not touch anything in the scene.
  U.tap(game, "3")
  U.wait(30)
  for _ = 1, ZOOM do
    if game.zoomStep then game:zoomStep(1) end
  end
  U.wait(30)

  -- BLINK off during the clip: it animates the eye over time and would show
  -- up on both sides, confusing anyone trying to see what the option changes.
  opcao("blink", "off")
  opcao("breath", "off"); opcao("sway", "off"); opcao("lag", "off")
  opcao("footfall", "off")
  U.wait(30)
  -- The left side can be a LEVEL, not just the off state.
  if VAL_ESQ ~= "off" then opcao(CHAVE, VAL_ESQ); U.wait(30) end

  -- MOTION LAG only exists with the character MOVING: standing still, the
  -- spring is at rest and both sides would come out identical, which would
  -- make the clip prove that the feature does nothing. So for this option
  -- both sides walk, and walk THE SAME WAY: same direction, same number of
  -- frames, reversing halfway so the character does not leave the frame.
  -- MOTION LAG and FOOTFALL only exist with the character MOVING. Standing
  -- still, the spring is at rest and the velocity is zero, so both sides
  -- would come out identical and the clip would prove the feature does nothing.
  local ANDA = (CHAVE == "lag" or CHAVE == "footfall")
    or os.getenv("VC_CLIP_ANDAR") == "1"
  -- How many frames WALKING before reversing direction. Changing direction
  -- costs a stop, and stopping is exactly what kills the effect we are trying
  -- to film, so the default walks long enough for three full 16-frame steps
  -- in each direction before turning around.
  local TRECHO = tonumber(os.getenv("VC_CLIP_TRECHO")) or 48

  -- ------------------------------------------------------- CAPTION IN FRAME
  -- The label is drawn INSIDE THE GAME, not pasted on afterward by ffmpeg, and
  -- the reason is concrete: this machine's ffmpeg was built without libfreetype,
  -- so it has no drawtext filter. A trailer pipeline that depends on a
  -- third-party build breaks on the first contributor who does not have it.
  --
  -- Drawn here, the text enters the source frame and survives everything that
  -- comes after: crop, scale, mp4 and gif. And each side carries its own
  -- label, so when the two are stacked BEFORE lands on the left and AFTER
  -- lands on the right without anyone coordinating anything.
  --
  -- WHAT TO WATCH is Kim's request, and it is the part that matters most: a
  -- clip without it requires whoever is watching to already know what the
  -- feature does. With it, the clip explains itself, which is what a trailer needs to do.
  local O_QUE_OLHAR = {
    breath = "os ombros subindo e descendo com o personagem parado",
    sway = "o corpo trocando o peso de um lado para o outro",
    lag = "o corpo ficando para tras ao arrancar e passando do ponto ao parar",
    footfall = "o corpo comprimindo a cada pisada e esticando entre elas",
    front_shape = "o degrade em degraus na face da frente",
    top_dome = "o topo da cabeca deixando de ser uma tampa chata",
    step_weight = "o solido inclinando junto com o passo da arte",
    shape = "como o volume e construido",
  }

  -- THE LEVEL'S LABEL COMES FROM THE MOD ITSELF, not from a table in this file.
  --
  -- The caption needs to say "NORMAL", not "0.7". Keeping a value-to-label map
  -- in this file would create a second source of truth that goes stale the
  -- first time someone touches a level, and the clip would start lying
  -- without any test complaining. Instead we build the menu rows through the
  -- same hook the game uses and read the row's value, which is literally the
  -- text that shows up on the options screen.
  local function rotuloDoNivel(chave)
    local ok, Runtime = pcall(require, "src.mods.Runtime")
    if not ok then return nil end
    local okRows, rows = pcall(Runtime.call, "ui.options.rows",
      function(_, r) return r end, game, {})
    if not (okRows and type(rows) == "table") then return nil end
    for _, row in ipairs(rows) do
      if tostring(row.id) == "voxel_characters:" .. chave and row.value then
        local okVal, v = pcall(row.value, game)
        if okVal then return v end
      end
    end
  end

  local fonteGrande = love.graphics.newFont(22)
  local fonteMedia = love.graphics.newFont(15)
  local legendaTag = nil

  -- The area clip.sh crops, in window coordinates. The caption needs to land
  -- INSIDE it, otherwise it exists in the full frame and disappears in the crop.
  local RX, RY, RW, RH = 232, 200, 560, 420
  do
    local r = os.getenv("VC_CLIP_RECORTE")
    if r then
      local w, h, xx, yy = r:match("^(%d+):(%d+):(%d+):(%d+)$")
      if w then RX, RY, RW, RH = tonumber(xx), tonumber(yy), tonumber(w), tonumber(h) end
    end
  end

  local desenhoOriginal = love.draw
  love.draw = function()
    if desenhoOriginal then desenhoOriginal() end
    if not legendaTag then return end
    local antes = legendaTag == "off"
    local rotuloLado = antes and tostring(VAL_ESQ):upper() or nil
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setBlendMode("alpha")

    -- top bar: BEFORE / AFTER and the option with its level
    love.graphics.setColor(0, 0, 0, 0.62)
    love.graphics.rectangle("fill", RX, RY, RW, 52)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(fonteGrande)
    -- BEFORE and AFTER only make sense when one of the sides is the current
    -- state. In an A/B between two levels both are candidates, so the caption
    -- switches to A and B: calling one of them "before" would lie about what is being compared.
    local ehContraOff = tostring(VAL_ESQ) == "off"
    love.graphics.print(
      ehContraOff and (antes and "BEFORE" or "AFTER") or (antes and "A" or "B"),
      RX + 12, RY + 5)
    love.graphics.setFont(fonteMedia)
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.print(
      string.upper(CHAVE) .. "   " .. (rotuloDoNivel(CHAVE)
        or tostring(antes and VAL_ESQ or VALOR)):upper(),
      RX + 12, RY + 31)

    -- bottom bar: what to watch
    local dica = O_QUE_OLHAR[CHAVE]
    if dica then
      love.graphics.setColor(0, 0, 0, 0.62)
      love.graphics.rectangle("fill", RX, RY + RH - 30, RW, 30)
      love.graphics.setColor(1, 1, 1, 0.92)
      love.graphics.setFont(fonteMedia)
      love.graphics.printf("olhe " .. dica, RX + 12, RY + RH - 22, RW - 24)
    end
    love.graphics.pop()
  end

  local function grava(tag)
    legendaTag = tag
    for i = 1, QUADROS do
      if ANDA then
        local dir = (math.floor((i - 1) / TRECHO) % 2 == 0) and "left" or "right"
        table.insert(game.input.pressQueue, dir)
        game.input.state[dir] = true
        game.input.state[dir == "left" and "right" or "left"] = false
      end
      love.graphics.captureScreenshot(string.format("vc_clip_%s_%04d.png", tag, i))
      for _ = 1, PASSO do coroutine.yield() end
    end
    if ANDA then
      game.input.state["left"] = false
      game.input.state["right"] = false
      U.wait(45)  -- let the spring return to rest before the next side
    end
    log("lado %s gravado%s", tag, ANDA and " (andando)" or "")
  end

  -- SAME STARTING POINT ON BOTH SIDES, and this was learned by watching the
  -- result. When the clip walks, the second side used to start from wherever
  -- the first one had stopped, so the side by side showed the character in
  -- DIFFERENT PLACES and nobody could see the effect: the eye compares
  -- position before it compares deformation. Returning to the same cell
  -- before each side leaves the option as the only visible difference.
  local function reposiciona()
    if not ANDA then return end
    U.teleport(game, mapa, x, y, os.getenv("VC_FACING") or "down")
    U.wait(45)
  end

  -- Left side: off.
  reposiciona()
  grava("off")

  -- THE FLOOR: the SAME side, recorded AGAIN, through the same path. It is the
  -- only way to know how much two clips differ from each other for a reason that is not the option.
  --
  -- The first attempt at a floor compared frame 10 to frame 40 of the SAME
  -- recording, and that measures something else: neighboring frames of one
  -- continuous run are correlated, while two separate runs start at different
  -- phases. Measured: with the same value on both sides, "between" gave 22 dB
  -- and "within" gave 28 dB, meaning the pair between sides looked MORE
  -- different, and the guard would approve an A/B that compared nothing.
  --
  -- These frames do not go into the video; they exist only to give scale.
  reposiciona()
  grava("piso")

  -- Right side: the requested option. MOTION LAG only shows up with the
  -- character moving, so for it both sides walk; for the others, both sides
  -- stay still. What the two sides never do is different things.
  opcao(CHAVE, NUM)
  U.wait(30)
  reposiciona()
  grava("on")

  legendaTag = nil
  love.draw = desenhoOriginal
  log("quadros por lado: %d", QUADROS)
  U.wait(10)
end
