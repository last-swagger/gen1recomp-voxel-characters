-- In-game gate for the life channel.
--
-- FIRST BUG IN THIS FILE, kept because it's instructive: the first version
-- wrapped Voxel3D.draw ABOVE the mod's wrap and read the matrix thinking it saw
-- the output. It sees the INPUT. Whoever wraps last runs first. The result was
-- "scale 1.000000 across 440 samples", which I almost read as "the feature does not
-- work" when the defect was in the instrument. From outside the mod's process
-- you cannot see the matrix it produces: it goes straight to a reference
-- that the mod captured in the patch.
--
-- So the division of labor ended up like this, and each side measures what only it can:
--
--   tests/voxel_chars_test.lua   the MATH. The mocked host is who receives the
--                                transformed matrix, so there it's fully visible:
--                                columns, mirror, shadow, phase.
--   this file                    the PIXELS. Whether the right math reaches the screen.
--
-- What this gate asks:
--
--   V0 the instrument is aimed        the camera rung is where the thresholds
--                                 were calibrated and the character mask is not
--                                 empty. Without this everything below measures
--                                 the empty set on an unknown scale.
--   V1 baseline is still              with everything OFF, a whole cycle of frames
--                                 is identical. Without this nothing below counts.
--   V2 breathing moves the screen  with BREATH on, the same cycle starts to
--                                 differ
--   V3 the menu is in control      the weakest level separates from the others
--                                 (the metric saturates above that, and says so)
--   V4 the change is OURS          with VOXEL CHARS OFF, BREATH changes nothing
--   V5 swaying moves it too        and also responds to the menu level
--   V6 the spring stays quiet      MOTION LAG with everyone still doesn't change
--                                 anything: spring at rest, target zero
--   V7 and wakes with the step     the same walk with and without LAG differs
--   V8 how much it costs           ms per frame in a full city, with and without
--
-- V4 is the one that doesn't pass by chance: it's the negative control. V6
-- and V7 are a pair: alone, either would pass for the wrong reason (a dead feature
-- passes V6; a feature that oscillates on its own passes V7).
--
-- ===========================================================================
-- THIS GATE USED TO ANSWER DIFFERENTLY ON TWO MACHINES, AND THE REASON WAS
-- NEVER THE MOD. Measured 2026-08-13, same commit, same map:
--
--   render machine (no third-party overworld mod)   floor 0 px, LAG 190 px
--   Kim's Mac Studio (Wilds of Kanto installed)     floor 1188 px, LAG 568 px
--
-- V1, V7 and V10 went red on the second machine and green on the first. The
-- floor is what two IDENTICAL runs differ by, so a floor of 1188 says
-- something in the scene moved that had nothing to do with the option under
-- test, and the checks correctly refused to call the remainder an effect.
--
-- WHAT WAS MOVING, and it was measured rather than guessed. A driver was run
-- that dumped every entity and drew a heat map of the changed pixels:
--
--   [diag] mapa REDS_HOUSE_2F em 2,3: 2 entidades, 1 npcs
--   [diag]   entidade 2 (...): id=REDS_HOUSE_2F_obj_901 cellX=6 cellY=3 ...
--   [diag] A1 (assinatura MUDOU): 358 px diferentes; caixa x 693..834 y 333..393
--
-- The changed pixels were nowhere near the player: they were a SECOND
-- CHARACTER standing six cells away, turning and stepping on its own. It is a
-- runtime engine NPC that overworld_wild_spawns (Wilds of Kanto) injects
-- through the host's own OverworldState:addRuntimeObject, so it lands in
-- game.overworld.entities like any map object and the room the header below
-- calls empty is not empty at all. The id changes on every map entry
-- (_obj_901, _obj_904, ...), which is why it was intermittent and why two
-- runs on the same machine could disagree.
--
-- It was ruled out early as "installed but not enabled", because
-- options.modProfiles[1].enabled does not list it. The list that decides is
-- options.mods, and there it reads `overworld_wild_spawns = true`.
--
-- THE FIX IS IN TWO LAYERS, and the second exists because the first cannot
-- cover everything:
--
--   1. THE SCENE IS EMPTIED. Everything that is not the player is taken out
--      of entities/npcs/ghosts after every teleport (`soOJogador`). This is
--      the host's own list surgery -- OverworldController:2600 and :3894
--      remove from exactly these lists -- and it is mod-agnostic: it does not
--      know or care which mod put someone there.
--
--   2. EVERY PIXEL COUNT IS TAKEN INSIDE A CHARACTER MASK, never over the
--      frame. The mask is built the way probe_hd and probe_walk build theirs:
--      photograph the same cell with the solid and with VOXEL CHARS OFF, and
--      keep the pixels that differ. Those are the character and nothing else,
--      found without knowing where it stands.
--
-- BOTH ARE NEEDED, AND THE EXPERIMENT THAT SAYS SO IS WORTH KEEPING. A
-- wandering stranger was INJECTED one cell from the player, through the same
-- addRuntimeObject the offending mod uses, and the floor measured four ways:
--
--                                     whole frame    inside the mask
--   stranger present, mask built
--     while he was there                     908                503
--   stranger present, mask built
--     before he arrived                      947                  0
--   scene emptied                              0                  0
--
-- The middle row is the mask doing its job. The top row is why the mask alone
-- is not enough: this mod turns EVERY character into a solid, so toggling
-- VOXEL CHARS moves the stranger's pixels too and he walks straight into the
-- mask that was supposed to exclude him. Emptying the scene is what makes the
-- mask mean "the player". The mask is what covers everything emptying cannot
-- reach -- animated tiles, a day/night cycle, another mod's HUD -- none of
-- which is an entity.
--
-- Measured on a quiet scene, the masked number and the whole-frame number came
-- out EQUAL for every check in this file -- baseline 0/0, BREATH STRONG
-- 101/101, SWAY NORMAL 23/23, one step with LAG 31/31, on the run that
-- established the mask. The mask throws away no signal; it only throws away the
-- room. (Those four figures are from that run and predate the two corrections
-- below, so they no longer match today's output. What they measured is the
-- mask, and that has not changed.)
--
-- THE CAMERA RUNG IS NOW REALLY PINNED, and that is what re-scaled the
-- thresholds. `U.tap(game, "3")` never arrived: the host's ladder is stepped
-- from its own Game:keypressed (DramaticShapeVoxelMod/main.lua, `cycleVoxel`),
-- which does not read the driver's input queue, so the block below REPORTED
-- the rung instead of setting it and every number in this file was taken at
-- whatever rung the machine's save happened to hold -- 3 here, 4 on the render
-- machine. Two machines were measuring two different character sizes. It is
-- now set through the host's own pipeline ladder, `Pipelines.setLevel`, and
-- restored at the end.
--
-- WHAT THE RUNG COST, and it is the reason two thresholds moved. At rung 4
-- (50 degrees) one step with MOTION LAG measured 190 px; at the pinned rung 3
-- (35 degrees, VoxelState.ANGLES_DEG's full-voxel step, and the step this file
-- has always claimed to want) the character is smaller, so fewer pixels change,
-- and V7's threshold of 40 sat ABOVE the whole of the thing it was meant to
-- accept.
--
-- TWO MORE PER-MACHINE LEAKS CAME OUT OF THE SAME HUNT, and they are described
-- where they are fixed. In short: this driver pinned seven options out of
-- twenty-one and inherited the other fourteen from the machine's save (see
-- `FIXO`), and it sampled the breath cycle in FRAMES while the mod advances it
-- on the wall clock with vsync off (see `esperaSegundos`). Between them they
-- were most of the remaining disagreement.
--
-- WHERE THE TWO MACHINES LAND NOW, three consecutive runs each, same commit,
-- same 1024x768, room emptied, everything pinned:
--
--                                  Mac Studio        render machine
--   character, standing              402 samples       406 samples
--   character, at the step's end     356               369
--   baseline, everything off           0                 0
--   BREATH  SUBTLE                    66  67  66        42  42  42
--           NORMAL                   130 130 130       110 110 110
--           STRONG                   188 188 185       186 175 175
--   VOXEL CHARS OFF + BREATH STRONG    0                 0
--   SWAY    SUBTLE                    32  37  34        37  37  37
--           NORMAL                    76  78  80        78  79  79
--   MOTION LAG, nobody moving          0                 0
--   FOOTFALL, nobody moving            0                 0
--   one step, floor (option off
--     on both sides)                   0                 0
--   one step with MOTION LAG          88  91 146       149 151 149
--   one step with FOOTFALL            24  24  24        22  22  22
--
-- Before this work the same two machines answered 0 and 1188 on that floor. The
-- one column that still disagrees by more than a few percent is BREATH SUBTLE
-- (66 against 42); nothing gates on its size, and it is written down here
-- rather than tuned away.
-- ===========================================================================

