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

-- v1.4.2, pente fino (item 5): trava do snapshot de pixels da lorelei. O
-- teste real de arte abaixo nao le assets/generated/sprites/lorelei.png em
-- tempo de execucao (nao ha decodificador PNG disponivel dentro do luajit
-- puro, so dentro do love real), entao os pixels foram extraidos uma vez e
-- viraram paint() fixos. Sem trava, se a arte for redesenhada a suite
-- continua verde contra pixels velhos e a marca de olho pode passar a
-- fechar sobre pele sem nenhum teste pegando, o defeito da v1.4.1 de
-- volta. FNV-1a em vez de sha256 porque nao precisa de biblioteca de
-- criptografia, so bit.bxor (LuaJIT builtin) e leitura de arquivo; e um
-- checksum de integridade, nao seguranca, entao a colisao teorica nao
-- importa aqui. Se este check falhar, a arte mudou: rode
-- tools/render (real, com PNG de verdade) pra reextrair os pixels e
-- atualize tanto o snapshot quanto este numero.
local function fnv1aFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  local bit = require("bit")
  local hash = 2166136261
  for i = 1, #data do
    hash = bit.bxor(hash, data:byte(i))
    hash = (hash * 16777619) % 4294967296
  end
  return hash
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

local function paintBlinkSide(pixels, sheetW, cellW, frame)
  local skin = rgba(0.80, 0.55, 0.40, 1)
  local eye = rgba(0.05, 0.05, 0.05, 1)
  for lx = 4, 8 do paint(pixels, sheetW, cellW, frame, lx, 7, skin) end
  paint(pixels, sheetW, cellW, frame, 5, 7, eye)
  paint(pixels, sheetW, cellW, frame, 5, 8, skin)
end

-- v1.4.2: mesma folha de paintBlinkFace, descida `dy` linhas, para simular
-- o passo da caminhada (frame 3 = frame 0 descido uma linha na arte real).
local function paintBlinkFaceShifted(pixels, sheetW, cellW, frame, dy)
  local skin = rgba(0.80, 0.55, 0.40, 1)
  local eye = rgba(0.05, 0.05, 0.05, 1)
  for lx = 5, 10 do paint(pixels, sheetW, cellW, frame, lx, 7 + dy, skin) end
  paint(pixels, sheetW, cellW, frame, 6, 7 + dy, eye)
  paint(pixels, sheetW, cellW, frame, 9, 7 + dy, eye)
  paint(pixels, sheetW, cellW, frame, 6, 8 + dy, skin)
  paint(pixels, sheetW, cellW, frame, 9, 8 + dy, skin)
end

-- v1.4.2: mesma silhueta (mesma opacidade, mesmas celulas) de
-- paintBlinkFaceShifted, mas sem nenhum pixel de tom de olho: simula uma
-- cabeca redesenhada de verdade, onde poseOffset ainda acha o deslocamento
-- certo (a silhueta bate) mas a marca de olho nao transfere porque o tom
-- mudou.
local function paintBlinkFaceRedrawn(pixels, sheetW, cellW, frame, dy)
  local skin = rgba(0.95, 0.70, 0.55, 1)
  for lx = 5, 10 do paint(pixels, sheetW, cellW, frame, lx, 7 + dy, skin) end
  paint(pixels, sheetW, cellW, frame, 6, 7 + dy, skin)
  paint(pixels, sheetW, cellW, frame, 9, 7 + dy, skin)
  paint(pixels, sheetW, cellW, frame, 6, 8 + dy, skin)
  paint(pixels, sheetW, cellW, frame, 9, 8 + dy, skin)
end

local function paintBlinkSideShifted(pixels, sheetW, cellW, frame, dy)
  local skin = rgba(0.80, 0.55, 0.40, 1)
  local eye = rgba(0.05, 0.05, 0.05, 1)
  for lx = 4, 8 do paint(pixels, sheetW, cellW, frame, lx, 7 + dy, skin) end
  paint(pixels, sheetW, cellW, frame, 5, 7 + dy, eye)
  paint(pixels, sheetW, cellW, frame, 5, 8 + dy, skin)
end

local function paintBlinkSideRedrawn(pixels, sheetW, cellW, frame, dy)
  local skin = rgba(0.95, 0.70, 0.55, 1)
  for lx = 4, 8 do paint(pixels, sheetW, cellW, frame, lx, 7 + dy, skin) end
  paint(pixels, sheetW, cellW, frame, 5, 7 + dy, skin)
  paint(pixels, sheetW, cellW, frame, 5, 8 + dy, skin)
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

-- v1.4.2: le o valor atual da row de STATUS, recalculado toda vez (nunca
-- cacheado), do mesmo jeito que o menu de opcoes leria.
local function statusRowValue(mod)
  local rows = {}
  mod._rows["ui.options.rows"](function(_, r) return r end, {}, rows)
  for _, row in ipairs(rows) do
    if row.label == "STATUS" then return row.value() end
  end
end

do
  local manifest = readJson(MANIFEST_PATH)
  local seen = {}
  for _, id in ipairs(manifest.optional_dependencies or {}) do seen[id] = true end
  check(seen.BATTLE_ART_VOXEL_FORK and seen.DRAMALESS_SHAPE
        and seen.DRAMATIC_SHAPE,
        "optional_dependencies lista os tres ids")
end

-- v1.4.2: decidir por capacidade, nao por numero de versao. Media de Kim
-- antes desta mudanca: "banana" (versao ilegivel) era ACEITO e "1.3.1"
-- (versao legivel, mas fora da faixa, com a API inteira presente) era
-- RECUSADO. Os testes abaixo trocam de lugar essa inversao.

do
  -- host com versao fora da faixa e API inteira e aceito, com aviso. Testa
  -- o proprio numero que Kim mediu (1.3.1 contra a faixa >=1.7.0 <2.0.0).
  local pixels = {}
  pixels[0] = 1
  local handle, modules, original = makeVoxelHandle("1.3.1", pixels, 16, 16,
    nil, nil, nil, nil, "BATTLE_ART_VOXEL_FORK")
  local mod = loadWith(makeMod(handle))
  check(modules.SpriteBillboards.mesh ~= original,
        "host com versao fora da faixa e API inteira e aceito")
  check(mod._rows["ui.options.rows"] ~= nil,
        "row aparece mesmo com versao fora da faixa")
  check(mod._logs.warn[1]
        and mod._logs.warn[1]:find("untested version", 1, true)
        and mod._logs.warn[1]:find("BATTLE_ART_VOXEL_FORK", 1, true),
        "versao fora da faixa avisa no log")
end

do
  -- host com versao impossivel de ler e API inteira e aceito. Este e o
  -- teste que representa o report do Angelus (host DRAMALESS_SHAPE 1.6.2.ST).
  local pixels = {}
  pixels[0] = 1
  local handle, modules, original = makeVoxelHandle("1.6.2.ST", pixels, 16, 16,
    nil, nil, nil, nil, "DRAMALESS_SHAPE")
  local mod = loadWith(makeMod(handle))
  check(modules.SpriteBillboards.mesh ~= original,
        "versao ilegivel e aceita com aviso")
  check(mod._logs.warn[1]
        and mod._logs.warn[1]:find("untested version", 1, true)
        and mod._logs.warn[1]:find("unparsable version", 1, true)
        and mod._logs.warn[1]:find("DRAMALESS_SHAPE", 1, true),
        "versao ilegivel loga aviso")
end

do
  -- sem host: a row de STATUS aparece dizendo NO HOST (em vez do vazio de
  -- antes, que fez o Colonel_Aureliano perder vinte minutos numa
  -- reinstalacao limpa e o Angelus achar que era o Wilds of Kanto).
  local mod = loadWith(makeMod(nil))
  check(mod._rows["ui.options.rows"] ~= nil,
        "row de STATUS aparece mesmo sem host suportado")
  local rows = {}
  local out = mod._rows["ui.options.rows"](function(_, r) return r end, {}, rows)
  eq(#out, 1, "sem host, so a row de STATUS aparece")
  eq(out[1].label, "STATUS", "a unica row sem host e STATUS")
  eq(out[1].step, nil, "STATUS e somente leitura, sem step")
  eq(out[1].value(), "NO HOST", "sem host, STATUS diz NO HOST")
  check(mod._logs.warn[1]
        and mod._logs.warn[1]:find("BATTLE_ART_VOXEL_FORK", 1, true)
        and mod._logs.warn[1]:find("DRAMALESS_SHAPE", 1, true)
        and mod._logs.warn[1]:find("DRAMATIC_SHAPE", 1, true),
        "sem host avisa quais ids foram procurados")
end

do
  -- o fork fora da faixa agora e aceito de cara (primeiro na lista de
  -- HOSTS), entao o legado nem chega a ser tentado. Antes desta mudanca o
  -- fork era recusado e o legado assumia; hoje nenhum dos dois e recusado
  -- por versao.
  local pixels = {}
  pixels[0] = 1
  local fork, forkModules, forkOriginal =
    makeVoxelHandle("1.3.1", pixels, 16, 16, nil, nil, nil, nil,
      "BATTLE_ART_VOXEL_FORK")
  local dramatic, dramaticModules, dramaticOriginal =
    makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod({
    BATTLE_ART_VOXEL_FORK = fork,
    DRAMATIC_SHAPE = dramatic,
  }))
  check(forkModules.SpriteBillboards.mesh ~= forkOriginal,
        "fork fora da faixa mas com API inteira e aceito de qualquer forma")
  local dramaticSprite = dramatic.exports.lib.require("SpriteBillboards")
  eq(dramaticSprite.mesh, dramaticOriginal,
     "o legado nem chega a ser tentado quando o fork ja foi aceito")
  check(mod._logs.warn[1] and mod._logs.warn[1]:find("untested version", 1, true),
        "fork fora da faixa loga aviso mas nao e recusado")
end

do
  -- nenhum host utilizavel agora so acontece por falha de capacidade, nao
  -- de versao: os tres ids existem, mas cada um falta um modulo diferente.
  -- O log tem que dizer qual faltou em cada um.
  local function brokenHandle(id, version, missingModule)
    local V = {}
    function V.require(name)
      if name == missingModule then error(missingModule .. " is not available") end
      if name == "Voxel3D" or name == "ImageCache" then return {} end
      if name == "SpriteBillboards" then return { mesh = function() end } end
      error("unexpected module " .. tostring(name))
    end
    return { id = id, version = version, exports = { lib = V } }
  end
  local mod = loadWith(makeMod({
    BATTLE_ART_VOXEL_FORK = brokenHandle("BATTLE_ART_VOXEL_FORK", "1.7.6", "Voxel3D"),
    DRAMALESS_SHAPE = brokenHandle("DRAMALESS_SHAPE", "1.6.2.ST", "ImageCache"),
    DRAMATIC_SHAPE = brokenHandle("DRAMATIC_SHAPE", "1.6.0", "SpriteBillboards"),
  }))
  local warn = mod._logs.warn[1] or ""
  check(warn:find("BATTLE_ART_VOXEL_FORK", 1, true)
        and warn:find("Voxel3D is missing", 1, true)
        and warn:find("DRAMALESS_SHAPE", 1, true)
        and warn:find("ImageCache is missing", 1, true)
        and warn:find("DRAMATIC_SHAPE", 1, true)
        and warn:find("SpriteBillboards is missing", 1, true),
        "nenhum host utilizavel: o log diz qual modulo faltou em cada um")
end

