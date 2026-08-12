-- HD SPRITE MUST NOT COST THE CHARACTER ITS COLOUR.
--
--   POKEPORT_VERSION=blue POKEPORT_DRIVER=mods/voxel_characters/tools/ingame/probe_hd.lua \
--     love .
--
-- WHY THIS EXISTS, and it is worth the whole paragraph because nothing else in
-- the battery could have caught it.
--
-- In voxel mode a character is NOT coloured by the screen-space shader the flat
-- game uses: the 3D canvas never runs through it. The host bakes the world
-- palette into the texture instead (VoxelScene: TerrainAtlas.forSprite). The
-- first HD SPRITE swapped that baked texture for a raw sheet read off disk --
-- and every sheet in this game is three greys, the colour living nowhere in the
-- file. So the character rendered in GREY beside NPCs that stayed in colour.
--
-- Every offline gate was green. The suite was green. The menu gate was green.
-- It took recording a clip and LOOKING at it, and then it still read like the
-- extra resolution had broken something deep in the engine, which it had not.
--
-- WHAT IT MEASURES. Colour, as the distance between a pixel's channels. Grey
-- has none by definition, whatever its brightness, so this is indifferent to
-- lighting, to the camera rung and to which map it stands on -- the three
-- things that made every brightness-based idea useless here.
--
-- THREE CHECKS, and the third is the one that stops an empty green:
--
--   H1 turning HD on CHANGED the screen. First, not last: everything below
--      reads the changed pixels, so an option that did nothing would leave the
--      other two measuring an empty set and passing for free;
--   H2 those changed pixels ARE the character, and they are in colour with HD
--      on -- which is the regression itself;
--   H3 they were in colour with HD off too. Without it H2 would pass on a
--      character that had no colour to begin with.
--
-- MEASURED OVER THE CHANGED PIXELS, NOT THE FRAME, and the first version of
-- this gate got that wrong and let the bug through its own mutation test. One
-- grey character costs 2.3% of a screen full of coloured scenery -- the signal
-- was real and the instrument was pointed at the wrong thing. Differencing the
-- two photos isolates the character with no idea where it is standing.
return function(game)
  local function log(f, ...) print("[hd] " .. string.format(f, ...)) end
  local U = dofile("tests/drivers/util.lua")
  local vereditos, todos = {}, true
  local function veredito(nome, ok, detalhe)
    if not ok then todos = false end
    vereditos[#vereditos + 1] = { nome = nome, ok = ok }
    log("%s  %s  %s", nome, ok and "PASSED" or "FAILED", detalhe or "")
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
    return game.mods and game.mods.events
      and pcall(game.mods.events.emit, game.mods.events, "mod.options_changed",
        { mod = "voxel_characters", key = chave, value = valor })
  end

  local function foto()
    local pronto
    love.graphics.captureScreenshot(function(d) pronto = d end)
    for _ = 1, 120 do coroutine.yield(); if pronto then return pronto end end
  end

  -- COLOUR IS THE DISTANCE BETWEEN A PIXEL'S CHANNELS. Grey has none by
  -- definition, whatever its brightness, so this is indifferent to lighting, to
  -- the camera rung and to which map it stands on -- the three things that made
  -- every brightness-based idea useless here.
  local function temCor(r, g, b)
    return math.max(r, g, b) - math.min(r, g, b) > 0.12
  end

  -- Walks both photos once and reports only about the pixels that DIFFER:
  -- how many there are, and how many carry colour on each side. Those pixels
  -- are the character, found without knowing where it stands.
  local function recorte(a, b)
    if not (a and b) then return 0, 0, 0 end
    local mudados, corA, corB = 0, 0, 0
    for y = 0, a:getHeight() - 1, 2 do
      for x = 0, a:getWidth() - 1, 2 do
        local r1, g1, b1 = a:getPixel(x, y)
        local r2, g2, b2 = b:getPixel(x, y)
        if math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2) > 0.05 then
          mudados = mudados + 1
          if temCor(r1, g1, b1) then corA = corA + 1 end
          if temCor(r2, g2, b2) then corB = corB + 1 end
        end
      end
    end
    return mudados, corA, corB
  end

  log("=== gate do HD SPRITE ===")
  local pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")
  local mapa, x, y = pouso.escolher(game,
    os.getenv("VC_MAP") or "OAKS_LAB",
    tonumber(os.getenv("VC_X")) or 5,
    tonumber(os.getenv("VC_Y")) or 10)
  U.teleport(game, mapa, x, y, "down")
  U.wait(60)
  if not (game.overworld and game.stack:top() == game.overworld) then
    veredito("H1", false, "nao cheguei ao mundo")
    return
  end

  opcao("hd_sprite", "off"); U.wait(30)
  local semHd = foto()
  opcao("hd_sprite", "on"); U.wait(30)
  local comHd = foto()

  local mudados, corSem, corCom = recorte(semHd, comHd)
  veredito("H1", mudados > 50, string.format(
    "ligar HD mudou %d pixels (sem isso, tudo abaixo mede o conjunto vazio)",
    mudados))

  -- SEVEN TENTHS, and the number is measured rather than picked. Running this
  -- against the fixed build and against the bug deliberately restored:
  --
  --   fixed   1016 coloured with HD on against  942 with HD off  -- 108%
  --   broken   437 coloured with HD on against 1038 with HD off  --  42%
  --
  -- The threshold sits in the gap. Half would also separate them, but only
  -- just, and it would sit closer to the failing side than the passing one.
  veredito("H2", corCom >= corSem * 0.7, string.format(
    "dos %d pixels que mudaram, %d tem cor com HD on contra %d com HD off. "
    .. "Em modo voxel a cor vive DENTRO da textura, entao trocar a folha sem "
    .. "assar a paleta deixa o personagem cinza", mudados, corCom, corSem))

  veredito("H3", corSem > 10, string.format(
    "com HD off esses mesmos pixels ja tinham cor (%d), senao H2 passaria "
    .. "sobre um personagem que nunca teve", corSem))

  opcao("hd_sprite", "off")
  log("")
  for _, v in ipairs(vereditos) do log("%-3s %s", v.nome, v.ok and "PASSED" or "FAILED") end
  log("VERDICT: %s", todos and "O HD MANTEM A COR" or "LER ACIMA")
  U.wait(10)
end
