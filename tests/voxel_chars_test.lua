package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Json = require("src.link.Json")
local MAIN_PATH = os.getenv("VOXEL_CHARS_MAIN")
  or "mods/voxel_characters/main.lua"
local MANIFEST_PATH = "mods/voxel_characters/manifest.json"

local function readJson(path)
  local f = assert(io.open(path, "rb"))
  local body = f:read("*a")
  f:close()
  local doc, err = Json.decode(body)
  assert(doc, tostring(err))
  return doc
end

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

local quadBoundsAt

local function frontQuadIndexAt(mesh, minX, maxX, minY, maxY)
  return quadIndex(mesh, function(i)
    local b = quadBoundsAt(mesh, i)
    return close(b.minX, minX) and close(b.maxX, maxX)
      and close(b.minY, minY) and close(b.maxY, maxY)
      and close(b.minZ, b.maxZ)
      and allQuad(mesh, i, function(v) return close(v[6], 0.90) end)
  end)
end

local function allUvAt(mesh, i, u, v)
  return i and allQuad(mesh, i, function(row)
    return close(row[4], u) and close(row[5], v)
  end)
end

local function uvSignature(mesh)
  local out = {}
  for i, v in ipairs(mesh.verts) do
    out[i] = ("%.4f,%.4f"):format(v[4], v[5])
  end
  return table.concat(out, ";")
end

local function vertexSignature(mesh)
  local out = {}
  for i, v in ipairs(mesh.verts) do
    out[i] = ("%.4f,%.4f,%.4f,%.4f,%.4f,%.4f"):format(
      v[1], v[2], v[3], v[4], v[5], v[6])
  end
  return table.concat(out, ";")
end