do
  -- host sem Voxel3D e recusado e o log diz qual modulo faltou.
  local V = {}
  function V.require(name)
    if name == "Voxel3D" then error("no Voxel3D on this host") end
    if name == "ImageCache" then return {} end
    if name == "SpriteBillboards" then return { mesh = function() end } end
    error("unexpected module " .. tostring(name))
  end
  local handle = { id = "DRAMATIC_SHAPE", version = "1.6.0", exports = { lib = V } }
  local mod = loadWith(makeMod(handle))
  check(mod._logs.warn[1] and mod._logs.warn[1]:find("Voxel3D is missing", 1, true),
        "host sem Voxel3D e recusado e o log diz qual modulo faltou")
end

do
  -- host cujo SpriteBillboards.mesh nao e funcao e recusado.
  local V = {}
  function V.require(name)
    if name == "Voxel3D" or name == "ImageCache" then return {} end
    if name == "SpriteBillboards" then return { mesh = "not a function" } end
    error("unexpected module " .. tostring(name))
  end
  local handle = { id = "DRAMATIC_SHAPE", version = "1.6.0", exports = { lib = V } }
  local mod = loadWith(makeMod(handle))
  check(mod._logs.warn[1]
        and mod._logs.warn[1]:find("SpriteBillboards.mesh is not a function", 1, true),
        "host cujo SpriteBillboards.mesh nao e funcao e recusado")
end

do
  -- host cujo require estoura e recusado sem derrubar o carregamento do
  -- mod inteiro (o buraco do main.lua original 1750). pcall ao redor de
  -- loadWith prova que o chunk inteiro nao lanca.
  local V = {}
  function V.require(name)
    if name == "Voxel3D" then error("boom inside host require") end
    if name == "ImageCache" then return {} end
    if name == "SpriteBillboards" then return { mesh = function() end } end
    error("unexpected module " .. tostring(name))
  end
  local handle = { id = "DRAMATIC_SHAPE", version = "1.6.0", exports = { lib = V } }
  local ok, mod = pcall(loadWith, makeMod(handle))
  check(ok, "host cujo require estoura nao derruba o carregamento do mod")
  check(ok and mod._logs.warn[1]
        and mod._logs.warn[1]:find("Voxel3D is missing", 1, true),
        "host cujo require estoura e recusado como modulo faltando")
end

