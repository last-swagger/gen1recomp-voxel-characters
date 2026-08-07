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
      local p = pixels[y * w + x]
      if type(p) == "table" then
        return p[1] or p.r or 0, p[2] or p.g or 0,
               p[3] or p.b or 0, p[4] or p.a or 1
      end
      return 1, 1, 1, p or 0
    end,
  }
end

local function paint(pixels, sheetW, cellW, frame, lx, ly, value)
  pixels[ly * sheetW + frame * cellW + lx] = value or 1
end

local function rgba(r, g, b, a)
  return { r, g, b, a or 1 }
end

local function close(a, b)
  return math.abs(a - b) < 0.0001
end

local function quadIndex(mesh, pred)
  for i = 1, #mesh.verts, 4 do
    if pred(i) then return i end
  end
end

local function allQuad(mesh, i, pred)
  for j = i, i + 3 do
    if not pred(mesh.verts[j]) then return false end
  end
  return true
end

local function quadUvBounds(mesh, i)
  local minU, maxU, minV, maxV = 1, 0, 1, 0
  for j = i, i + 3 do
    minU = math.min(minU, mesh.verts[j][4])
    maxU = math.max(maxU, mesh.verts[j][4])
    minV = math.min(minV, mesh.verts[j][5])
    maxV = math.max(maxV, mesh.verts[j][5])
  end
  return minU, maxU, minV, maxV
end

