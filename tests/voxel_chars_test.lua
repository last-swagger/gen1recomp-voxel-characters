package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local function resetLoaded()
  package.loaded["src.render.Assets"] = nil
  package.loaded["src.mods.Semver"] = nil
end

local function fakeImage(pixels, w, h)
  return {
    getDimensions = function() return w, h end,
    getPixel = function(_, x, y)
      local a = pixels[y * w + x] or 0
      return 1, 1, 1, a
    end,
  }
end

local function fakeMesh(verts, map)
  return {
    verts = verts,
    map = map,
    released = false,
    setVertexMap = function(self, m) self.map = m end,
    setTexture = function(self, tex) self.texture = tex end,
    release = function(self) self.released = true end,
  }
end

local function makeVoxelHandle(version, pixels, w, h, angle, spriteLean)
  local modules = {}
  local V = {}
  local original = function(def, frame)
    return { original = true, def = def, frame = frame }
  end
  function V.require(name)
    if modules[name] then return modules[name] end
    if name == "Voxel3D" then
      modules[name] = {
        created = 0,
        FORMAT = {
          { "VertexPosition", "float", 3 },
          { "VertexTexCoord", "float", 2 },
          { "VertexShade", "float", 1 },
        },
        pushQuad = function(map, n)
          local b = n * 4
          map[#map + 1], map[#map + 2], map[#map + 3] = b + 1, b + 2, b + 3
          map[#map + 4], map[#map + 5], map[#map + 6] = b + 1, b + 3, b + 4
        end,
        newMesh = function(verts, map)
          if #verts == 0 then return nil end
          modules[name].created = modules[name].created + 1
          return fakeMesh(verts, map)
        end,
      }
    elseif name == "ImageCache" then
      modules[name] = { get = function() return fakeImage(pixels, w, h) end }
    elseif name == "SpriteBillboards" then
      modules[name] = { mesh = original, shadowQuad = original }
    elseif name == "VoxelState" then
      modules[name] = { angle = angle or math.pi / 2 }
    elseif name == "VoxelScene" then
      modules[name] = { spriteLean = spriteLean }
    elseif name == "FirstPerson" then
      modules[name] = { cardBlend = function() return 0 end }
    else
      error("unexpected module " .. tostring(name))
    end
    return modules[name]
  end
  return { id = "DRAMATIC_SHAPE", version = version, exports = { lib = V } }, modules, original
end

local function makeMod(handle, stored)
  local schema, rows, events = nil, {}, {}
  local logs = { info = {}, warn = {}, error = {} }
  local function record(level)
    return function(_, fmt, ...)
      logs[level][#logs[level] + 1] = tostring(fmt):format(...)
    end
  end
  local mod = {
    id = "voxel_characters",
    version = "1.0.0",
    path = "mods/voxel_characters",
    options = {},
    hooks = {},
    events = {},
    log = { info = record("info"), warn = record("warn"), error = record("error") },
  }
  function mod.options:define(s) schema = s end
  function mod.options:get(key)
    if stored and stored[key] ~= nil then return stored[key] end
    for _, row in ipairs(schema or {}) do
      if row.key == key then return row.default end
    end
  end
  function mod.hooks:wrap(name, fn)
    rows[name] = fn
  end
  function mod.events:on(name, fn)
    events[name] = fn
  end
  function mod.find(id)
    if id == "DRAMATIC_SHAPE" then return handle end
  end
  mod._rows, mod._events, mod._logs = rows, events, logs
  return mod
end

local function loadWith(mod)
  resetLoaded()
  local chunk = assert(loadfile("mods/voxel_characters/main.lua"))
  chunk(mod)
  return mod
end

do
  local pixels = {}
  pixels[0] = 1
  local handle, modules, original = makeVoxelHandle("2.0.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle))
  local SpriteBillboards = handle.exports.lib.require("SpriteBillboards")
  eq(SpriteBillboards.mesh, original, "versao fora da faixa preserva original")
  eq(mod._rows["ui.options.rows"], nil, "row nao aparece sem patch suportado")
end

do
  local mod = loadWith(makeMod(nil))
  eq(mod._rows["ui.options.rows"], nil, "row nao aparece sem Dramatic Shape")
end

do
  local pixels = {}
  pixels[0] = 1
  local handle, modules, original = makeVoxelHandle("1.6.0", pixels, 16, 16)
  loadWith(makeMod(handle, { depth = "off" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  check(got and got.original, "OFF chama a funcao original")
  eq(got.frame, 0, "OFF preserva o frame pedido")
  check(original ~= modules.SpriteBillboards.mesh, "OFF ainda passa pelo wrapper instalado")
end

do
  local pixels = {}
  pixels[0] = 1
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle, { depth = 10 }))
  local emitted, writes = {}, 0
  local game = {
    save = { options = {} },
    mods = {
      modOptions = {},
      events = {
        emit = function(_, name, payload)
          emitted[#emitted + 1] = { name = name, payload = payload }
          if mod._events[name] then mod._events[name](payload) end
        end,
      },
    },
    writeOptions = function() writes = writes + 1 end,
  }
  local rows = { { id = "base" } }
  local out = mod._rows["ui.options.rows"](function(g, r)
    eq(g, game, "hook repassa game ao next")
    eq(r, rows, "hook repassa rows ao next")
    return r
  end, game, rows)
  eq(out, rows, "hook devolve a tabela do next")
  eq(#rows, 2, "hook anexa a row do voxel characters")
  local option = rows[2]
  eq(option.value(), "10", "row mostra o label atual")
  check(option.step(game, 1), "step informa mudanca ao OptionsMenu")
  eq(game.save.options.modOptions.voxel_characters.depth, "off",
     "step persiste no save com wraparound")
  eq(game.mods.modOptions.voxel_characters.depth, "off",
     "step persiste no loader com wraparound")
  eq(option.value(), "OFF", "value reflete o label apos step")
  eq(writes, 0, "step deixa OptionsMenu gravar options.lua uma vez")
  eq(#emitted, 1, "step emite mod.options_changed")
  eq(emitted[1].name, "mod.options_changed", "evento usa o nome canonico")
  eq(emitted[1].payload.value, "off", "evento carrega o valor novo")
  local other = mod._rows["ui.options.rows"](function() return "vanilla" end, game, {})
  eq(other, "vanilla", "hook preserva retorno nao tabela do next")
end

do
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle, { depth = 1 }))
  local def = { image = "sheet.png", frames = 1 }
  local a = modules.SpriteBillboards.mesh(def, 0)
  mod._events["mod.options_changed"]({ mod = mod.id, key = "depth", value = 5 })
  local b = modules.SpriteBillboards.mesh(def, 0)
  check(a ~= b, "options_changed troca a malha em cache proprio")
  local minZ = 0
  for _, v in ipairs(b.verts) do
    if v[3] < minZ then minZ = v[3] end
  end
  check(math.abs(minZ + 5) < 0.0001, "options_changed aplica o novo depth")
end

do
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16)
  loadWith(makeMod(handle, { depth = 2 }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  check(got and not got.original, "profundidade 2 devolve malha")
  check(type(got.verts[1]) == "table" and #got.verts[1] == 6,
        "vertice tem seis componentes")
end

do
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 96)
  loadWith(makeMod(handle, { depth = 2 }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 6,
                                              frameHeight = 16 }, 5)
  check(got and not got.original, "frameHeight sozinho cai no layout vertical")
end

do
  local pixels = {}
  pixels[0] = 1
  pixels[1] = 0
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16)
  loadWith(makeMod(handle, { depth = 2 }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local transparentU = (1 + 0.5) / 16
  local foundTransparentUv = false
  for _, v in ipairs(got.verts) do
    if math.abs(v[4] - transparentU) < 0.0001 then foundTransparentUv = true end
  end
  check(not foundTransparentUv, "pixel totalmente transparente nao gera quad")
end

do
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16, math.rad(75))
  loadWith(makeMod(handle, { depth = 2 }))
  local def = { image = "sheet.png", frames = 1 }
  local a = modules.SpriteBillboards.mesh(def, 0)
  modules.VoxelState.angle = math.rad(50)
  local b = modules.SpriteBillboards.mesh(def, 0)
  check(a ~= b, "mudanca de pitch reconstrói a malha em chave propria")
end

do
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
                                          math.rad(30), math.rad(75))
  loadWith(makeMod(handle, { depth = 2 }))
  local def = { image = "sheet.png", frames = 1 }
  local a = modules.SpriteBillboards.mesh(def, 0)
  modules.VoxelState.angle = math.rad(10)
  local b = modules.SpriteBillboards.mesh(def, 0)
  eq(a, b, "spriteLean tem precedencia sobre VoxelState.angle")
  modules.VoxelScene.spriteLean = math.rad(50)
  local c = modules.SpriteBillboards.mesh(def, 0)
  check(c ~= a, "mudanca de spriteLean reconstrói a malha")
end

do
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16, math.rad(75))
  loadWith(makeMod(handle, { depth = 2 }))
  local def = { image = "sheet.png", frames = 1 }
  local a = modules.SpriteBillboards.mesh(def, 0)
  modules.VoxelState.angle = math.rad(74.8)
  local b = modules.SpriteBillboards.mesh(def, 0)
  eq(a, b, "pitches dentro do bucket de 1 grau compartilham cache")
  eq(modules.Voxel3D.created, 1, "dois pitches proximos criam uma entrada")
end

do
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 4, 2)
  loadWith(makeMod(handle, { depth = 2 }))
  local a = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 2,
                                            columns = 1 }, 0)
  local b = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 2,
                                            columns = 2 }, 0)
  check(a ~= b, "layouts com columns diferente nao compartilham malha")
  eq(modules.Voxel3D.created, 2, "layout entra na chave do cache")