local function quadCount(mesh)
  return math.floor(#mesh.verts / 4)
end

function quadBoundsAt(mesh, i)
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

local function horizontalFaceUvAt(mesh, shade, top)
  local bestI, bestY
  for i = 1, #mesh.verts, 4 do
    local b = quadBoundsAt(mesh, i)
    if close(b.minY, b.maxY) and b.maxZ > b.minZ
        and allQuad(mesh, i, function(v) return close(v[6], shade) end) then
      if not bestY or (top and b.minY > bestY) or ((not top) and b.minY < bestY) then
        bestI, bestY = i, b.minY
      end
    end
  end
  if bestI then return mesh.verts[bestI][4], mesh.verts[bestI][5] end
end

local function horizontalFaceUvInBounds(mesh, shade, minX, maxX, minY, maxY)
  for i = 1, #mesh.verts, 4 do
    local b = quadBoundsAt(mesh, i)
    if close(b.minX, minX) and close(b.maxX, maxX)
        and close(b.minY, minY) and close(b.maxY, maxY)
        and close(b.minY, b.maxY) and b.maxZ > b.minZ
        and allQuad(mesh, i, function(v) return close(v[6], shade) end) then
      return mesh.verts[i][4], mesh.verts[i][5]
    end
  end
end

local function countHorizontalFacesAtY(mesh, shade, y)
  local count = 0
  for i = 1, #mesh.verts, 4 do
    local b = quadBoundsAt(mesh, i)
    if close(b.minY, y) and close(b.maxY, y) and b.maxZ > b.minZ
        and allQuad(mesh, i, function(v) return close(v[6], shade) end) then
      count = count + 1
    end
  end
  return count
end

local function countSideFaces(mesh)
  local count = 0
  for i = 1, #mesh.verts, 4 do
    local b = quadBoundsAt(mesh, i)
    if close(b.minX, b.maxX) and b.maxZ > b.minZ
        and allQuad(mesh, i, function(v) return close(v[6], 0.78) end) then
      count = count + 1
    end
  end
  return count
end

local function countSideFacesAtX(mesh, x)
  local count = 0
  for i = 1, #mesh.verts, 4 do
    local b = quadBoundsAt(mesh, i)
    if close(b.minX, x) and close(b.maxX, x) and b.maxZ > b.minZ
        and allQuad(mesh, i, function(v) return close(v[6], 0.78) end) then
      count = count + 1
    end
  end
  return count
end

local function frontFaceZAt(mesh, minX, maxX, minY, maxY)
  for i = 1, #mesh.verts, 4 do
    local b = quadBoundsAt(mesh, i)
    if close(b.minX, minX) and close(b.maxX, maxX)
        and close(b.minY, minY) and close(b.maxY, maxY)
        and close(b.minZ, b.maxZ)
        and allQuad(mesh, i, function(v) return close(v[6], 0.90) end) then
      return b.minZ
    end
  end
end

local function frontVertexShadeAt(mesh, x, y)
  for _, v in ipairs(mesh.verts) do
    if close(v[1], x) and close(v[2], y) and close(v[3], 0) then
      return v[6]
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

local function setGroundShadeWithoutClearing(modules, value)
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
  for i = 1, 50 do
    local name = debug.getupvalue(voxelMesh, i)
    if name == "groundShadeValue" then
      debug.setupvalue(voxelMesh, i, value)
      return true
    end
  end
  return check(false, "teste encontra groundShadeValue em voxelMesh")
end

local function setBlinkWithoutClearing(modules, value)
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
  for i = 1, 70 do
    local name = debug.getupvalue(voxelMesh, i)
    if name == "blinkValue" then
      debug.setupvalue(voxelMesh, i, value)
      return true
    end
  end
  return check(false, "teste encontra blinkValue em voxelMesh")
end

local function setTopEdgeWithoutClearing(modules, value)
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
  for i = 1, 80 do
    local name = debug.getupvalue(voxelMesh, i)
    if name == "topEdgeValue" then
      debug.setupvalue(voxelMesh, i, value)
      return true
    end
  end
  return check(false, "teste encontra topEdgeValue em voxelMesh")
end

local function blinkHashName(name)
  local h = 5381
  name = tostring(name or "")
  for i = 1, #name do
    h = (h * 33 + name:byte(i)) % 4294967296
  end
  return h
end

local function blinkTimes(baseName)
  local h = blinkHashName(baseName)
  local period = 3 + (h % 3000) / 1000
  local phase = (math.floor(h / 3000) % 3000) / 1000
  return period - phase + 0.01, period - phase + 0.25
end

local function withLoveTime(value, fn)
  local prev = love.timer.getTime
  love.timer.getTime = function() return value end
  local ok, err = pcall(fn)
  love.timer.getTime = prev
  if not ok then error(err) end
end

local function paintBlinkFace(pixels, sheetW, cellW, frame)
  local skin = rgba(0.80, 0.55, 0.40, 1)
  local eye = rgba(0.05, 0.05, 0.05, 1)
  for lx = 5, 10 do paint(pixels, sheetW, cellW, frame, lx, 7, skin) end
  paint(pixels, sheetW, cellW, frame, 6, 7, eye)
  paint(pixels, sheetW, cellW, frame, 9, 7, eye)
  paint(pixels, sheetW, cellW, frame, 6, 8, skin)
  paint(pixels, sheetW, cellW, frame, 9, 8, skin)
end

local function fakeMesh(verts, map)
  return {
    verts = verts,
    map = map,
    released = false,
    setVertex = function(self, index, row, ...)
      if type(row) == "table" then
        self.verts[index] = { row[1], row[2], row[3], row[4], row[5], row[6] }
      else
        self.verts[index] = { row, ... }
      end
    end,
    setVertexMap = function(self, m) self.map = m end,
    setTexture = function(self, tex) self.texture = tex end,
    release = function(self) self.released = true end,
  }
end

-- cardBlend e omitFirstPerson dao suporte ao defeito 3 (main.lua:1043+, roda
-- antes de SLAB e CARVED). cardBlend controla o retorno do stub de
-- FirstPerson.cardBlend(); omitFirstPerson tira o modulo do namespace, para
-- provar a versao do host onde FirstPerson nem existe.
local function makeVoxelHandle(version, pixels, w, h, angle, spriteLean,
                               cardBlend, omitFirstPerson, hostId)
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
        -- Statement per statement as in Voxel3D.lua:412-420. Packed into two
        -- multiple assignments this leaves holes (1 2 3 nil nil nil 7 ...),
        -- because `#map` resolves before the assignments land. Nothing here
        -- asserts on the map, so the stub was quietly building a corrupt one.
        pushQuad = function(map, n)
          local b = n * 4
          map[#map + 1] = b + 1
          map[#map + 1] = b + 2
          map[#map + 1] = b + 3
          map[#map + 1] = b + 1
          map[#map + 1] = b + 3
          map[#map + 1] = b + 4
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
      if omitFirstPerson then
        error("unexpected module " .. tostring(name))
      end
      modules[name] = { cardBlend = function() return cardBlend or 0 end }
    else
      error("unexpected module " .. tostring(name))
    end
    return modules[name]
  end
  return {
    id = hostId or "DRAMATIC_SHAPE",
    version = version,
    exports = { lib = V },
  }, modules, original
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
  local hosts = {}
  if handle and handle.exports then
    hosts[handle.id or "DRAMATIC_SHAPE"] = handle
  elseif handle then
    hosts = handle
  end
  function mod.find(id)
    return hosts[id]
  end
  mod._rows, mod._events, mod._logs = rows, events, logs
  return mod
end

local function loadWith(mod)
  resetLoaded()
  local chunk = assert(loadfile(MAIN_PATH))
  chunk(mod)
  return mod
end

do
  local manifest = readJson(MANIFEST_PATH)
  local seen = {}
  for _, id in ipairs(manifest.optional_dependencies or {}) do seen[id] = true end
  check(seen.BATTLE_ART_VOXEL_FORK and seen.DRAMATIC_SHAPE,
        "optional_dependencies lista os dois ids")
end

do
  local pixels = {}
  pixels[0] = 1
  local handle, modules, original = makeVoxelHandle("2.0.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle))
  local SpriteBillboards = handle.exports.lib.require("SpriteBillboards")
  eq(SpriteBillboards.mesh, original, "versao fora da faixa preserva original")
  eq(mod._rows["ui.options.rows"], nil, "row nao aparece sem patch suportado")
  check(mod._logs.warn[1]
        and mod._logs.warn[1]:find("outside supported range", 1, true),
        "versao fora da faixa avisa no log")
end

do
  local mod = loadWith(makeMod(nil))
  eq(mod._rows["ui.options.rows"], nil, "row nao aparece sem Dramatic Shape")
  check(mod._logs.warn[1]
        and mod._logs.warn[1]:find("BATTLE_ART_VOXEL_FORK", 1, true)
        and mod._logs.warn[1]:find("DRAMATIC_SHAPE", 1, true),
        "sem host avisa quais ids foram procurados")
end

do
  local pixels = {}
  pixels[0] = 1
  local fork, _, forkOriginal =
    makeVoxelHandle("1.3.1", pixels, 16, 16, nil, nil, nil, nil,
      "BATTLE_ART_VOXEL_FORK")
  local dramatic, dramaticModules, dramaticOriginal =
    makeVoxelHandle("1.6.0", pixels, 16, 16)
  loadWith(makeMod({
    BATTLE_ART_VOXEL_FORK = fork,
    DRAMATIC_SHAPE = dramatic,
  }))
  local forkSprite = fork.exports.lib.require("SpriteBillboards")
  check(dramaticModules.SpriteBillboards.mesh ~= dramaticOriginal
        and forkSprite.mesh == forkOriginal,
        "fork fora da faixa e legado valido: o legado e usado")
end

do
  local pixels = {}
  pixels[0] = 1
  local fork = makeVoxelHandle("1.3.1", pixels, 16, 16, nil, nil, nil, nil,
    "BATTLE_ART_VOXEL_FORK")
  local dramatic = makeVoxelHandle("2.0.0", pixels, 16, 16)
  local mod = loadWith(makeMod({
    BATTLE_ART_VOXEL_FORK = fork,
    DRAMATIC_SHAPE = dramatic,
  }))
  local warn = mod._logs.warn[1] or ""
  check(warn:find("BATTLE_ART_VOXEL_FORK", 1, true)
        and warn:find("found 1.3.1", 1, true)
        and warn:find(">=1.7.0 <2.0.0", 1, true)
        and warn:find("DRAMATIC_SHAPE", 1, true)
        and warn:find("found 2.0.0", 1, true)
        and warn:find(">=1.5.0 <2.0.0", 1, true)
        and warn:find("outside supported range", 1, true),
        "nenhum host valido: o log diz o que achou e por que rejeitou")
end

do
  local pixels = {}
  pixels[0] = 1
  local handle, modules, original = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle))
  check(modules.SpriteBillboards.mesh ~= original, "host DRAMATIC_SHAPE e aceito")
  check(mod._logs.info[1]
        and mod._logs.info[1]:find("Dramatic Shape 1.6.0", 1, true),
        "host DRAMATIC_SHAPE encontrado e logado")
end

do
  local pixels = {}
  pixels[0] = 1
  local handle, modules, original = makeVoxelHandle("1.7.6", pixels, 16, 16,
    nil, nil, nil, nil, "BATTLE_ART_VOXEL_FORK")
  local mod = loadWith(makeMod(handle))
  check(modules.SpriteBillboards.mesh ~= original,
        "host BATTLE_ART_VOXEL_FORK e aceito")
  check(mod._logs.info[1]
        and mod._logs.info[1]:find("Battle Art Voxel Fork 1.7.6", 1, true),
        "host BATTLE_ART_VOXEL_FORK encontrado e logado")
end

do
  local pixels = {}
  pixels[0] = 1
  local dramatic, dramaticModules, dramaticOriginal =
    makeVoxelHandle("1.6.0", pixels, 16, 16)
  local fork, forkModules, forkOriginal =
    makeVoxelHandle("1.7.6", pixels, 16, 16, nil, nil, nil, nil,
      "BATTLE_ART_VOXEL_FORK")
  local mod = loadWith(makeMod({
    DRAMATIC_SHAPE = dramatic,
    BATTLE_ART_VOXEL_FORK = fork,
  }))
  local dramaticSprite = dramatic.exports.lib.require("SpriteBillboards")
  eq(dramaticSprite.mesh, dramaticOriginal,
    "com dois hosts, DRAMATIC_SHAPE fica sem patch")
  check(forkModules.SpriteBillboards.mesh ~= forkOriginal,
        "com dois hosts, BATTLE_ART_VOXEL_FORK tem precedencia")
  check(mod._logs.info[1]
        and mod._logs.info[1]:find("BATTLE_ART_VOXEL_FORK", 1, true),
        "com dois hosts, o fork escolhido e logado")
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
  eq(#rows, 7, "hook anexa as rows do voxel characters")
  local option = rows[2]
  eq(rows[3].label, "SIDE COLOR", "hook anexa a row de cor lateral")
  eq(rows[4].label, "SHAPE", "hook anexa a row de shape")
  eq(rows[5].label, "GROUND SHADE", "hook anexa a row de ground shade")
  eq(rows[6].label, "BLINK", "hook anexa a row de blink")
  eq(rows[7].label, "TOP EDGE", "hook anexa a row de top edge")
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
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle, { depth = 1 }))
  local emitted = {}
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
  }
  local rows = {}
  mod._rows["ui.options.rows"](function(_, r) return r end, game, rows)
  local option = rows[6]
  eq(option.label, "TOP EDGE", "row de TOP EDGE fica depois de BLINK")
  eq(option.value(), "OFF", "TOP EDGE default e OFF")
  check(option.step(game, 1), "step de TOP EDGE informa mudanca")
  eq(option.value(), "ON", "TOP EDGE alterna para ON")
  eq(game.save.options.modOptions.voxel_characters.top_edge, "on",
     "TOP EDGE persiste no save")
  eq(game.mods.modOptions.voxel_characters.top_edge, "on",
     "TOP EDGE persiste no loader")
  eq(emitted[1].payload.value, "on", "TOP EDGE emite o valor novo")
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
  -- Pixel vive no frame 5 (linha 80 de uma folha vertical de 16px por
  -- frame), nao no frame 0: desde a v1.3.0 a mascara SLAB e por frame
  -- corrente (defeito 1), entao um pixel opaco so no frame 0 nao bastaria
  -- mais para provar que o frame 5 constroi malha.
  pixels[80 * 16] = 1
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
    if sameY and frameUv and shadeTop and math.abs(y - 1) < 0.0001 then
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
      return close(v[1], 0) and close(v[6], 0.78)
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
      return close(v[1], 0) and close(v[6], 0.78)
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
        return close(v[3], 0) and close(v[6], 0.90)
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
    [1] = rgba(0.80, 0.80, 0.80, 1),
    [2] = rgba(0.80, 0.80, 0.80, 1),
    [3] = rgba(0.80, 0.80, 0.80, 1),
  }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 2, 2)
  loadWith(makeMod(handle, { depth = 2, side_color = "body" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local u, v = horizontalFaceUvInBounds(got, 1.0, 0, 1, 2, 2)
  check(u and close(u, 0.25) and close(v, 0.75),
        "face de topo SLAB busca corpo na vertical quando o run mistura tons")
end

do
  local pixels = {
    [0] = rgba(0.80, 0.80, 0.80, 1),
    [1] = rgba(0.80, 0.80, 0.80, 1),
    [2] = rgba(0.20, 0.20, 0.20, 1),
    [3] = rgba(0.80, 0.80, 0.80, 1),
  }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 2, 2)
  loadWith(makeMod(handle, { depth = 2, side_color = "body" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local u, v = horizontalFaceUvInBounds(got, 0.55, 0, 1, 0, 0)
  check(u and close(u, 0.25) and close(v, 0.25),
        "face de base SLAB busca corpo para cima")
end

do
  local cellW, cellH = 2, 2
  local pixels = {}
  for ly = 0, cellH - 1 do
    for lx = 0, cellW - 1 do paint(pixels, cellW, cellW, 0, lx, ly, 1) end
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  eq(countHorizontalFacesAtY(got, 1.0, 2), 2,
     "face de topo SLAB so aparece onde o pixel acima esta vazio")
  eq(countHorizontalFacesAtY(got, 1.0, 1), 0,
     "face de topo SLAB nao aparece dentro do corpo")
end

do
  local cellW, cellH = 2, 2
  local pixels = {}
  for ly = 0, cellH - 1 do
    for lx = 0, cellW - 1 do paint(pixels, cellW, cellW, 0, lx, ly, 1) end
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  eq(countHorizontalFacesAtY(got, 0.55, 0), 2,
     "face de base SLAB so aparece onde o pixel abaixo esta vazio")
  eq(countHorizontalFacesAtY(got, 0.55, 1), 0,
     "face de base SLAB nao aparece dentro do corpo")
end

do
  local cellW, cellH = 1, 2
  local pixels = { [0] = 1, [1] = 1 }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  eq(countHorizontalFacesAtY(got, 1.0, 1), 0,
     "SLAB nao emite faces coplanares dentro do corpo")
  eq(countHorizontalFacesAtY(got, 0.55, 1), 0,
     "SLAB nao emite bases coplanares dentro do corpo")
end

do
  local cellW, cellH = 3, 1
  local pixels = { [0] = 1, [1] = 1, [2] = 1 }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  eq(countSideFaces(got), 2,
     "face lateral SLAB so aparece onde o pixel ao lado esta vazio")
  eq(countSideFacesAtX(got, 0), 1,
     "face lateral SLAB emite exatamente a borda esquerda exposta")
  eq(countSideFacesAtX(got, 3), 1,
     "face lateral SLAB emite exatamente a borda direita exposta")
  eq(quadCount(got), 10,
     "run horizontal SLAB de tres pixels tem contagem exata de quads")
end

do
  local cellW, cellH = 3, 1
  local pixels = { [0] = 1, [1] = 1, [2] = 1 }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  eq(countSideFacesAtX(got, 1), 0,
     "SLAB nao emite laterais coplanares dentro de um run")
  eq(countSideFacesAtX(got, 2), 0,
     "SLAB nao emite a segunda lateral coplanar dentro de um run")
end

do
  local pixels = { [0] = 1 }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 1, 1)
  loadWith(makeMod(handle, { depth = 2, shape = "slab" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  check(countSideFacesAtX(got, 0) == 1 and countSideFacesAtX(got, 1) == 1,
        "SIDE_INSET zero deixa as laterais SLAB no limite do voxel")
  check(countHorizontalFacesAtY(got, 1.0, 1) == 1
        and countHorizontalFacesAtY(got, 0.55, 0) == 1,
        "SIDE_INSET zero deixa topo e base SLAB no limite do voxel")
end

do
  local cellW, cellH = 1, 6
  local pixels = {
    [0] = rgba(0.20, 0.20, 0.20, 1),
    [1] = rgba(0.20, 0.20, 0.20, 1),
    [2] = rgba(0.20, 0.20, 0.20, 1),
    [3] = rgba(0.20, 0.20, 0.20, 1),
    [4] = rgba(0.20, 0.20, 0.20, 1),
    [5] = rgba(0.80, 0.80, 0.80, 1),
  }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, side_color = "body" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local u, v = horizontalFaceUvInBounds(got, 1.0, 0, 1, 6, 6)
  check(u and close(u, 0.5) and close(v, 0.5 / cellH),
        "face de topo SLAB preserva o contorno quando nao ha corpo em 4 pixels")
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
      return close(v[1], 0) and close(v[6], 0.78)
    end)
  end)
  check(q ~= nil, "folha de um tom so encontra a face lateral")
  check(q and allQuad(got, q, function(v) return close(v[4], 0.25) end),
        "folha de um tom so falha a busca e preserva o UV proprio")
end

do
  local pixels = { [0] = 1 }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 1, 1)
  loadWith(makeMod(handle, { depth = 2, shape = "slab" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local front = quadIndex(got, function(i)
    local b = quadBoundsAt(got, i)
    return close(b.minZ, 0) and close(b.maxZ, 0)
      and allQuad(got, i, function(v) return close(v[6], 0.90) end)
  end)
  check(front ~= nil, "shade frontal SLAB usa 0.90")
end

do
  local pixels = { [0] = 1 }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 1, 1)
  loadWith(makeMod(handle, { depth = 2, shape = "slab" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local left = quadIndex(got, function(i)
    local b = quadBoundsAt(got, i)
    return close(b.minX, 0) and close(b.maxX, 0)
      and allQuad(got, i, function(v) return close(v[6], 0.78) end)
  end)
  local right = quadIndex(got, function(i)
    local b = quadBoundsAt(got, i)
    return close(b.minX, 1) and close(b.maxX, 1)
      and allQuad(got, i, function(v) return close(v[6], 0.78) end)
  end)
  check(left ~= nil and right ~= nil, "shade lateral SLAB permanece simetrico")
end

do
  local pixels = { [0] = 1 }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 1, 1)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", top_edge = "on" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local onlyTop = true
  for i = 1, #got.verts, 4 do
    local b = quadBoundsAt(got, i)
    for j = i, i + 3 do
      if close(got.verts[j][6], 0.82) then
        onlyTop = onlyTop and close(b.minY, 1) and close(b.maxY, 1)
          and b.maxZ > b.minZ
      end
    end
  end
  check(onlyTop and countHorizontalFacesAtY(got, 0.82, 1) == 1,
        "TOP EDGE ligado escurece so a face de topo")
end

do
  local pixels = { [0] = 1 }
  local handleA, modulesA = makeVoxelHandle("1.6.0", pixels, 1, 1)
  loadWith(makeMod(handleA, { depth = 2, shape = "slab" }))
  local defaultMesh = modulesA.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local handleB, modulesB = makeVoxelHandle("1.6.0", pixels, 1, 1)
  loadWith(makeMod(handleB, { depth = 2, shape = "slab", top_edge = "off" }))
  local offMesh = modulesB.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  eq(vertexSignature(offMesh), vertexSignature(defaultMesh),
     "TOP EDGE desligado nao muda nenhum vertice")
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
  local cellW, cellH = 3, 4
  local sheetW = cellW * 6
  local pixels = {}
  for _, frame in ipairs({ 0, 1, 2 }) do
    paint(pixels, sheetW, cellW, frame, 1, 0, rgba(0.05, 0.05, 0.05, 1))
    paint(pixels, sheetW, cellW, frame, 1, 1, rgba(0.80, 0.10, 0.10, 1))
    paint(pixels, sheetW, cellW, frame, 1, 2, rgba(0.05, 0.05, 0.05, 1))
  end
  for _, frame in ipairs({ 3, 4, 5 }) do
    paint(pixels, sheetW, cellW, frame, 1, 1, rgba(0.05, 0.05, 0.05, 1))
    paint(pixels, sheetW, cellW, frame, 1, 2, rgba(0.80, 0.10, 0.10, 1))
    paint(pixels, sheetW, cellW, frame, 1, 3, rgba(0.05, 0.05, 0.05, 1))
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", side_color = "body" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local stand = modules.SpriteBillboards.mesh(def, 0)
  local walk = modules.SpriteBillboards.mesh(def, 3)
  local topU0, topV0 = horizontalFaceUvAt(stand, 1.0, true)
  local topU1, topV1 = horizontalFaceUvAt(walk, 1.0, true)
  check(topU0 and topU1 and close(topU0, topU1) and close(topV0, topV1),
        "face de topo SLAB nao muda classificacao de cor entre frames")
end

do
  local cellW, cellH = 1, 4
  local sheetW = cellW * 6
  local pixels = {}
  -- A partir da v1.3.0 a geometria SLAB e por frame corrente (defeito 1), nao
  -- mais a uniao, entao o parado (linhas 1-3) precisa cobrir a linha que o
  -- andar (linhas 1-2) consulta como referencia de role 0: sem essa
  -- sobreposicao a busca por referencia falha e cai para o proprio frame,
  -- o que so provaria estabilidade trivial.
  for _, frame in ipairs({ 0, 1, 2 }) do
    paint(pixels, sheetW, cellW, frame, 0, 1, rgba(0.05, 0.05, 0.05, 1))
    paint(pixels, sheetW, cellW, frame, 0, 2, rgba(0.80, 0.10, 0.10, 1))
    paint(pixels, sheetW, cellW, frame, 0, 3, rgba(0.05, 0.05, 0.05, 1))
  end
  for _, frame in ipairs({ 3, 4, 5 }) do
    paint(pixels, sheetW, cellW, frame, 0, 1, rgba(0.80, 0.10, 0.10, 1))
    paint(pixels, sheetW, cellW, frame, 0, 2, rgba(0.05, 0.05, 0.05, 1))
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", side_color = "body" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local stand = modules.SpriteBillboards.mesh(def, 0)
  local walk = modules.SpriteBillboards.mesh(def, 3)
  local baseU0, baseV0 = horizontalFaceUvAt(stand, 0.55, false)
  local baseU1, baseV1 = horizontalFaceUvAt(walk, 0.55, false)
  check(baseU0 and baseU1 and close(baseU0, baseU1) and close(baseV0, baseV1),
        "face de base SLAB nao muda classificacao de cor entre frames")
end

do
  local cellW, cellH = 2, 1
  local sheetW = cellW * 6
  local pixels = {}
  paint(pixels, sheetW, cellW, 0, 0, 0, rgba(0.05, 0.05, 0.05, 1))
  paint(pixels, sheetW, cellW, 0, 1, 0, rgba(0.80, 0.10, 0.10, 1))
  paint(pixels, sheetW, cellW, 3, 0, 0, rgba(0.05, 0.05, 0.05, 1))
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", side_color = "body" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local stand = modules.SpriteBillboards.mesh(def, 0)
  local walk = modules.SpriteBillboards.mesh(def, 3)
  local sideU0, sideV0 = sideFaceUvAt(stand, 0, 0, 0, 1)
  local sideU1, sideV1 = sideFaceUvAt(walk, 0, 0, 0, 1)
  check(sideU0 and sideU1 and close(sideU0, sideU1) and close(sideV0, sideV1),
        "face lateral SLAB nao muda classificacao de cor entre frames")
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
  local cellW, cellH = 3, 1
  local sheetW = cellW * 6
  local pixels = {}
  for _, frame in ipairs({ 0, 3 }) do
    paint(pixels, sheetW, cellW, frame, 0, 0, 1)
    paint(pixels, sheetW, cellW, frame, 1, 0, 1)
  end
  for _, frame in ipairs({ 1, 4 }) do
    paint(pixels, sheetW, cellW, frame, 2, 0, 1)
  end
  for _, frame in ipairs({ 2, 5 }) do
    paint(pixels, sheetW, cellW, frame, 0, 0, 1)
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 6,
                                              frameWidth = cellW }, 0)
  eq(projectedCells(got, 1, 3), "0,-1",
     "CARVED usa a vista de costas espelhada para cortar o casco")
end

do
  local cellW, cellH = 3, 1
  local sheetW = cellW * 6
  local pixels = {}
  for _, frame in ipairs({ 0, 3 }) do
    paint(pixels, sheetW, cellW, frame, 0, 0, 1)
  end
  for _, frame in ipairs({ 1, 4 }) do
    paint(pixels, sheetW, cellW, frame, 2, 0, 1)
  end
  for _, frame in ipairs({ 2, 5 }) do
    paint(pixels, sheetW, cellW, frame, 0, 0, 1)
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 6,
                                              frameWidth = cellW }, 0)
  check(got and not got.original, "espelho correto preserva voxel assimetrico")
  eq(quadCount(got), 6,
     "espelho invertido da vista de costas removeria o voxel assimetrico")
end

do
  local cellW, cellH = 3, 1
  local sheetW = cellW * 6
  local pixels = {}
  for _, frame in ipairs({ 0, 3 }) do
    paint(pixels, sheetW, cellW, frame, 1, 0, 1)
  end
  for _, frame in ipairs({ 1, 4 }) do
    paint(pixels, sheetW, cellW, frame, 2, 0, 1)
  end
  for _, frame in ipairs({ 2, 5 }) do
    paint(pixels, sheetW, cellW, frame, 0, 0, 1)
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 6,
                                              frameWidth = cellW }, 0)
  check(got and not got.original,
        "espelho frente-costas ignora a lateral que alarga o bbox global")
  eq(quadCount(got), 6,
     "mirrorX global removeria voxel legitimo quando a lateral alarga o bbox")
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
        and allQuad(mesh, i, function(v) return close(v[6], 0.90) end)
    end
  end
  local backPlane = function(i)
    local b = quadBoundsAt(back, i)
    return close(b.minZ, 0) and close(b.maxZ, 0)
      and allQuad(back, i, function(v) return close(v[6], 0.68) end)
  end
  eq(projectedCells(front, 1, 2, frontPlane(front)),
     "1,1;2,1;2,2",
     "silhueta CARVED de frente bate em posicao absoluta com frame 0")
  eq(projectedCells(back, 1, 2, backPlane), "1,1;2,1",
     "silhueta CARVED de costas fica espelhada em posicao absoluta")
  eq(projectedCells(side),
     "0,1;0,2;1,2;2,1",
     "silhueta CARVED lateral bate em posicao absoluta com frame 2")
  check(projectedCells(side) ~= projectedCells(front, 1, 2, frontPlane(front)),
        "frame lateral com rotacao zerada quebraria a silhueta")
  eq(projectedCells(side, 1, 3), "0,-2;0,-3;1,-2;2,-2;2,-3",
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
  for _, frame in ipairs({ 0, 3 }) do
    paint(pixels, sheetW, cellW, frame, 0, 1, 1)
  end
  for _, frame in ipairs({ 1, 4 }) do
    paint(pixels, sheetW, cellW, frame, 2, 1, 1)
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
  local cellW, cellH = 3, 4
  local sheetW = cellW * 6
  local pixels = {}
  for _, frame in ipairs({ 0, 1, 2 }) do
    paint(pixels, sheetW, cellW, frame, 1, 0, rgba(0.05, 0.05, 0.05, 1))
    paint(pixels, sheetW, cellW, frame, 1, 1, rgba(0.80, 0.10, 0.10, 1))
    paint(pixels, sheetW, cellW, frame, 1, 2, rgba(0.05, 0.05, 0.05, 1))
  end
  for _, frame in ipairs({ 3, 4, 5 }) do
    paint(pixels, sheetW, cellW, frame, 1, 1, rgba(0.05, 0.05, 0.05, 1))
    paint(pixels, sheetW, cellW, frame, 1, 2, rgba(0.80, 0.10, 0.10, 1))
    paint(pixels, sheetW, cellW, frame, 1, 3, rgba(0.05, 0.05, 0.05, 1))
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved", side_color = "body" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local stand = modules.SpriteBillboards.mesh(def, 0)
  local walk = modules.SpriteBillboards.mesh(def, 3)
  local topU0, topV0 = horizontalFaceUvAt(stand, 1.0, true)
  local topU1, topV1 = horizontalFaceUvAt(walk, 1.0, true)
  check(topU0 and topU1 and close(topU0, topU1) and close(topV0, topV1),
        "face de topo CARVED nao muda classificacao de cor entre frames")
end

do
  local cellW, cellH = 1, 3
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do
    paint(pixels, sheetW, cellW, frame, 0, 1, rgba(0.80, 0.10, 0.10, 1))
    paint(pixels, sheetW, cellW, frame, 0, 2, rgba(0.05, 0.05, 0.05, 1))
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved", side_color = "body" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 6,
                                              frameWidth = cellW }, 0)
  local _, baseV = horizontalFaceUvAt(got, 0.55, false)
  check(baseV and close(baseV, 1.5 / cellH),
        "face de base CARVED usa o corpo acima para estabilizar a cor")
end

do
  local cellW, cellH = 3, 2
  local sheetW = cellW * 6
  local pixels = {}
  for _, frame in ipairs({ 0, 3 }) do
    paint(pixels, sheetW, cellW, frame, 0, 0, rgba(0.90, 0.90, 0.90, 1))
    paint(pixels, sheetW, cellW, frame, 1, 0, rgba(0.60, 0.60, 0.60, 1))
    paint(pixels, sheetW, cellW, frame, 2, 0, rgba(0.30, 0.30, 0.30, 1))
    paint(pixels, sheetW, cellW, frame, 0, 1, rgba(0.05, 0.05, 0.05, 1))
  end
  for _, frame in ipairs({ 1, 4 }) do
    for lx = 0, cellW - 1 do
      paint(pixels, sheetW, cellW, frame, lx, 0, rgba(0.90, 0.90, 0.90, 1))
    end
  end
  for _, frame in ipairs({ 2, 5 }) do
    for sx = 0, cellW - 1 do
      paint(pixels, sheetW, cellW, frame, sx, 0, rgba(0.90, 0.90, 0.90, 1))
    end
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved_plus" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 6,
                                              frameWidth = cellW }, 0)
  local lightZ = frontFaceZAt(got, 0, 1, 1, 2)
  local midZ = frontFaceZAt(got, 1, 2, 1, 2)
  local darkZ = frontFaceZAt(got, 2, 3, 1, 2)
  check(lightZ and midZ and darkZ, "CARVED+ mantem face frontal nos tres tons")
  check(lightZ > midZ and midZ > darkZ,
        "CARVED+ recua mais os pixels mais escuros")
  check(close(lightZ, 0) and close(midZ, -1) and close(darkZ, -2),
        "CARVED+ aplica recuo proporcional de zero, um e dois passos")
end

do
  local cellW, cellH = 3, 2
  local sheetW = cellW * 6
  local pixels = {}
  for _, frame in ipairs({ 0, 3 }) do
    paint(pixels, sheetW, cellW, frame, 0, 0, rgba(0.90, 0.90, 0.90, 1))
    paint(pixels, sheetW, cellW, frame, 1, 0, rgba(0.60, 0.60, 0.60, 1))
    paint(pixels, sheetW, cellW, frame, 2, 0, rgba(0.30, 0.30, 0.30, 1))
    paint(pixels, sheetW, cellW, frame, 0, 1, rgba(0.05, 0.05, 0.05, 1))
  end
  for _, frame in ipairs({ 1, 4 }) do
    for lx = 0, cellW - 1 do
      paint(pixels, sheetW, cellW, frame, lx, 0, rgba(0.90, 0.90, 0.90, 1))
    end
  end
  for _, frame in ipairs({ 2, 5 }) do
    paint(pixels, sheetW, cellW, frame, 0, 0, rgba(0.90, 0.90, 0.90, 1))
    paint(pixels, sheetW, cellW, frame, 2, 1, rgba(0.90, 0.90, 0.90, 1))
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved_plus" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 6,
                                              frameWidth = cellW }, 0)
  eq(projectedCells(got, 1, 2), "0,1;1,1;2,1",
     "CARVED+ limita o recuo e nao apaga coluna inteira em profundidade 1")
  local lightZ = frontFaceZAt(got, 0, 1, 1, 2)
  local midZ = frontFaceZAt(got, 1, 2, 1, 2)
  local darkZ = frontFaceZAt(got, 2, 3, 1, 2)
  check(lightZ and midZ and darkZ
        and close(lightZ, 0) and close(midZ, 0) and close(darkZ, 0),
        "CARVED+ preserva a camada unica quando nao ha profundidade sobrando")
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
  setShapeWithoutClearing(modules, "carved_plus")
  local c = modules.SpriteBillboards.mesh(def, 0)
  check(a ~= b and b ~= c and a ~= c,
        "cacheKey separa SHAPE mesmo sem limpar o cache")
  eq(modules.Voxel3D.created, 3,
     "cacheKey cria uma entrada propria para cada degrau de SHAPE")
