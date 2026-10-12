-- BLINK ON A SHEET NO HAND TABLE KNOWS, measured in the running game.
--
--   POKEPORT_VERSION=blue POKEPORT_DRIVER=mods/voxel_characters/tools/ingame/probe_wilds.lua \
--     love .
--
-- WHY THIS EXISTS. Kim reported that this mod works well with Wilds of Kanto,
-- which puts wild Pokemon in the overworld, but that the blinking does not.
-- Nothing offline could have told him whether that was true of the real thing:
-- the suite's sheets are painted by the suite, and the ROM sheets all have a
-- hand-measured entry in EYE_MARKS. Only the game loads a Wilds of Kanto PNG
-- through the host's own ImageCache and hands it to our mesh builder.
--
-- WHAT IT MEASURES. The UVs of the mesh this mod builds, at two instants of the
-- blink clock: the moment that sheet's eye is closed, and the moment it is open.
-- `blinkClosedForBase` is a pure function of `love.timer.getTime()` and the
-- sheet's base name, so swapping the clock around a single `mesh()` call puts
-- the eye in a known state with no waiting and no sampling luck. If the UVs at
-- the two instants are the same, that sheet does not blink. That is the whole
-- instrument.
--
-- FOUR CHECKS, and the first two are what makes the other two mean anything:
--
--   W1 a Wilds of Kanto sheet exists and this mod builds a mesh out of it.
--      Without it every comparison below runs on nil and passes for free;
--   W2 with BLINK DETECT off, that mesh's UVs do NOT change between the two
--      instants. This is Kim's report, reproduced as a number: EYE_MARKS is
--      keyed by sheet base name and has no entry for `025-normal`;
--   W3 with BLINK DETECT on, they DO change. That is the feature;
--   W4 `red.png`, which HAS a hand entry, blinks to exactly the same UVs with
--      the option on as with it off. The hand table is the authority and the
--      detector must not touch a sheet it already covers;
--   W5 there was a Wilds of Kanto Pokemon in the world when the photo was
--      taken, so the picture is of the thing and not of an empty field.
return function(game)
  local linhas = {}
  local function nota(f, ...)
    local ok, s = pcall(string.format, f, ...)
    linhas[#linhas + 1] = ok and s or tostring(f)
    print("[wilds] " .. linhas[#linhas])
    pcall(love.filesystem.write, "vc_wilds.txt",
      table.concat(linhas, "\n") .. "\n")
  end
  local U = dofile("tests/drivers/util.lua")
  dofile("mods/voxel_characters/tools/ingame/erro.lua")()
  io.stdout:setvbuf("line")
  if love.window and love.window.setVSync then pcall(love.window.setVSync, 0) end

  local todos = true
  local function veredito(nome, ok, detalhe)
    if not ok then todos = false end
    nota("%-3s %s  %s", nome, ok and "PASSED" or "FAILED", detalhe or "")
  end

  local function opcao(modId, chave, valor)
    local o = game.save and game.save.options
    if o then
      o.modOptions = o.modOptions or {}
      o.modOptions[modId] = o.modOptions[modId] or {}
      o.modOptions[modId][chave] = valor
    end
    if game.mods and game.mods.modOptions then
      game.mods.modOptions[modId] = game.mods.modOptions[modId] or {}
      game.mods.modOptions[modId][chave] = valor
    end
    return game.mods and game.mods.events
      and pcall(game.mods.events.emit, game.mods.events, "mod.options_changed",
        { mod = modId, key = chave, value = valor })
  end

  -- The same hash the mod uses (main.lua, blinkTiming). Copied rather than
  -- imported because the mod exports no such function, and a driver that
  -- guessed the timing would be measuring its own guess.
  local function tempos(base)
    local h = 5381
    for i = 1, #base do h = (h * 33 + base:byte(i)) % 4294967296 end
    local period = 3 + (h % 3000) / 1000
    local phase = (math.floor(h / 3000) % 3000) / 1000
    -- Closed lasts 0.12 s from the start of the period; 0.01 is inside it and
    -- half a period is as far from it as this clock goes.
    return 0.01 - phase + period, period / 2 - phase + period
  end

  -- Every UV in the mesh, as one string. Comparing the whole set rather than
  -- hunting for the eye quad: a blink that moved any texel shows up here, and a
  -- sheet that does not blink produces two identical strings.
  local function assinatura(mesh)
    if not (mesh and mesh.getVertexCount and mesh.getVertex) then return nil end
    local okN, n = pcall(mesh.getVertexCount, mesh)
    if not (okN and n and n > 0) then return nil end
    local out = {}
    for i = 1, n do
      local ok, _, _, _, u, v = pcall(mesh.getVertex, mesh, i)
      out[#out + 1] = ok and string.format("%.5f,%.5f", u or 0, v or 0) or "?"
    end
    return table.concat(out, ";"), n
  end

  local function noInstante(t, fn)
    local antes = love.timer.getTime
    love.timer.getTime = function() return t end
    local ok, a, b = pcall(fn)
    love.timer.getTime = antes
    if not ok then return nil end
    return a, b
  end

  nota("=== BLINK DETECT over Wilds of Kanto ===")

  local HOSTS = { "BATTLE_ART_VOXEL_FORK", "DRAMALESS_SHAPE", "DRAMATIC_SHAPE",
                  "TERRARIUM", "potato_voxel" }
  local V
  for _, id in ipairs(HOSTS) do
    local exports = game.mods and game.mods.exports and game.mods.exports[id]
    if exports and exports.lib then V = exports.lib nota("host: %s", id) break end
  end
  if not V then
    veredito("W1", false, "no voxel mod exports a lib")
    return
  end
  local okS, SpriteBillboards = pcall(V.require, "SpriteBillboards")
  if not (okS and SpriteBillboards and SpriteBillboards.mesh) then
    veredito("W1", false, "V.require failed on SpriteBillboards")
    return
  end

  -- What the mesh builder actually resolved, read off its own upvalue. Without
  -- this the driver can only say that the screen did not change, not whether
  -- the option ever reached the code that reads it -- and those two look
  -- identical from outside. It earned its place twice on the first day: once on
  -- a missing cache key, and once on a stale `main.lua` in a tree shared with
  -- another session, where `blink_detect` read `nil` because the running mod
  -- had never heard of the option. Both read as "the feature does not work".
  local function estado()
    local wrapper = SpriteBillboards and SpriteBillboards.mesh
    if type(wrapper) ~= "function" then return "no wrapper" end
    local voxelMesh
    for i = 1, 30 do
      local nome, up = debug.getupvalue(wrapper, i)
      if nome == "voxelMesh" then voxelMesh = up break end
    end
    if type(voxelMesh) ~= "function" then return "no voxelMesh" end
    for i = 1, 60 do
      local nome, up = debug.getupvalue(voxelMesh, i)
      if nome == "optionState" and type(up) == "table" then
        return tostring(up.blink_detect)
      end
    end
    return "no optionState"
  end

  local pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")
  local mapa, x, y = pouso.escolher(game,
    os.getenv("VC_MAP") or "ROUTE_1",
    tonumber(os.getenv("VC_X")) or 5,
    tonumber(os.getenv("VC_Y")) or 10)
  U.teleport(game, mapa, x, y, "down")
  U.wait(60)

  local SHEET = os.getenv("VC_WILD_SHEET")
    or "mods/overworld_wild_spawns/assets/generated/followsprites_runtime/025-normal.png"
  local BASE = SHEET:match("([^/]+)%.png$") or "025-normal"
  local existe = love.filesystem.getInfo and love.filesystem.getInfo(SHEET)
  nota("sheet: %s  (present: %s)", SHEET, tostring(existe and true or false))

  local def = { image = SHEET, frames = 6, walker = true }
  local fechado, aberto = tempos(BASE)

  local function assinaturaEm(t, d)
    return noInstante(t, function()
      local mesh = SpriteBillboards.mesh(d, 0)
      return assinatura(mesh)
    end)
  end

  opcao("voxel_characters", "depth", 3)
  opcao("voxel_characters", "shape", "slab")
  opcao("voxel_characters", "blink", "on")
  opcao("voxel_characters", "blink_detect", "off")
  U.wait(10)

  local estadoAntes = estado()
  local semA, verts = assinaturaEm(fechado, def)
  local semB = assinaturaEm(aberto, def)
  veredito("W1", semA ~= nil and semB ~= nil and (verts or 0) > 0,
    string.format("the mod built a mesh from the Wilds of Kanto sheet: "
      .. "%s vertices", tostring(verts)))
  if not (semA and semB) then
    nota("VERDICT: READ ABOVE")
    return
  end

  veredito("W2", semA == semB,
    "with BLINK DETECT off this sheet does not blink: the UVs at the two "
    .. "instants of the clock are identical. EYE_MARKS is keyed by sheet base "
    .. "name and has no entry for " .. BASE .. " -- the defect Kim reported")

  opcao("voxel_characters", "blink_detect", "on")
  U.wait(10)
  nota("optionState.blink_detect: off-phase=%s on-phase=%s",
    tostring(estadoAntes), tostring(estado()))
  local comA, vertsCom = assinaturaEm(fechado, def)
  local comB = assinaturaEm(aberto, def)
  nota("vertices with the option off: %s | with it on: %s",
    tostring(verts), tostring(vertsCom))
  veredito("W3", comA ~= nil and comB ~= nil and comA ~= comB,
    "with BLINK DETECT on the UVs differ between the two instants: the eye "
    .. "was found in the sprite itself")

  -- W4: the hand table is untouched. `red.png` has EYE_MARKS {{6,7},{9,7}}.
  -- Asked of the engine's own sprite registry rather than written out as a
  -- path: the ROM-derived cache is not something a mod may name (modkit MK301),
  -- and this is how a real consumer would get the def anyway.
  local okReg, Sprites = pcall(require, "data.generated.sprites")
  local red = okReg and Sprites and Sprites.SPRITE_RED
  local defRed = red and { image = red.image, frames = red.frames }
  if not defRed then
    veredito("W4", false, "the engine's sprite registry has no SPRITE_RED")
    return
  end
  local redFechado, redAberto = tempos("red")
  opcao("voxel_characters", "blink_detect", "off")
  U.wait(10)
  local redSemA = assinaturaEm(redFechado, defRed)
  local redSemB = assinaturaEm(redAberto, defRed)
  opcao("voxel_characters", "blink_detect", "on")
  U.wait(10)
  local redComA = assinaturaEm(redFechado, defRed)
  local redComB = assinaturaEm(redAberto, defRed)
  local mediu = redSemA and redSemB and redComA and redComB
  veredito("W4",
    mediu and redSemA ~= redSemB and redSemA == redComA and redSemB == redComB,
    "red.png blinks with the option off and blinks to exactly the same UVs "
    .. "with it on: the hand-measured table is still the authority")

  -- THE PICTURE, which is the part a person can judge. Force Wilds of Kanto to
  -- put something on the grass, then WALK TO IT: the spawner places its mons
  -- across the whole encounter area, and the first run of this driver
  -- photographed an empty field twenty tiles from three Rattata.
  opcao("voxel_characters", "blink_detect", "on")
  opcao("overworld_wild_spawns", "force_test_spawn", true)
  U.wait(240)

  local function acharBicho()
    local ow = game.overworld
    local listas = { ow and ow.entities, ow and ow.npcs }
    for _, lista in ipairs(listas) do
      if type(lista) == "table" then
        for _, e in pairs(lista) do
          local id = type(e) == "table" and tostring(e.id or "") or ""
          if id:find("wilds_of_kanto_entity_", 1, true) then
            local ex = tonumber(e.x or e.cellX or e.tileX)
            local ey = tonumber(e.y or e.cellY or e.tileY)
            if ex and ey then return id, ex, ey end
          end
        end
      end
    end
  end

  local id, ex, ey = acharBicho()
  if id then
    nota("found %s at (%d, %d); walking there", id, ex, ey)
    local m2, x2, y2 = pouso.escolher(game, mapa, ex, ey + 2)
    U.teleport(game, m2, x2, y2, "up")
    U.wait(120)
  else
    nota("no Wilds of Kanto entity in the overworld list")
  end

  local pronto
  love.graphics.captureScreenshot(function(d) pronto = d end)
  for _ = 1, 180 do coroutine.yield() if pronto then break end end
  if pronto then
    pcall(pronto.encode, pronto, "png", "vc_wilds_detect_on.png")
    nota("photo: vc_wilds_detect_on.png")
  end
  veredito("W5", id ~= nil,
    "there was a Wilds of Kanto Pokemon in the world for the photo to show")
  opcao("voxel_characters", "blink_detect", "off")
  opcao("overworld_wild_spawns", "force_test_spawn", false)

  nota("VERDICT: %s", todos
    and "THE DETECTOR FINDS THE EYE ON AN UNMEASURED SHEET AND LEAVES THE "
        .. "HAND TABLE ALONE"
    or "READ ABOVE")
  U.wait(10)
end