end

do
  local pixels = {}
  pixels[0] = 1
  local handle, modules, original = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local sprite = handle.exports.lib.require("SpriteBillboards")
  local prior = function(def, frame) return original(def, frame) end
  sprite.mesh = prior
  local mod = loadWith(makeMod(handle, { depth = 2 }))
  eq(sprite.__voxelCharactersOriginal, prior, "patch encadeia sobre wrapper anterior")
  check(mod._logs.warn[1]
        and mod._logs.warn[1]:find("already patched", 1, true),
        "patch avisa quando encadeia sobre outro wrapper")
end

do
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16, math.rad(75))
  loadWith(makeMod(handle, { depth = 2 }))
  local first = modules.SpriteBillboards.mesh({ image = "sheet-001.png",
                                                frames = 1 }, 0)
  for i = 2, 65 do
    modules.SpriteBillboards.mesh({ image = ("sheet-%03d.png"):format(i),
                                    frames = 1 }, 0)
  end
  check(first.released, "LRU solta a malha mais antiga ao passar de 64 entradas")
end

do
  local pixels = {}
  local w, h = 2, 4
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, w, h)
  loadWith(makeMod(handle, { depth = 2 }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 2 }, 9)
  local inFirstFrame = true
  for _, v in ipairs(got.verts) do
    inFirstFrame = inFirstFrame and v[5] < 0.5
  end
  check(inFirstFrame, "frame fora de faixa volta para o frame zero")
end

do
  local pixels = {}
  local w, h = 2, 4
  pixels[0 * w + 0] = 1
  pixels[1 * w + 0] = 1
  pixels[3 * w + 0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, w, h)
  loadWith(makeMod(handle, { depth = 2 }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 2 }, 1)
  local minV = (2 + 1 + 0.05) / h
  local maxV = (2 + 1 + 0.95) / h
  local foundTop = false
  for i = 1, #got.verts, 4 do
    local y = got.verts[i][2]
    local sameY = true
    local frameUv = true
    local shadeTop = true
    for j = i, i + 3 do
      sameY = sameY and math.abs(got.verts[j][2] - y) < 0.0001
      frameUv = frameUv and got.verts[j][5] >= minV - 0.0001
        and got.verts[j][5] <= maxV + 0.0001
      shadeTop = shadeTop and math.abs(got.verts[j][6] - 1.0) < 0.0001
    end
    if sameY and frameUv and shadeTop and math.abs(y - 0.97) < 0.0001 then
      foundTop = true
    end
  end
  check(foundTop, "topo existe mesmo quando a frame atual remove o pixel acima")
end

T.finish("voxel_chars_test")
