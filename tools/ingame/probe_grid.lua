-- Probe for the host's GRID: do our characters get the wireframe?
--
-- Kim asked whether the mod should "behave in accordance" with the voxel
-- mod's grid. Before designing anything, the question is whether it isn't already solved.
--
-- Reading the host: the grid isn't an overlay drawn on top, it's the scene's
-- OWN shader measuring the fragment's distance to the nearest whole plane, in
-- MODEL space (VoxelGrid.lua:1-18). Every mesh drawn by Voxel3D.draw goes
-- through that shader, and ours does too. So the prediction is that the solid
-- already gets the wireframe for free, and that "support" would be zero code.
--
-- Prediction is not measurement. This measures.
--
--   G1 the state can be read   VoxelGrid.enabled() responds and set() changes it
--   G2 grid changes the screen control: turning the grid on has to change
--                              something, otherwise nothing below counts
--   G3 does NOT touch the character the grid's delta has to be the SAME with the mod
--                              on and off
--
-- G3 STATES THE OPPOSITE OF WHAT THIS FILE PREDICTED, and the reversal is the result.
--
-- The prediction was that the solid would get the wireframe for free, because
-- the grid is the scene's own shader measuring distance to the nearest whole
-- plane in model space, and our mesh goes through that shader. Measured: 54700
-- samples change with the mod on and 54701 with it off. The grid doesn't touch us.
--
-- The reason is written in the host, and it's a decision, not an oversight
-- (VoxelScene.lua:584-589, drawCast calls Voxel3D.seams(false)):
--
--   "Characters carry no wireframe out here, whatever the V-GRID row says. The
--    seams are what makes the WORLD read as built out of voxels, and the people
--    walking around in it are the one thing that should read as drawn instead
--    -- a grid over a 16x16 sprite lands a line every couple of display pixels
--    and turns a face into a mesh."
--
-- In other words: our mod already behaves correctly, by inheritance, and
-- "turning the grid on for characters" wouldn't be filling a gap, it would be
-- GOING AGAINST the host author on a point he thought through. It remains a
-- possible product option, with a declared cost: the solid's side and top
-- faces have no art at all, and seams over them would highlight exactly the invented surface.
--
-- So this gate stopped asking "does it already work?" and started protecting
-- the contract: if the wireframe ever starts appearing on the characters,
-- someone changed something and we want to know the same day..