end

do
  local cellW, cellH = 1, 1
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paint(pixels, sheetW, cellW, frame, 0, 0, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", ground_shade = "off" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local a = modules.SpriteBillboards.mesh(def, 0)
  setGroundShadeWithoutClearing(modules, "on")
  local b = modules.SpriteBillboards.mesh(def, 0)
  check(a ~= b, "cacheKey separa GROUND SHADE mesmo sem limpar o cache")
  eq(modules.Voxel3D.created, 2,
     "cacheKey cria uma entrada propria para cada GROUND SHADE")
end

do
  local cellW, cellH = 1, 1
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paint(pixels, sheetW, cellW, frame, 0, 0, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", top_edge = "off" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local a = modules.SpriteBillboards.mesh(def, 0)
  setTopEdgeWithoutClearing(modules, "on")
  local b = modules.SpriteBillboards.mesh(def, 0)
  check(a ~= b, "cacheKey separa TOP EDGE mesmo sem limpar o cache")
  eq(modules.Voxel3D.created, 2,
     "cacheKey cria uma entrada propria para cada TOP EDGE")
end

do
  local cellW, cellH = 1, 1
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paint(pixels, sheetW, cellW, frame, 0, 0, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved", top_edge = "off" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local a = modules.SpriteBillboards.mesh(def, 0)
  setTopEdgeWithoutClearing(modules, "on")
  local b = modules.SpriteBillboards.mesh(def, 0)
  eq(a, b, "cacheKey ignora TOP EDGE quando SHAPE e CARVED")
  eq(modules.Voxel3D.created, 1,
     "CARVED nao duplica malha identica ao trocar TOP EDGE")
end

do
  local cellW, cellH = 1, 7
  local pixels = {}
  for ly = 0, cellH - 1 do paint(pixels, cellW, cellW, 0, 0, ly, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, {
    depth = 2, shape = "slab", ground_shade = "on",
  }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local ok, foundLow, foundHigh = true, false, false
  for i = 1, #got.verts, 4 do
    local b = quadBoundsAt(got, i)
    if close(b.minZ, 0) and close(b.maxZ, 0) then
      for j = i, i + 3 do
        local y = got.verts[j][2]
        local t = y < 6 and math.max(0, y) / 6 or 1
        local expected = 0.90 * (1 - 0.288 * (1 - t))
        if y >= 6 then expected = 0.90 end
        ok = ok and close(got.verts[j][6], expected)
        foundLow = foundLow or (y < 6 and got.verts[j][6] < 0.90)
        foundHigh = foundHigh or (y >= 6 and close(got.verts[j][6], 0.90))
      end
    end
  end
  check(ok and foundLow and foundHigh,
        "contato com o chao escurece so os 6 pixels de baixo")
end

do
  local cellW, cellH = 1, 7
  local pixels = {}
  for ly = 0, cellH - 1 do paint(pixels, cellW, cellW, 0, 0, ly, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, {
    depth = 2, shape = "slab", ground_shade = "off",
  }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local unchanged = true
  for _, v in ipairs(got.verts) do
    unchanged = unchanged and (
      close(v[6], 0.90) or close(v[6], 0.68) or close(v[6], 0.78)
      or close(v[6], 1.0) or close(v[6], 0.55)
    )
  end
  check(unchanged and close(frontVertexShadeAt(got, 0, 0), 0.90),
        "contato com o chao desligado nao muda nenhum vertice")
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

do
  local cellW, cellH = 1, 1
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paint(pixels, sheetW, cellW, frame, 0, 0, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved_plus" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local a = modules.SpriteBillboards.mesh(def, 0)
  setDepthWithoutClearing(modules, 5)
  local b = modules.SpriteBillboards.mesh(def, 0)
  eq(a, b, "cacheKey ignora DEPTH quando SHAPE e CARVED+")
  eq(modules.Voxel3D.created, 1,
     "CARVED+ nao duplica malha identica ao trocar DEPTH")
end

do
  local cellW, cellH = 16, 16
  local pixels = {}
  paintBlinkFace(pixels, cellW, cellW, 0)
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", blink = "off" }))
  local got = modules.SpriteBillboards.mesh({ image = "red.png", frames = 1 }, 0)
  local leftEye = frontQuadIndexAt(got, 6, 7, 8, 9)
  local rightEye = frontQuadIndexAt(got, 9, 10, 8, 9)
  check(leftEye ~= nil and rightEye ~= nil,
        "olho SLAB vira quad proprio mesmo com BLINK desligado")
  check(allUvAt(got, leftEye, 6.5 / 16, 7.5 / 16),
        "olho SLAB aberto aponta para o proprio texel")
end

do
  local cellW, cellH = 16, 16
  local pixels = {}
  paintBlinkFace(pixels, cellW, cellW, 0)
  local closedTime, openTime = blinkTimes("red")
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", blink = "on" }))
  local def = { image = "red.png", frames = 1 }
  withLoveTime(closedTime, function()
    local got = modules.SpriteBillboards.mesh(def, 0)
    local leftEye = frontQuadIndexAt(got, 6, 7, 8, 9)
    check(allUvAt(got, leftEye, 6.5 / 16, 8.5 / 16),
          "piscar acontece no frame 0")
  end)
  withLoveTime(openTime, function()
    local got = modules.SpriteBillboards.mesh(def, 0)
    local leftEye = frontQuadIndexAt(got, 6, 7, 8, 9)
    check(allUvAt(got, leftEye, 6.5 / 16, 7.5 / 16),
          "olho SLAB aberto aponta para o proprio texel")
  end)
end

do
  local cellW, cellH = 16, 16
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paintBlinkFace(pixels, sheetW, cellW, frame) end
  local closedTime, openTime = blinkTimes("red")
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", blink = "on" }))
  local def = { image = "red.png", frames = 6, frameWidth = cellW }
  local backOpen, backClosed, sideOpen, sideClosed
  withLoveTime(openTime, function()
    backOpen = uvSignature(modules.SpriteBillboards.mesh(def, 1))
    sideOpen = uvSignature(modules.SpriteBillboards.mesh(def, 2))
  end)
  withLoveTime(closedTime, function()
    local walk = modules.SpriteBillboards.mesh(def, 3)
    local walkEye = frontQuadIndexAt(walk, 6, 7, 8, 9)
    check(allUvAt(walk, walkEye, (3 * cellW + 6.5) / sheetW, 7.5 / cellH),
          "piscar nao acontece no frame 3")
    backClosed = uvSignature(modules.SpriteBillboards.mesh(def, 1))
    sideClosed = uvSignature(modules.SpriteBillboards.mesh(def, 2))
  end)
  eq(backOpen, backClosed, "piscar so acontece no role 0")
  eq(sideOpen, sideClosed, "piscar so acontece no role 0")
end

do
  local cellW, cellH = 16, 16
  local pixels = {}
  paintBlinkFace(pixels, cellW, cellW, 0)
  local closedTime, openTime = blinkTimes("unknown")
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", blink = "on" }))
  local def = { image = "unknown.png", frames = 1 }
  local openSig, closedSig
  withLoveTime(openTime, function()
    openSig = uvSignature(modules.SpriteBillboards.mesh(def, 0))
  end)
  withLoveTime(closedTime, function()
    closedSig = uvSignature(modules.SpriteBillboards.mesh(def, 0))
  end)
  eq(openSig, closedSig, "folha sem entrada na tabela nao pisca")
end

do
  local cellW, cellH = 16, 16
  local pixels = {}
  paint(pixels, cellW, cellW, 0, 6, 7, rgba(0.05, 0.05, 0.05, 1))
  local closedTime, openTime = blinkTimes("red")
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", blink = "on" }))
  local def = { image = "red.png", frames = 1 }
  local openSig, closedSig
  withLoveTime(openTime, function()
    openSig = uvSignature(modules.SpriteBillboards.mesh(def, 0))
  end)
  withLoveTime(closedTime, function()
    closedSig = uvSignature(modules.SpriteBillboards.mesh(def, 0))
  end)
  eq(openSig, closedSig, "folha cujo olho nao acha corpo em 4 pixels nao pisca")
end

do
  local cellW, cellH = 16, 16
  local pixels = {}
  paintBlinkFace(pixels, cellW, cellW, 0)
  local closedTime, openTime = blinkTimes("red")
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", blink = "off" }))
  local def = { image = "red.png", frames = 1 }
  local openSig, closedSig
  withLoveTime(openTime, function()
    openSig = uvSignature(modules.SpriteBillboards.mesh(def, 0))
  end)
  withLoveTime(closedTime, function()
    closedSig = uvSignature(modules.SpriteBillboards.mesh(def, 0))
  end)
  eq(openSig, closedSig, "BLINK desligado nao muda nenhum UV")
end

do
  local cellW, cellH = 16, 16
  local pixels = {}
  paintBlinkFace(pixels, cellW, cellW, 0)
  local closedTime, openTime = blinkTimes("red")
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", blink = "on" }))
  local def = { image = "red.png", frames = 1 }
  local openMesh, closedMesh
  withLoveTime(openTime, function()
    openMesh = modules.SpriteBillboards.mesh(def, 0)
  end)
  withLoveTime(closedTime, function()
    closedMesh = modules.SpriteBillboards.mesh(def, 0)
  end)
  eq(openMesh, closedMesh, "o cacheKey nao muda com o estado de piscada")
  eq(modules.Voxel3D.created, 1,
     "estado de piscada troca UV sem criar outra malha")
end

-- v1.3.0 defeito 1 (SLAB): a mascara passa a ser a do frame corrente, nao a
-- uniao de todos os frames. Folha de 6 frames (frameWidth=cellW forca layout
-- horizontal) com um pixel exclusivo do frame 0 (lx=0), um pixel exclusivo do
-- frame 3 (lx=1) e uma ancora sempre opaca (lx=3) so para manter a malha viva
-- em todo frame.
do
  local cellW, cellH = 4, 1
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do
    paint(pixels, sheetW, cellW, frame, 3, 0, 1)
  end
  paint(pixels, sheetW, cellW, 0, 0, 0, 1)
  paint(pixels, sheetW, cellW, 3, 1, 0, 1)
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local f0 = modules.SpriteBillboards.mesh(def, 0)
  local f3 = modules.SpriteBillboards.mesh(def, 3)

  check(frontFaceZAt(f0, 0, 1, 0, 1) ~= nil,
        "geometria SLAB usa mascara do frame corrente, nao da uniao (frame 0 tem seu proprio pixel)")
  check(frontFaceZAt(f3, 0, 1, 0, 1) == nil,
        "geometria SLAB usa mascara do frame corrente, nao da uniao")

  -- Se `at()` regredisse para `m.mask` (a uniao), o pixel exclusivo do
  -- frame 0 vazaria para o frame 3 e a asserção acima falharia. Esta cobre o
  -- sentido oposto: o pixel exclusivo do frame 3 tem que aparecer nele
  -- mesmo, nao pode ser cortado por engano.
  check(frontFaceZAt(f3, 1, 2, 0, 1) ~= nil,
        "geometria SLAB nao usa o frame errado no lugar do frame corrente (pixel proprio do frame 3 aparece)")
  -- Num sheet de 6 frames, roleForFrame(3, 6) = 0, entao a referencia de cor
  -- do role 0 e o proprio frame 0 (referenceFramesForRole). Se `at()` fosse
  -- trocado para consultar essa referencia em vez do frame pedido, o pixel
  -- exclusivo do frame 3 sumiria (frame 0 nao o tem), e esta asserção pegaria
  -- isso.
  check(frontFaceZAt(f0, 1, 2, 0, 1) == nil,
        "geometria SLAB nao usa o frame errado no lugar do frame corrente (frame 0 nao tem o pixel do frame 3)")

  local sideAtF0 = sideFaceUvAt(f0, 0, 0, 0, 1)
  local sideAtF3 = sideFaceUvAt(f3, 0, 0, 0, 1)
  check(sideAtF0 ~= nil,
        "face lateral SLAB some quando o pixel some no frame (existe enquanto o pixel existe)")
  check(sideAtF3 == nil,
        "face lateral SLAB some quando o pixel some no frame")
end

-- v1.3.0 defeito 2 (SLAB): X passa a ser relativo a celula do sprite, nao a
-- bbox opaca. Primeira coluna (lx=0) inteiramente transparente; a arte
-- comeca em lx=1, e a malha tem que preservar esse deslocamento em vez de
-- reancorar em X=0 como a bbox opaca faria.
do
  local cellW, cellH = 2, 1
  local pixels = { [1] = 1 }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  check(got and not got.original,
        "geometria SLAB alinha com a celula do sprite: malha construida")
  if got and not got.original then
    local b = meshBounds(got)
    check(close(b.minX, 1),
          "geometria SLAB alinha com a celula do sprite, nao com a bbox opaca")
  end
end

-- v1.3.0 defeito 2b (SLAB): o eixo Y tem a mesma regra que o X. O host pivota
-- o lean no chao, entao y = 0 e a linha de BAIXO da CELULA, nao a linha opaca
-- mais baixa da arte. Celula de duas linhas com arte so na de cima: a malha
-- tem que flutuar um pixel acima do chao, como o card original faz, em vez de
-- reancorar os pes na propria arte. Sao 8 das 67 folhas reais, entre elas
-- poke_ball.png por 2 pixels.
do
  local cellW, cellH = 1, 2
  local pixels = { [0] = 1 }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  check(got and not got.original,
        "geometria SLAB ancora no chao da celula: malha construida")
  if got and not got.original then
    local b = meshBounds(got)
    check(close(b.minY, 1),
          "geometria SLAB ancora no chao da celula, nao na arte mais baixa")
    check(close(b.maxY, 2),
          "geometria SLAB preserva a altura de um pixel acima do chao")
  end
end

-- v1.3.0 defeito B (SLAB): laterais adjacentes na vertical podem virar uma
-- face so quando a amostragem resolvida e exatamente a mesma. A altura
-- infinita aqui e intencional: no stub, ela faz os dois centros de texel terem
-- o mesmo V numerico sem mudar a geometria finita da celula.
do
  local cellW, cellH = 1, 2
  local pixels = { [0] = 1, [1] = 1 }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, math.huge)
  loadWith(makeMod(handle, { depth = 2, shape = "slab" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1,
                                              frameWidth = cellW,
                                              frameHeight = cellH }, 0)
  eq(quadCount(got), 8,
     "face lateral SLAB mescla verticalmente quando o UV coincide")
end

do
  local cellW, cellH = 1, 2
  local pixels = { [0] = 1, [1] = 1 }
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1,
                                              frameWidth = cellW,
                                              frameHeight = cellH }, 0)
  eq(quadCount(got), 10,
     "face lateral SLAB nao mescla quando o UV difere")
end

-- v1.3.0 defeito 2 (CARVED): mesma ancora de X do SLAB. O casco usa as
-- tres vistas, mas o espaco emitido tem que continuar sendo o da celula do
-- sprite. Primeira coluna transparente em todas as vistas; bbox opaca
-- reancoraria a malha em X=0.
do
  local cellW, cellH = 3, 1
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do
    paint(pixels, sheetW, cellW, frame, 1, 0, 1)
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 6,
                                              frameWidth = cellW }, 0)
  check(got and not got.original,
        "geometria CARVED alinha com a celula do sprite: malha construida")
  if got and not got.original then
    local b = meshBounds(got)
    check(close(b.minX, 1),
          "geometria CARVED alinha com a celula do sprite, nao com a bbox opaca")
  end
end

-- v1.3.0 defeito A (CARVED): o espelho frente/costas usa o mesmo eixo de
-- celula que a rotacao por role. A folha e assimetrica dentro da celula:
-- a coluna extra em lx=5 mudaria o eixo da bbox para 6 e apagaria o voxel
-- legitimo do role de costas se `mirrorX` nao fosse `cellW - 1 - lx`.
do
  local cellW, cellH = 6, 1
  local sheetW = cellW * 6
  local pixels = {}
  paint(pixels, sheetW, cellW, 0, 1, 0, 1)
  paint(pixels, sheetW, cellW, 0, 5, 0, 1)
  paint(pixels, sheetW, cellW, 1, 4, 0, 1)
  paint(pixels, sheetW, cellW, 2, 0, 0, 1)
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 6,
                                              frameWidth = cellW }, 1)
  eq(quadCount(got), 6,
     "espelho CARVED usa eixo da celula em folha assimetrica")
  local b = meshBounds(got)
  -- O valor antigo, X 1..2, era a coluna logica antes da rotacao do role 1:
  -- ele passava porque o casco espelhava o X uma vez no `solid` e outra em
  -- p(). A tela precisa receber a coluna 4..5, onde o frame 1 tem arte.
  check(close(b.minX, 4) and close(b.maxX, 5),
        "espelho CARVED posiciona o role de costas no mesmo eixo da celula")
