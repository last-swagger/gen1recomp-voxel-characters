-- Records the frames of a side-by-side clip: the same place, the same camera,
-- the same number of frames, once with the option off and once with it on.
-- clip.sh is what assembles the video, with ffmpeg.
--
-- WHY THIS EXISTS: BREATH, SWAY and MOTION LAG only mean anything over TIME.
-- A still photo judges none of the three, and until now the only way to show
-- the effect to someone was asking them to open the game. A three-second
-- clip solves that, and it is also what the community can see in a Discord
-- message.
--
-- POLISH, for posting (roadmap 21.2): a lower third names the option and its
-- level on each side and fades in and out like trailer.lua's captions do; a
-- title card is captured once here and held for two seconds by clip.sh
-- before the comparison; the camera step now defaults to "alto" instead of
-- whatever the save had, so the framing is consistent clip to clip, not just
-- side to side within one.

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

  -- THE KEY MUST EXIST, checked HERE, before a single frame is recorded.
  --
  -- Found building the negative gate test: a key this mod does not have
  -- (clip.sh's own `naoexiste=1` check) used to sail all the way through
  -- recording and land on the PSNR gate downstream, and that gate is a
  -- STATISTICAL check built for a different failure (a REAL option whose
  -- mesh did not rebuild, historically byte-for-byte identical, an
  -- unambiguous signal). It is not reliable for "this key does not exist at
  -- all": `opcao()` writes the value and emits the change event regardless
  -- of whether anything reads it, and the scene's own rebuild-on-any-change
  -- behavior can measurably shift a handful of pixels even when nothing
  -- meaningful changed, sometimes enough to look like an effect and
  -- sometimes not. Measured across many runs, on this rewrite AND on the
  -- code before it: `naoexiste=1` published about as often as it correctly
  -- refused. A key that is simply ABSENT from the mod's own options list is
  -- knowable with certainty, so it gets answered with certainty, here,
  -- instead of leaving it to a measurement that was never built to answer it.
  do
    local okRuntime, Runtime = pcall(require, "src.mods.Runtime")
    local existe = false
    if okRuntime then
      local okRows, rows = pcall(Runtime.call, "ui.options.rows",
        function(_, r) return r end, game, {})
      if okRows and type(rows) == "table" then
        for _, row in ipairs(rows) do
          if tostring(row.id) == "voxel_characters:" .. CHAVE then
            existe = true
            break
          end
        end
      end
    end
    if not existe then
      log("unknown option: %s (voxel_characters nao tem essa chave)", CHAVE)
      return
    end
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
    local ok = game.mods and game.mods.events
      and pcall(game.mods.events.emit, game.mods.events, "mod.options_changed",
        { mod = "voxel_characters", key = chave, value = valor })
    if not ok then log("WARNING: a troca de %s NAO foi emitida", chave) end
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
  -- PINNED BY DEFAULT, not left to the save. Without VC_CLIP_DEGRAU the
  -- camera used to stay at whatever step the save had, which drifts between
  -- runs and breaks the framing consistency roadmap 21.2 asks for: a feature
  -- filmed in March would not line up with one filmed today if the two saves
  -- happened to differ in camera step. "alto" is the default because it is
  -- the angle that reads a standing character best without going all the way
  -- to first person.
  local pedido = os.getenv("VC_CLIP_DEGRAU")
  if not pedido or pedido == "" then pedido = "alto" end
  do
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
  -- WAIT LONG ENOUGH FOR A "full" CLEAR, not just a "mesh" one. Found while
  -- fixing the gate above: DEPTH is the one option in main.lua's OPTIONS
  -- table with `clears = "full"` (it invalidates masks too, not just the
  -- mesh), and 30 frames was not enough for it to finish rebuilding.
  -- Measured directly off the captured PNGs: off vs on was byte-for-byte
  -- IDENTICAL at frame 10 (48 ticks after opcao(CHAVE, ...)) and clearly
  -- different by frame 20 (68 ticks). ESPERA_OPCAO gives every option, not
  -- only the light ones, room to actually finish before anything gets
  -- captured or measured.
  local ESPERA_OPCAO = 75

  -- OPTIONS HELD IDENTICAL ON BOTH SIDES, from VC_CLIP_FIXO.
  --
  -- Some options do nothing on their own, which makes a two-sided clip of them
  -- dishonest by construction. `PART LAG` delays whatever MOTION LAG, SWAY or
  -- ATTENTION are doing, so with all three off it delays a constant and both
  -- sides come out the same: the mod's own help text says so. `AUTHORED
  -- REGIONS` is worse -- it only changes WHERE `PART LAG` cuts, so with PART
  -- LAG off it is provably a no-op.
  --
  -- Without this, filming either one produces two identical halves, and the
  -- PSNR guard downstream would correctly refuse to publish it. The refusal
  -- would be right and the reason would be invisible: it looks like the option
  -- does nothing, when in fact nothing was there for it to act on.
  --
  -- These are applied BEFORE the varying option and never changed again, so
  -- both halves see exactly the same scene apart from the one thing under test.
  --
  --   VC_CLIP_FIXO="part_lag=0.16,lag=1.2"
  local FIXO = os.getenv("VC_CLIP_FIXO") or ""
  if FIXO ~= "" then
    for par in FIXO:gmatch("[^,]+") do
      local k, v = par:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if not k then
        log("VC_CLIP_FIXO ilegivel: %s", par)
        return
      end
      opcao(k, tonumber(v) or v)
      log("fixo nos dois lados: %s=%s", k, tostring(v))
    end
    U.wait(ESPERA_OPCAO)
  end

  -- The left side can be a LEVEL, not just the off state.
  if VAL_ESQ ~= "off" then opcao(CHAVE, VAL_ESQ); U.wait(ESPERA_OPCAO) end

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
  -- feature does. With it, the clip explains itself, which is what a trailer
  -- needs to do. Written in English now (not the earlier Portuguese hints):
  -- this text is BURNED INTO THE VIDEO, it is the artifact being posted, and
  -- the project's own language policy for artifacts is en-US.
  -- GERUND FORM ("shoulders RISING", not "shoulders rise"), on purpose, not
  -- a style pick: this same string is used two ways, "watch " .. dica in the
  -- lower third and "Watch " .. dica .. "." as the title card's own
  -- sentence, and a gerund is the one verb form that reads correctly after
  -- "watch" regardless of whether the subject is singular or plural. The
  -- conjugated form ("the sprite extrudes") does not: "watch the sprite
  -- extrudes" is not a sentence, and this rendered straight into a shipped
  -- clip's lower third before it got caught here.
  local O_QUE_OLHAR = {
    breath = "the shoulders rising and falling while standing still",
    sway = "the body shifting its weight from one side to the other",
    lag = "the body lagging behind on the start and overshooting on the stop",
    footfall = "the body compressing on each step and stretching between them",
    front_shape = "a stepped gradient shading the front of the face",
    top_dome = "the top of the head no longer being a flat cap",
    step_weight = "the solid tilting along with the art's own step",
    shape = "how the volume itself is built",
    depth = "the sprite extruding into a voxel volume instead of a flat card",
    side_color = "the new side, top, and bottom faces changing color",
    ground_shade = "the lowest pixels picking up contact shade against the ground",
    blink = "the eyes closing on their own timer",
    top_edge = "the exposed top face darkening for a false top-down edge",
    first_person = "the character staying solid instead of a flat card up close",
  }
  -- Unknown keys fall back to a generic line instead of erroring. The key
  -- itself is validated separately, further up, before any of this runs; the
  -- fallback here is for a key that IS real but has not earned its own line
  -- in this table yet (the mod's OPTIONS list moves faster than this one).
  local DESCRICAO = O_QUE_OLHAR[CHAVE] or "a voxel_characters visual option"

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

  local fonteTitulo = love.graphics.newFont(28)
  local fonteGrande = love.graphics.newFont(22)
  local fonteMedia = love.graphics.newFont(15)
  local legendaTag, legendaAlpha = nil, 0

  -- The area clip.sh crops, in window coordinates. Everything drawn here
  -- needs to land INSIDE it, otherwise it exists in the full frame and
  -- disappears the moment ffmpeg crops.
  --
  -- DETERMINISTIC ACROSS TIME, not just between the two sides: the desktop
  -- window opens at a fixed, non-resizable 1024x768 (conf.lua), so this pixel
  -- box always means the same patch of screen, whether the clip is filmed in
  -- March or today. clip.sh passes the SAME $RECORTE to both sides of a
  -- single clip, so the two halves of an A/B are always framed identically too.
  local RX, RY, RW, RH = 232, 200, 560, 420
  do
    local r = os.getenv("VC_CLIP_RECORTE")
    if r then
      local w, h, xx, yy = r:match("^(%d+):(%d+):(%d+):(%d+)$")
      if w then RX, RY, RW, RH = tonumber(xx), tonumber(yy), tonumber(w), tonumber(h) end
    end
  end

  local desenhoOriginal = love.draw
  local function desenhoComLegenda()
    if desenhoOriginal then desenhoOriginal() end
    if not legendaTag or legendaAlpha <= 0 then return end

    -- PISO READS AS "off" TOO, on purpose. The floor pass repeats the off
    -- condition to measure natural noise; captioning it as the OTHER side
    -- would put a real pixel difference (different text, same spot, same
    -- frame index) into exactly the frame the gate measures, and that
    -- difference is not noise, it would be the gate reading its own caption
    -- instead of the game. The old top bar did exactly that.
    local antes = legendaTag == "off" or legendaTag == "piso"
    local ehContraOff = tostring(VAL_ESQ) == "off"
    -- BEFORE and AFTER only make sense when one of the sides is the current
    -- state. In an A/B between two levels both are candidates, so the label
    -- switches to A and B: calling one of them "before" would lie about what
    -- is being compared.
    local rotulo = ehContraOff and (antes and "BEFORE" or "AFTER")
                                 or (antes and "A" or "B")
    local valorLado = antes and VAL_ESQ or VALOR
    local linha1 = string.format("%s | %s %s", rotulo, string.upper(CHAVE),
      tostring(rotuloDoNivel(CHAVE) or valorLado):upper())
    local dica = O_QUE_OLHAR[CHAVE]
    local linha2 = dica and ("watch " .. dica) or nil

    -- LOWER THIRD, no box: a black box in a Game Boy game reads as game
    -- interface and not as video caption. A shadow solves legibility over
    -- any background without competing with the art, and it fades in and out
    -- within the recording instead of snapping on and off, same style as
    -- trailer.lua, and it needs to: these clips get cut into the same trailer.
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setBlendMode("alpha")
    love.graphics.setFont(fonteGrande)
    local y1 = RY + RH - (linha2 and 56 or 34)
    local x1 = RX + (RW - fonteGrande:getWidth(linha1)) / 2
    love.graphics.setColor(0, 0, 0, 0.75 * legendaAlpha)
    love.graphics.print(linha1, x1 + 2, y1 + 2)
    love.graphics.setColor(1, 1, 1, legendaAlpha)
    love.graphics.print(linha1, x1, y1)
    if linha2 then
      love.graphics.setFont(fonteMedia)
      local y2 = y1 + 27
      local x2 = RX + (RW - fonteMedia:getWidth(linha2)) / 2
      love.graphics.setColor(0, 0, 0, 0.75 * legendaAlpha)
      love.graphics.print(linha2, x2 + 2, y2 + 2)
      love.graphics.setColor(1, 1, 1, 0.85 * legendaAlpha)
      love.graphics.print(linha2, x2, y2)
    end
    love.graphics.pop()
  end

  -- TITLE CARD: two seconds at the head of the clip with the option's name
  -- and one sentence of what it does, so the clip explains itself before the
  -- comparison starts. Captured ONCE, right here, on a solid card that fills
  -- the whole crop rect; clip.sh holds this single frame for two seconds with
  -- ffmpeg. Same division of labor as the crop and the scale: the GAME draws
  -- pixels, ffmpeg only holds and stitches them together.
  love.draw = function()
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setColor(0.04, 0.04, 0.07, 1)
    love.graphics.rectangle("fill", RX, RY, RW, RH)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(fonteTitulo)
    local titulo = string.upper(CHAVE)
    love.graphics.print(titulo,
      RX + (RW - fonteTitulo:getWidth(titulo)) / 2, RY + RH / 2 - 44)
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.setFont(fonteMedia)
    -- Same "Watch " framing as the lower third's hint, and the same reason:
    -- DESCRICAO is stored as a gerund phrase so one string reads correctly
    -- both ways, here as a full sentence and there after "watch ".
    love.graphics.printf("Watch " .. DESCRICAO .. ".",
      RX + 28, RY + RH / 2 + 6, RW - 56, "center")
    love.graphics.pop()
  end
  love.graphics.captureScreenshot("vc_clip_title_0001.png")
  for _ = 1, PASSO do coroutine.yield() end
  love.draw = desenhoComLegenda
  log("title card captured: %s", CHAVE)

  -- ATRASO keeps the lower third OFF through frame 10, the one frame
  -- clip.sh's gate reads (vc_clip_*_0010.png) on every side it records.
  --
  -- Found by running the negative gate test against this very rewrite:
  -- `naoexiste=1`, a key this mod does not have, PUBLISHED. The lower third
  -- shows different text on "off" and "on" ON PURPOSE ("BEFORE | X OFF"
  -- against "AFTER | X 1"), because naming what changed is the point of the
  -- feature; but that text difference alone was enough to make the sides
  -- look more different than the noise floor, even though the game drew
  -- nothing different. A first fix tried cropping the caption's band out of
  -- frame 10 in clip.sh instead, after the fact; that turned out to be
  -- fragile (measured: it also hid a real difference a few dozen pixels
  -- away, on a different option). Keeping the caption off the ONE frame
  -- that gets measured, at the source, has no such failure mode.
  --
  -- Fixed at 10, not proportional to QUADROS: the gate's frame index is a
  -- constant in clip.sh, so `i > ATRASO` at ATRASO=10 guarantees frame 10
  -- never carries the caption for ANY clip length, including the shortest
  -- one clip.sh still accepts (10 frames, in which case the caption simply
  -- never appears, which is fine: a clip that short is not this feature's
  -- normal use).
  local ATRASO = 10

  local function grava(tag)
    legendaTag = tag
    for i = 1, QUADROS do
      -- The lower third fades in and out within the recording rather than
      -- snapping on and off, same curve as trailer.lua: appearing all at
      -- once together with the cut makes the eye read both things at the
      -- same time and read neither.
      legendaAlpha = 0
      if i > ATRASO and i <= QUADROS - ATRASO and QUADROS > 2 * ATRASO then
        local t = (i - ATRASO) / (QUADROS - 2 * ATRASO)
        legendaAlpha = math.min(1, math.min(t, 1 - t) * 6)
      end
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
  -- SAME WAIT AS "on", not the old shorter one, and this is not cosmetic.
  -- Found running the negative gate test AGAIN after adding ESPERA_OPCAO: the
  -- floor used to be recorded right after "off", with none of the extra wait
  -- "on" now takes for a "full" clear to settle. Other people in frame keep
  -- breathing on their own phase (see WHY INDOORS above) whether the tested
  -- option is real or not, so a LONGER gap before "on" than before "piso"
  -- gave the floor less time to drift and made `naoexiste=1`, a key this mod
  -- does not have, look more different from "off" than the floor was, for a
  -- reason that had nothing to do with the option. The floor only means
  -- anything if it sits the same distance in time from "off" that "on" does.
  --
  -- These frames do not go into the video; they exist only to give scale.
  U.wait(ESPERA_OPCAO)
  reposiciona()
  grava("piso")

  -- Right side: the requested option. MOTION LAG only shows up with the
  -- character moving, so for it both sides walk; for the others, both sides
  -- stay still. What the two sides never do is different things.
  opcao(CHAVE, NUM)
  U.wait(ESPERA_OPCAO)
  reposiciona()
  grava("on")

  legendaTag = nil
  legendaAlpha = 0
  love.draw = desenhoOriginal
  log("frames per side: %d", QUADROS)
  U.wait(10)
end