return function(game)
  local U = dofile("tests/drivers/util.lua")
  dofile("mods/voxel_characters/tools/ingame/erro.lua")()
  io.stdout:setvbuf("line")
  if love.window and love.window.setVSync then pcall(love.window.setVSync, 0) end

  local linhas = {}
  local function nota(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    local linha = ok and s or tostring(fmt)
    linhas[#linhas + 1] = linha
    print("[vida] " .. linha)
    love.filesystem.write("vc_life.txt", table.concat(linhas, "\n") .. "\n")
  end

  local direcao, tentaPasso
  local vereditos = {}
  local function veredito(nome, ok, detalhe)
    vereditos[#vereditos + 1] = { nome = nome, ok = ok }
    nota("%-3s %s  %s", nome, ok and "PASSED" or "FAILED", detalhe or "")
  end

  nota("=== gate de pixel do canal de vida ===")

  -- Captures a frame as ImageData, without going through disk. The
  -- captureScreenshot callback runs at the end of the frame, so we yield until it arrives.
  local function captura()
    local pronto
    love.graphics.captureScreenshot(function(imageData) pronto = imageData end)
    for _ = 1, 120 do
      coroutine.yield()
      if pronto then return pronto end
    end
    return nil
  end

  -- THE CHARACTER MASK, and every number in this file is counted inside it.
  --
  -- Sampled on a stride of 3 on both axes: a ninth of the work, and no effect
  -- of this size hides in a 3 px grid when the game draws at ~5 screen px per
  -- Game Boy pixel. LARG/ALT come from the first photograph, so nothing here
  -- assumes a resolution.
  --
  -- MASCARA is nil until `fazMascara` has run, and while it is nil `difere`
  -- counts the whole frame. That is deliberate: the mask is built BY
  -- differencing frames, so the builder needs the unmasked counter.
  local LARG, ALT
  local MASCARA, CORPO

  local function grade()
    local g = {}
    for y = 0, ALT - 1, 3 do g[y] = {} end
    return g
  end

  -- Walks two photographs once on the sampling lattice and hands each sample
  -- to `fn` with whether the two differ there.
  local function varre(a, b, fn)
    for y = 0, ALT - 1, 3 do
      for x = 0, LARG - 1, 3 do
        local r1, g1, b1 = a:getPixel(x, y)
        local r2, g2, b2 = b:getPixel(x, y)
        fn(x, y, not (r1 == r2 and g1 == g2 and b1 == b2))
      end
    end
  end

  local function difere(a, b)
    if not (a and b) then return -1 end
    local w, h = a:getWidth(), a:getHeight()
    if b:getWidth() ~= w or b:getHeight() ~= h then return -1 end
    local n = 0
    for y = 0, h - 1, 3 do
      local linha = MASCARA and MASCARA[y]
      if linha or not MASCARA then
        for x = 0, w - 1, 3 do
          if (not MASCARA) or linha[x] then
            local r1, g1, b1 = a:getPixel(x, y)
            local r2, g2, b2 = b:getPixel(x, y)
            if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 then n = n + 1 end
          end
        end
      end
    end
    return n
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
    if not ok then nota("WARNING: the change of %s was NOT emitted", chave) end
    return ok
  end

  -- NOBODY IN THE ROOM BUT THE PLAYER, enforced instead of assumed.
  --
  -- The header explains what walked in. This takes everyone who is not the
  -- player out of the three lists the host draws and updates from, which is
  -- the same surgery the host performs on itself when a runtime object is
  -- dropped (OverworldController:2600, :3894, :4264). `ghosts` holds
  -- neighbour-map NPCs and each entry wraps its npc in `.npc`.
  --
  -- setMap rebuilds these lists from the map definition, so this has to run
  -- after EVERY teleport, and a mod that adds its object again mid-run has to
  -- be caught mid-run: `espera` re-applies it every ten frames and the total
  -- is reported, so a run where somebody kept coming back is visible in the
  -- log instead of showing up as an unexplained floor.
  local retirados = 0
  local function soOJogador()
    local ow = game.overworld
    if not ow then return 0 end
    local p = ow.player
    local n = 0
    for _, lista in ipairs({ ow.entities or {}, ow.npcs or {}, ow.ghosts or {} }) do
      for i = #lista, 1, -1 do
        local e = lista[i]
        if (e.npc or e) ~= p then table.remove(lista, i); n = n + 1 end
      end
    end
    retirados = retirados + n
    return n
  end

  local function espera(n)
    for i = 1, n do
      if i % 10 == 0 then soOJogador() end
      coroutine.yield()
    end
  end

  -- WAIT IN SECONDS, NOT IN FRAMES, and this is a defect the gate carried from
  -- the day it was written.
  --
  -- The life channel advances on the WALL CLOCK: `lifeAdvance(inst, px, py,
  -- now, rate / BREATH_PERIOD)` with BREATH_PERIOD = 3.1 seconds. The envelope
  -- below photographs six moments "across a period" and it counted FRAMES to
  -- get there -- and the first thing this driver does is turn vsync OFF, so a
  -- frame is however long the machine needs, 4.6 ms here and 8.9 ms on the
  -- render machine. Thirty-one frames is half a second on one machine and a
  -- quarter of a second on the other, and neither is the 0.517 s that would be
  -- a sixth of a breath.
  --
  -- What that produced: BREATH STRONG measured 9 pixels against SUBTLE's 28 in
  -- the same run -- the strongest setting moving the screen LESS than the
  -- weakest -- because all six photographs had landed inside one short arc of
  -- the sine instead of spread around it. The same inversion the header of
  -- `envelope` blames on a fixed pair of frames, arriving through the sampling
  -- interval instead.
  local function esperaSegundos(segundos)
    local fim = love.timer.getTime() + segundos
    local n = 0
    while love.timer.getTime() < fim and n < 1200 do
      n = n + 1
      if n % 10 == 0 then soOJogador() end
      coroutine.yield()
    end
  end

  -- THE MASK IS BUILT WHERE THE PLAYER IS STANDING RIGHT NOW, so it has to be
  -- rebuilt whenever the measurement moves him (the walk in V7/V10 does).
  --
  -- Two photographs with the solid and two with VOXEL CHARS OFF. A sample
  -- joins the mask when it DIFFERS between the two states and is STABLE
  -- within each pair. The stability test is what keeps something that is
  -- moving out of the mask: it cannot be still in both pairs and different
  -- between them for the reason we are asking about.
  --
  -- DILATED BY TWO LATTICE CELLS (6 screen px). The mask is the union of what
  -- the flat card covers and what the solid covers; BREATH and SWAY move the
  -- solid by fractions of a Game Boy pixel, so an edge can land just outside
  -- that union. Measured on a quiet scene, the masked number equals the
  -- whole-frame number for every check here, which is the check on the
  -- dilation: it is generous enough to lose nothing.
  local function fazMascara()
    local s1 = captura()
    if not s1 then return false end
    LARG, ALT = s1:getWidth(), s1:getHeight()
    espera(9)
    local s2 = captura()
    opcao("depth", "off"); espera(50)
    local c1 = captura()
    espera(9)
    local c2 = captura()
    opcao("depth", 3); espera(50)
    if not (s2 and c1 and c2) then return false end
    local estavelS, estavelC, dif = grade(), grade(), grade()
    varre(s1, s2, function(x, y, d) estavelS[y][x] = not d end)
    varre(c1, c2, function(x, y, d) estavelC[y][x] = not d end)
    varre(s1, c1, function(x, y, d) dif[y][x] = d end)
    local cru, bruto = grade(), 0
    for y = 0, ALT - 1, 3 do
      for x = 0, LARG - 1, 3 do
        if dif[y][x] and estavelS[y][x] and estavelC[y][x] then
          cru[y][x] = true; bruto = bruto + 1
        end
      end
    end
    local R, m, total = 2, grade(), 0
    for y = 0, ALT - 1, 3 do
      for x = 0, LARG - 1, 3 do
        if cru[y][x] then m[y][x] = true
        else
          for dy = -R, R do
            local linha = cru[y + dy * 3]
            if linha then
              for dx = -R, R do
                if linha[x + dx * 3] then m[y][x] = true break end
              end
            end
            if m[y][x] then break end
          end
        end
        if m[y][x] then total = total + 1 end
      end
    end
    MASCARA, CORPO = m, bruto
    nota("character mask: %d samples, %d after dilating, out of %d on screen",
      bruto, total, math.ceil(LARG / 3) * math.ceil(ALT / 3))
    return bruto > 0
  end

  -- THE OPTIONS THIS RUN TOUCHES ARE PUT BACK WHERE IT FOUND THEM.
  --
  -- This driver pins ten of them and the game writes options.lua on the way
  -- out, so a gate run used to leave a player's menu rearranged -- and, worse,
  -- left the NEXT run starting from a different place than the previous one.
  -- Two runs of the same gate on the same machine have to be the same
  -- experiment.
  local opcoesAntes = {}
  do
    local o = game.mods and game.mods.modOptions
      and game.mods.modOptions.voxel_characters
    o = o or (game.save and game.save.options and game.save.options.modOptions
      and game.save.options.modOptions.voxel_characters)
    for k, v in pairs(o or {}) do opcoesAntes[k] = v end
  end

  -- A PLACE WITH NO ONE ELSE, and this was learned the hard way.
  --
  -- The first choice was Oak's lab, "because there's people standing around." There are
  -- ELEVEN object events, and within three seconds someone always turns or takes a
  -- step. The gate kept failing on NPC movement and I almost read that as
  -- a spring defect. Red's room upstairs has ZERO object events IN THE ROM:
  -- vanilla, the only character on screen is the player, who stays exactly
  -- where we left them. One character is enough, because what this gate
  -- measures is whether the effect REACHES the screen and responds to the
  -- menu; that two instances end up out of phase is proven in the offline
  -- suite, where you can read the whole matrix.
  --
  -- "ZERO OBJECT EVENTS IN THE ROM" IS NOT THE SAME CLAIM AS "NOBODY IS
  -- THERE", and the difference cost this gate a release. A mod can put a real
  -- engine NPC on any map at runtime, and one did (see the header). Choosing an
  -- empty room is still right -- it keeps the mask small and the scene cheap --
  -- but it is now a preference, not the guarantee. `soOJogador` is the
  -- guarantee.
  local MAPA = os.getenv("VC_MAP") or "REDS_HOUSE_2F"
  local Pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")
  local _, PX, PY = Pouso.escolher(game, MAPA, 3, 4)
  U.teleport(game, MAPA, PX, PY, "down")
  U.wait(60)
  if not (game.overworld and game.stack:top() == game.overworld) then
    veredito("V1", false, "nao cheguei ao mundo"); return
  end
  local estranhos = #(game.overworld.entities or {}) - 1
  soOJogador()
  espera(60)
  nota("map %s: %d entities on arrival, %d after taking out everyone who is "
    .. "not the player (%d stranger(s) in the room)", MAPA, estranhos + 1,
    #(game.overworld.entities or {}), estranhos)

  -- PINNING THE CAMERA STEP, and this is a fix for a gate defect.
  --
  -- The previous version gave ONE tap on "3" and moved on. The step is saved in the
  -- options, so the starting point depended on how the PREVIOUS run
  -- had left the game, and a single tap landed on a different step each time.
  -- Different step means a different character size on screen, and the number of
  -- pixels that change scales with that: the same option measured 266 in one run and
  -- 77 in the next, and I almost read the drop as a regression in the feature. It wasn't the
  -- feature, it was the camera.
  --
  -- AND THE TAP NEVER ARRIVED, measured 2026-08-13 while recalibrating V10. The
  -- loop was instrumented to print the rung on every iteration: it printed
  -- "50.00 graus, level 4" twelve times in a row. `U.tap(game, "3")` goes
  -- through the driver's input queue, and the host mod's ladder is stepped from
  -- its own `Game:keypressed` (DramaticShapeVoxelMod/main.lua, `cycleVoxel`),
  -- which never reads that queue. So the block REPORTED the rung instead of
  -- setting it, and every pixel count in this file was taken at whichever rung
  -- the machine's save happened to hold: 3 on the Mac Studio, 4 on the mbp.
  --
  -- IT IS NOW SET THROUGH THE HOST'S OWN LADDER, which is what `cycleVoxel`
  -- calls once it has decided a key belongs to it. Two things this does NOT do,
  -- both on purpose:
  --
  --   * it does not call `Pipelines.syncOptions`. That is the function that
  --     copies the live ladder back into save.options.pipelines, and the game
  --     writes options.lua on the way out. Not calling it is what keeps a gate
  --     run from editing the rung a player chose;
  --   * it does not leave the ladder where it put it: the level read on arrival
  --     is restored at the end of the run.
  --
  -- Setting a world pipeline above zero switches TILT off in the live module
  -- (Pipelines.excludeTilt). That is the host's rule, not ours, and since
  -- nothing here writes options it lasts exactly as long as this process.
  --
  -- RUNG 3 IS 35 DEGREES, VoxelState.ANGLES_DEG's full-voxel step, and it is the
  -- step this file has always said it wanted. Pinning it cost signal, because
  -- the character is smaller at 35 than at 50: one step with MOTION LAG
  -- measured 190 px at the unpinned rung 4 and measures 31 px at rung 3. V7 and
  -- V10 are re-derived against the smaller figure further down.
  local RUNG = tonumber(os.getenv("VC_RUNG")) or 3
  local Pipelines = require("src.render.Pipelines")
  local rungAntes = Pipelines.level("voxel")
  local rungAgora = Pipelines.setLevel("voxel", RUNG)
  nota("camera rung: was %s, now %s (target %d, ladder max %s)",
    tostring(rungAntes), tostring(rungAgora), RUNG,
    tostring(Pipelines.maxLevel("voxel")))
  -- EVERY OPTION IS PINNED, NOT JUST THE SEVEN UNDER TEST, and this is the last
  -- of the three per-machine leaks this file had.
  --
  -- Every number here counts CHANGED PIXELS, so it scales with what is on
  -- screen, and thirteen options this driver never touched decide what is on
  -- screen. They were inherited from whatever the machine's save happened to
  -- hold, and the two machines hold different things:
  --
  --                    Kim's Mac Studio      the render machine
  --   front_shape            0.22                   off
  --   ground_shade           on                     off
  --   side_color             outline                body
  --   step_weight            0.5                    off
  --   attention              0.5                    (absent, default off)
  --   grid_chars             off                    (absent, default ON)
  --   hd_sprite              off                    on
  --
  -- Measured through this very probe with those two sets, same commit, same
  -- pinned rung, same screen size, both stable across four runs each: one step
  -- with and without FOOTFALL came out 26..27 px on one machine and 18 px on
  -- the other. A gate cannot be calibrated against a number that depends on a
  -- menu the player is free to change.
  --
  -- THE VALUES ARE THE SHIPPED DEFAULTS, with one exception. Defaults, because
  -- that is what an install measures -- the same argument HD SPRITE was pinned
  -- on. The exception is GRID CHARS, whose default is ON: it paints a marker on
  -- the ground under every character, and that marker toggles with VOXEL CHARS,
  -- so it would join the character mask below and inflate the very number the
  -- step thresholds are a fraction of. It has its own gate (probe_grid).
  --
  -- HD SPRITE stays OFF for the two reasons it was pinned off on 2026-08-13: it
  -- is the shipped default, so it is what an install measures; and it needs no
  -- asset on disk, while ON silently falls back to the ROM sheet wherever
  -- hd/<sheet>.png is missing, which would make the pin a lie on some machines
  -- and not others. Measured through this probe, one step with and without
  -- FOOTFALL is 46 pixels on the ROM sheet and 37 on the enlarged one: the same
  -- check, the same code, two different numbers.
  local FIXO = {
    depth = 3, side_color = "outline", shape = "slab", ground_shade = "on",
    blink = "off", blink_detect = "off", grid_chars = "off", top_edge = "on",
    front_shape = 0.22, top_dome = "off", step_weight = "off",
    breath = "off", sway = "off", lag = "off", footfall = "off",
    attention = "off", part_lag = "off", hd_sprite = "off",
    authored_regions = "off", first_person = "card", demo_fx = "off",
  }
  -- A key this machine did not have is REMOVED again at the end, not left at
  -- the value we pinned it to: adding it would be editing a player's menu.
  local ausentes = {}
  for k, v in pairs(FIXO) do
    if opcoesAntes[k] == nil then ausentes[#ausentes + 1] = k end
    opcao(k, v)
  end
  espera(20)
  -- The host lib is fetched HERE, not at the top: this version of the probe measures pixels
  -- and doesn't need the host for anything else, so loading it only where it's used avoids
  -- an absent host bringing down the whole gate instead of just losing one check.
  local VoxelState
  do
    local V
    for _, id in ipairs({ "BATTLE_ART_VOXEL_FORK", "DRAMALESS_SHAPE", "DRAMATIC_SHAPE" }) do
      local e = game.mods and game.mods.exports and game.mods.exports[id]
      if e and e.lib then V = e.lib break end
    end
    if V then
      local ok, mod = pcall(V.require, "VoxelState")
      VoxelState = ok and mod or nil
    end
  end
  local okEstado = VoxelState ~= nil
  local ALVO = math.rad(35)
  local degrauOk = rungAgora == RUNG
  -- WAIT FOR THE ANGLE TO SETTLE before reading it. VoxelState.angle is
  -- smoothed: right after the ladder moves it is halfway between two steps, and
  -- reading there reports a step that is on its way somewhere.
  local function assenta()
    local anterior
    for _ = 1, 90 do
      local a = tonumber(VoxelState.angle)
      if anterior and a and math.abs(a - anterior) < 1e-6 then return a end
      anterior = a
      coroutine.yield()
    end
    return tonumber(VoxelState.angle)
  end
  -- THE ANGLE IS THE INDEPENDENT CONFIRMATION, not the mechanism. The ladder
  -- above is what SETS the rung; this reads what the renderer actually ended up
  -- drawing with, through the host mod's own state. Two readings that disagree
  -- would mean the ladder and the camera had come apart, which is worth a line
  -- in the log even though nothing here can fix it.
  if okEstado and VoxelState then
    -- Long enough for the smoothing to start before waiting for it to stop:
    -- `assenta` returns as soon as two consecutive readings match, and right
    -- after the ladder moves they are still equal, because the animation has
    -- not begun.
    espera(30)
    local a = assenta()
    local anguloOk = a and math.abs(a - ALVO) < 0.02
    nota("camera angle: %.1f degrees (target 35, agrees: %s)",
      math.deg(tonumber(a) or 0), tostring(anguloOk))
    if not anguloOk then
      degrauOk = false
      nota("WARNING: the ladder says rung %s but the camera is at %.0f degrees; "
        .. "the numbers below are comparable with each other, not with another "
        .. "machine's", tostring(rungAgora), math.deg(tonumber(a) or 0))
    end
  else
    nota("WARNING: no VoxelState, so the camera rung could not be confirmed")
  end
  espera(30)

  -- BLINK is a confounder: it animates the eyes over time, so the baseline
  -- would never stay still and V1 would accuse the innocent. It, and everything
  -- else that moves on its own, is already off in FIXO above.
  espera(45)

  -- ---------------------------------------------------------------- V0
  -- THE INSTRUMENT, BEFORE ANYTHING IT MEASURES.
  --
  -- Two ways this file can go green having measured nothing, and both have
  -- happened to its neighbours:
  --
  --   * the rung is not where the thresholds were calibrated, so every number
  --     below is on a different scale (probe_hd's lesson, one option over);
  --   * the character mask comes out EMPTY, and then every check reads the
  --     empty set: zero changed pixels satisfies V1, V4, V6 and V9 for free
  --     and the three that want movement fail for a reason that is not the
  --     mod. This is probe_hd's H1, in mask form.
  local mascaraOk = fazMascara()
  veredito("V0", degrauOk and mascaraOk and (CORPO or 0) > 100, string.format(
    "the camera rung %s on target %d and the character covers %d samples of the "
    .. "grid; without both, everything below measures the empty set on an "
    .. "unknown scale", degrauOk and "is" or "is NOT", RUNG, CORPO or -1))

  -- Scene signature: where each entity is. If it changes between the two
  -- photos, someone took a step, and a step changes hundreds of pixels, which
  -- drowns out a half-pixel effect.
  --
  -- This is NOT a convenience: the first version measured 1261 pixels in SUBTLE
  -- against 566 in STRONG, and the inverted order looked like a mod defect. It was a
  -- lab assistant taking a step inside the measurement window. Without
  -- proving the scene was still, the number doesn't measure the feature, it measures the NPC.
  --
  -- AND POSITION ISN'T ENOUGH. An NPC with NPC_CHANGE_FACING "marches" in place: it
  -- switches direction and walk frame without leaving its spot (NPC.lua:70-79
  -- keeps px and py pinned). A position-only signature doesn't see this, and the frame
  -- switch changes hundreds of pixels, which is how MOTION LAG at rest measured 476
  -- pixels and looked like a spring oscillating on its own. So the signature carries
  -- everything that picks the sprite: where, toward where, and at what point in the step.
  --
  -- AFTER `soOJogador` THIS IS THE PLAYER'S OWN POSE, and that is the right
  -- scope for it now: a stranger is no longer in the list to be caught, and one
  -- outside the mask can no longer reach the number anyway. It still earns its
  -- place -- it is what refuses a window in which the PLAYER moved -- and it is
  -- also the second line of defence on the emptying: somebody who came back
  -- mid-window shows up here as an unstable signature and the envelope retries.
  local function assinatura()
    local t = {}
    for _, e in ipairs(game.overworld.entities or {}) do
      -- walkPhase() is the real frame selector, and on NPC it has no
      -- side effect (NPC.lua:124-127). pcall because the player doesn't have one.
      local ok, fase = pcall(function() return e:walkPhase() end)
      t[#t + 1] = string.format("%d,%d,%s,%s,%s,%s",
        e.px or 0, e.py or 0, tostring(e.facing), tostring(e.progress),
        tostring(e.stepFlip), ok and tostring(fase) or "-")
    end
    return table.concat(t, ";")
  end

  -- ENVELOPE, not a pair of frames.
  --
  -- A pair separated by a FIXED interval measures |s(t2) - s(t1)|, which depends on the
  -- phase each character was in. With ten people in different phases the
  -- number swings: I measured NORMAL 525 against STRONG 510 and SUBTLE 1261 against
  -- STRONG 566 in different runs, and both inversions were the instrument's,
  -- not the mod's. The right answer is to sweep the CYCLE: one reference photo and
  -- five comparisons spread across a period, keeping the LARGEST. This measures
  -- the excursion, which is what the amplitude controls, and doesn't depend on where the
  -- sine wave was when the gate started.
  --
  -- AND IT IS EVERY PAIR, NOT EVERY PAIR WITH THE FIRST PHOTO, which is the
  -- same argument one step further and it was left half-made. Comparing the
  -- five against a single reference still depends on where the sine wave was
  -- when the shutter first opened: a reference taken mid-swing halves every
  -- number below it. Comparing all six against each other measures the real
  -- excursion of the window.
  --
  -- IT DID NOT MOVE A SINGLE NUMBER, and that is written down rather than
  -- quietly dropped, because the change was made expecting it would. Rung 3,
  -- this map, mask, room emptied, two runs each way -- measured BEFORE the
  -- sampling interval was fixed below, so the figures are smaller than what the
  -- gate prints today; the comparison between the two columns is the point:
  --
  --                        against the reference   over every pair
  --   the still baseline           0    0                 0    0
  --   BREATH SUBTLE               11    6                 9    8
  --   BREATH NORMAL               68   81                82   82
  --   BREATH STRONG               79   92                90   94
  --   SWAY SUBTLE                  5    3                 3    3
  --   SWAY NORMAL                 82   13                13   14
  --
  -- Every difference there is inside the run-to-run spread of the same
  -- formulation (SWAY NORMAL alone reads 82 and 13 against the reference). So
  -- this buys no signal at this rung. It is kept because the weakness it
  -- removes is real -- a reference photograph taken mid-swing halves every
  -- number underneath it, and that is precisely the class of instrument bug
  -- this file is made of -- and because it was measured to cost nothing: the
  -- photographs were already being taken, only the comparisons are new.
  --
  -- The still checks cannot be affected either way: photographs of a still
  -- scene are identical however they are paired.
  --
  -- WHAT IT DID NOT FIX was the sampling interval, and that turned out to be
  -- the whole problem: see `esperaSegundos`. With the window measured in
  -- seconds instead of frames, the weakest signal in the file went from 3
  -- samples out of 400 to 32, and the three BREATH levels came out in order for
  -- the first time (66, 130, 188 against a baseline of 0). Nothing here asserts
  -- that order -- the offline suite owns magnitude -- but an instrument that
  -- reports STRONG below SUBTLE is not measuring the thing it names, and this
  -- one was doing that on the run that found it: 28, 53, 9.
  -- The mod's own BREATH_PERIOD (main.lua, `lifeDrawWrap`), in seconds, because
  -- that is the unit the effect is written in. SWAY_PERIOD is 8.86 s, nearly
  -- three times this, so one window covers about a third of a sway -- enough
  -- for V5, which asks whether it moves at all, and the reason SWAY's numbers
  -- are the smallest in the file.
  local PERIODO = 3.1
  local function envelope()
    for tentativa = 1, 6 do
      local antes = assinatura()
      local fotos = { captura() }
      local pior, estavel, medidas = 0, true, 0
      for k = 1, 5 do
        esperaSegundos(PERIODO / 6)
        local q = captura()
        if assinatura() ~= antes then estavel = false; break end
        fotos[#fotos + 1] = q
        local d = -1
        for i = 1, #fotos - 1 do
          local e = difere(fotos[i], q)
          if e > d then d = e end
        end
        -- COUNT THE MEASUREMENTS THAT SUCCEEDED, not just the highest value.
        --
        -- `difere` returns -1 when one of the captures came back nil (the capture
        -- gives up after 120 frames). With `pior` starting at zero, a run
        -- where NO photo came out returned zero, and zero is exactly what
        -- four checks in this file require to say "the scene is
        -- still": V1, V4 (the negative control), V6 and V9. Broken capture
        -- left all four green without a single measurement. Zero-from-nothing has
        -- to be distinguishable from zero-measured.
        if d >= 0 then
          medidas = medidas + 1
          if d > pior then pior = d end
        end
      end
      if estavel and medidas > 0 then return pior, tentativa end
      espera(30)
    end
    return -1, 6
  end
  local parDeQuadros = envelope

  -- ---------------------------------------------------------------- V1
  --
  -- FORTY, AND IT IS THE SAME NUMBER AS BEFORE FOR A DIFFERENT REASON. It used
  -- to be a guess at how much a whole frame drifts; it is now a tenth of the
  -- character, and both sides of it are measured at rung 3 on this map:
  --
  --   quiet scene, inside the mask                        0
  --   a stranger walking, inside a mask built without him 0
  --   a stranger walking, inside a mask built with him  503
  --   a stranger walking, whole frame              908..947
  --
  -- The character itself is around 400 samples, so 40 sits at a tenth of it and
  -- an order of magnitude below anything a second character produces. The same
  -- number and the same reasoning cover V4, V6 and V9, which all ask "is this
  -- still".
  local PARADO = 40
  opcao("breath", "off")
  espera(30)
  local base, tb = parDeQuadros()
  nota("linha de base (tudo OFF): envelope de %d pixels (%d tentativas)", base, tb)
  veredito("V1", base >= 0 and base < PARADO,
    "com tudo OFF a cena tem que estar parada")

  -- ---------------------------------------------------------------- V2, V3
  local medidas = {}
  for _, nivel in ipairs({ { "SUBTLE", 0.010 }, { "NORMAL", 0.020 }, { "STRONG", 0.035 } }) do
    opcao("breath", nivel[2])
    espera(30)
    local n, tt = parDeQuadros()
    medidas[#medidas + 1] = { nome = nivel[1], valor = nivel[2], px = n }
    nota("BREATH %-6s (%.3f): envelope de %d pixels (%d tentativas)",
      nivel[1], nivel[2], n, tt)
  end

  veredito("V2", medidas[3] and medidas[3].px > base + 40, string.format(
    "STRONG mudou %d pixels contra %d da linha de base",
    medidas[3] and medidas[3].px or -1, base))

  -- THIS METRIC DOES NOT MEASURE MAGNITUDE, AND THE GATE STOPPED PRETENDING IT DOES.
  --
  -- Counting changed pixels has two bad ranges and one good one, and the good one is narrow.
  -- While the displacement is smaller than one screen pixel, only part of the edges
  -- flip and the number grows. Past that, every edge has already flipped and it saturates.
  -- And the character's size on screen depends on the CAMERA STEP, which stays
  -- saved in the options between runs: the same option measured 266 in one run and 9
  -- in the next, just because the camera was on a different step.
  --
  -- I tried to pin the step and couldn't do it reliably. So the
  -- monotonicity claim LEFT here instead of failing by chance. It
  -- wasn't lost: the offline suite measures the EXACT magnitude of each level, with
  -- an absolute ceiling, and there the number is the matrix's scale, not counted pixels.
  --
  -- What this gate asserts, and holds: each level produces movement on screen, and
  -- the baseline is silent. Presence is the negative control, not size.
  local semEfeito = {}
  for _, med in ipairs(medidas) do
    if med.px <= base then semEfeito[#semEfeito + 1] = med.nome end
  end
  veredito("V3", #semEfeito == 0, string.format(
    "SUBTLE %d, NORMAL %d, STRONG %d contra base %d; niveis sem efeito: [%s]",
    medidas[1] and medidas[1].px or -1, medidas[2] and medidas[2].px or -1,
    medidas[3] and medidas[3].px or -1, base, table.concat(semEfeito, ", ")))

  -- ---------------------------------------------------------------- V4
  -- Without solid there is nothing to breathe: the mod returns the host's original card and
  -- the draw wrap doesn't recognize the mesh as ours. If pixels still changed,
  -- the change would come from somewhere else and the three measurements above wouldn't hold.
  opcao("depth", "off")
  espera(40)
  local semSolido, ts = parDeQuadros()
  nota("VOXEL CHARS OFF com BREATH STRONG: %d pixels diferentes (%d tentativas)",
    semSolido, ts)
  veredito("V4", semSolido >= 0 and semSolido < PARADO,
    "sem solido, BREATH nao pode mexer em nada")

  -- ---------------------------------------------------------------- V5
  -- SWAY is an idle oscillation, like breathing: scene still, screen changes,
  -- and more strength changes more.
  opcao("depth", 3); opcao("breath", "off")
  espera(40)
  local balanco = {}
  for _, nivel in ipairs({ { "SUBTLE", 0.20 }, { "NORMAL", 0.45 } }) do
    opcao("sway", nivel[2])
    espera(30)
    local n, ts2 = parDeQuadros()
    balanco[#balanco + 1] = n
    nota("SWAY %-6s (%.2f): envelope de %d pixels (%d tentativas)",
      nivel[1], nivel[2], n, ts2)
  end
  -- Same reason as V3: presence, not order. The order between levels is proven in the
  -- offline suite, where the number is the matrix's scale.
  veredito("V5", balanco[1] and balanco[2]
    and balanco[1] > base and balanco[2] > base, string.format(
    "SUBTLE %d e NORMAL %d, os dois acima da base %d",
    balanco[1] or -1, balanco[2] or -1, base))

  -- ---------------------------------------------------------------- V6
  -- MOTION LAG cannot appear with the character STILL for a long time: the
  -- spring is at rest and the target is zero. If it appeared, the effect would be
  -- coming from somewhere else (or the spring would be oscillating on its own, which is the classic
  -- failure mode of an underdamped spring).
  opcao("sway", "off"); opcao("lag", 1.2)
  espera(90)  -- plenty of time for the spring to settle
  local lagParado, tl = parDeQuadros()
  nota("MOTION LAG NORMAL com todo mundo parado: %d pixels (%d tentativas)",
    lagParado, tl)
  veredito("V6", lagParado >= 0 and lagParado < PARADO,
    "com ninguem se movendo, a mola tem que estar em repouso")

  -- ---------------------------------------------------------------- V7
  -- And it has to appear AFTER a step. The exact same sequence run with
  -- LAG off and on: same map, same starting cell, same number
  -- of frames. The player ends up in the same cell with the same sprite frame
  -- in both, so the only possible difference between the two photos is the delay.
  -- THE ROOM IS SMALL AND HAS FURNITURE. The first version sent "down" from a
  -- spot where the bed blocks: the player didn't move, velocity zero,
  -- delay zero, and both photos came out IDENTICAL. Zero pixels of difference
  -- looked like "the feature does nothing" and was "the test didn't move". So: find
  -- a direction that actually moves first, and only then measure.
  -- THE SEQUENCE EMPTIES THE ROOM AGAIN AFTER EVERY TELEPORT, because setMap
  -- rebuilds entities/npcs from the map definition and a mod's runtime object
  -- is in that definition: whoever was taken out at the top of the run walks
  -- back in on the next teleport, in a DIFFERENT cell, which is precisely the
  -- 908..1152 px floor this gate used to report.
  local PARTIDA_X, PARTIDA_Y = 3, 4
  function tentaPasso(dir)
    U.teleport(game, MAPA, PARTIDA_X, PARTIDA_Y, dir)
    espera(20)
    soOJogador()
    espera(30)
    local antes = game.overworld.player.cellY * 1000 + game.overworld.player.cellX
    U.hold(game, dir, 16)
    espera(6)
    local depois = game.overworld.player.cellY * 1000 + game.overworld.player.cellX
    return depois ~= antes, captura()
  end

  -- THE MARGIN FOR BOTH STEP CHECKS, AND IT IS A SHARE OF THE CHARACTER RATHER
  -- THAN A PIXEL COUNT.
  --
  -- V7 asked for 40 px over the floor and V10 for 20. Both numbers were taken
  -- at whatever camera rung the machine happened to hold, and the rung is now
  -- pinned at 3, where the character is smaller. Measured at rung 3, HD off,
  -- scene emptied, mask rebuilt at the step's end cell (CORPO = 356 samples):
  --
  --                floor    Mac Studio      render machine    smallest share
  --   MOTION LAG      0      88  91 146      149 151 149          24.7%
  --   FOOTFALL        0      24  24  24       22  22  22           6.0%
  --
  -- The floor is the same sequence with the option OFF on both sides, and it
  -- has measured 0 in every one of those six runs: an emptied room walked
  -- through twice is byte-identical. MOTION LAG's spread is real -- the spring
  -- is photographed wherever the step left it -- and it is why the bar is set
  -- off the SMALLEST value, not the average.
  --
  -- At the unpinned rung 4 the same MOTION LAG step measured 190. So V7's old
  -- 40 was BELOW the effect at rung 4 and ABOVE it at rung 3: the check was
  -- passing on one machine and failing on the other for the size of the
  -- character, not for the delay. That is the whole disagreement, and it is why
  -- the number could not simply be lowered until it passed.
  --
  -- 3.5% of the character is 12.5 samples here and 12.9 on the render machine,
  -- which is almost exactly HALF of FOOTFALL's 24 and 22 -- the conservatism
  -- V10's 20 was chosen to carry ("roughly half the real effect"), restored
  -- after the rung shrank the character. Expressed against CORPO it survives
  -- the next rung change, the next screen size and the next sheet resolution,
  -- all three of which have re-scaled these numbers before. A broken feature
  -- measures exactly the floor, because on-against-off collapses to
  -- off-against-off, so the gate separates 0 from 22..24 with the bar at 12.5.
  local FRACAO_PASSO = 0.035
  local function margemPasso()
    return math.max(8, (CORPO or 0) * FRACAO_PASSO)
  end

  opcao("lag", "off"); espera(20)
  local semLag
  for _, dir in ipairs({ "down", "left", "right", "up" }) do
    local andou, foto = tentaPasso(dir)
    if andou then direcao, semLag = dir, foto; break end
  end
  if not direcao then
    veredito("V7", false,
      "o jogador nao conseguiu andar em nenhuma direcao; o teste nao vale")
  else
    nota("direcao que move a partir de (%d,%d): %s", PARTIDA_X, PARTIDA_Y, direcao)
    -- THE MASK IS REBUILT HERE, at the cell the walk ENDS on. The one built at
    -- the landing cell is around the wrong pixels now: the player has moved.
    -- Everything is already pinned still, so the rebuild only costs four
    -- photographs.
    if not fazMascara() then
      nota("WARNING: could not rebuild the mask at the end of the step")
    end
    -- FLOOR: the SAME sequence, the SAME option (LAG off) on both sides. Two
    -- independent runs don't land on the same animated-tile phase or NPC
    -- turning between them; this measures how much time passing ALONE changes, so that
    -- the comparison with LAG on below doesn't confuse this with the effect.
    local _, semLag2 = tentaPasso(direcao)
    local piso = difere(semLag, semLag2)
    opcao("lag", 1.2); espera(20)
    local andou, comLag = tentaPasso(direcao)
    local dLag = andou and difere(semLag, comLag) or -1
    nota("floor (LAG off on both sides): %d pixels; one step to %s, with and without MOTION LAG: %d pixels diferentes (character %d samples, bar %.1f)",
      piso, direcao, dLag, CORPO or -1, margemPasso())
    veredito("V7", piso >= 0 and dLag > piso + margemPasso(),
      "o atraso tem que superar o piso de ruido entre duas corridas identicas")
  end

  -- ---------------------------------------------------------------- V9
  -- FOOTFALL only exists while WALKING, and has to vanish on its own when the character
  -- stops. Same pair of checks as MOTION LAG, for the same reason: alone, one
  -- of them would pass for a dead feature and the other for a feature that oscillates on its own.
  opcao("breath", "off"); opcao("sway", "off"); opcao("lag", "off")
  opcao("footfall", 0.7)
  espera(90)
  local pisadaParado = parDeQuadros()
  nota("FOOTFALL NORMAL com todo mundo parado: %d pixels", pisadaParado)
  veredito("V9", pisadaParado >= 0 and pisadaParado < PARADO,
    "parado, a pisada nao pode achatar ninguem")

  -- ---------------------------------------------------------------- V10
  do
    -- reuses the same deterministic sequence from V7: same starting
    -- cell, same number of frames, only the option changes.
    opcao("footfall", "off"); espera(20)
    local andou1, a = tentaPasso(direcao or "left")
    -- FLOOR: same reason as V7. FOOTFALL off on both sides, same sequence,
    -- measures what only the passage of time changes between two runs.
    local andou1b, a2 = tentaPasso(direcao or "left")
    local piso = (andou1 and andou1b) and difere(a, a2) or -1
    opcao("footfall", 0.7); espera(20)
    local andou2, b = tentaPasso(direcao or "left")
    local d = (andou1 and andou2) and difere(a, b) or -1
    nota("floor (FOOTFALL off on both sides): %d pixels; one step, with and without FOOTFALL: %d pixels diferentes (character %d samples, bar %.1f)",
      piso, d, CORPO or -1, margemPasso())
    -- THE MARGIN IS 20, AND IT WAS 40. 40 came from a number that was more than
    -- half defect, and the defect has since been fixed.
    --
    -- Before 7d299ee, `rowsForUv` copied each eye quad's POSITION while the quad
    -- was emitted -- which is before `escalaParaTile` divides every vertex by
    -- the HD factor -- and the first `applyBlinkUv` wrote those copies straight
    -- back into the mesh. On a 64 px sheet they were four times too large, so
    -- the two eye quads landed far outside the cell, above and beside the head:
    -- "uns dois quadrados acima do personagem", as Kim reported it. They are
    -- geometry like any other, so FOOTFALL's squash moved them along with the
    -- body, and this check counted them as part of the step.
    --
    -- Measured on one machine, one map, one camera rung, one step with and
    -- without FOOTFALL, over the floor of 0 that every run of this check has
    -- reported:
    --
    --   before the fix, HD SPRITE on     85 px, of which 48 fall inside the
    --                                    footprint of the two stray quads (the
    --                                    region that differs between the two
    --                                    builds with FOOTFALL OFF) and 37
    --                                    outside it
    --   after the fix,  HD SPRITE on     37 px, none of them in that footprint
    --   before AND after, HD SPRITE off  46 px, the same on both builds
    --
    -- Those two sets of 37 are the SAME 37 pixels, point for point, at the same
    -- sampled coordinates: what FOOTFALL reaches on screen did not move at all,
    -- and the 48 that vanished were never it.
    --
    -- The last row is what settles it. Outside HD the fix changed nothing, so
    -- FOOTFALL did not lose anything: 85 was never FOOTFALL's effect, and a
    -- threshold taken from it was asking the step to be twice the size it is.
    -- Whoever reads this after a red V10 should look for a number BELOW 37
    -- before suspecting the step: 37 and 46 are what the feature measures.
    --
    -- 20 keeps the conservatism the 40 was meant to carry -- roughly half the
    -- real effect, at either resolution -- against a floor that has measured 0
    -- in every run, on both builds and at both resolutions.
    --
    -- AND 20 IS NOW `margemPasso()`, WHICH IS 12.5 AT THIS RUNG. Everything
    -- above was measured at the unpinned rung, where the character is bigger:
    -- 37 and 46 px of FOOTFALL. Pinned at rung 3, with every option pinned and
    -- the room emptied, the same step measures 24 here and 22 on the render
    -- machine, so 20 had gone from "roughly half the effect" to nine tenths of
    -- it, which is not a margin. Expressing the bar as a share of the character
    -- (see `FRACAO_PASSO`) keeps the intent through the next change of rung,
    -- resolution or sheet, all three of which have re-scaled this number
    -- before. Whoever reads this after a red V10 should still look for a number
    -- BELOW the effect before suspecting the step: 22 and 24 at rung 3, 37 and
    -- 46 at rung 4, are what the feature measures.
    veredito("V10", piso >= 0 and d > piso + margemPasso(),
      "a pisada tem que superar o piso de ruido entre duas corridas identicas")
    opcao("footfall", "off"); espera(10)
  end

  -- ---------------------------------------------------------------- V8
  -- COST. The wrap runs once per character per draw, and in a full city
  -- that's fifty times per frame. The number that matters isn't "it's fast",
  -- it's "how much of the 16.7 ms budget it eats up".
  --
  -- TWO TRAPS, both already paid for in this project:
  --
  -- 1. vsync. With it on, every frame costs 16.67 ms no matter what, and the
  --    benchmark measures the monitor. Turned off above.
  -- 2. WARM-UP. The first version measured 11.45 ms off and 4.35 ms
  --    on: turning the feature on made the game 2.6 times FASTER, which is
  --    impossible. What was being measured was the mod building the city's 25
  --    meshes on the first pass, all of it landing on whichever condition ran
  --    first. An absurd number is the instrument talking, not the code.
  --
  -- Fixed with warm-up beforehand and A/B/A/B afterward: if the difference were
  -- warm-up drift, it would vanish in the second pair.
  do
    -- POSITIVE CONTROL, MEASURED IN THE EMPTY ROOM, BEFORE GOING TO THE CITY.
    --
    -- The timing block below only times; if opcao() fails silently
    -- (WARNING in "nota", broken emit), liga() and desliga() end up identical and the
    -- measured cost comes out ~0, and "below the noise, not measurable" would pass for
    -- "the feature is cheap" when the real problem is that it never turned on.
    --
    -- The city does NOT work for this control: Viridian has NPCs walking and animated
    -- water, and a pair of OFF-against-OFF photos there gave 0 pixels in one window and
    -- 817 in the next, just from NPCs, the same instrument error V7 and V10
    -- had before the floor. So the control uses the ENVELOPE (same discipline
    -- as the rest of the file: only measures when the scene signature stays still) in the
    -- empty room that the rest of this driver already established, and only AFTER that
    -- does it teleport to the full city, where the per-frame cost is realistic.
    opcao("breath", "off"); opcao("sway", "off"); opcao("lag", "off")
    espera(30)
    local controleBase = parDeQuadros()
    opcao("breath", 0.020); opcao("sway", 0.45); opcao("lag", 1.2)
    espera(30)
    local controleLigado = parDeQuadros()
    local controleOk = controleBase >= 0 and controleLigado > controleBase + 40
    nota("positive control (empty room): envelope of %d OFF, %d on (%s)",
      controleBase, controleLigado, controleOk and "OK" or "FAILED")
    opcao("breath", "off"); opcao("sway", "off"); opcao("lag", "off")
    espera(20)

    -- THE CITY IS LEFT EXACTLY AS IT IS, crowd and all. `soOJogador` is never
    -- called here on purpose: the claim this block makes is "fifty characters
    -- per frame in a full town", and emptying it would measure an empty street
    -- and call it a city. The measurement is a frame time, not a pixel count,
    -- so a walking NPC costs it nothing in correctness -- which is exactly why
    -- the positive control above runs in the quiet room instead.
    U.teleport(game, "VIRIDIAN_CITY", 17, 17, "down")
    U.wait(60)
    local function mede(quadros)
      local soma, n = 0, 0
      for _ = 1, quadros do
        coroutine.yield()
        local dt = love.timer.getDelta()
        if dt > 0 and dt < 0.2 then soma = soma + dt; n = n + 1 end
      end
      return n > 0 and (soma / n * 1000) or -1
    end
    local function desliga()
      opcao("breath", "off"); opcao("sway", "off"); opcao("lag", "off")
      U.wait(30)
    end
    local function liga()
      opcao("breath", 0.020); opcao("sway", 0.45); opcao("lag", 1.2)
      U.wait(30)
    end
    -- Warm-up: builds the mesh, loads the texture, lets the LRU settle.
    liga(); mede(300); desliga(); mede(300)

    local off1 = mede(240); liga()
    local on1 = mede(240); desliga()
    local off2 = mede(240); liga()
    local on2 = mede(240); desliga()
    local off = (off1 + off2) / 2
    local on = (on1 + on2) / 2
    nota("cost per frame in town, A/B/A/B after warming up:")
    nota("  desligado  %.3f e %.3f ms   media %.3f", off1, off2, off)
    nota("  ligado     %.3f e %.3f ms   media %.3f", on1, on2, on)
    nota("  diferenca  %.3f ms de 16.7 ms de orcamento (%.1f%%)",
      on - off, (on - off) / 16.7 * 100)
    -- HOW TO READ THIS. The measurement's noise floor is the variation between two readings
    -- of the SAME condition. If the difference between on and off is smaller than
    -- that floor, the cost isn't "small": it's NOT MEASURABLE with this ruler, and the
    -- sign of the difference becomes a coin flip. Requiring the two pairs to agree
    -- on the sign would be requiring the noise to behave, and would fail exactly the
    -- best possible result.
    local ruido = math.max(math.abs(off1 - off2), math.abs(on1 - on2))
    local diferenca = math.abs(on - off)
    nota("  noise floor of the ruler: %.3f ms", ruido)
    -- The criterion IS the noise floor, with an absolute ceiling only as a safety net: the
    -- previous version failed with 0.503 ms against a floor of 0.577 and printed
    -- "below the noise" on the same line, because the condition was a fixed limit of
    -- 0.5 that had nothing to do with the message. A verdict that contradicts its
    -- own text is worse than no verdict at all.
    local aceitavel = diferenca < ruido or diferenca < 0.5
    -- THE ABSOLUTE CEILING BECAME A VALIDITY CHECK ON THE FLOOR, and the change came from
    -- a failure that contradicted its own message: difference 2.557 ms,
    -- floor 7.800 ms, text saying "below the noise, the cost is not measurable"
    -- and verdict FAILED, because a fixed ceiling of 1.5 ms tripped below the
    -- floor criterion. Two criteria that can disagree, and the printed line
    -- only spoke about one.
    --
    -- A floor of 7.8 ms in a 16.7 budget is not a mod defect, it's a busy machine:
    -- in this case I had LOVE and ssh running alongside. With this much noise the
    -- measurement has no POWER, and failing it would mean blaming the code for the environment,
    -- while passing it would mean claiming it measured. So the ceiling now asks whether the
    -- floor is any good, and the message says which of the two spoke.
    local pisoUtil = ruido < 3.0
    if not pisoUtil then
      nota("  a floor of %.3f ms is too high: busy machine, the measurement loses "
           .. "poder. Rode de novo com a maquina quieta.", ruido)
    end
    veredito("V8", controleOk and off > 0 and on > 0 and aceitavel and pisoUtil,
      string.format("controle positivo %s (envelope OFF %d, ligado %d); diferenca %.3f ms contra piso de ruido %.3f ms: %s",
        controleOk and "OK" or "FAILED", controleBase, controleLigado, diferenca, ruido, diferenca < ruido
          and "abaixo do ruido, o custo nao e mensuravel aqui"
          or "acima do ruido, e um custo real"))
  end

  -- Photos for Kim to judge by eye, since a number doesn't say whether it's any good.
  opcao("depth", 3); opcao("breath", 0.020); U.wait(40)
  love.graphics.captureScreenshot("vc_life_a.png"); U.wait(8)
  U.wait(46)
  love.graphics.captureScreenshot("vc_life_b.png"); U.wait(8)

  nota("")
  local todos = true
  for _, v in ipairs(vereditos) do
    if not v.ok then todos = false end
    nota("%-3s %s", v.nome, v.ok and "PASSED" or "FAILED")
  end
  nota("VERDICT: %s", todos and "A RESPIRACAO CHEGA NA TELA" or "LER ACIMA")

  -- PUT THE MACHINE BACK. The rung first, because the option restore below
  -- emits events that make the mod rebuild its meshes and it should rebuild
  -- them for the camera the player left behind, not for ours. Nothing here ever
  -- called Pipelines.syncOptions, so save.options.pipelines was never written
  -- and this only undoes the live ladder.
  Pipelines.setLevel("voxel", rungAntes)
  local restauradas = 0
  for k, v in pairs(opcoesAntes) do
    opcao(k, v); restauradas = restauradas + 1
  end
  for _, k in ipairs(ausentes) do opcao(k, nil) end
  nota("put back: camera rung %s, %d mod option(s), %d key(s) this machine did "
    .. "not have removed again; %d stranger(s) were taken out of the scene "
    .. "during the run", tostring(rungAntes), restauradas, #ausentes, retirados)
  -- The two lines that used to sit here -- BREATH off, BLINK on -- were this
  -- driver's idea of a tidy end state, and they are gone: the restore above
  -- already puts back whatever the player had, which is the only end state that
  -- makes two runs of this gate the same experiment.
  U.wait(10)
end