end

-- Role 1 precisa de folha assimetrica para expor o espelho duplo: numa folha
-- simetrica, validar uma coluna e desenhar a outra produz o mesmo resultado.
-- Aqui o frame de costas tem arte em lx=4; o role 1 tambem deve aparecer na
-- coluna de tela 4, porque p() ja faz a unica espelhada de apresentacao.
do
  local cellW, cellH = 6, 1
  local sheetW = cellW * 6
  local pixels = {}
  paint(pixels, sheetW, cellW, 0, 1, 0, 1)
  paint(pixels, sheetW, cellW, 1, 4, 0, 1)
  paint(pixels, sheetW, cellW, 2, 0, 0, 1)
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 6,
                                              frameWidth = cellW }, 1)
  eq(projectedCells(got, 1, 2), "4,0",
     "CARVED role 1 desenha na mesma coluna de tela da arte do frame 1")
end

do
  local cellW, cellH = 6, 2
  local sheetW = cellW * 6
  local pixels = {}
  for ly = 0, 1 do
    paint(pixels, sheetW, cellW, 0, 1, ly, 1)
    paint(pixels, sheetW, cellW, 0, 5, ly, 1)
    paint(pixels, sheetW, cellW, 1, 4, ly, 1)
    paint(pixels, sheetW, cellW, 2, 0, ly, 1)
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 6,
                                              frameWidth = cellW }, 1)
  eq(quadCount(got), 10,
     "intersecao CARVED nao perde corpo com espelho da celula")