do
  -- BLOQUEANTE do pente fino: patch() tem que ser atomico. SpriteBillboards
  -- protegida contra escrita: um proxy vazio cujo __index le de uma tabela
  -- escondida (entao .mesh existe e a sonda de capacidade aceita o host,
  -- porque probeHost so LE .mesh, nunca testa escrita) e cujo __newindex
  -- lanca em QUALQUER atribuicao (entao a folha nunca acumula chaves reais,
  -- diferente de um __newindex normal que so dispara em chave nova). A
  -- segunda escrita arriscada de patch() (spriteBillboards.mesh =
  -- installed) lanca; sem commit atomico, SpriteBillboards ja tinha sido
  -- setada e STATUS lia REPLACED por uma substituicao que nunca aconteceu,
  -- pior que NO HOST porque aponta a investigacao para outro mod
  -- inexistente. Com commit atomico, nenhuma upvalue de modulo e tocada.
  local hidden = { mesh = function() end }
  local frozen = setmetatable({}, {
    __index = hidden,
    __newindex = function() error("attempt to modify a frozen table") end,
  })
  local V = {}
  function V.require(name)
    if name == "Voxel3D" or name == "ImageCache" then return {} end
    if name == "SpriteBillboards" then return frozen end
    error("unexpected module " .. tostring(name))
  end
  local handle = { id = "DRAMATIC_SHAPE", version = "1.6.0", exports = { lib = V } }
  local mod = loadWith(makeMod(handle))
  check(mod._logs.warn[#mod._logs.warn]
        and mod._logs.warn[#mod._logs.warn]:find("could not patch", 1, true)
        and mod._logs.warn[#mod._logs.warn]:find("frozen table", 1, true),
        "tabela protegida contra escrita: patch() falha e loga a causa")
  eq(statusRowValue(mod), "NO HOST",
     "host com tabela protegida contra escrita produz STATUS: NO HOST")
  local rows = {}
  mod._rows["ui.options.rows"](function(_, r) return r end, {}, rows)
  eq(#rows, 1,
     "host com tabela protegida contra escrita nao registra as seis rows")
end

do
  -- pente fino, item 1: a escrita parcial nao pode ficar na tabela do
  -- host. O bloqueante cobriu "as duas escritas falham" (host que bloqueia
  -- tudo); este cobre o caso mais plausivel, um host que protege so a
  -- chave `mesh` (ja existente, nunca vira chave bruta, sempre passa pelo
  -- __newindex) e permite chave nova (assim se defende uma API publica
  -- sem travar extensao). A primeira escrita (__voxelCharactersOriginal,
  -- chave nova) sucede; a segunda (.mesh) lanca. Sem desfazer a primeira,
  -- __voxelCharactersOriginal ficava gravado na tabela do host pra
  -- sempre, mesmo com o patch nunca tendo pegado, contradizendo o README
  -- ("does not modify the Voxel Mod").
  local hidden = { mesh = function() end }
  local guarded = setmetatable({}, {
    __index = hidden,
    __newindex = function(t, k, v)
      if k == "mesh" then error("attempt to modify a frozen table") end
      rawset(t, k, v)
    end,
  })
  local V = {}
  function V.require(name)
    if name == "Voxel3D" or name == "ImageCache" then return {} end
    if name == "SpriteBillboards" then return guarded end
    error("unexpected module " .. tostring(name))
  end
  local handle = { id = "DRAMATIC_SHAPE", version = "1.6.0", exports = { lib = V } }
  local mod = loadWith(makeMod(handle))
  check(mod._logs.warn[#mod._logs.warn]
        and mod._logs.warn[#mod._logs.warn]:find("could not patch", 1, true)
        and mod._logs.warn[#mod._logs.warn]:find("frozen table", 1, true),
        "escrita parcial: patch() falha e loga a causa")
  eq(statusRowValue(mod), "NO HOST",
     "host com escrita parcial produz STATUS: NO HOST")
  eq(rawget(guarded, "__voxelCharactersOriginal"), nil,
     "a escrita parcial e desfeita: a tabela do host fica byte a byte como estava")
  eq(rawget(guarded, "mesh"), nil,
     "mesh nunca chegou a virar chave bruta na tabela do host")
end

do
  -- pente fino, item 1, caso de repatch: se __voxelCharactersOriginal ja
  -- existia de verdade (um patch anterior bem sucedido) e a segunda
  -- escrita falha, o valor anterior tem que voltar, nunca virar nil.
  -- Apagar um __voxelCharactersOriginal legitimo quebraria a cadeia de
  -- chaining que warnChainedMesh depende para detectar quem patcheou
  -- antes da gente.
  local originalMarker = function() end
  local hidden = { mesh = function() end }
  local guarded = setmetatable({ __voxelCharactersOriginal = originalMarker }, {
    __index = hidden,
    __newindex = function(t, k, v)
      if k == "mesh" then error("attempt to modify a frozen table") end
      rawset(t, k, v)
    end,
  })
  local V = {}
  function V.require(name)
    if name == "Voxel3D" or name == "ImageCache" then return {} end
    if name == "SpriteBillboards" then return guarded end
    error("unexpected module " .. tostring(name))
  end
  local handle = { id = "DRAMATIC_SHAPE", version = "1.6.0", exports = { lib = V } }
  loadWith(makeMod(handle))
  eq(rawget(guarded, "__voxelCharactersOriginal"), originalMarker,
     "repatch com escrita parcial: o __voxelCharactersOriginal anterior volta, nao vira nil")
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
  local handle, modules, original = makeVoxelHandle("1.6.2.ST", pixels, 16, 16,
    nil, nil, nil, nil, "DRAMALESS_SHAPE")
  local mod = loadWith(makeMod(handle))
  check(modules.SpriteBillboards.mesh ~= original, "host DRAMALESS_SHAPE e aceito")
  check(mod._logs.info[1]
        and mod._logs.info[1]:find("Dramaless Shape Voxel Mod 1.6.2.ST", 1, true),
        "host DRAMALESS_SHAPE encontrado e logado")
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
  eq(#rows, 8, "hook anexa as rows do voxel characters, mais STATUS")
  eq(rows[2].label, "STATUS", "hook anexa a row de STATUS logo depois do next")
  local option = rows[3]
  eq(rows[4].label, "SIDE COLOR", "hook anexa a row de cor lateral")
  eq(rows[5].label, "SHAPE", "hook anexa a row de shape")
  eq(rows[6].label, "GROUND SHADE", "hook anexa a row de ground shade")
  eq(rows[7].label, "BLINK", "hook anexa a row de blink")
  eq(rows[8].label, "TOP EDGE", "hook anexa a row de top edge")
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
  local option = rows[7]
  eq(option.label, "TOP EDGE", "row de TOP EDGE fica depois de BLINK")
  eq(option.value(), "ON", "TOP EDGE default e ON")
  check(option.step(game, 1), "step de TOP EDGE informa mudanca")
  eq(option.value(), "OFF", "TOP EDGE alterna para OFF")
  eq(game.save.options.modOptions.voxel_characters.top_edge, "off",
     "TOP EDGE persiste no save")
  eq(game.mods.modOptions.voxel_characters.top_edge, "off",
     "TOP EDGE persiste no loader")
  eq(emitted[1].payload.value, "off", "TOP EDGE emite o valor novo")
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
  loadWith(makeMod(handle, { depth = 2, top_edge = "off" }))
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
  loadWith(makeMod(handle, { depth = 2, side_color = "body", top_edge = "off" }))
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
  loadWith(makeMod(handle, { depth = 2, shape = "slab", top_edge = "off" }))
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
  loadWith(makeMod(handle, { depth = 2, shape = "slab", top_edge = "off" }))
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
  loadWith(makeMod(handle, { depth = 2, side_color = "body", top_edge = "off" }))
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
  loadWith(makeMod(handleB, { depth = 2, shape = "slab", top_edge = "on" }))
  local onMesh = modulesB.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  eq(vertexSignature(onMesh), vertexSignature(defaultMesh),
     "TOP EDGE default equivale a ON")
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
  loadWith(makeMod(handle, {
    depth = 2, shape = "slab", side_color = "body", top_edge = "off",
  }))
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

-- v1.4.2: poseOffset compensa o deslocamento entre a pose parada e a
-- andando antes de ler a referencia (AngelusRole: "when a character's head
-- is set to use the body color, the top of the head flickers while
-- walking"). Os testes de classificacao acima usam so 3 tons e nao pegavam
-- o defeito porque a busca de corpo por outline caia na mesma faixa por
-- coincidencia; os testes abaixo isolam o deslocamento em si.

do
  -- poseOffset acha o deslocamento de uma linha: o frame 3 e o frame 0
  -- descido uma linha. Tres tons (nao so 2) para que qualquer deslocamento
  -- errado, nao so "sem deslocamento", resolva para um tom diferente do
  -- topo parado.
  local cellW, cellH = 1, 6
  local sheetW = cellW * 6
  local pixels = {}
  local toneA = rgba(0.95, 0.95, 0.95, 1)
  local toneB = rgba(0.55, 0.55, 0.55, 1)
  local red = rgba(0.80, 0.10, 0.10, 1)
  for _, frame in ipairs({ 0, 1, 2 }) do
    paint(pixels, sheetW, cellW, frame, 0, 0, toneA)
    paint(pixels, sheetW, cellW, frame, 0, 1, toneB)
    paint(pixels, sheetW, cellW, frame, 0, 2, red)
  end
  for _, frame in ipairs({ 3, 4, 5 }) do
    paint(pixels, sheetW, cellW, frame, 0, 1, toneA)
    paint(pixels, sheetW, cellW, frame, 0, 2, toneB)
    paint(pixels, sheetW, cellW, frame, 0, 3, red)
  end
  -- ancora escura para fixar outlineLuma longe dos tons do teste, senao o
  -- tom mais escuro do proprio teste (red) vira contorno por ser o minimo.
  paint(pixels, sheetW, cellW, 1, 0, 5, rgba(0.02, 0.02, 0.02, 1))
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, {
    depth = 2, shape = "slab", side_color = "body", top_edge = "off",
  }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local stand = modules.SpriteBillboards.mesh(def, 0)
  local walk = modules.SpriteBillboards.mesh(def, 3)
  local topU0, topV0 = horizontalFaceUvAt(stand, 1.0, true)
  local topU1, topV1 = horizontalFaceUvAt(walk, 1.0, true)
  check(topU0 and topU1 and close(topU0, topU1) and close(topV0, topV1),
        "poseOffset acha o deslocamento de uma linha")
end

do
  -- poseOffset devolve zero quando as poses coincidem: o caso das 6 folhas
  -- que nao deslocam. Checa topo E base porque, sozinha, cada uma mascara
  -- um dos dois sinais errados via o fallback sem compensar (topo nao pega
  -- dy=-1 errado, base nao pega dy=+1 errado); as duas juntas pegam os dois.
  local cellW, cellH = 1, 4
  local sheetW = cellW * 6
  local pixels = {}
  local toneA = rgba(0.95, 0.95, 0.95, 1)
  local toneB = rgba(0.55, 0.55, 0.55, 1)
  local red = rgba(0.80, 0.10, 0.10, 1)
  for _, frame in ipairs({ 0, 1, 2, 3, 4, 5 }) do
    paint(pixels, sheetW, cellW, frame, 0, 0, toneA)
    paint(pixels, sheetW, cellW, frame, 0, 1, toneB)
    paint(pixels, sheetW, cellW, frame, 0, 2, red)
  end
  paint(pixels, sheetW, cellW, 1, 0, 3, rgba(0.02, 0.02, 0.02, 1))
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, {
    depth = 2, shape = "slab", side_color = "body", top_edge = "off",
  }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local stand = modules.SpriteBillboards.mesh(def, 0)
  local walk = modules.SpriteBillboards.mesh(def, 3)
  local topU0, topV0 = horizontalFaceUvAt(stand, 1.0, true)
  local topU1, topV1 = horizontalFaceUvAt(walk, 1.0, true)
  local baseU0, baseV0 = horizontalFaceUvAt(stand, 0.55, false)
  local baseU1, baseV1 = horizontalFaceUvAt(walk, 0.55, false)
  check(topU0 and topU1 and close(topU0, topU1) and close(topV0, topV1)
        and baseU0 and baseU1 and close(baseU0, baseU1) and close(baseV0, baseV1),
        "poseOffset devolve zero quando as poses coincidem")
end

do
  -- poseOffset desempata de forma deterministica: folha onde o frame 3 tem
  -- um unico pixel opaco e o frame 0 tem dois, um uma linha acima e outro
  -- uma linha abaixo dele, entao dy=-1 e dy=1 empatam em |dx|+|dy|. A
  -- varredura canonica roda sempre de 0 (o menor indice) pra 3, entao a
  -- regra "empate, menor dy" decide poseOffset(0,3) = (0,-1); a chamada
  -- real e na direcao oposta, poseOffset(3,0), que e o negativo por
  -- construcao: (0,1). Compensado, a linha 2 do frame 3 aponta pra linha 3
  -- do frame 0 (toneQ), nao a linha 1 (pente fino, item 2: antes da
  -- canonicalizacao, cada direcao escaneava pro seu lado e "menor dy"
  -- escolhia -1 nas DUAS direcoes, quebrando poseOffset(A,B) ==
  -- -poseOffset(B,A)). Roda a mesma folha sob dois nomes de imagem
  -- diferentes (o stub de ImageCache ignora o nome e devolve os mesmos
  -- pixels) para forcar duas mascaras e duas varreduras independentes,
  -- provando que o desempate nao depende de cache nem de ordem de
  -- varredura incidental.
  local cellW, cellH = 1, 5
  local sheetW = cellW * 6
  local pixels = {}
  local toneP = rgba(0.40, 0.40, 0.40, 1)
  local toneQ = rgba(0.65, 0.65, 0.65, 1)
  local red = rgba(0.80, 0.10, 0.10, 1)
  paint(pixels, sheetW, cellW, 0, 0, 1, toneP)
  paint(pixels, sheetW, cellW, 0, 0, 3, toneQ)
  paint(pixels, sheetW, cellW, 3, 0, 2, red)
  paint(pixels, sheetW, cellW, 1, 0, 0, rgba(0.02, 0.02, 0.02, 1))
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, {
    depth = 2, shape = "slab", side_color = "body", top_edge = "off",
  }))
  local defA = { image = "sheet_a.png", frames = 6, frameWidth = cellW }
  local defB = { image = "sheet_b.png", frames = 6, frameWidth = cellW }
  local walkA = modules.SpriteBillboards.mesh(defA, 3)
  local walkB = modules.SpriteBillboards.mesh(defB, 3)
  local cellBottom = cellH - 1
  -- face de topo e um plano horizontal: Y e constante (cellBottom - ly + 1),
  -- nao uma faixa, entao minY e maxY tem que ser o mesmo valor.
  local topY = cellBottom - 2 + 1
  local expectedU = (0 + 0.5) / sheetW
  local expectedV = (3 + 0.5) / cellH
  local uA, vA = horizontalFaceUvInBounds(walkA, 1.0, 0, 1, topY, topY)
  local uB, vB = horizontalFaceUvInBounds(walkB, 1.0, 0, 1, topY, topY)
  check(uA and close(uA, expectedU) and close(vA, expectedV),
        "poseOffset desempata de forma deterministica: canonicaliza pro menor indice de frame")
  check(uB and close(uB, expectedU) and close(vB, expectedV),
        "poseOffset desempata de forma deterministica: repete numa varredura independente")
end

do
  -- pente fino, item 4: o teste acima (e o de repeticao entre duas
  -- varreduras) prova so REPETIBILIDADE, que continua verdadeira mesmo
  -- se o bloco de desempate explicito for apagado (a lente C removeu o
  -- bloco inteiro, deixando so `score > bestScore`, e a suite inteira
  -- passou: sem o bloco, empate vira "o primeiro que o laco encontrar
  -- fica", que E deterministico, so que segue a ORDEM DO LACO (dy de -3 a
  -- 3 por fora, dx de -2 a 2 por dentro: empate "ganha" o menor dy, sem
  -- olhar |dx|+|dy|), nao a politica documentada (menor |dx|+|dy|
  -- primeiro). Dataset que distingue as duas: A opaco so em (0,3); B
  -- opaco em (2,0) [dx=2,dy=-3, o PRIMEIRO candidato que o laco visita,
  -- |dx|+|dy|=5] e em (0,4) [dx=0,dy=1, visitado bem depois, |dx|+|dy|=1].
  -- Os dois empatam em score=1, e so esses dois pontuam. A ordem do laco
  -- escolheria (2,-3) porque dy=-3 vem primeiro; a politica documentada
  -- escolhe (0,1) porque |dx|+|dy|=1 e menor que 5. So um teste que espera
  -- (0,1) pega um dev futuro apagando o bloco de desempate num refactor.
  local cellW, cellH = 3, 7
  local sheetW = cellW * 6
  local pixels = {}
  paint(pixels, sheetW, cellW, 0, 0, 3, 1)
  paint(pixels, sheetW, cellW, 3, 2, 0, 1)
  paint(pixels, sheetW, cellW, 3, 0, 4, 1)
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local function getUpvalue(fn, name)
    for i = 1, 80 do
      local n, v = debug.getupvalue(fn, i)
      if n == nil then break end
      if n == name then return v end
    end
  end
  local wrapper = modules.SpriteBillboards.mesh
  local voxelMeshFn = getUpvalue(wrapper, "voxelMesh")
  local buildSelectedMeshFn = getUpvalue(voxelMeshFn, "buildSelectedMesh")
  local buildCarvedMeshFn = getUpvalue(buildSelectedMeshFn, "buildCarvedMesh")
  local poseOffsetFn = getUpvalue(buildCarvedMeshFn, "poseOffset")
  check(type(poseOffsetFn) == "function",
        "teste encontra poseOffset (desempate distingue politica de ordem)")

  local fakeM = {
    data = fakeImage(pixels, sheetW, cellH),
    sheetW = sheetW, sheetH = cellH,
    frames = 6, cellW = cellW, cellH = cellH, columns = 6,
  }
  local dx, dy = poseOffsetFn(fakeM, 0, 3)
  eq(dx, 0, "empate: a politica de menor |dx|+|dy| vence a ordem do laco em X")
  eq(dy, 1, "empate: a politica de menor |dx|+|dy| vence a ordem do laco em Y")
end

do
  -- a face de topo da coroa resolve para o mesmo texel nos dois frames: o
  -- teste que representa o report do Angelus. Folha de 3 colunas com
  -- deslocamento de uma linha; pega a face de topo da coluna do meio no
  -- frame parado e no frame andando e prova que aponta para o mesmo tom.
  local cellW, cellH = 3, 5
  local sheetW = cellW * 6
  local pixels = {}
  local toneA = rgba(0.95, 0.95, 0.95, 1)
  local toneB = rgba(0.60, 0.60, 0.60, 1)
  local red = rgba(0.80, 0.10, 0.10, 1)
  local dark = rgba(0.05, 0.05, 0.05, 1)
  for _, frame in ipairs({ 0, 1, 2 }) do
    for lx = 0, cellW - 1 do
      paint(pixels, sheetW, cellW, frame, lx, 0, toneA)
      paint(pixels, sheetW, cellW, frame, lx, 1, toneB)
      paint(pixels, sheetW, cellW, frame, lx, 2, red)
      paint(pixels, sheetW, cellW, frame, lx, 3, dark)
    end
  end
  for _, frame in ipairs({ 3, 4, 5 }) do
    for lx = 0, cellW - 1 do
      paint(pixels, sheetW, cellW, frame, lx, 1, toneA)
      paint(pixels, sheetW, cellW, frame, lx, 2, toneB)
      paint(pixels, sheetW, cellW, frame, lx, 3, red)
      paint(pixels, sheetW, cellW, frame, lx, 4, dark)
    end
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, {
    depth = 2, shape = "slab", side_color = "body", top_edge = "off",
  }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local stand = modules.SpriteBillboards.mesh(def, 0)
  local walk = modules.SpriteBillboards.mesh(def, 3)
  local cellBottom = cellH - 1
  -- face de topo e um plano horizontal: Y e constante (cellBottom - ly + 1),
  -- nao uma faixa, entao minY e maxY tem que ser o mesmo valor.
  local standU, standV = horizontalFaceUvInBounds(stand, 1.0, 1, 2,
    cellBottom - 0 + 1, cellBottom - 0 + 1)
  local walkU, walkV = horizontalFaceUvInBounds(walk, 1.0, 1, 2,
    cellBottom - 1 + 1, cellBottom - 1 + 1)
  check(standU and walkU and close(standU, walkU) and close(standV, walkV),
        "a face de topo da coroa resolve para o mesmo texel nos dois frames")
end

do
  -- o equivalente do teste da coroa para a face lateral (sideUv). Coluna
  -- unica de 2 pixels (tom de corpo e contorno) que desce uma linha ao
  -- andar; sem compensar, a leitura sem sucesso da referencia cai no
  -- contorno em vez do corpo, porque a folha de 1 pixel de largura nao tem
  -- coluna vizinha para a busca interna alcancar.
  local cellW, cellH = 1, 3
  local sheetW = cellW * 6
  local pixels = {}
  local toneA = rgba(0.90, 0.90, 0.90, 1)
  local dark = rgba(0.05, 0.05, 0.05, 1)
  for _, frame in ipairs({ 0, 1, 2 }) do
    paint(pixels, sheetW, cellW, frame, 0, 0, toneA)
    paint(pixels, sheetW, cellW, frame, 0, 1, dark)
  end
  for _, frame in ipairs({ 3, 4, 5 }) do
    paint(pixels, sheetW, cellW, frame, 0, 1, toneA)
    paint(pixels, sheetW, cellW, frame, 0, 2, dark)
  end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, {
    depth = 2, shape = "slab", side_color = "body", top_edge = "off",
  }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local stand = modules.SpriteBillboards.mesh(def, 0)
  local walk = modules.SpriteBillboards.mesh(def, 3)
  local cellBottom = cellH - 1
  local standU, standV = sideFaceUvAt(stand, 0, 0, cellBottom - 0, cellBottom - 0 + 1)
  local walkU, walkV = sideFaceUvAt(walk, 0, 0, cellBottom - 1, cellBottom - 1 + 1)
  check(standU and walkU and close(standU, walkU) and close(standV, walkV),
        "a face lateral da coroa resolve para o mesmo texel nos dois frames")
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

-- Rodada 2, "o mesmo defeito que voce acabou de corrigir, no
-- buildCarvedMesh" (v1.4.2): topUv e sideUv do CARVED tem a mesma estrutura
-- de busca por frame de referencia que o SLAB tinha, sem compensar o passo.
-- O teste de classificacao acima nao pega isso pelo mesmo motivo do SLAB:
-- so 2 tons, entao a busca de corpo cai na mesma faixa por coincidencia.

do
  -- a face de topo E a face lateral da coroa do CARVED resolvem para o
  -- mesmo texel nos dois frames. Tres vistas (frente, costas, perfil), com
  -- deslocamento de uma linha em todas; a de perfil so pinta a coluna 0 de
  -- proposito, para so existir uma face lateral por linha (sem isso, varias
  -- profundidades dariam varias faces laterais na mesma borda e o teste
  -- nao saberia qual delas checar).
  local cellW, cellH = 3, 6
  local sheetW = cellW * 6
  local pixels = {}
  local toneA = rgba(0.95, 0.95, 0.95, 1)
  local toneB = rgba(0.60, 0.60, 0.60, 1)
  local red = rgba(0.80, 0.10, 0.10, 1)
  local dark = rgba(0.05, 0.05, 0.05, 1)
  for _, frame in ipairs({ 0, 1 }) do
    for lx = 0, cellW - 1 do
      paint(pixels, sheetW, cellW, frame, lx, 0, toneA)
      paint(pixels, sheetW, cellW, frame, lx, 1, toneB)
      paint(pixels, sheetW, cellW, frame, lx, 2, red)
      paint(pixels, sheetW, cellW, frame, lx, 3, dark)
    end
  end
  for _, frame in ipairs({ 3, 4 }) do
    for lx = 0, cellW - 1 do
      paint(pixels, sheetW, cellW, frame, lx, 1, toneA)
      paint(pixels, sheetW, cellW, frame, lx, 2, toneB)
      paint(pixels, sheetW, cellW, frame, lx, 3, red)
      paint(pixels, sheetW, cellW, frame, lx, 4, dark)
    end
  end
  paint(pixels, sheetW, cellW, 2, 0, 0, toneA)
  paint(pixels, sheetW, cellW, 2, 0, 1, toneB)
  paint(pixels, sheetW, cellW, 2, 0, 2, red)
  paint(pixels, sheetW, cellW, 2, 0, 3, dark)
  paint(pixels, sheetW, cellW, 5, 0, 1, toneA)
  paint(pixels, sheetW, cellW, 5, 0, 2, toneB)
  paint(pixels, sheetW, cellW, 5, 0, 3, red)
  paint(pixels, sheetW, cellW, 5, 0, 4, dark)
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved", side_color = "body" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local stand = modules.SpriteBillboards.mesh(def, 0)
  local walk = modules.SpriteBillboards.mesh(def, 3)
  local cellBottom = cellH - 1
  local standTopU, standTopV = horizontalFaceUvInBounds(stand, 1.0, 1, 2,
    cellBottom - 0 + 1, cellBottom - 0 + 1)
  local walkTopU, walkTopV = horizontalFaceUvInBounds(walk, 1.0, 1, 2,
    cellBottom - 1 + 1, cellBottom - 1 + 1)
  check(standTopU and walkTopU and close(standTopU, walkTopU)
        and close(standTopV, walkTopV),
        "CARVED: a face de topo da coroa resolve para o mesmo texel nos dois frames")
  local standSideU, standSideV = sideFaceUvAt(stand, 0, 0, cellBottom - 0,
    cellBottom - 0 + 1)
  local walkSideU, walkSideV = sideFaceUvAt(walk, 0, 0, cellBottom - 1,
    cellBottom - 1 + 1)
  check(standSideU and walkSideU and close(standSideU, walkSideU)
        and close(standSideV, walkSideV),
        "CARVED: a face lateral da coroa resolve para o mesmo texel nos dois frames")

  -- "confirme que a compensacao entra no espaco de textura e nao no espaco
  -- de geometria": frame 3 (role 0) e frame 4 (role 1) tem o MESMO
  -- pose.front/back/side (o CARVED so gira a malha por role, nao reconstroi
  -- a textura), entao a sequencia de UV emitida tem que ser identica entre
  -- os dois, mesmo com a geometria girada 180 graus no mundo.
  local mesh4 = modules.SpriteBillboards.mesh(def, 4)
  eq(quadCount(walk), quadCount(mesh4),
     "CARVED: role 0 e role 1 do mesmo pose tem a mesma contagem de quads")
  eq(uvSignature(walk), uvSignature(mesh4),
     "CARVED: a compensacao entra no espaco de textura, nao no espaco de geometria")
end

do
  -- poseOffset so compensa entre frames do MESMO role: comparar a mascara
  -- de frente com a de perfil mede diferenca de silhueta, nao passo, e
  -- devolveria um numero com cara de deslocamento que na verdade e lixo.
  -- Extrai poseOffset de dentro de buildCarvedMesh (upvalue) e chama direto,
  -- sem passar pela malha: a fiacao correta do CARVED nunca chama
  -- poseOffset com frames de roles diferentes, entao testar so pela malha
  -- nunca exercitaria este branch.
  local cellW, cellH = 4, 4
  local sheetW = cellW * 6
  local pixels = {}
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local function getUpvalue(fn, name)
    for i = 1, 80 do
      local n, v = debug.getupvalue(fn, i)
      if n == nil then break end
      if n == name then return v end
    end
  end
  local wrapper = modules.SpriteBillboards.mesh
  local voxelMeshFn = getUpvalue(wrapper, "voxelMesh")
  check(type(voxelMeshFn) == "function",
        "teste encontra voxelMesh no wrapper para poseOffset")
  local buildSelectedMeshFn = getUpvalue(voxelMeshFn, "buildSelectedMesh")
  check(type(buildSelectedMeshFn) == "function", "teste encontra buildSelectedMesh")
  local buildCarvedMeshFn = getUpvalue(buildSelectedMeshFn, "buildCarvedMesh")
  check(type(buildCarvedMeshFn) == "function", "teste encontra buildCarvedMesh")
  local poseOffsetFn = getUpvalue(buildCarvedMeshFn, "poseOffset")
  check(type(poseOffsetFn) == "function", "teste encontra poseOffset em buildCarvedMesh")

  -- frame 0 (frente, role 0): um pixel so, no canto.
  paint(pixels, sheetW, cellW, 0, 0, 0, 1)
  -- frame 2 (perfil, role 2): coincidencia adversarial de forma. Um bloco
  -- solido 2 linhas abaixo do pixel de frente; se poseOffset comparasse
  -- frente com perfil por sobreposicao de mascara, dx=0,dy=2 "acharia" 100%
  -- de interseccao, uma leitura confiante e completamente errada.
  paint(pixels, sheetW, cellW, 2, 0, 2, 1)
  local fakeM = {
    data = fakeImage(pixels, sheetW, cellH),
    sheetW = sheetW, sheetH = cellH,
    frames = 6, cellW = cellW, cellH = cellH, columns = 6,
  }
  local guardDx, guardDy = poseOffsetFn(fakeM, 0, 2)
  eq(guardDx, 0, "poseOffset entre roles diferentes nao compensa em X")
  eq(guardDy, 0, "poseOffset entre roles diferentes nao compensa em Y")

  -- controle: o mesmo par de indices, mas do MESMO role (0 e 3, os dois
  -- frente), ainda acha o deslocamento real. Prova que o guard nao trava o
  -- caso legitimo.
  paint(pixels, sheetW, cellW, 3, 0, 1, 1)
  local sameRoleDx, sameRoleDy = poseOffsetFn(fakeM, 0, 3)
  eq(sameRoleDx, 0, "poseOffset entre frames do mesmo role ainda acha X")
  eq(sameRoleDy, 1, "poseOffset entre frames do mesmo role ainda acha Y")
end

do
  -- pente fino, item 2: poseOffset(a,b) tem que ser exatamente o negativo
  -- de poseOffset(b,a), mesmo com empate genuino de score em +dy e -dy.
  -- Dataset do revisor: A (frame 0) opaco so em ly=2; B (frame 3, mesmo
  -- role de A) opaco em ly=1 e ly=3. dy=-1 e dy=1 empatam (cada um alinha
  -- A com um dos dois pixels de B). Sem canonicalizar o par pro menor
  -- indice de frame antes de escanear, cada direcao escanearia pro seu
  -- proprio lado e a regra "menor dy" escolheria -1 nas DUAS direcoes,
  -- quebrando a simetria; isso importa porque a compensacao do olho pede
  -- poseOffset(refFrame, frame) e a geometria pede
  -- poseOffset(frame, frameIndex), direcoes opostas do mesmo par.
  local cellW, cellH = 1, 4
  local sheetW = cellW * 6
  local pixels = {}
  paint(pixels, sheetW, cellW, 0, 0, 2, 1)
  paint(pixels, sheetW, cellW, 3, 0, 1, 1)
  paint(pixels, sheetW, cellW, 3, 0, 3, 1)
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved" }))
  local function getUpvalue(fn, name)
    for i = 1, 80 do
      local n, v = debug.getupvalue(fn, i)
      if n == nil then break end
      if n == name then return v end
    end
  end
  local wrapper = modules.SpriteBillboards.mesh
  local voxelMeshFn = getUpvalue(wrapper, "voxelMesh")
  local buildSelectedMeshFn = getUpvalue(voxelMeshFn, "buildSelectedMesh")
  local buildCarvedMeshFn = getUpvalue(buildSelectedMeshFn, "buildCarvedMesh")
  local poseOffsetFn = getUpvalue(buildCarvedMeshFn, "poseOffset")
  check(type(poseOffsetFn) == "function", "teste encontra poseOffset (simetria)")

  local fakeM = {
    data = fakeImage(pixels, sheetW, cellH),
    sheetW = sheetW, sheetH = cellH,
    frames = 6, cellW = cellW, cellH = cellH, columns = 6,
  }
  local ax, ay = poseOffsetFn(fakeM, 0, 3)
  local bx, by = poseOffsetFn(fakeM, 3, 0)
  eq(ay, -1, "poseOffset(a,b) desempata para o menor dy no par canonico")
  eq(bx, -ax, "poseOffset(b,a) e o negativo exato de poseOffset(a,b) em X")
  eq(by, -ay, "poseOffset(b,a) e o negativo exato de poseOffset(a,b) em Y")
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
    depth = 2, shape = "slab", ground_shade = "off", top_edge = "off",
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
  -- v1.4.2: piscar passa a acontecer tambem na pose andando quando a marca
  -- transfere. paintBlinkSide pinta o mesmo texel em todos os frames, sem
  -- nenhum deslocamento entre a pose parada (2) e a andando (5), entao
  -- poseOffset(2, 5) mede (0, 0) e a marca de perfil transfere de forma
  -- trivial: o frame 5 tem que piscar exatamente como o frame 2. Frame 1
  -- (costas) continua sem marca, e sem piscar, porque essa parte nao mudou.
  local cellW, cellH = 16, 16
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paintBlinkSide(pixels, sheetW, cellW, frame) end
  local closedTime, openTime = blinkTimes("red")
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", blink = "on" }))
  local def = { image = "red.png", frames = 6, frameWidth = cellW }
  local backOpen, backClosed
  withLoveTime(openTime, function()
    backOpen = uvSignature(modules.SpriteBillboards.mesh(def, 1))
    local sideWalk = modules.SpriteBillboards.mesh(def, 5)
    local sideWalkEye = frontQuadIndexAt(sideWalk, 5, 6, 8, 9)
    check(allUvAt(sideWalk, sideWalkEye, (5 * cellW + 5.5) / sheetW, 7.5 / cellH),
          "olho SLAB aberto no frame 5 aponta para o proprio texel")
  end)
  withLoveTime(closedTime, function()
    local side = modules.SpriteBillboards.mesh(def, 2)
    local sideEye = frontQuadIndexAt(side, 5, 6, 8, 9)
    check(allUvAt(side, sideEye, (2 * cellW + 5.5) / sheetW, 8.5 / cellH),
          "piscar acontece no frame 2 com a tabela lateral")
    backClosed = uvSignature(modules.SpriteBillboards.mesh(def, 1))
    local sideWalk = modules.SpriteBillboards.mesh(def, 5)
    local sideWalkEye = frontQuadIndexAt(sideWalk, 5, 6, 8, 9)
    check(allUvAt(sideWalk, sideWalkEye, (5 * cellW + 5.5) / sheetW, 8.5 / cellH),
          "piscar agora acontece no frame 5 quando a marca de perfil transfere")
  end)
  eq(backOpen, backClosed, "piscar continua nao acontecendo no frame 1")
end

do
  local cellW, cellH = 16, 16
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paintBlinkSide(pixels, sheetW, cellW, frame) end
  local closedTime, openTime = blinkTimes("unknown")
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", blink = "on" }))
  local def = { image = "unknown.png", frames = 6, frameWidth = cellW }
  local openSig, closedSig
  withLoveTime(openTime, function()
    openSig = uvSignature(modules.SpriteBillboards.mesh(def, 2))
  end)
  withLoveTime(closedTime, function()
    closedSig = uvSignature(modules.SpriteBillboards.mesh(def, 2))
  end)
  eq(openSig, closedSig, "folha sem entrada lateral nao pisca de perfil")
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

-- v1.4.2, "os personagens so piscam parados": a pose andando (frames 3 e 5)
-- passa a piscar quando a marca de olho transfere, medido folha a folha e
-- pose a pose via poseOffset, nunca por tabela escrita a mao. O frame 3 ja
-- mordeu este projeto uma vez na v1.4.1 (piscada validada so no frame 0,
-- fechando o "olho" em cima de pele no frame 3 porque a face desce uma
-- linha ao andar); os dois testes de frame 3 abaixo sao os mais
-- importantes do lote.

do
  -- a pose andando pisca quando o olho transfere: frame 3 e o frame 0
  -- descido uma linha (o passo da caminhada), a marca de frente transfere,
  -- e o quad de olho do frame 3 aponta para o texel certo, aberto e
  -- fechado.
  local cellW, cellH = 16, 18
  local sheetW = cellW * 6
  local pixels = {}
  paintBlinkFaceShifted(pixels, sheetW, cellW, 0, 0)
  paintBlinkFaceShifted(pixels, sheetW, cellW, 3, 1)
  local closedTime, openTime = blinkTimes("red")
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", blink = "on" }))
  local def = { image = "red.png", frames = 6, frameWidth = cellW }
  withLoveTime(openTime, function()
    local walk = modules.SpriteBillboards.mesh(def, 3)
    local eye = frontQuadIndexAt(walk, 6, 7, 9, 10)
    check(allUvAt(walk, eye, (3 * cellW + 6.5) / sheetW, 8.5 / cellH),
          "pose andando aberta no frame 3 aponta para o proprio texel")
  end)
  withLoveTime(closedTime, function()
    local walk = modules.SpriteBillboards.mesh(def, 3)
    local eye = frontQuadIndexAt(walk, 6, 7, 9, 10)
    check(allUvAt(walk, eye, (3 * cellW + 6.5) / sheetW, 9.5 / cellH),
          "a pose andando pisca quando o olho transfere")
  end)
end

do
  -- a pose andando NAO pisca quando o olho nao transfere: o frame 3 tem a
  -- mesma silhueta descida uma linha (poseOffset ainda acha (0, 1)), mas a
  -- cabeca foi redesenhada com outro tom onde o olho estaria. A folha fica
  -- de olho aberto nesta pose, exatamente como hoje: nada de piscar meio
  -- olho. Este e o teste que impede a regressao da v1.4.1.
  local cellW, cellH = 16, 18
  local sheetW = cellW * 6
  local pixels = {}
  paintBlinkFaceShifted(pixels, sheetW, cellW, 0, 0)
  paintBlinkFaceRedrawn(pixels, sheetW, cellW, 3, 1)
  local closedTime, openTime = blinkTimes("red")
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", blink = "on" }))
  local def = { image = "red.png", frames = 6, frameWidth = cellW }
  local openSig, closedSig
  withLoveTime(openTime, function()
    openSig = uvSignature(modules.SpriteBillboards.mesh(def, 3))
  end)
  withLoveTime(closedTime, function()
    closedSig = uvSignature(modules.SpriteBillboards.mesh(def, 3))
  end)
  eq(openSig, closedSig, "a pose andando nao pisca quando o olho nao transfere")
end

do
  -- o equivalente de frente para o perfil: frame 5 e o frame 2 descido uma
  -- linha, a marca de perfil transfere, o frame 5 pisca na coordenada certa.
  local cellW, cellH = 16, 18
  local sheetW = cellW * 6
  local pixels = {}
  paintBlinkSideShifted(pixels, sheetW, cellW, 2, 0)
  paintBlinkSideShifted(pixels, sheetW, cellW, 5, 1)
  local closedTime, openTime = blinkTimes("red")
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", blink = "on" }))
  local def = { image = "red.png", frames = 6, frameWidth = cellW }
  withLoveTime(openTime, function()
    local walk = modules.SpriteBillboards.mesh(def, 5)
    local eye = frontQuadIndexAt(walk, 5, 6, 9, 10)
    check(allUvAt(walk, eye, (5 * cellW + 5.5) / sheetW, 8.5 / cellH),
          "pose andando de perfil aberta no frame 5 aponta para o proprio texel")
  end)
  withLoveTime(closedTime, function()
    local walk = modules.SpriteBillboards.mesh(def, 5)
    local eye = frontQuadIndexAt(walk, 5, 6, 9, 10)
    check(allUvAt(walk, eye, (5 * cellW + 5.5) / sheetW, 9.5 / cellH),
          "a pose andando de perfil pisca quando o olho transfere")
  end)
end

do
  -- equivalente de perfil do teste que nao transfere: frame 5 com a cabeca
  -- redesenhada fica de olho aberto, mesmo com a silhueta batendo.
  local cellW, cellH = 16, 18
  local sheetW = cellW * 6
  local pixels = {}
  paintBlinkSideShifted(pixels, sheetW, cellW, 2, 0)
  paintBlinkSideRedrawn(pixels, sheetW, cellW, 5, 1)
  local closedTime, openTime = blinkTimes("red")
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", blink = "on" }))
  local def = { image = "red.png", frames = 6, frameWidth = cellW }
  local openSig, closedSig
  withLoveTime(openTime, function()
    openSig = uvSignature(modules.SpriteBillboards.mesh(def, 5))
  end)
  withLoveTime(closedTime, function()
    closedSig = uvSignature(modules.SpriteBillboards.mesh(def, 5))
  end)
  eq(openSig, closedSig,
     "a pose andando de perfil nao pisca quando o olho nao transfere")
end

do
  -- lorelei pisca de frente e de perfil, contra a arte real (nao
  -- sintetica): pixels extraidos de assets/generated/sprites/lorelei.png
  -- (16x16, 6 frames), frames 0, 2, 3 e 5. Medido antes de escrever isto: o
  -- preto de (5..10, 7) no frame 0 reaparece preto uma linha abaixo no
  -- frame 3, e o preto de (5, 6) no frame 2 reaparece preto uma linha
  -- abaixo no frame 5, entao as duas marcas transferem.
  -- sha256 do PNG de origem no momento da extracao (conferencia humana):
  -- 2bf59a656c6f7e76ddcac68cc011bde718b853f7fda1b13280fc3aa3a4feb3ec
  eq(fnv1aFile("assets/generated/sprites/lorelei.png"), 1159453232,
     "lorelei.png nao mudou desde que os pixels foram extraidos (regenere o snapshot se isto falhar)")
  local cellW, cellH = 16, 16
  local sheetW = cellW * 6
  local pixels = {}
  -- frame 0
  for lx = 5, 7 do paint(pixels, sheetW, cellW, 0, lx, 0, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 9, 10 do paint(pixels, sheetW, cellW, 0, lx, 0, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 4, 1, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 5, 7 do paint(pixels, sheetW, cellW, 0, lx, 1, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 8, 1, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 9, 10 do paint(pixels, sheetW, cellW, 0, lx, 1, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 11, 1, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 0, 3, 2, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 4, 7 do paint(pixels, sheetW, cellW, 0, lx, 2, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 8, 2, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 9, 11 do paint(pixels, sheetW, cellW, 0, lx, 2, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 12, 2, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 0, 2, 3, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 3, 5 do paint(pixels, sheetW, cellW, 0, lx, 3, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 6, 3, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 7, 8 do paint(pixels, sheetW, cellW, 0, lx, 3, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 9, 3, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 10, 12 do paint(pixels, sheetW, cellW, 0, lx, 3, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 13, 3, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 0, 2, 4, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 3, 4 do paint(pixels, sheetW, cellW, 0, lx, 4, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 5, 4, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 0, 6, 4, rgba(0.666667, 0.666667, 0.666667, 1.0))
  for lx = 7, 8 do paint(pixels, sheetW, cellW, 0, lx, 4, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 9, 4, rgba(0.666667, 0.666667, 0.666667, 1.0))
  paint(pixels, sheetW, cellW, 0, 10, 4, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 11, 12 do paint(pixels, sheetW, cellW, 0, lx, 4, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 13, 4, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 0, 2, 5, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 0, 3, 5, rgba(0.333333, 0.333333, 0.333333, 1.0))
  for lx = 4, 6 do paint(pixels, sheetW, cellW, 0, lx, 5, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 7, 8 do paint(pixels, sheetW, cellW, 0, lx, 5, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  for lx = 9, 11 do paint(pixels, sheetW, cellW, 0, lx, 5, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 12, 5, rgba(0.333333, 0.333333, 0.333333, 1.0))
  paint(pixels, sheetW, cellW, 0, 13, 5, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 3, 4 do paint(pixels, sheetW, cellW, 0, lx, 6, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 5, 6 do paint(pixels, sheetW, cellW, 0, lx, 6, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  for lx = 7, 8 do paint(pixels, sheetW, cellW, 0, lx, 6, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 9, 10 do paint(pixels, sheetW, cellW, 0, lx, 6, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  for lx = 11, 12 do paint(pixels, sheetW, cellW, 0, lx, 6, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 3, 7, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 0, 4, 7, rgba(0.666667, 0.666667, 0.666667, 1.0))
  for lx = 5, 6 do paint(pixels, sheetW, cellW, 0, lx, 7, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 7, 8 do paint(pixels, sheetW, cellW, 0, lx, 7, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  for lx = 9, 10 do paint(pixels, sheetW, cellW, 0, lx, 7, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 11, 7, rgba(0.666667, 0.666667, 0.666667, 1.0))
  paint(pixels, sheetW, cellW, 0, 12, 7, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 0, 4, 8, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 5, 6 do paint(pixels, sheetW, cellW, 0, lx, 8, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  for lx = 7, 8 do paint(pixels, sheetW, cellW, 0, lx, 8, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  for lx = 9, 10 do paint(pixels, sheetW, cellW, 0, lx, 8, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 11, 8, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 3, 12 do paint(pixels, sheetW, cellW, 0, lx, 9, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 2, 10, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 3, 4 do paint(pixels, sheetW, cellW, 0, lx, 10, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  for lx = 5, 10 do paint(pixels, sheetW, cellW, 0, lx, 10, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 11, 12 do paint(pixels, sheetW, cellW, 0, lx, 10, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 13, 10, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 0, 2, 11, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 3, 4 do paint(pixels, sheetW, cellW, 0, lx, 11, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 5, 11, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 0, 6, 11, rgba(0.333333, 0.333333, 0.333333, 1.0))
  for lx = 7, 8 do paint(pixels, sheetW, cellW, 0, lx, 11, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 9, 11, rgba(0.333333, 0.333333, 0.333333, 1.0))
  paint(pixels, sheetW, cellW, 0, 10, 11, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 11, 12 do paint(pixels, sheetW, cellW, 0, lx, 11, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  paint(pixels, sheetW, cellW, 0, 13, 11, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 3, 12 do paint(pixels, sheetW, cellW, 0, lx, 12, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 4, 11 do paint(pixels, sheetW, cellW, 0, lx, 13, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 4, 11 do paint(pixels, sheetW, cellW, 0, lx, 14, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 5, 6 do paint(pixels, sheetW, cellW, 0, lx, 15, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 9, 10 do paint(pixels, sheetW, cellW, 0, lx, 15, rgba(0.0, 0.0, 0.0, 1.0)) end
  -- frame 2
  for lx = 5, 8 do paint(pixels, sheetW, cellW, 2, lx, 0, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 3, 4 do paint(pixels, sheetW, cellW, 2, lx, 1, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 5, 8 do paint(pixels, sheetW, cellW, 2, lx, 1, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 9, 1, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 2, 2, 2, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 3, 4 do paint(pixels, sheetW, cellW, 2, lx, 2, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 5, 2, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 6, 9 do paint(pixels, sheetW, cellW, 2, lx, 2, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 10, 2, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 2, 1, 3, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 2, 5 do paint(pixels, sheetW, cellW, 2, lx, 3, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 6, 3, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 7, 10 do paint(pixels, sheetW, cellW, 2, lx, 3, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 11, 3, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 1, 3 do paint(pixels, sheetW, cellW, 2, lx, 4, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 4, 6 do paint(pixels, sheetW, cellW, 2, lx, 4, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 7, 4, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 8, 10 do paint(pixels, sheetW, cellW, 2, lx, 4, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 11, 4, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 2, 4 do paint(pixels, sheetW, cellW, 2, lx, 5, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 5, 6 do paint(pixels, sheetW, cellW, 2, lx, 5, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 7, 5, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 8, 10 do paint(pixels, sheetW, cellW, 2, lx, 5, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 11, 5, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 2, 2, 6, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 3, 4 do paint(pixels, sheetW, cellW, 2, lx, 6, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 5, 6, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 2, 6, 6, rgba(0.333333, 0.333333, 0.333333, 1.0))
  paint(pixels, sheetW, cellW, 2, 7, 6, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 8, 10 do paint(pixels, sheetW, cellW, 2, lx, 6, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 11, 6, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 2, 4 do paint(pixels, sheetW, cellW, 2, lx, 7, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 5, 7, rgba(0.666667, 0.666667, 0.666667, 1.0))
  for lx = 6, 8 do paint(pixels, sheetW, cellW, 2, lx, 7, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 9, 10 do paint(pixels, sheetW, cellW, 2, lx, 7, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 11, 7, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 2, 2, 8, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 3, 7 do paint(pixels, sheetW, cellW, 2, lx, 8, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  for lx = 8, 9 do paint(pixels, sheetW, cellW, 2, lx, 8, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 10, 8, rgba(0.333333, 0.333333, 0.333333, 1.0))
  paint(pixels, sheetW, cellW, 2, 11, 8, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 2, 3, 9, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 2, 4, 9, rgba(0.333333, 0.333333, 0.333333, 1.0))
  for lx = 5, 8 do paint(pixels, sheetW, cellW, 2, lx, 9, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  for lx = 9, 10 do paint(pixels, sheetW, cellW, 2, lx, 9, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 11, 9, rgba(0.666667, 0.666667, 0.666667, 1.0))
  paint(pixels, sheetW, cellW, 2, 12, 9, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 2, 4, 10, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 2, 5, 10, rgba(0.333333, 0.333333, 0.333333, 1.0))
  for lx = 6, 9 do paint(pixels, sheetW, cellW, 2, lx, 10, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 10, 12 do paint(pixels, sheetW, cellW, 2, lx, 10, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 13, 10, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 4, 5 do paint(pixels, sheetW, cellW, 2, lx, 11, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 6, 11, rgba(0.333333, 0.333333, 0.333333, 1.0))
  paint(pixels, sheetW, cellW, 2, 7, 11, rgba(0.666667, 0.666667, 0.666667, 1.0))
  paint(pixels, sheetW, cellW, 2, 8, 11, rgba(0.333333, 0.333333, 0.333333, 1.0))
  for lx = 9, 10 do paint(pixels, sheetW, cellW, 2, lx, 11, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 11, 12 do paint(pixels, sheetW, cellW, 2, lx, 11, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 13, 11, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 4, 6 do paint(pixels, sheetW, cellW, 2, lx, 12, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 7, 8 do paint(pixels, sheetW, cellW, 2, lx, 12, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 9, 12, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 11, 12 do paint(pixels, sheetW, cellW, 2, lx, 12, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 4, 13, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 2, 5, 13, rgba(0.333333, 0.333333, 0.333333, 1.0))
  paint(pixels, sheetW, cellW, 2, 6, 13, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 7, 8 do paint(pixels, sheetW, cellW, 2, lx, 13, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  paint(pixels, sheetW, cellW, 2, 9, 13, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 4, 9 do paint(pixels, sheetW, cellW, 2, lx, 14, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 3, 8 do paint(pixels, sheetW, cellW, 2, lx, 15, rgba(0.0, 0.0, 0.0, 1.0)) end
  -- frame 3
  for lx = 5, 7 do paint(pixels, sheetW, cellW, 3, lx, 1, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 9, 10 do paint(pixels, sheetW, cellW, 3, lx, 1, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 3, 4, 2, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 5, 7 do paint(pixels, sheetW, cellW, 3, lx, 2, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 3, 8, 2, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 9, 10 do paint(pixels, sheetW, cellW, 3, lx, 2, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 3, 11, 2, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 3, 3, 3, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 4, 7 do paint(pixels, sheetW, cellW, 3, lx, 3, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 3, 8, 3, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 9, 11 do paint(pixels, sheetW, cellW, 3, lx, 3, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 3, 12, 3, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 3, 2, 4, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 3, 5 do paint(pixels, sheetW, cellW, 3, lx, 4, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 3, 6, 4, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 7, 8 do paint(pixels, sheetW, cellW, 3, lx, 4, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 3, 9, 4, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 10, 12 do paint(pixels, sheetW, cellW, 3, lx, 4, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 3, 13, 4, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 3, 2, 5, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 3, 4 do paint(pixels, sheetW, cellW, 3, lx, 5, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 3, 5, 5, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 3, 6, 5, rgba(0.666667, 0.666667, 0.666667, 1.0))
  for lx = 7, 8 do paint(pixels, sheetW, cellW, 3, lx, 5, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 3, 9, 5, rgba(0.666667, 0.666667, 0.666667, 1.0))
  paint(pixels, sheetW, cellW, 3, 10, 5, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 11, 12 do paint(pixels, sheetW, cellW, 3, lx, 5, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 3, 13, 5, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 3, 2, 6, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 3, 3, 6, rgba(0.333333, 0.333333, 0.333333, 1.0))
  for lx = 4, 6 do paint(pixels, sheetW, cellW, 3, lx, 6, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 7, 8 do paint(pixels, sheetW, cellW, 3, lx, 6, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  for lx = 9, 11 do paint(pixels, sheetW, cellW, 3, lx, 6, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 3, 12, 6, rgba(0.333333, 0.333333, 0.333333, 1.0))
  paint(pixels, sheetW, cellW, 3, 13, 6, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 3, 4 do paint(pixels, sheetW, cellW, 3, lx, 7, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 5, 6 do paint(pixels, sheetW, cellW, 3, lx, 7, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  for lx = 7, 8 do paint(pixels, sheetW, cellW, 3, lx, 7, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 9, 10 do paint(pixels, sheetW, cellW, 3, lx, 7, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  for lx = 11, 12 do paint(pixels, sheetW, cellW, 3, lx, 7, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 3, 3, 8, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 3, 4, 8, rgba(0.666667, 0.666667, 0.666667, 1.0))
  for lx = 5, 6 do paint(pixels, sheetW, cellW, 3, lx, 8, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 7, 8 do paint(pixels, sheetW, cellW, 3, lx, 8, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  for lx = 9, 10 do paint(pixels, sheetW, cellW, 3, lx, 8, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 3, 11, 8, rgba(0.666667, 0.666667, 0.666667, 1.0))
  paint(pixels, sheetW, cellW, 3, 12, 8, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 2, 4 do paint(pixels, sheetW, cellW, 3, lx, 9, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 5, 6 do paint(pixels, sheetW, cellW, 3, lx, 9, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  for lx = 7, 8 do paint(pixels, sheetW, cellW, 3, lx, 9, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  for lx = 9, 10 do paint(pixels, sheetW, cellW, 3, lx, 9, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  for lx = 11, 12 do paint(pixels, sheetW, cellW, 3, lx, 9, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 3, 2, 10, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 3, 3, 10, rgba(0.666667, 0.666667, 0.666667, 1.0))
  for lx = 4, 12 do paint(pixels, sheetW, cellW, 3, lx, 10, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 3, 9 do paint(pixels, sheetW, cellW, 3, lx, 11, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 10, 11 do paint(pixels, sheetW, cellW, 3, lx, 11, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  paint(pixels, sheetW, cellW, 3, 12, 11, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 3, 5 do paint(pixels, sheetW, cellW, 3, lx, 12, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 3, 6, 12, rgba(0.333333, 0.333333, 0.333333, 1.0))
  paint(pixels, sheetW, cellW, 3, 7, 12, rgba(0.666667, 0.666667, 0.666667, 1.0))
  paint(pixels, sheetW, cellW, 3, 8, 12, rgba(0.333333, 0.333333, 0.333333, 1.0))
  paint(pixels, sheetW, cellW, 3, 9, 12, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 10, 11 do paint(pixels, sheetW, cellW, 3, lx, 12, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  paint(pixels, sheetW, cellW, 3, 12, 12, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 4, 11 do paint(pixels, sheetW, cellW, 3, lx, 13, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 4, 7 do paint(pixels, sheetW, cellW, 3, lx, 14, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 5, 6 do paint(pixels, sheetW, cellW, 3, lx, 15, rgba(0.0, 0.0, 0.0, 1.0)) end
  -- frame 5
  for lx = 5, 8 do paint(pixels, sheetW, cellW, 5, lx, 1, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 3, 4 do paint(pixels, sheetW, cellW, 5, lx, 2, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 5, 8 do paint(pixels, sheetW, cellW, 5, lx, 2, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 5, 9, 2, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 5, 2, 3, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 3, 4 do paint(pixels, sheetW, cellW, 5, lx, 3, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 5, 5, 3, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 6, 9 do paint(pixels, sheetW, cellW, 5, lx, 3, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 5, 10, 3, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 5, 1, 4, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 2, 5 do paint(pixels, sheetW, cellW, 5, lx, 4, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 5, 6, 4, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 7, 10 do paint(pixels, sheetW, cellW, 5, lx, 4, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 5, 11, 4, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 1, 3 do paint(pixels, sheetW, cellW, 5, lx, 5, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 4, 6 do paint(pixels, sheetW, cellW, 5, lx, 5, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 5, 7, 5, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 8, 10 do paint(pixels, sheetW, cellW, 5, lx, 5, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 5, 11, 5, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 2, 4 do paint(pixels, sheetW, cellW, 5, lx, 6, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 5, 6 do paint(pixels, sheetW, cellW, 5, lx, 6, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 5, 7, 6, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 8, 10 do paint(pixels, sheetW, cellW, 5, lx, 6, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 5, 11, 6, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 5, 2, 7, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 3, 4 do paint(pixels, sheetW, cellW, 5, lx, 7, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  paint(pixels, sheetW, cellW, 5, 5, 7, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 5, 6, 7, rgba(0.333333, 0.333333, 0.333333, 1.0))
  paint(pixels, sheetW, cellW, 5, 7, 7, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 8, 10 do paint(pixels, sheetW, cellW, 5, lx, 7, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 5, 11, 7, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 2, 4 do paint(pixels, sheetW, cellW, 5, lx, 8, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 5, 5, 8, rgba(0.666667, 0.666667, 0.666667, 1.0))
  for lx = 6, 8 do paint(pixels, sheetW, cellW, 5, lx, 8, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 9, 10 do paint(pixels, sheetW, cellW, 5, lx, 8, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 5, 11, 8, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 5, 2, 9, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 3, 7 do paint(pixels, sheetW, cellW, 5, lx, 9, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  for lx = 8, 9 do paint(pixels, sheetW, cellW, 5, lx, 9, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 5, 10, 9, rgba(0.333333, 0.333333, 0.333333, 1.0))
  paint(pixels, sheetW, cellW, 5, 11, 9, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 5, 3, 10, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 5, 4, 10, rgba(0.333333, 0.333333, 0.333333, 1.0))
  for lx = 5, 8 do paint(pixels, sheetW, cellW, 5, lx, 10, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  for lx = 9, 10 do paint(pixels, sheetW, cellW, 5, lx, 10, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 5, 11, 10, rgba(0.666667, 0.666667, 0.666667, 1.0))
  paint(pixels, sheetW, cellW, 5, 12, 10, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 5, 4, 11, rgba(0.0, 0.0, 0.0, 1.0))
  paint(pixels, sheetW, cellW, 5, 5, 11, rgba(0.333333, 0.333333, 0.333333, 1.0))
  for lx = 6, 9 do paint(pixels, sheetW, cellW, 5, lx, 11, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 10, 12 do paint(pixels, sheetW, cellW, 5, lx, 11, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 5, 13, 11, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 4, 5 do paint(pixels, sheetW, cellW, 5, lx, 12, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 6, 7 do paint(pixels, sheetW, cellW, 5, lx, 12, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 5, 8, 12, rgba(0.666667, 0.666667, 0.666667, 1.0))
  for lx = 9, 10 do paint(pixels, sheetW, cellW, 5, lx, 12, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 11, 12 do paint(pixels, sheetW, cellW, 5, lx, 12, rgba(0.333333, 0.333333, 0.333333, 1.0)) end
  paint(pixels, sheetW, cellW, 5, 13, 12, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 2, 7 do paint(pixels, sheetW, cellW, 5, lx, 13, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 8, 9 do paint(pixels, sheetW, cellW, 5, lx, 13, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  for lx = 10, 12 do paint(pixels, sheetW, cellW, 5, lx, 13, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 2, 5 do paint(pixels, sheetW, cellW, 5, lx, 14, rgba(0.0, 0.0, 0.0, 1.0)) end
  paint(pixels, sheetW, cellW, 5, 6, 14, rgba(0.333333, 0.333333, 0.333333, 1.0))
  paint(pixels, sheetW, cellW, 5, 7, 14, rgba(0.0, 0.0, 0.0, 1.0))
  for lx = 8, 9 do paint(pixels, sheetW, cellW, 5, lx, 14, rgba(0.666667, 0.666667, 0.666667, 1.0)) end
  for lx = 10, 11 do paint(pixels, sheetW, cellW, 5, lx, 14, rgba(0.0, 0.0, 0.0, 1.0)) end
  for lx = 3, 9 do paint(pixels, sheetW, cellW, 5, lx, 15, rgba(0.0, 0.0, 0.0, 1.0)) end
  local closedTime, openTime = blinkTimes("lorelei")
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", blink = "on" }))
  local def = { image = "lorelei.png", frames = 6, frameWidth = cellW }
  local frontOpen, frontClosed, sideOpen, sideClosed
  withLoveTime(openTime, function()
    frontOpen = uvSignature(modules.SpriteBillboards.mesh(def, 3))
    sideOpen = uvSignature(modules.SpriteBillboards.mesh(def, 5))
  end)
  withLoveTime(closedTime, function()
    frontClosed = uvSignature(modules.SpriteBillboards.mesh(def, 3))
    sideClosed = uvSignature(modules.SpriteBillboards.mesh(def, 5))
  end)
  check(frontOpen ~= frontClosed, "lorelei pisca de frente andando (frame 3)")
  check(sideOpen ~= sideClosed, "lorelei pisca de perfil andando (frame 5)")
end

do
  -- monster e bike_shop_clerk deram empate de tres candidatos no score de
  -- deteccao de marca (sem evidencia); ficam sem entrada de proposito e
  -- continuam de olho aberto em toda pose, mesmo com pixels escuros na
  -- posicao que outras folhas usariam como olho.
  for _, baseName in ipairs({ "monster", "bike_shop_clerk" }) do
    local cellW, cellH = 16, 16
    local sheetW = cellW * 6
    local pixels = {}
    for frame = 0, 5 do paintBlinkFace(pixels, sheetW, cellW, frame) end
    local closedTime, openTime = blinkTimes(baseName)
    local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
    loadWith(makeMod(handle, { depth = 2, shape = "slab", blink = "on" }))
    local def = { image = baseName .. ".png", frames = 6, frameWidth = cellW }
    local openSig, closedSig
    withLoveTime(openTime, function()
      openSig = uvSignature(modules.SpriteBillboards.mesh(def, 0))
    end)
    withLoveTime(closedTime, function()
      closedSig = uvSignature(modules.SpriteBillboards.mesh(def, 0))
    end)
    eq(openSig, closedSig, baseName .. " continua de olho aberto (sem marca)")
  end
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

-- v1.4.2, "um mod de terceiro derruba o modo voxel do jogo inteiro"
-- (AngelusRole): o host concatena `def.image .. "#" .. frame` sem guarda de
-- tipo (DramaticShapeVoxelMod/lib/SpriteBillboards.lua:65); um frame nulo de
-- QUALQUER mod de entidade lanca ali, sem pcall, dentro do loop de desenho
-- do host, e derruba o modo voxel do jogo inteiro ate reiniciar. O stub
-- padrao de teste (`original`) nunca lanca, entao os testes abaixo instalam
-- um "original" que reproduz a conta do host de verdade, senao mediriam a
-- coisa errada e passariam tanto antes quanto depois da correcao.

do
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local sprite = handle.exports.lib.require("SpriteBillboards")
  sprite.mesh = function(def, frame) return def.image .. "#" .. frame end
  loadWith(makeMod(handle, { depth = 2 }))
  local ok = pcall(modules.SpriteBillboards.mesh, { frames = 6 }, 0)
  check(ok == true, "def sem image nao lanca excecao")
end

do
  -- este e o caminho provavel do report: def com image valido, frame nulo.
  -- depth=off forca o primeiro dos cinco pontos sem pcall, antes de
  -- qualquer normalizacao interna de frame acontecer.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local sprite = handle.exports.lib.require("SpriteBillboards")
  sprite.mesh = function(def, frame) return def.image .. "#" .. frame end
  loadWith(makeMod(handle, { depth = "off" }))
  local def = { image = "sheet.png", frames = 6 }
  local ok = pcall(modules.SpriteBillboards.mesh, def, nil)
  check(ok == true, "frame nil nao lanca excecao")
end

do
  -- teste que representa o report do Angelus: forca o original mockado do
  -- host a lancar (aqui pelo caminho de primeira pessoa, um dos cinco
  -- pontos) e prova que o wrapper devolve nil, nao propaga a excecao.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16, nil, nil, 1)
  local sprite = handle.exports.lib.require("SpriteBillboards")
  sprite.mesh = function() error("boom from host original") end
  loadWith(makeMod(handle, { depth = 2 }))
  local def = { image = "sheet.png", frames = 6, frameWidth = 16 }
  local ok, mesh = pcall(modules.SpriteBillboards.mesh, def, 0)
  check(ok and mesh == nil, "o fallback ao original nao propaga excecao")
end

do
  -- o aviso sai uma vez so: o mesmo caminho de falha, chamado tres vezes.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local sprite = handle.exports.lib.require("SpriteBillboards")
  sprite.mesh = function(def, frame) return def.image .. "#" .. frame end
  local mod = loadWith(makeMod(handle, { depth = "off" }))
  local def = { image = "sheet.png", frames = 6 }
  modules.SpriteBillboards.mesh(def, nil)
  modules.SpriteBillboards.mesh(def, nil)
  modules.SpriteBillboards.mesh(def, nil)
  local count = 0
  for _, msg in ipairs(mod._logs.warn) do
    if msg:find("original mesh call failed", 1, true) then count = count + 1 end
  end
  eq(count, 1, "o aviso sai uma vez so")
end

-- v1.4.2, AngelusRole/Tyler Durden/TwoTracks: a row de STATUS. Os testes
-- abaixo cobrem os quatro estados de patch (NO HOST ja coberto acima,
-- ACTIVE, REPLACED, FIRST PERSON) e os tres resultados de desenho que o
-- TwoTracks expos (mask_failed, build_failed, exception no wrapper
-- externo), incluindo o requisito de nao ficar preso em erro por uma folha
-- ruim isolada (item C) e o log latching por causa distinta (item D).

do
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle))
  eq(statusRowValue(mod), "ACTIVE", "com host, STATUS e ACTIVE")
end

do
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle))
  eq(statusRowValue(mod), "ACTIVE", "antes de ser substituido, STATUS e ACTIVE")
  -- este e o teste que representa o report do TwoTracks: outro mod troca
  -- SpriteBillboards.mesh DEPOIS do nosso patch, sem chamar shadowQuad nem
  -- escrever em cardBlend (as duas hipoteses que a investigacao descartou).
  modules.SpriteBillboards.mesh = function(def, frame) return { original = true } end
  eq(statusRowValue(mod), "REPLACED",
     "quando outro mod substitui SpriteBillboards.mesh depois de nos, STATUS vira REPLACED")
  check(mod._logs.warn[#mod._logs.warn]
        and mod._logs.warn[#mod._logs.warn]:find("replaced", 1, true),
        "REPLACED loga uma vez")
  local warnCount = #mod._logs.warn
  statusRowValue(mod)
  statusRowValue(mod)
  eq(#mod._logs.warn, warnCount, "REPLACED nao loga de novo em leituras seguintes")
end

do
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16, nil, nil, 1)
  local mod = loadWith(makeMod(handle))
  eq(statusRowValue(mod), "FIRST PERSON",
     "com primeira pessoa ativa, STATUS vira FIRST PERSON")
end

do
  -- as rows existentes continuam aparecendo na mesma ordem, depois do
  -- STATUS.
  local pixels = {}
  pixels[0] = 1
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle))
  local rows = {}
  mod._rows["ui.options.rows"](function(_, r) return r end, {}, rows)
  eq(#rows, 7, "com host, sete rows: STATUS mais as seis de sempre")
  eq(rows[1].label, "STATUS", "STATUS vem primeiro")
  eq(rows[2].label, "VOXEL CHARS", "DEPTH continua na mesma posicao relativa")
  eq(rows[3].label, "SIDE COLOR", "SIDE COLOR continua na mesma posicao relativa")
  eq(rows[4].label, "SHAPE", "SHAPE continua na mesma posicao relativa")
  eq(rows[5].label, "GROUND SHADE", "GROUND SHADE continua na mesma posicao relativa")
  eq(rows[6].label, "BLINK", "BLINK continua na mesma posicao relativa")
  eq(rows[7].label, "TOP EDGE", "TOP EDGE continua na mesma posicao relativa")
end

do
  -- mascara que falha vira STATUS de erro e loga uma vez com a mensagem.
  -- def sem image: maskFor devolve nil sem lancar, toda chamada, entao
  -- consecutiveDrawFailures sobe em toda chamada, nao so na primeira.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle, { depth = 2 }))
  local def = { frames = 6 }
  for _ = 1, 10 do
    modules.SpriteBillboards.mesh(def, 0)
  end
  eq(statusRowValue(mod), "MASK ERROR",
     "mascara que falha repetidamente vira STATUS de erro")
  check(mod._logs.warn[#mod._logs.warn]
        and mod._logs.warn[#mod._logs.warn]:find("mask_failed", 1, true),
        "mask_failed loga a mensagem")
  local warnCount = #mod._logs.warn
  modules.SpriteBillboards.mesh(def, 0)
  eq(#mod._logs.warn, warnCount, "a mesma causa de mask_failed loga uma vez so")
end

do
  -- malha que falha vira STATUS de erro e loga uma vez com a mensagem
  -- original. Voxel3D.newMesh quebrado forca buildSlabMesh a lancar no
  -- final da construcao, com maskFor ja tendo funcionado.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle, { depth = 2 }))
  modules.Voxel3D.newMesh = function() error("boom from Voxel3D.newMesh") end
  local def = { image = "sheet.png", frames = 1 }
  for _ = 1, 10 do
    modules.SpriteBillboards.mesh(def, 0)
  end
  eq(statusRowValue(mod), "BUILD ERROR",
     "malha que falha repetidamente vira STATUS de erro")
  check(mod._logs.warn[#mod._logs.warn]
        and mod._logs.warn[#mod._logs.warn]:find("build_failed", 1, true)
        and mod._logs.warn[#mod._logs.warn]:find("boom from Voxel3D.newMesh", 1, true),
        "build_failed loga a mensagem original, mesmo vindo do cache")
  local warnCount = #mod._logs.warn
  modules.SpriteBillboards.mesh(def, 0)
  eq(#mod._logs.warn, warnCount, "a mesma causa de build_failed loga uma vez so")
end

do
  -- excecao no wrapper mais externo vira STATUS de erro e loga uma vez com
  -- a mensagem original. Quebra cacheKey (upvalue de voxelMesh) para forcar
  -- uma excecao que nenhum pcall interno de voxelMesh pega, so o wrapper.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle, { depth = 2 }))
  local wrapper = modules.SpriteBillboards.mesh
  local voxelMeshFn
  for i = 1, 20 do
    local n, v = debug.getupvalue(wrapper, i)
    if n == "voxelMesh" then voxelMeshFn = v; break end
  end
  check(type(voxelMeshFn) == "function", "teste encontra voxelMesh no wrapper")
  local found = false
  for i = 1, 40 do
    local n = debug.getupvalue(voxelMeshFn, i)
    if n == "cacheKey" then
      debug.setupvalue(voxelMeshFn, i, function() error("boom from cacheKey") end)
      found = true
      break
    end
  end
  check(found, "teste encontra cacheKey em voxelMesh")
  local def = { image = "sheet.png", frames = 1 }
  for _ = 1, 10 do
    modules.SpriteBillboards.mesh(def, 0)
  end
  eq(statusRowValue(mod), "DRAW ERROR",
     "excecao no wrapper externo repetida vira STATUS de erro")
  check(mod._logs.warn[#mod._logs.warn]
        and mod._logs.warn[#mod._logs.warn]:find("exception", 1, true)
        and mod._logs.warn[#mod._logs.warn]:find("boom from cacheKey", 1, true),
        "exception loga a mensagem original")
  local warnCount = #mod._logs.warn
  modules.SpriteBillboards.mesh(def, 0)
  eq(#mod._logs.warn, warnCount, "a mesma causa de exception loga uma vez so")
end

do
  -- item C: um sprite que falha no meio de varios que funcionam nao deixa
  -- o STATUS preso em erro. Uma folha ruim a cada quatro boas, 20 desenhos
  -- no total (4 ruins, 16 bons): dentro de QUALQUER janela de 8 desenhos
  -- consecutivos deste padrao ha no maximo 2 falhas, 25%, bem abaixo dos
  -- 50% que escalam o STATUS.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle, { depth = 2 }))
  local goodDef = { image = "sheet.png", frames = 1 }
  local badDef = { frames = 6 }
  for i = 1, 20 do
    modules.SpriteBillboards.mesh(goodDef, 0)
    if i % 4 == 0 then
      modules.SpriteBillboards.mesh(badDef, 0)
    end
  end
  eq(statusRowValue(mod), "ACTIVE",
     "uma folha ruim isolada no meio de varias boas nao deixa o STATUS preso em erro")
end

do
  -- pente fino, item 1: um contador de falhas SEGUIDAS e derrotavel por
  -- intercalacao (o sprite do jogador desenha bem a cada quadro, um NPC de
  -- fonte quebrada falha intercalado, e nenhuma sequencia de falhas chega
  -- ao limite, mesmo com metade da tela caindo pra card plano). Alternancia
  -- estrita bom/ruim, 16 desenhos (8 bons, 8 ruins): a janela dos ultimos 8
  -- fica com metade de falha, e o STATUS escala mesmo sem nenhuma sequencia
  -- ininterrupta de falhas.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle, { depth = 2 }))
  local goodDef = { image = "sheet.png", frames = 1 }
  local badDef = { frames = 6 }
  for _ = 1, 8 do
    modules.SpriteBillboards.mesh(goodDef, 0)
    modules.SpriteBillboards.mesh(badDef, 0)
  end
  eq(statusRowValue(mod), "MASK ERROR",
     "alternancia estrita ok, falha, ok, falha com maioria de falhas escala o STATUS")
end

do
  -- causas distintas (duas folhas quebradas de jeitos diferentes) logam
  -- cada uma a sua vez, nao colapsam numa so.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle, { depth = 2 }))
  local defA = { image = "a.png", frames = 1 }
  local defB = { image = "b.png", frames = 1 }
  local callCount = 0
  modules.Voxel3D.newMesh = function()
    callCount = callCount + 1
    error("boom " .. callCount)
  end
  modules.SpriteBillboards.mesh(defA, 0)
  modules.SpriteBillboards.mesh(defB, 0)
  local buildWarnings = 0
  for _, msg in ipairs(mod._logs.warn) do
    if msg:find("build_failed", 1, true) then buildWarnings = buildWarnings + 1 end
  end
  eq(buildWarnings, 2,
     "duas causas distintas de build_failed logam cada uma a sua vez")
end

do
  -- pente fino, item 2: o rotulo do STATUS mostra a causa DOMINANTE da
  -- janela, nao a mais recente. Sete falhas de mask_failed e uma de
  -- exception por ultimo (numa folha diferente): o rotulo tem que ser
  -- MASK ERROR (a causa de 7 dos 8 desenhos da janela), nao DRAW ERROR (a
  -- ultima, mas so 1 dos 8). O rotulo e o produto desta row: e ele que diz
  -- pro jogador o que esta acontecendo sem precisar pedir log.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle, { depth = 2 }))
  local badDef = { frames = 6 } -- sem image: mask_failed toda vez
  for _ = 1, 7 do
    modules.SpriteBillboards.mesh(badDef, 0)
  end
  -- quebra cacheKey (upvalue de voxelMesh) so pra forcar uma excecao no
  -- oitavo desenho, numa folha diferente das sete primeiras.
  local wrapper = modules.SpriteBillboards.mesh
  local voxelMeshFn
  for i = 1, 20 do
    local n, v = debug.getupvalue(wrapper, i)
    if n == "voxelMesh" then voxelMeshFn = v; break end
  end
  check(type(voxelMeshFn) == "function",
        "teste encontra voxelMesh no wrapper (dominante da janela)")
  local found = false
  for i = 1, 40 do
    local n = debug.getupvalue(voxelMeshFn, i)
    if n == "cacheKey" then
      debug.setupvalue(voxelMeshFn, i, function() error("boom from cacheKey") end)
      found = true
      break
    end
  end
  check(found, "teste encontra cacheKey em voxelMesh (dominante da janela)")
  local otherDef = { image = "sheet.png", frames = 1 }
  modules.SpriteBillboards.mesh(otherDef, 0)
  eq(statusRowValue(mod), "MASK ERROR",
     "STATUS mostra a causa dominante da janela (7 mask_failed), nao a mais recente (1 exception)")
end

T.finish("voxel_chars_test")
