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
    nota("%-3s %s  %s", nome, ok and "PASSOU" or "FALHOU", detalhe or "")
  end
  local function fim()
    nota("")
    local todos = true
    for _, v in ipairs(vereditos) do
      nota("%-3s %s", v.nome, v.ok and "PASSOU" or "FALHOU")
      todos = todos and v.ok
    end
    nota("VEREDITO: %s", todos
      and "O GRID PINTA O MUNDO E NAO PINTA GENTE, COMO O HOST QUER"
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

  local HOSTS = { "BATTLE_ART_VOXEL_FORK", "DRAMALESS_SHAPE", "DRAMATIC_SHAPE" }
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

  local Pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")
  local MAPA = os.getenv("VC_MAP") or "REDS_HOUSE_2F"
  local _, PX, PY = Pouso.escolher(game, MAPA, 3, 4)
  U.teleport(game, MAPA, PX, PY, "down")
  U.wait(60)
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

  -- With the MOD ON: how much the grid changes the screen.
  opcao("depth", 3)
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
  local folga = math.max(200, dSemMod * 0.02)
  veredito("G3", math.abs(dMod - dSemMod) <= folga,
    string.format("o grid nao encosta no nosso solido: %d com o mod contra %d "
      .. "sem, folga %d", dMod, dSemMod, math.floor(folga)))

  grid(false)
  fim()
end