end

-- v1.3.0 defeito 2b (CARVED): mesma ancora de Y do SLAB. Rodape vazio na
-- celula deve ficar vazio tambem no casco, em vez de puxar a arte para o chao.
do
  local cellW, cellH = 1, 2
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do
    paint(pixels, sheetW, cellW, frame, 0, 0, 1)
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 6,
                                              frameWidth = cellW }, 0)
  check(got and not got.original,
        "geometria CARVED ancora no chao da celula: malha construida")
  if got and not got.original then
    local b = meshBounds(got)
    check(close(b.minY, 1),
          "geometria CARVED ancora no chao da celula")
    check(close(b.maxY, 2),
          "geometria CARVED preserva o rodape vazio da celula")
  end
end

do
  local cellW, cellH = 4, 3
  local sheetW = cellW * 6
  local pixels = {}
  for _, frame in ipairs({ 0, 3 }) do
    paint(pixels, sheetW, cellW, frame, 1, 1, 1)
  end
  for _, frame in ipairs({ 1, 4 }) do
    paint(pixels, sheetW, cellW, frame, 2, 1, 1)
  end
  for _, frame in ipairs({ 2, 5 }) do
    paint(pixels, sheetW, cellW, frame, 1, 1, 1)
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 6,
                                              frameWidth = cellW }, 0)
  local b = meshBounds(got)
  check(close(b.minX, 1) and close(b.maxX, 2)
        and close(b.minY, 1) and close(b.maxY, 2)
        and close(b.minZ, -1) and close(b.maxZ, 0),
        "geometria CARVED role 0 preserva posicao absoluta na celula")