return function(game)

  -- NOBODY IN THE ROOM BUT THE PLAYER, enforced instead of assumed.
  --
  -- This gate differences photographs of a room the ROM leaves empty. An
  -- INSTALL does not: a mod can put a real engine NPC on any map at runtime
  -- through the host's own OverworldState:addRuntimeObject, and
  -- overworld_wild_spawns does exactly that here. Measured 2026-08-13 in
  -- probe_walk, on this same map, by planting a wandering stranger one cell
  -- from the player: two photographs of the SAME pose with the SAME options
  -- went from 0 pixels apart to 639, which is most of a character, and the gate
  -- went red on a mod that was working.
  --
  -- So everyone who is not the player comes out of the three lists the host
  -- draws and updates from -- the same surgery the host performs on itself when
  -- a runtime object is dropped (OverworldController:2600, :3894). setMap
  -- rebuilds those lists, so it runs after every teleport, and `espera` repeats
  -- it every ten frames because a mod that adds its object back mid-run has to
  -- be caught mid-run.
  local retirados = 0
  local function soOJogador()
    local ow = game.overworld
    if not ow then return end
    local p = ow.player
    for _, lista in ipairs({ ow.entities or {}, ow.npcs or {}, ow.ghosts or {} }) do
      for i = #lista, 1, -1 do
        local e = lista[i]
        if (e.npc or e) ~= p then table.remove(lista, i); retirados = retirados + 1 end
      end
    end
  end
  local function espera(n)
    for i = 1, n do
      if i % 10 == 0 then soOJogador() end
      coroutine.yield()
    end
  end
  local U = dofile("tests/drivers/util.lua")
  dofile("mods/voxel_characters/tools/ingame/erro.lua")()
  io.stdout:setvbuf("line")
  if love.window and love.window.setVSync then pcall(love.window.setVSync, 0) end

  local linhas = {}
  local function nota(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    linhas[#linhas + 1] = ok and s or tostring(fmt)
    print("[grid] " .. linhas[#linhas])
    love.filesystem.write("vc_grid.txt", table.concat(linhas, "\n") .. "\n")
  end
  local vereditos = {}
  local function veredito(nome, ok, detalhe)
    vereditos[#vereditos + 1] = { nome = nome, ok = ok }
    nota("%-3s %s  %s", nome, ok and "PASSED" or "FAILED", detalhe or "")
  end
  local function fim()
    nota("")
    local todos = true
    for _, v in ipairs(vereditos) do
      nota("%-3s %s", v.nome, v.ok and "PASSED" or "FAILED")
      todos = todos and v.ok
    end
    nota("VERDICT: %s", todos
      and "O GRID PINTA O MUNDO; SO PINTA GENTE QUANDO V-GRID CHARS PEDE"
      or "AINDA NAO")
  end

  nota("=== sonda do grid ===")

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
    U.wait(12)
  end

  local function captura()
    local pronto
    love.graphics.captureScreenshot(function(img) pronto = img end)
    for _ = 1, 120 do
      coroutine.yield()
      if pronto then return pronto end
    end
    return nil
  end
  local function difere(a, b)
    if not (a and b) then return -1 end
    local n = 0
    for y = 0, a:getHeight() - 1, 3 do
      for x = 0, a:getWidth() - 1, 3 do
        local ar, ag, ab = a:getPixel(x, y)
        local br, bg, bb = b:getPixel(x, y)
        if math.abs(ar - br) + math.abs(ag - bg) + math.abs(ab - bb) > 0.02 then
          n = n + 1
        end
      end
    end
    return n
  end

  -- EVERY PIXEL, over the middle of the screen, for the V-GRID CHARS checks
  -- below -- and both halves of that sentence were paid for.
  --
  -- Every pixel, because one character is a small thing: the seam pass over
  -- the player measured 1267 pixels changed, which the stride-3 counter above
  -- reports as 151, close enough to nothing to be indistinguishable from a
  -- threshold chosen carelessly. Sampling that is right for "did the whole
  -- world change" is the wrong instrument for "did this one body change".
  --
  -- The middle of the screen, because the camera is centred on the player, so
  -- that is where the body is (measured: the change sat in a 63x59 box at
  -- 439,322 of a 1024x768 frame), and scanning a quarter of the frame at
  -- stride 1 costs about what the whole frame at stride 3 costs.
  local function difereCentro(a, b)
    if not (a and b) then return -1 end
    local w, h = a:getWidth(), a:getHeight()
    local x0, x1 = math.floor(w * 0.25), math.floor(w * 0.75) - 1
    local y0, y1 = math.floor(h * 0.25), math.floor(h * 0.75) - 1
    local n = 0
    for y = y0, y1 do
      for x = x0, x1 do
        local ar, ag, ab = a:getPixel(x, y)
        local br, bg, bb = b:getPixel(x, y)
        if math.abs(ar - br) + math.abs(ag - bg) + math.abs(ab - bb) > 0.02 then
          n = n + 1
        end
      end
    end
    return n
  end

  -- THE HOST THE MOD ITSELF ATTACHED TO COMES FIRST, and it has to, because
  -- V-GRID CHARS asks ITS VoxelGrid and no other. All four lineages ship a
  -- module by that name and each owns its own state, so a probe that picked a
  -- different one would set the grid on a host that is not drawing and then
  -- photograph a screen where nothing changed -- a red gate with a green mod,
  -- or worse, the reverse.
  --
  -- This is not hypothetical here: only `false` disables a mod
  -- (src/mods/Loader.lua:156), so every host merely absent from options.mods
  -- counts as ENABLED, and this machine's save has three of the four in that
  -- state while naming only one.
  local HOSTS = { "BATTLE_ART_VOXEL_FORK", "DRAMALESS_SHAPE", "DRAMATIC_SHAPE",
                  "TERRARIUM", "potato_voxel" }
  local anexado
  pcall(function()
    anexado = game.mods.exports.voxel_characters.hostReport().host
  end)
  if anexado then
    nota("the mod reports it attached to %s", tostring(anexado))
    table.insert(HOSTS, 1, anexado)
  else
    nota("the mod did not report a host; falling back to the known order")
  end
  local lib
  for _, id in ipairs(HOSTS) do
    for _, f in ipairs({
      function() return game.mods.exports[id].lib end,
      function() return game.mods:find(id).exports.lib end,
      function() return game.mods.find(id).exports.lib end,
    }) do
      local ok, v = pcall(f)
      if ok and type(v) == "table" and v.require then lib = v break end
    end
    if lib then break end
  end
  if not lib then veredito("G1", false, "sem lib do host"); return fim() end
  local okG, VoxelGrid = pcall(lib.require, "VoxelGrid")
  if not (okG and VoxelGrid and VoxelGrid.enabled) then
    veredito("G1", false, "host sem VoxelGrid")
    return fim()
  end

  -- ------------------------------- listening to the DECISION, not its result
  --
  -- G6 below needs something the camera cannot give it, and the reason is in
  -- the host's own note on Voxel3D.seams: with the world grid off, the plain
  -- scene shader is bound and it has no `gridDark` uniform compiled into it
  -- at all, so the send does not fail, it lands nowhere. A mod that stopped
  -- consulting the world grid and asked for seams unconditionally would
  -- therefore look IDENTICAL on screen -- measured: that mutation moves the
  -- same 1271 pixels with the grid on and the same 0 with it off, and passes
  -- a pixel gate untouched.
  --
  -- It would not be identical the day a host compiles that uniform into both
  -- variants, or the day one of the four lineages decides differently. So the
  -- check has to hear the mod ASK rather than watch the asking work.
  --
  -- Both functions are chained on top of whatever the mod already installed,
  -- so `dentroDoNosso` is true exactly for the dynamic extent of one of our
  -- character draws. The host calls seams(false)/seams(true) around its own
  -- cast loop every frame (VoxelScene drawCast) and those land outside that
  -- extent, which is what makes the count mean "ours" and not "any".
  local dentroDoNosso, pedidosDeCostura = false, 0
  local okChain = pcall(function()
    local Voxel3D = lib.require("Voxel3D")
    local seamsAntes = Voxel3D.seams
    local drawAntes = Voxel3D.draw
    assert(type(seamsAntes) == "function" and type(drawAntes) == "function")
    Voxel3D.seams = function(on)
      if dentroDoNosso and on then pedidosDeCostura = pedidosDeCostura + 1 end
      return seamsAntes(on)
    end
    Voxel3D.draw = function(mesh, texture, model, pull, sunModel)
      dentroDoNosso = true
      local ok, r = pcall(drawAntes, mesh, texture, model, pull, sunModel)
      dentroDoNosso = false
      if not ok then error(r, 0) end
      return r
    end
  end)
  if not okChain then
    nota("could not chain Voxel3D.seams/draw; G6 will not be measured")
  end

  local Pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")
  local MAPA = os.getenv("VC_MAP") or "REDS_HOUSE_2F"
  local _, PX, PY = Pouso.escolher(game, MAPA, 3, 4)
  U.teleport(game, MAPA, PX, PY, "down")
  U.wait(30)
  soOJogador()
  espera(30)
  nota("%d stranger(s) taken out of the scene", retirados)
  pcall(require("src.render.Pipelines").setLevel, "voxel", 4)
  U.wait(60)

  local function grid(v)
    pcall(VoxelGrid.set, v, game)
    U.wait(18)
    local ok, e = pcall(VoxelGrid.enabled)
    return ok and e
  end

  local ligou = grid(true)
  local desligou = grid(false)
  veredito("G1", ligou == true and desligou == false,
    string.format("o estado do grid responde: ligado=%s desligado=%s",
      tostring(ligou), tostring(desligou)))

  -- WHAT grid_chars WAS, so this probe hands the save back the way it found
  -- it. probe_grid is run straight by the battery, with no shell around it to
  -- back options.lua up the way hosts.sh does, and V-GRID CHARS is a row the
  -- player sets: leaving it wherever the last check happened to park it would
  -- be this gate editing a preference to measure it.
  local charsAntes
  pcall(function()
    charsAntes = game.mods.modOptions.voxel_characters.grid_chars
  end)

  -- HOLD THE CHARACTER STILL, for the same reason the strangers were taken
  -- out of the room above: every number below is a difference between two
  -- photographs, and anything that moves on its own between them is counted
  -- as evidence. BREATH ships on and BLINK ships on, so the player is never
  -- twice in the same pose -- measured here before this was fixed, flipping
  -- an option that provably did nothing still moved 81 samples, which is most
  -- of the way to the 200 the checks below need to be able to trust.
  --
  -- The five rows are the STILL preset's, minus the one being measured.
  local vidaAntes = {}
  for _, k in ipairs({ "breath", "sway", "lag", "footfall", "attention",
                       "blink" }) do
    pcall(function() vidaAntes[k] = game.mods.modOptions.voxel_characters[k] end)
    opcao(k, "off")
  end

  -- THE NOISE FLOOR, measured in this run rather than assumed. With the
  -- character held still it should be zero, and it is measured anyway: a
  -- floor that is asserted rather than read is a floor that silently stops
  -- being true.
  opcao("depth", 3)
  opcao("grid_chars", "off")
  grid(true)
  local ruidoA = captura()
  local ruidoB = captura()
  local ruido = difereCentro(ruidoA, ruidoB)
  nota("noise floor between two photographs of the same scene: %d pixels", ruido)

  -- With the MOD ON: how much the grid changes the screen.
  grid(false); local semGrid = captura()
  grid(true);  local comGrid = captura()
  local dMod = difere(semGrid, comGrid)

  -- With the MOD OFF: how much the grid changes the screen without our solid. The
  -- difference between the two numbers is the area the grid paints ON TOP OF WHAT
  -- WE DRAW. Without this second term, G3 would be measuring the scenery.
  opcao("depth", "off")
  grid(false); local semGridSemMod = captura()
  grid(true);  local comGridSemMod = captura()
  local dSemMod = difere(semGridSemMod, comGridSemMod)
  opcao("depth", 3)

  nota("grid muda %d amostras com o mod, %d sem o mod", dMod, dSemMod)
  veredito("G2", dMod > 200,
    string.format("o grid muda a tela: %d amostras", dMod))
  -- The host suppresses seams on characters on purpose (drawCast calls
  -- Voxel3D.seams(false)). So the correct behavior is for the two numbers to match: the grid
  -- paints the world and doesn't paint people, with or without our solid on screen.
  --
  -- MEASURED WITH V-GRID CHARS EXPLICITLY OFF since 1.8.2, and that word
  -- "explicitly" is the fix. This check used to inherit whatever the save
  -- said, and the save on the machine that runs the battery said "off", so it
  -- was green for a reason that had nothing to do with the contract it claims
  -- to protect: with the shipped default (ON) it was measuring the mod's own
  -- feature and calling it the host's rule. That is the same shape of hole
  -- 1.8.0 shipped through -- a gate that only ever saw one configuration.
  local folga = math.max(200, dSemMod * 0.02)
  veredito("G3", math.abs(dMod - dSemMod) <= folga,
    string.format("o grid nao encosta no nosso solido: %d com o mod contra %d "
      .. "sem, folga %d", dMod, dSemMod, math.floor(folga)))

  -- ------------------------------------------------- V-GRID CHARS, both ways
  --
  -- G3 above protects the HOST's rule. These two protect OURS, and they are
  -- the reason this file exists in this shape: Kim pressed 5, the world got
  -- the grid, the characters did not join it, and every gate in the project
  -- was green. Nothing measured the positive.
  --
  -- The contract V-GRID CHARS actually promises is two-sided, so it takes two
  -- checks. One of them alone is worth very little: a row wired to nothing
  -- passes G5, and a row that ignores the world grid passes G4.
  --
  --   G4  world grid ON  -> turning V-GRID CHARS on CHANGES the character
  --   G5  world grid OFF -> turning V-GRID CHARS on changes NOTHING
  --
  -- G5 is not a nicety. It is the whole "rides the world grid" decision from
  -- 1.7.x: with the grid off the host binds the plain scene shader, which has
  -- no seam uniform compiled into it at all (Voxel3D.beginScene, and the note
  -- on Voxel3D.seams says it in the host's own words). Asking for seams there
  -- does not fail, it silently does nothing -- so an implementation that
  -- forgot to consult the world grid would look identical from the outside
  -- except on the day the host starts answering.
  opcao("grid_chars", "on")
  grid(true); local comGridChars = captura()
  local dChars = difereCentro(comGrid, comGridChars)
  pedidosDeCostura = 0; U.wait(18)
  local pedidosComGrade = pedidosDeCostura
  grid(false); local semGridChars = captura()
  local dCharsSemGrid = difereCentro(semGrid, semGridChars)
  pedidosDeCostura = 0; U.wait(18)
  local pedidosSemGrade = pedidosDeCostura
  opcao("grid_chars", "off")

  -- WHERE THE BAR COMES FROM. Two terms, both measured in this same run --
  -- the floor doctrine run.sh already follows, because a threshold that does
  -- not come from a number measured beside it passes a neutralised mod by a
  -- hair on the day the scene gets quieter.
  --
  -- The constant term is 300 pixels and it is not a round number chosen to
  -- clear the measurement. The host's own note on Voxel3D.seams draws the
  -- line this check has to sit on: a mesh whose model space is one unit per
  -- voxel gets a wireframe, and a mesh whose model space is not "gets
  -- whichever of its integer planes happen to fall inside it, which is a
  -- stray line rather than a seam". A body that fills roughly 63x59 pixels
  -- here is about 3700 pixels of character; a couple of stray lines across it
  -- is under a hundred, and a wireframe is over a thousand (measured:
  -- 1267). 300 is inside that gap and near the bottom of it, so the check
  -- fails a stray line without demanding the seams stay exactly as dense as
  -- they were the day it was written.
  local pisoChars = math.max(300, ruido * 3)
  nota("V-GRID CHARS moves %d pixels with the world grid on, %d with it off "
    .. "(floor %d)", dChars, dCharsSemGrid, pisoChars)
  veredito("G4", dChars > pisoChars,
    string.format("com a grade do mundo ligada, V-GRID CHARS pinta o "
      .. "personagem: %d pixels contra piso %d", dChars, pisoChars))
  -- G5 IS THE WEAKER OF THE PAIR AND IT SAYS SO. On this host it can only
  -- ever read 0, because a seam asked for with the grid off lands nowhere
  -- (see the chain above). What it still guards is an implementation that
  -- painted seams by some route OTHER than the host's shader -- an overlay of
  -- our own, say -- which would show up here and nowhere else. G6 is the one
  -- that watches the decision.
  veredito("G5", dCharsSemGrid <= pisoChars,
    string.format("sem a grade do mundo, V-GRID CHARS nao inventa costura: "
      .. "%d pixels contra piso %d", dCharsSemGrid, pisoChars))

  if okChain then
    nota("our draw asked for seams %d times with the world grid on, %d times "
      .. "with it off", pedidosComGrade, pedidosSemGrade)
    veredito("G6", pedidosComGrade > 0 and pedidosSemGrade == 0,
      string.format("V-GRID CHARS so pede costura quando o mundo tem grade: "
        .. "%d pedidos com grade, %d sem", pedidosComGrade, pedidosSemGrade))
  end

  grid(false)
  if charsAntes ~= nil then opcao("grid_chars", charsAntes) end
  for k, v in pairs(vidaAntes) do opcao(k, v) end
  fim()
end