local function quadCount(mesh)
  return math.floor(#mesh.verts / 4)
end

local function quadBoundsAt(mesh, i)
  local b = {
    minX = math.huge, maxX = -math.huge,
    minY = math.huge, maxY = -math.huge,
    minZ = math.huge, maxZ = -math.huge,
  }
  for j = i, i + 3 do
    local v = mesh.verts[j]
    b.minX, b.maxX = math.min(b.minX, v[1]), math.max(b.maxX, v[1])
    b.minY, b.maxY = math.min(b.minY, v[2]), math.max(b.maxY, v[2])
    b.minZ, b.maxZ = math.min(b.minZ, v[3]), math.max(b.maxZ, v[3])
  end
  return b
end

local function projectedCells(mesh, ax, ay, pred)
  ax, ay = ax or 1, ay or 2
  local cells = {}
  for i = 1, #mesh.verts, 4 do
    if not (pred and not pred(i)) then
      local minA, maxA = math.huge, -math.huge
      local minB, maxB = math.huge, -math.huge
      for j = i, i + 3 do
        local v = mesh.verts[j]
        minA, maxA = math.min(minA, v[ax]), math.max(maxA, v[ax])
        minB, maxB = math.min(minB, v[ay]), math.max(maxB, v[ay])
      end
      local a0 = math.floor(minA + 0.0001)
      local a1 = math.ceil(maxA - 0.0001) - 1
      local b0 = math.floor(minB + 0.0001)
      local b1 = math.ceil(maxB - 0.0001) - 1
      for b = b0, b1 do
        for a = a0, a1 do
          cells[#cells + 1] = { a = a, b = b }
        end
      end
    end
  end
  local out, seen = {}, {}
  for _, cell in ipairs(cells) do
    local key = cell.a .. "," .. cell.b
    seen[key] = true
  end
  for key in pairs(seen) do out[#out + 1] = key end
  table.sort(out)
  return table.concat(out, ";")
end

local function expectedCells(pixels, sheetW, cellW, cellH, frame)
  local cells, maxY = {}, nil
  for ly = 0, cellH - 1 do
    for lx = 0, cellW - 1 do
      if pixels[ly * sheetW + frame * cellW + lx] then
        cells[#cells + 1] = { x = lx, y = ly }
        maxY = maxY and math.max(maxY, ly) or ly
      end
    end
  end
  local out = {}
  for _, cell in ipairs(cells) do
    out[#out + 1] = cell.x .. "," .. (maxY - cell.y)
  end
  table.sort(out)
  return table.concat(out, ";")
end

local function meshBounds(mesh)
  local b = {
    minX = math.huge, maxX = -math.huge,
    minY = math.huge, maxY = -math.huge,
    minZ = math.huge, maxZ = -math.huge,
  }
  for _, v in ipairs(mesh.verts) do
    b.minX, b.maxX = math.min(b.minX, v[1]), math.max(b.maxX, v[1])
    b.minY, b.maxY = math.min(b.minY, v[2]), math.max(b.maxY, v[2])
    b.minZ, b.maxZ = math.min(b.minZ, v[3]), math.max(b.maxZ, v[3])
  end
  return b
end

local function sameRange(a0, a1, b0, b1)
  return close(a0, b0) and close(a1, b1)
end

local function sideFaceUvAt(mesh, minX, maxX, minY, maxY)
  for i = 1, #mesh.verts, 4 do
    local bx = quadBoundsAt(mesh, i)
    if close(bx.minX, minX) and close(bx.maxX, maxX)
        and close(bx.minY, minY) and close(bx.maxY, maxY)
        and allQuad(mesh, i, function(v) return close(v[6], 0.78) end) then
      return mesh.verts[i][4], mesh.verts[i][5]
    end
  end
end

local function setDepthWithoutClearing(modules, value)
  local wrapper = modules.SpriteBillboards.mesh
  local voxelMesh
  for i = 1, 20 do
    local name, upvalue = debug.getupvalue(wrapper, i)
    if name == "voxelMesh" then
      voxelMesh = upvalue
      break
    end
  end
  check(type(voxelMesh) == "function", "teste encontra voxelMesh no wrapper para depth")
  for i = 1, 40 do
    local name = debug.getupvalue(voxelMesh, i)
    if name == "depthValue" then
      debug.setupvalue(voxelMesh, i, value)
      return true
    end
  end
  return check(false, "teste encontra depthValue em voxelMesh")
end

local function setSideColorWithoutClearing(modules, value)
  local wrapper = modules.SpriteBillboards.mesh
  local voxelMesh
  for i = 1, 20 do
    local name, upvalue = debug.getupvalue(wrapper, i)
    if name == "voxelMesh" then
      voxelMesh = upvalue
      break
    end
  end
  check(type(voxelMesh) == "function", "teste encontra voxelMesh no wrapper")
  for i = 1, 40 do
    local name = debug.getupvalue(voxelMesh, i)
    if name == "sideColorValue" then
      debug.setupvalue(voxelMesh, i, value)
      return true
    end
  end
  return check(false, "teste encontra sideColorValue em voxelMesh")
end

local function setShapeWithoutClearing(modules, value)
  local wrapper = modules.SpriteBillboards.mesh
  local voxelMesh
  for i = 1, 20 do
    local name, upvalue = debug.getupvalue(wrapper, i)
    if name == "voxelMesh" then
      voxelMesh = upvalue
      break
    end
  end
  check(type(voxelMesh) == "function", "teste encontra voxelMesh no wrapper")
  for i = 1, 40 do
    local name = debug.getupvalue(voxelMesh, i)
    if name == "shapeValue" then
      debug.setupvalue(voxelMesh, i, value)
      return true
    end
  end
  return check(false, "teste encontra shapeValue em voxelMesh")
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
  eq(#rows, 4, "hook anexa as rows do voxel characters")
  local option = rows[2]
  eq(rows[3].label, "SIDE COLOR", "hook anexa a row de cor lateral")
  eq(rows[4].label, "SHAPE", "hook anexa a row de shape")
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

do
  local pixels = {
    [0] = rgba(0.20, 0.20, 0.20, 1),
    [1] = rgba(0.80, 0.80, 0.80, 1),
  }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 2, 1)
  loadWith(makeMod(handle, { depth = 2, side_color = "body" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local q = quadIndex(got, function(i)
    return allQuad(got, i, function(v)
      return close(v[1], 0.03) and close(v[6], 0.78)
    end)
  end)
  check(q ~= nil, "BODY encontra a face lateral da borda")
  check(q and allQuad(got, q, function(v) return close(v[4], 0.75) end),
        "BODY usa o UV da coluna clara na face lateral")
end

do
  local pixels = {
    [0] = rgba(0.20, 0.20, 0.20, 1),
    [1] = rgba(0.80, 0.80, 0.80, 1),
  }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 2, 1)
  loadWith(makeMod(handle, { depth = 2, side_color = "outline" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local q = quadIndex(got, function(i)
    return allQuad(got, i, function(v)
      return close(v[1], 0.03) and close(v[6], 0.78)
    end)
  end)
  check(q ~= nil, "OUTLINE encontra a face lateral da borda")
  check(q and allQuad(got, q, function(v) return close(v[4], 0.25) end),
        "OUTLINE preserva o UV da borda na face lateral")
end

do
  local pixels = {
    [0] = rgba(0.20, 0.20, 0.20, 1),
    [1] = rgba(0.20, 0.20, 0.20, 1),
    [2] = rgba(0.80, 0.80, 0.80, 1),
    [3] = rgba(0.80, 0.80, 0.80, 1),
  }
  local expectedMinU, expectedMaxU = 0.025, 0.975
  local expectedMinV, expectedMaxV = 0.025, 0.475
  for _, mode in ipairs({ "body", "outline" }) do
    local handle, modules = makeVoxelHandle("1.6.0", pixels, 2, 2)
    loadWith(makeMod(handle, { depth = 2, side_color = mode }))
    local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
    local q = quadIndex(got, function(i)
      return allQuad(got, i, function(v)
        return close(v[3], 0) and close(v[6], 1.0)
      end)
    end)
    local minU, maxU, minV, maxV = 0, 0, 0, 0
    if q then minU, maxU, minV, maxV = quadUvBounds(got, q) end
    check(q and close(minU, expectedMinU) and close(maxU, expectedMaxU)
          and close(minV, expectedMinV) and close(maxV, expectedMaxV),
          "frente usa o UV original no modo " .. mode)
  end
end

do
  local pixels = {
    [0] = rgba(0.20, 0.20, 0.20, 1),
    [1] = rgba(0.20, 0.20, 0.20, 1),
    [2] = rgba(0.80, 0.80, 0.80, 1),
    [3] = rgba(0.80, 0.80, 0.80, 1),
  }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 2, 2)
  loadWith(makeMod(handle, { depth = 2, side_color = "body" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local q = quadIndex(got, function(i)
    return allQuad(got, i, function(v)
      return close(v[2], 1.97) and close(v[6], 1.0)
    end)
  end)
  local minU, maxU, minV, maxV = 0, 0, 0, 0
  if q then minU, maxU, minV, maxV = quadUvBounds(got, q) end
  check(q and close(minV, 0.525) and close(maxV, 0.975),
        "topo com run inteiro em contorno usa UV da linha de corpo abaixo")
end

do
  local pixels = {
    [0] = rgba(0.80, 0.80, 0.80, 1),
    [1] = rgba(0.80, 0.80, 0.80, 1),
    [2] = rgba(0.20, 0.20, 0.20, 1),
    [3] = rgba(0.20, 0.20, 0.20, 1),
  }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 2, 2)
  loadWith(makeMod(handle, { depth = 2, side_color = "body" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local q = quadIndex(got, function(i)
    return allQuad(got, i, function(v)
      return close(v[2], 0.03) and close(v[6], 0.55)
    end)
  end)
  local minU, maxU, minV, maxV = 0, 0, 0, 0
  if q then minU, maxU, minV, maxV = quadUvBounds(got, q) end
  check(q and close(minV, 0.025) and close(maxV, 0.475),
        "base com run inteiro em contorno usa UV da linha de corpo acima")
end

do
  local pixels = {
    [0] = rgba(0.20, 0.20, 0.20, 1),
    [1] = rgba(0.20, 0.20, 0.20, 1),
    [2] = rgba(0.80, 0.80, 0.80, 1),
    [3] = rgba(0.20, 0.20, 0.20, 1),
  }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 2, 2)
  loadWith(makeMod(handle, { depth = 2, side_color = "body" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local q = quadIndex(got, function(i)
    return allQuad(got, i, function(v)
      return close(v[2], 1.97) and close(v[6], 1.0)
    end)
  end)
  local minU, maxU, minV, maxV = 0, 0, 0, 0
  if q then minU, maxU, minV, maxV = quadUvBounds(got, q) end
  check(q and close(minV, 0.025) and close(maxV, 0.475),
        "topo com corpo parcial na linha candidata preserva o UV original")
end

do
  local pixels = {
    [0] = rgba(0.40, 0.40, 0.40, 1),
    [1] = rgba(0.40, 0.40, 0.40, 1),
  }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 2, 1)
  loadWith(makeMod(handle, { depth = 2, side_color = "body" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local q = quadIndex(got, function(i)
    return allQuad(got, i, function(v)
      return close(v[1], 0.03) and close(v[6], 0.78)
    end)
  end)
  check(q ~= nil, "folha de um tom so encontra a face lateral")
  check(q and allQuad(got, q, function(v) return close(v[4], 0.25) end),
        "folha de um tom so falha a busca e preserva o UV proprio")
end

do
  local pixels = {
    [0] = rgba(0.20, 0.20, 0.20, 1),
    [1] = rgba(0.80, 0.80, 0.80, 1),
  }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 2, 1)
  local mod = loadWith(makeMod(handle, { depth = 2, side_color = "body" }))
  local def = { image = "sheet.png", frames = 1 }
  local a = modules.SpriteBillboards.mesh(def, 0)
  mod._events["mod.options_changed"]({ mod = mod.id, key = "side_color",
                                        value = "outline" })
  local b = modules.SpriteBillboards.mesh(def, 0)
  check(a ~= b, "trocar SIDE COLOR nao serve a malha do outro modo")
  check(a.released and modules.Voxel3D.created == 2,
        "trocar SIDE COLOR limpa o cache de malhas")
end

do
  local pixels = {
    [0] = rgba(0.20, 0.20, 0.20, 1),
    [1] = rgba(0.80, 0.80, 0.80, 1),
  }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 2, 1)
  loadWith(makeMod(handle, { depth = 2, side_color = "body" }))
  local def = { image = "sheet.png", frames = 1 }
  local a = modules.SpriteBillboards.mesh(def, 0)
  setSideColorWithoutClearing(modules, "outline")
  local b = modules.SpriteBillboards.mesh(def, 0)
  check(a ~= b, "cacheKey separa SIDE COLOR mesmo sem limpar o cache")
  eq(modules.Voxel3D.created, 2,
     "cacheKey cria uma entrada propria para cada SIDE COLOR")
end

do
  local cellW, cellH = 2, 2
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do
    for ly = 0, cellH - 1 do
      for lx = 0, cellW - 1 do
        paint(pixels, sheetW, cellW, frame, lx, ly, 1)
      end
    end
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 6,
                                              frameWidth = cellW }, 0)
  eq(quadCount(got), 24,
     "CARVED em cubo 2x2x2 emite so as faces de superficie")
end

do
  local cellW, cellH = 4, 4
  local sheetW = cellW * 6
  local pixels = {}
  for _, frame in ipairs({ 0, 3 }) do
    paint(pixels, sheetW, cellW, frame, 0, 1, 1)
    paint(pixels, sheetW, cellW, frame, 1, 1, 1)
    paint(pixels, sheetW, cellW, frame, 2, 1, 1)
    paint(pixels, sheetW, cellW, frame, 1, 2, 1)
    paint(pixels, sheetW, cellW, frame, 2, 2, 1)
    paint(pixels, sheetW, cellW, frame, 0, 3, 1)
  end
  for _, frame in ipairs({ 1, 4 }) do
    paint(pixels, sheetW, cellW, frame, 0, 1, 1)
    paint(pixels, sheetW, cellW, frame, 1, 1, 1)
    paint(pixels, sheetW, cellW, frame, 1, 2, 1)
    paint(pixels, sheetW, cellW, frame, 2, 2, 1)
    paint(pixels, sheetW, cellW, frame, 2, 3, 1)
  end
  for _, frame in ipairs({ 2, 5 }) do
    paint(pixels, sheetW, cellW, frame, 0, 1, 1)
    paint(pixels, sheetW, cellW, frame, 0, 2, 1)
    paint(pixels, sheetW, cellW, frame, 1, 1, 1)
    paint(pixels, sheetW, cellW, frame, 2, 2, 1)
    paint(pixels, sheetW, cellW, frame, 2, 3, 1)
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local front = modules.SpriteBillboards.mesh(def, 0)
  local back = modules.SpriteBillboards.mesh(def, 1)
  local side = modules.SpriteBillboards.mesh(def, 2)
  local frontPlane = function(mesh)
    return function(i)
      local b = quadBoundsAt(mesh, i)
      return close(b.minZ, 0) and close(b.maxZ, 0)
        and allQuad(mesh, i, function(v) return close(v[6], 1.0) end)
    end
  end
  local backPlane = function(i)
    local b = quadBoundsAt(back, i)
    return close(b.minZ, 0) and close(b.maxZ, 0)
      and allQuad(back, i, function(v) return close(v[6], 0.68) end)
  end
  eq(projectedCells(front, 1, 2, frontPlane(front)),
     "0,2;1,1;1,2;2,1;2,2",
     "silhueta CARVED de frente bate em posicao absoluta com frame 0")
  eq(projectedCells(back, 1, 2, backPlane), "0,0;0,1;1,1",
     "silhueta CARVED de costas fica espelhada em posicao absoluta")
  eq(projectedCells(side),
     "0,1;0,2;1,2;2,0;2,1",
     "silhueta CARVED lateral bate em posicao absoluta com frame 2")
  check(projectedCells(side) ~= projectedCells(front, 1, 2, frontPlane(front)),
        "frame lateral com rotacao zerada quebraria a silhueta")
  eq(projectedCells(side, 1, 3), "0,-1;0,-2;0,-3;1,-1;1,-2;1,-3;2,-1;2,-2;2,-3",
        "eixo de profundidade preserva a frente na esquerda do frame lateral")
  local fb, bb, sb = meshBounds(front), meshBounds(back), meshBounds(side)
  check(sameRange(fb.minY, fb.maxY, bb.minY, bb.maxY)
        and sameRange(fb.minY, fb.maxY, sb.minY, sb.maxY),
        "roles CARVED ocupam a mesma faixa absoluta de Y sem pitch")
  check(sb.maxZ <= 0 and sb.minZ < sb.maxZ,
        "role lateral mantem profundidade em Z nao positivo")
end

do
  local cellW, cellH = 3, 3
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do
    for ly = 0, cellH - 1 do
      for lx = 0, cellW - 1 do
        paint(pixels, sheetW, cellW, frame, lx, ly, 1)
      end
    end
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH, 0)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local front = meshBounds(modules.SpriteBillboards.mesh(def, 0))
  local back = meshBounds(modules.SpriteBillboards.mesh(def, 1))
  local side = meshBounds(modules.SpriteBillboards.mesh(def, 2))
  check(sameRange(front.minY, front.maxY, back.minY, back.maxY)
        and sameRange(front.minY, front.maxY, side.minY, side.maxY),
        "roles CARVED ocupam a mesma faixa absoluta de Y com pitch")
end

do
  local cellW, cellH = 2, 2
  local sheetW = cellW * 3
  local pixels = {}
  for frame = 0, 2 do
    for ly = 0, cellH - 1 do
      for lx = 0, cellW - 1 do
        paint(pixels, sheetW, cellW, frame, lx, ly, 1)
      end
    end
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 3,
                                              frameWidth = cellW }, 0)
  eq(quadCount(got), 24, "CARVED aceita folha parada de tres frames")
end

do
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  check(got and not got.original, "CARVED sem tres vistas degrada para laje")
  eq(quadCount(got), 6, "fallback de CARVED sem tres vistas preserva o slab")
end

do
  local cellW, cellH = 3, 2
  local sheetW = cellW * 6
  local pixels = {}
  for _, frame in ipairs({ 0, 1, 3, 4 }) do
    paint(pixels, sheetW, cellW, frame, 0, 1, 1)
  end
  paint(pixels, sheetW, cellW, 2, 0, 1, rgba(0.20, 0.20, 0.20, 1))
  paint(pixels, sheetW, cellW, 2, 1, 1, rgba(0.80, 0.80, 0.80, 1))
  paint(pixels, sheetW, cellW, 5, 0, 1, rgba(0.20, 0.20, 0.20, 1))
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved", side_color = "body" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local stand = modules.SpriteBillboards.mesh(def, 2)
  local walk = modules.SpriteBillboards.mesh(def, 5)
  local u0, v0 = sideFaceUvAt(stand, 0, 1, 0, 1)
  local u1, v1 = sideFaceUvAt(walk, 0, 1, 0, 1)
  check(u0 and u1 and close(u0, u1) and close(v0, v1),
        "face lateral CARVED nao muda classificacao de cor entre frames")
end

do
  local cellW, cellH = 1, 1
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paint(pixels, sheetW, cellW, frame, 0, 0, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  local mod = loadWith(makeMod(handle, { depth = 2, shape = "slab" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local a = modules.SpriteBillboards.mesh(def, 0)
  mod._events["mod.options_changed"]({ mod = mod.id, key = "shape",
                                        value = "carved" })
  local b = modules.SpriteBillboards.mesh(def, 0)
  check(a ~= b, "trocar SHAPE nao serve a malha do outro modo")
  check(a.released and modules.Voxel3D.created == 2,
        "trocar SHAPE limpa o cache de malhas")
end

do
  local cellW, cellH = 1, 1
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paint(pixels, sheetW, cellW, frame, 0, 0, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local a = modules.SpriteBillboards.mesh(def, 0)
  setShapeWithoutClearing(modules, "carved")
  local b = modules.SpriteBillboards.mesh(def, 0)
  check(a ~= b, "cacheKey separa SHAPE mesmo sem limpar o cache")
  eq(modules.Voxel3D.created, 2,
     "cacheKey cria uma entrada propria para cada SHAPE")
end

do
  local cellW, cellH = 1, 1
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paint(pixels, sheetW, cellW, frame, 0, 0, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local a = modules.SpriteBillboards.mesh(def, 0)
  setDepthWithoutClearing(modules, 5)
  local b = modules.SpriteBillboards.mesh(def, 0)
  eq(a, b, "cacheKey ignora DEPTH quando SHAPE e CARVED")
  eq(modules.Voxel3D.created, 1,
     "CARVED nao duplica malha identica ao trocar DEPTH")
end

T.finish("voxel_chars_test")