end

do
  local cellW, cellH = 4, 3
  local sheetW = cellW * 6
  local pixels = {}
  for _, frame in ipairs({ 0, 3 }) do
    paint(pixels, sheetW, cellW, frame, 1, 1, 1)
  end
  for _, frame in ipairs({ 1, 4 }) do
    paint(pixels, sheetW, cellW, frame, 2, 1, 1)
  end
  for _, frame in ipairs({ 2, 5 }) do
    paint(pixels, sheetW, cellW, frame, 1, 1, 1)
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 6,
                                              frameWidth = cellW }, 1)
  local b = meshBounds(got)
  -- O X antigo, 1..2, era o espaco logico da frente vazando para a assercao.
  -- No role 1 a rotacao de p() apresenta esse voxel na coluna de costas,
  -- portanto a posicao absoluta preservada na celula e 2..3.
  check(close(b.minX, 2) and close(b.maxX, 3)
        and close(b.minY, 1) and close(b.maxY, 2)
        and close(b.minZ, -1) and close(b.maxZ, 0),
        "geometria CARVED role 1 preserva posicao absoluta na celula")
end

do
  local cellW, cellH = 4, 3
  local sheetW = cellW * 6
  local pixels = {}
  for _, frame in ipairs({ 0, 3 }) do
    paint(pixels, sheetW, cellW, frame, 1, 1, 1)
  end
  for _, frame in ipairs({ 1, 4 }) do
    paint(pixels, sheetW, cellW, frame, 2, 1, 1)
  end
  for _, frame in ipairs({ 2, 5 }) do
    paint(pixels, sheetW, cellW, frame, 1, 1, 1)
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 6,
                                              frameWidth = cellW }, 2)
  local b = meshBounds(got)
  check(close(b.minX, 1) and close(b.maxX, 2)
        and close(b.minY, 1) and close(b.maxY, 2)
        and close(b.minZ, -3) and close(b.maxZ, -2),
        "geometria CARVED role 2 preserva posicao absoluta na celula")
end

-- v1.3.0 defeito 3 (SLAB e CARVED, o guard roda em voxelMesh antes dos dois):
-- primeira pessoa cai para o card original em vez do solido, porque o shader
-- de primeira pessoa do host move vertices individualmente e um volume
-- atravessa o near plane.
do
  local cellW, cellH = 1, 1
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paint(pixels, sheetW, cellW, frame, 0, 0, 1) end
  local handle, modules, original = makeVoxelHandle("1.6.0", pixels, sheetW, cellH,
    nil, nil, 0.5)
  loadWith(makeMod(handle, { depth = 2, shape = "slab" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local got = modules.SpriteBillboards.mesh(def, 2)
  check(got and got.original, "primeira pessoa devolve o card original")
  eq(got.def, def, "primeira pessoa preserva o def pedido")
  eq(got.frame, 2, "primeira pessoa preserva o frame pedido")
  check(original ~= modules.SpriteBillboards.mesh,
        "primeira pessoa ainda passa pelo wrapper instalado")
end

do
  local cellW, cellH = 1, 1
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paint(pixels, sheetW, cellW, frame, 0, 0, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH,
    nil, nil, 0)
  loadWith(makeMod(handle, { depth = 2, shape = "slab" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local got = modules.SpriteBillboards.mesh(def, 2)
  check(got and not got.original,
        "primeira pessoa com blend zero mantem a malha solida")
end

do
  local cellW, cellH = 1, 1
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paint(pixels, sheetW, cellW, frame, 0, 0, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH,
    nil, nil, nil, true)
  loadWith(makeMod(handle, { depth = 2, shape = "slab" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local got = modules.SpriteBillboards.mesh(def, 2)
  check(got and not got.original,
        "primeira pessoa sem FirstPerson no host mantem a malha solida")
end

T.finish("voxel_chars_test")
