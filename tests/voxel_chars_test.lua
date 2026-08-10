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

-- v1.6.0: como vertexSignature, mas sem a coluna de shade (v[6]). TOP DOME
-- e TOP EDGE so mudam shade, nunca posicao de vertice nem UV; esta
-- assinatura prova a geometria byte a byte identica enquanto o shade muda
-- livremente por cima dela.
local function positionSignature(mesh)
  local out = {}
  for i, v in ipairs(mesh.verts) do
    out[i] = ("%.4f,%.4f,%.4f,%.4f,%.4f"):format(v[1], v[2], v[3], v[4], v[5])
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

-- v1.6.0: como frontVertexShadeAt, mas devolve Z em vez de shade e nao exige
-- Z == 0: STEP WEIGHT cisalha Z proporcional a altura (Y), entao um vertice
-- de frente deixa de estar exatamente no plano Z = 0 quando a opcao esta
-- ligada -- e a propria posicao sheared que o teste quer ler. `shade`
-- desambigua entre frente (0.90), tras (0.68), lateral (0.78), topo (1.00)
-- e base (0.55) quando (x, y) coincide entre faces diferentes.
local function vertexZAt(mesh, x, y, shade)
  for _, v in ipairs(mesh.verts) do
    if close(v[1], x) and close(v[2], y)
        and (not shade or close(v[6], shade)) then
      return v[3]
    end
  end
end

-- v1.6.0: como positionSignature, mas so a coluna de X (v[1]), na mesma
-- ordem de emissao dos vertices. STEP WEIGHT cisalha Z proporcional a
-- altura e nunca mexe em X -- a garantia contra o espelho do host, que so
-- inverte sinal em X. Comparar esta assinatura entre a malha com a opcao
-- ligada e desligada prova X identico vertice a vertice, nao so "a mesma
-- silhueta por acaso".
local function xSignature(mesh)
  local out = {}
  for i, v in ipairs(mesh.verts) do
    out[i] = ("%.4f"):format(v[1])
  end
  return table.concat(out, ";")
end

-- v1.6.0: como frontFaceZAt, mas sem exigir shade == 0.90, porque um quad
-- de FRONT SHAPE em degrau pode sair mais escuro que o shade plano de
-- sempre. Acha o quad frontal (z1, plano em z = 0) pelas bordas X/Y e
-- devolve o shade que ele levou, para comparar bordas e centro de um run.
local function frontQuadShadeAt(mesh, minX, maxX, minY, maxY)
  for i = 1, #mesh.verts, 4 do
    local b = quadBoundsAt(mesh, i)
    if close(b.minX, minX) and close(b.maxX, maxX)
        and close(b.minY, minY) and close(b.maxY, maxY)
        and close(b.minZ, b.maxZ) and close(b.minZ, 0) then
      return mesh.verts[i][6]
    end
  end
end

-- v1.6.0: conta quantos quads frontais (z1, plano em z = 0) tem alguma
-- borda dentro de [minX, maxX], para provar que um segmento se dividiu
-- (mais de um quad) ou nao (um so).
local function countFrontQuadsInRange(mesh, minX, maxX)
  local count = 0
  for i = 1, #mesh.verts, 4 do
    local b = quadBoundsAt(mesh, i)
    if close(b.minZ, b.maxZ) and close(b.minZ, 0)
        and b.minX >= minX - 0.0001 and b.maxX <= maxX + 0.0001 then
      count = count + 1
    end
  end
  return count
end

-- v1.6.0: como frontQuadShadeAt, mas para a face de TOPO (achatada em Y,
-- com extensao em Z): acha o quad na altura Y e nos limites X dados e
-- devolve o shade que ele levou, sem exigir um valor especifico -- o
-- objetivo e comparar shades diferentes entre borda e centro de um run de
-- TOP DOME.
local function topQuadShadeAt(mesh, minX, maxX, y)
  for i = 1, #mesh.verts, 4 do
    local b = quadBoundsAt(mesh, i)
    if close(b.minX, minX) and close(b.maxX, maxX)
        and close(b.minY, y) and close(b.maxY, y) and b.maxZ > b.minZ then
      return mesh.verts[i][6]
    end
  end
end

-- Refatoracao da tabela de opcoes: main.lua nao guarda mais um
-- upvalue dedicado por opcao (depthValue, sideColorValue, ...). Todo valor
-- resolvido mora agora numa tabela unica, `optionState` (upvalue de
-- voxelMesh, indexada pela chave da opcao: "depth", "side_color", ...). Os
-- nove helpers abaixo continuam com o mesmo proposito de sempre (mudar o
-- valor resolvido SEM passar por setOption, entao sem disparar o
-- clearCache/clearMeshCache que setOption dispara), so que agora acham
-- `optionState` (a TABELA, um objeto por referencia) e escrevem direto no
-- campo, em vez de sobrescrever um upvalue escalar via debug.setupvalue.
local function setOptionStateWithoutClearing(modules, key, value)
  local wrapper = modules.SpriteBillboards.mesh
  local voxelMesh
  for i = 1, 20 do
    local name, upvalue = debug.getupvalue(wrapper, i)
    if name == "voxelMesh" then
      voxelMesh = upvalue
      break
    end
  end
  check(type(voxelMesh) == "function", "teste encontra voxelMesh no wrapper para " .. key)
  for i = 1, 40 do
    local name, state = debug.getupvalue(voxelMesh, i)
    if name == "optionState" then
      state[key] = value
      return true
    end
  end
  return check(false, "teste encontra optionState em voxelMesh")
end

local function setDepthWithoutClearing(modules, value)
  return setOptionStateWithoutClearing(modules, "depth", value)
end

local function setSideColorWithoutClearing(modules, value)
  return setOptionStateWithoutClearing(modules, "side_color", value)
end

local function setShapeWithoutClearing(modules, value)
  return setOptionStateWithoutClearing(modules, "shape", value)
end

local function setGroundShadeWithoutClearing(modules, value)
  return setOptionStateWithoutClearing(modules, "ground_shade", value)
end

local function setBlinkWithoutClearing(modules, value)
  return setOptionStateWithoutClearing(modules, "blink", value)
end

local function setTopEdgeWithoutClearing(modules, value)
  return setOptionStateWithoutClearing(modules, "top_edge", value)
end

local function setFrontShapeWithoutClearing(modules, value)
  return setOptionStateWithoutClearing(modules, "front_shape", value)
end

local function setTopDomeWithoutClearing(modules, value)
  return setOptionStateWithoutClearing(modules, "top_dome", value)
end

local function setStepWeightWithoutClearing(modules, value)
  return setOptionStateWithoutClearing(modules, "step_weight", value)
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

-- vida: monta uma matriz de mundo de 16 numeros, row-major, no mesmo
-- formato que VoxelScene.billboardMatrix entrega (traducao na 4a coluna de
-- cada linha). model[1] faz dupla funcao, exatamente como no host: sinal do
-- espelho E x da linha 0 na formula de cisalhamento. As outras 15 celulas
-- sao numeros fixos e distintos (cada celula vale o proprio indice, exceto
-- as tres do contrato: model[1], model[4] e model[12]), para os testes
-- conseguirem distinguir "essa celula mudou" de "essa celula nao mudou"
-- sem precisar inspecionar nada alem da propria matriz.
local function lifeModel(px, py, mirrored)
  local sign = mirrored and -1 or 1
  return {
    sign, 2, 3, mirrored and (px + 16) or px,
    5, 6, 7, 8,
    9, 10, 11, py + 8,
    13, 14, 15, 16,
  }
end

-- compara duas matrizes de 16 numeros celula a celula, com a mesma
-- tolerancia de `close`.
local function sameMatrix(a, b)
  for i = 1, 16 do
    if not close(a[i], b[i]) then return false end
  end
  return true
end

-- vida, magnitude: mesma ideia de withLoveTime, mas para uma SEQUENCIA de
-- instantes em vez de um so. `fn` recebe `setClock`, que o teste chama a
-- cada quadro simulado antes de desenhar. Restaura love.timer.getTime no
-- final, mesmo se `fn` lancar.
local function withDrivenClock(fn)
  local prev = love.timer.getTime
  local now = 0
  love.timer.getTime = function() return now end
  local ok, err = pcall(fn, function(value) now = value end)
  love.timer.getTime = prev
  if not ok then error(err) end
end

-- vida, magnitude: compara dois numeros com tolerancia RELATIVA (fracao de
-- `want`). Os niveis do menu vao de 0.010 (BREATH SUBTLE) a 1.2 (MOTION LAG
-- NORMAL); uma tolerancia absoluta fixa como a de `close` nao serve nos
-- dois extremos.
local function closePercent(got, want, pct)
  return math.abs(got - want) <= math.abs(want) * pct
end

-- vida, magnitude: diferente de lifeModel (que so precisa provar "essa
-- celula mudou" ou "nao mudou"), os testes de magnitude precisam ler s, kx
-- e kz separados a partir da SAIDA. Esta matriz isola os tres numa linha
-- cada, direto da formula de lifeApply (out[c+2] = m[c+2]*s + m[c+1]*kx +
-- m[c+3]*kz):
--   linha 0 (c=0): m[1]=sinal (contrato), m[2]=0, m[3]=0 -> out[2] = sinal*kx
--   linha 1 (c=4): m[5]=0, m[6]=1, m[7]=0 -> out[6] = s
--   linha 2 (c=8): m[9]=0, m[10]=0, m[11]=1 -> out[10] = kz
-- (linha 3 nao e lida por ninguem, fica de recheio). Os contratos de
-- model[1] (sinal do espelho), model[4] (px) e model[12] (py + 8) continuam
-- valendo.
local function lifeProbeModel(px, py, mirrored)
  local sign = mirrored and -1 or 1
  return {
    sign, 0, 0, mirrored and (px + 16) or px,
    0, 1, 0, 0,
    0, 0, 1, py + 8,
    0, 0, 0, 1,
  }
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

-- v1.6.0: mesma folha de paintBlinkFace, mas com a faixa de pele esticada
-- pela celula inteira nos dois lados dos olhos, para garantir que pelo
-- menos um segmento em volta de um olho passe do limiar de 3 pixels e
-- realmente entre no caminho de degrau do FRONT SHAPE (paintBlinkFace
-- sozinha so produz segmentos de 1 e 2 pixels, curtos demais para dividir).
local function paintBlinkFaceWide(pixels, sheetW, cellW, frame, dy)
  dy = dy or 0
  local skin = rgba(0.80, 0.55, 0.40, 1)
  local eye = rgba(0.05, 0.05, 0.05, 1)
  for lx = 0, cellW - 1 do paint(pixels, sheetW, cellW, frame, lx, 7 + dy, skin) end
  paint(pixels, sheetW, cellW, frame, 6, 7 + dy, eye)
  paint(pixels, sheetW, cellW, frame, 9, 7 + dy, eye)
  paint(pixels, sheetW, cellW, frame, 6, 8 + dy, skin)
  paint(pixels, sheetW, cellW, frame, 9, 8 + dy, skin)
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
--
-- withDraw da suporte ao canal de vida (main.lua, lifeDrawWrap): sem ele o
-- Voxel3D do mock nao tem campo `draw`, do mesmo jeito que o host de sempre
-- neste arquivo, entao drawWrap fica false e LIFE le NO CHANNEL. Com ele, o
-- mock ganha um `draw` que so registra a chamada (mesh, texture, model,
-- pull, sunModel) em Voxel3D.drawCalls, para os testes lerem depois, e
-- devolve "drew" para simular um retorno qualquer do host.
local function makeVoxelHandle(version, pixels, w, h, angle, spriteLean,
                               cardBlend, omitFirstPerson, hostId, withDraw)
  local modules = {}
  local V = {}
  local original = function(def, frame)
    return { original = true, def = def, frame = frame }
  end
  function V.require(name)
    if modules[name] then return modules[name] end
    if name == "Voxel3D" then
      local voxel3D
      voxel3D = {
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
          voxel3D.created = voxel3D.created + 1
          return fakeMesh(verts, map)
        end,
      }
      if withDraw then
        voxel3D.drawCalls = {}
        voxel3D.draw = function(mesh, texture, model, pull, sunModel)
          local calls = voxel3D.drawCalls
          calls[#calls + 1] = { mesh = mesh, texture = texture,
            model = model, pull = pull, sunModel = sunModel }
          return "drew"
        end
      end
      modules[name] = voxel3D
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

-- SO_ESTA: fixa todas as opcoes de vida em OFF e liga apenas as pedidas.
--
-- Existe porque mudar um DEFAULT do produto quebrou oito checks de uma vez, e
-- eles quebraram pelo motivo certo: testavam uma opcao e deixavam as outras no
-- default, entao o dia em que BREATH passou a nascer ligado, um teste sobre
-- FOOTFALL passou a medir os dois somados. Teste sobre uma coisa fixa todas as
-- outras; default e assunto do teste que cobre default, e de mais nenhum.
local function soEsta(extra)
  local o = { blink = "off", breath = "off", sway = "off", lag = "off",
              footfall = "off" }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
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

-- vida: mesma ideia de statusRowValue, para a row de LIFE.
local function lifeRowValue(mod)
  local rows = {}
  mod._rows["ui.options.rows"](function(_, r) return r end, {}, rows)
  for _, row in ipairs(rows) do
    if row.label == "LIFE" then return row.value() end
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
  -- A versao REAL e atual do Dramaless Shape, travada aqui de proposito.
  --
  -- O repositorio do Dramatic Shape original saiu do ar pela segunda vez, e
  -- este fork passou a ser o host que a maior parte da comunidade roda. A
  -- faixa `>=1.5.0 <2.0.0` cobre 1.6.4 hoje; se alguem apertar essa faixa numa
  -- rodada futura sem perceber, o mod passa a logar "untested version" para o
  -- host mais usado que existe, e ninguem descobre porque nada quebra. Este
  -- teste existe para quebrar antes disso.
  --
  -- Conferido contra a release de verdade: id DRAMALESS_SHAPE, api 2, e os
  -- seis modulos que a gente consome presentes, com SpriteBillboards.mesh
  -- ainda campo de tabela.
  local pixels = {}
  pixels[0] = 1
  local handle, modules, original = makeVoxelHandle("1.6.4", pixels, 16, 16,
    nil, nil, nil, nil, "DRAMALESS_SHAPE")
  local mod = loadWith(makeMod(handle))
  check(modules.SpriteBillboards.mesh ~= original,
        "Dramaless Shape 1.6.4 e aceito")
  local avisoDeVersao = false
  for _, w in ipairs(mod._logs.warn or {}) do
    if w:find("untested version", 1, true) then avisoDeVersao = true end
  end
  check(not avisoDeVersao,
        "Dramaless Shape 1.6.4 esta DENTRO da faixa testada, sem aviso")
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
  eq(#rows, 13, "hook anexa as rows, mais STATUS, LIFE e CAMERA FIT")
  eq(rows[2].label, "STATUS", "hook anexa a row de STATUS logo depois do next")
  eq(rows[3].label, "LIFE", "hook anexa a row de LIFE logo depois do STATUS")
  eq(rows[4].label, "CAMERA FIT", "CAMERA FIT vem depois de LIFE, antes das opcoes")
  local option = rows[5]
  eq(rows[6].label, "SIDE COLOR", "hook anexa a row de cor lateral")
  eq(rows[7].label, "SHAPE", "hook anexa a row de shape")
  eq(rows[8].label, "GROUND SHADE", "hook anexa a row de ground shade")
  eq(rows[9].label, "BLINK", "hook anexa a row de blink")
  eq(rows[10].label, "TOP EDGE", "hook anexa a row de top edge")
  eq(rows[11].label, "FRONT SHAPE", "hook anexa a row de front shape")
  eq(rows[12].label, "TOP DOME", "hook anexa a row de top dome")
  eq(rows[13].label, "STEP WEIGHT", "hook anexa a row de step weight")
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
  local option = rows[9]
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
  -- v1.6.0: a row de FRONT SHAPE, no mesmo padrao das outras: default OFF
  -- (regra da casa), quatro degraus (OFF, LOW 0.12, MED 0.17, HIGH 0.22),
  -- step troca e persiste no save e no loader.
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
  local option = rows[10]
  eq(option.label, "FRONT SHAPE", "row de FRONT SHAPE fica depois de TOP EDGE")
  eq(option.value(), "OFF", "FRONT SHAPE default e OFF")
  check(option.step(game, 1), "step de FRONT SHAPE informa mudanca")
  eq(option.value(), "LOW", "FRONT SHAPE alterna para LOW")
  eq(game.save.options.modOptions.voxel_characters.front_shape, 0.12,
     "FRONT SHAPE persiste no save")
  eq(game.mods.modOptions.voxel_characters.front_shape, 0.12,
     "FRONT SHAPE persiste no loader")
  eq(emitted[1].payload.value, 0.12, "FRONT SHAPE emite o valor novo")
  check(option.step(game, 1), "FRONT SHAPE segue avancando")
  eq(option.value(), "MED", "FRONT SHAPE alterna para MED")
  check(option.step(game, 1), "FRONT SHAPE segue avancando")
  eq(option.value(), "HIGH", "FRONT SHAPE alterna para HIGH")
  check(option.step(game, 1), "FRONT SHAPE da a volta")
  eq(option.value(), "OFF", "FRONT SHAPE volta para OFF depois de HIGH")
end

do
  -- v1.6.0: a row de TOP DOME, no mesmo padrao das outras: default OFF
  -- (regra da casa), dois degraus (OFF, LOW 0.15, HIGH 0.30 -- so os dois
  -- pontos medidos, sem um MED interpolado), step troca e persiste no save
  -- e no loader.
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
  local option = rows[11]
  eq(option.label, "TOP DOME", "row de TOP DOME fica depois de FRONT SHAPE")
  eq(option.value(), "OFF", "TOP DOME default e OFF")
  check(option.step(game, 1), "step de TOP DOME informa mudanca")
  eq(option.value(), "LOW", "TOP DOME alterna para LOW")
  eq(game.save.options.modOptions.voxel_characters.top_dome, 0.15,
     "TOP DOME persiste no save")
  eq(game.mods.modOptions.voxel_characters.top_dome, 0.15,
     "TOP DOME persiste no loader")
  eq(emitted[1].payload.value, 0.15, "TOP DOME emite o valor novo")
  check(option.step(game, 1), "TOP DOME segue avancando")
  eq(option.value(), "HIGH", "TOP DOME alterna para HIGH")
  check(option.step(game, 1), "TOP DOME da a volta")
  eq(option.value(), "OFF", "TOP DOME volta para OFF depois de HIGH")
end

do
  -- v1.6.0: a row de STEP WEIGHT, no mesmo padrao das outras: default OFF
  -- (regra da casa -- alem disso, e a primeira opcao desta branch que move
  -- vertice em vez de shade, entao o conservadorismo pesa ainda mais), dois
  -- degraus (OFF, LOW 0.25, HIGH 0.5), step troca e persiste no save e no
  -- loader.
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
  local option = rows[12]
  eq(option.label, "STEP WEIGHT", "row de STEP WEIGHT fica depois de TOP DOME")
  eq(option.value(), "OFF", "STEP WEIGHT default e OFF")
  check(option.step(game, 1), "step de STEP WEIGHT informa mudanca")
  eq(option.value(), "LOW", "STEP WEIGHT alterna para LOW")
  eq(game.save.options.modOptions.voxel_characters.step_weight, 0.25,
     "STEP WEIGHT persiste no save")
  eq(game.mods.modOptions.voxel_characters.step_weight, 0.25,
     "STEP WEIGHT persiste no loader")
  eq(emitted[1].payload.value, 0.25, "STEP WEIGHT emite o valor novo")
  check(option.step(game, 1), "STEP WEIGHT segue avancando")
  eq(option.value(), "HIGH", "STEP WEIGHT alterna para HIGH")
  check(option.step(game, 1), "STEP WEIGHT da a volta")
  eq(option.value(), "OFF", "STEP WEIGHT volta para OFF depois de HIGH")
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
  -- v1.6.0, teste obrigatorio 5: "a chave de cache muda com a forca". Sem
  -- isso a opcao nao muda nada na tela: e literalmente o defeito que o
  -- Colonel_Aureliano reportou na v1.4.0 (trocar a opcao no menu nao mudava
  -- nada, porque a malha continuava vindo do cache antigo).
  local cellW, cellH = 1, 1
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paint(pixels, sheetW, cellW, frame, 0, 0, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", front_shape = "off" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local off = modules.SpriteBillboards.mesh(def, 0)
  setFrontShapeWithoutClearing(modules, 0.12)
  local low = modules.SpriteBillboards.mesh(def, 0)
  setFrontShapeWithoutClearing(modules, 0.22)
  local high = modules.SpriteBillboards.mesh(def, 0)
  check(off ~= low and low ~= high and off ~= high,
        "cacheKey separa FRONT SHAPE mesmo sem limpar o cache")
  eq(modules.Voxel3D.created, 3,
     "cacheKey cria uma entrada propria para cada FRONT SHAPE")
end

do
  local cellW, cellH = 1, 1
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paint(pixels, sheetW, cellW, frame, 0, 0, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved", front_shape = "off" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local a = modules.SpriteBillboards.mesh(def, 0)
  setFrontShapeWithoutClearing(modules, 0.12)
  local b = modules.SpriteBillboards.mesh(def, 0)
  eq(a, b, "cacheKey ignora FRONT SHAPE quando SHAPE e CARVED")
  eq(modules.Voxel3D.created, 1,
     "CARVED nao duplica malha identica ao trocar FRONT SHAPE")
end

do
  local cellW, cellH = 1, 1
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paint(pixels, sheetW, cellW, frame, 0, 0, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved", top_dome = "off" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local a = modules.SpriteBillboards.mesh(def, 0)
  setTopDomeWithoutClearing(modules, 0.15)
  local b = modules.SpriteBillboards.mesh(def, 0)
  eq(a, b, "cacheKey ignora TOP DOME quando SHAPE e CARVED")
  eq(modules.Voxel3D.created, 1,
     "CARVED nao duplica malha identica ao trocar TOP DOME")
end

do
  -- v1.6.0, teste obrigatorio 5: "a chave de cache muda com a forca". Sem
  -- isso a opcao nao muda nada na tela: e literalmente o defeito que o
  -- Colonel_Aureliano reportou na v1.4.0 (trocar a opcao no menu nao mudava
  -- nada, porque a malha continuava vindo do cache antigo).
  local cellW, cellH = 1, 1
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paint(pixels, sheetW, cellW, frame, 0, 0, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", top_dome = "off" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local off = modules.SpriteBillboards.mesh(def, 0)
  setTopDomeWithoutClearing(modules, 0.15)
  local low = modules.SpriteBillboards.mesh(def, 0)
  setTopDomeWithoutClearing(modules, 0.30)
  local high = modules.SpriteBillboards.mesh(def, 0)
  check(off ~= low and low ~= high and off ~= high,
        "cacheKey separa TOP DOME mesmo sem limpar o cache (off/low/high)")
  eq(modules.Voxel3D.created, 3,
     "cacheKey cria uma entrada propria para cada forca de TOP DOME")
end

do
  -- v1.6.0, teste obrigatorio 6: "a chave de cache muda com a forca". Sem
  -- isso a opcao nao muda nada na tela ate o LRU reciclar por acaso, o
  -- mesmo defeito que o Colonel_Aureliano reportou na v1.4.0. Prova por
  -- reversao: sem `stepWeightPart` em cacheKey, off/low/high colapsam na
  -- MESMA chave e `Voxel3D.created` fica em 1, nao 3.
  local cellW, cellH = 1, 1
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paint(pixels, sheetW, cellW, frame, 0, 0, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", step_weight = "off" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local off = modules.SpriteBillboards.mesh(def, 0)
  setStepWeightWithoutClearing(modules, 0.25)
  local low = modules.SpriteBillboards.mesh(def, 0)
  setStepWeightWithoutClearing(modules, 0.5)
  local high = modules.SpriteBillboards.mesh(def, 0)
  check(off ~= low and low ~= high and off ~= high,
        "cacheKey separa STEP WEIGHT mesmo sem limpar o cache (off/low/high)")
  eq(modules.Voxel3D.created, 3,
     "cacheKey cria uma entrada propria para cada forca de STEP WEIGHT")
end

do
  -- STEP WEIGHT, como FRONT SHAPE e TOP DOME, so existe para SLAB: CARVED
  -- constroi a partir do casco visual em voxels, sem o `p()` que aplica o
  -- cisalhamento. A chave ignora a forca de proposito fora do SLAB, para
  -- nao duplicar malhas identicas so porque o menu trocou de nivel.
  local cellW, cellH = 1, 1
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paint(pixels, sheetW, cellW, frame, 0, 0, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "carved", step_weight = "off" }))
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }
  local a = modules.SpriteBillboards.mesh(def, 0)
  setStepWeightWithoutClearing(modules, 0.5)
  local b = modules.SpriteBillboards.mesh(def, 0)
  eq(a, b, "cacheKey ignora STEP WEIGHT quando SHAPE e CARVED")
  eq(modules.Voxel3D.created, 1,
     "CARVED nao duplica malha identica ao trocar STEP WEIGHT")
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
  -- STATUS e da LIFE.
  local pixels = {}
  pixels[0] = 1
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle))
  local rows = {}
  mod._rows["ui.options.rows"](function(_, r) return r end, {}, rows)
  eq(#rows, 12, "com host, doze rows: STATUS, LIFE, CAMERA FIT e as nove de sempre")
  eq(rows[1].label, "STATUS", "STATUS vem primeiro")
  eq(rows[2].label, "LIFE", "LIFE vem logo depois do STATUS")
  eq(rows[3].label, "CAMERA FIT", "CAMERA FIT vem depois de LIFE")
  eq(rows[4].label, "VOXEL CHARS", "DEPTH continua na mesma posicao relativa")
  eq(rows[5].label, "SIDE COLOR", "SIDE COLOR continua na mesma posicao relativa")
  eq(rows[6].label, "SHAPE", "SHAPE continua na mesma posicao relativa")
  eq(rows[7].label, "GROUND SHADE", "GROUND SHADE continua na mesma posicao relativa")
  eq(rows[8].label, "BLINK", "BLINK continua na mesma posicao relativa")
  eq(rows[9].label, "TOP EDGE", "TOP EDGE continua na mesma posicao relativa")
  eq(rows[10].label, "FRONT SHAPE", "FRONT SHAPE aparece depois de TOP EDGE")
  eq(rows[11].label, "TOP DOME", "TOP DOME aparece depois de FRONT SHAPE")
  eq(rows[12].label, "STEP WEIGHT", "STEP WEIGHT aparece depois de TOP DOME")

  -- APERTAR A NUMA ROW SO DE LEITURA NAO PODE FECHAR O MENU.
  --
  -- OptionsMenu:update (src/ui/OptionsMenu.lua:549-566) resolve A, esquerda e
  -- direita no mesmo ramo, nesta ordem: `activate`, senao `step`, senao, se foi
  -- A, trata como CANCEL e da pop no menu. STATUS e LIFE tem `value` e mais
  -- nada, entao caiam no terceiro caso: A em cima delas fechava a tela de
  -- opcoes inteira. E A e a primeira tecla que alguem aperta numa linha que nao
  -- reconhece, que e exatamente o publico da row de STATUS.
  --
  -- O teste amarra o CONTRATO do motor, nao a nossa implementacao: toda row que
  -- oferece `value` sem `step` precisa de `activate`, senao o motor a confunde
  -- com o CANCEL.
  for _, row in ipairs(rows) do
    if row.value and not row.step then
      check(type(row.activate) == "function",
        "row so de leitura " .. tostring(row.label) ..
        " tem activate, senao A nela fecharia o menu")
    end
  end
  eq(type(rows[1].activate), "function", "STATUS tem activate")
  eq(type(rows[2].activate), "function", "LIFE tem activate")
  eq(rows[1].step, nil, "STATUS continua sem step: nao e para ciclar nada")
  eq(rows[2].step, nil, "LIFE continua sem step")
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

-- v1.6.0: FRONT SHAPE. Volume na face frontal do SLAB em degraus alinhados
-- ao pixel, opcao nova de menu com default OFF. Os cinco testes abaixo sao
-- os obrigatorios da spec da rodada; a row/step/persist e as duas variantes
-- de cacheKey (SLAB separa, CARVED ignora) ja foram cobertas mais acima,
-- junto das rows e cacheKeys das outras opcoes.

do
  -- teste obrigatorio 1: "com a opcao desligada, a malha e byte a byte a de
  -- hoje". Um run de largura 6 (bem acima do limiar de degrau) continua
  -- saindo como UM quad so, no shade OBJ_SHADE.front de sempre, tanto com
  -- front_shape = "off" explicito quanto sem a chave (default). Se o degrau
  -- vazasse por baixo do OFF, este run quebraria em varios quads ou mudaria
  -- de shade.
  local cellW, cellH = 16, 16
  local pixels = {}
  for lx = 4, 9 do paint(pixels, cellW, cellW, 0, lx, 7, 1) end
  local def = { image = "sheet.png", frames = 1 }

  local handleOff, modulesOff = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handleOff, { depth = 2, shape = "slab", front_shape = "off" }))
  local gotOff = modulesOff.SpriteBillboards.mesh(def, 0)

  local handleDefault, modulesDefault = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handleDefault, { depth = 2, shape = "slab" }))
  local gotDefault = modulesDefault.SpriteBillboards.mesh(def, 0)

  check(frontQuadIndexAt(gotOff, 4, 10, 8, 9) ~= nil,
        "FRONT SHAPE desligado mantem o run inteiro num quad so, shade de sempre")
  eq(countFrontQuadsInRange(gotOff, 4, 10), 1,
     "FRONT SHAPE desligado nao divide o run em mais de um quad")
  eq(vertexSignature(gotOff), vertexSignature(gotDefault),
     "FRONT SHAPE OFF explicito e o default (sem a chave) produzem a mesma malha, byte a byte")
end

do
  -- teste obrigatorio 2: "run de 2 pixels nao se divide -- contagem exata".
  -- A mesma linha tem dois runs separados por um vao: um de 2 pixels (1 a
  -- 2) e um de 6 pixels (6 a 11, bem acima do limiar de degrau). O teste
  -- prova que excluir runs curtos e uma REGRA (largura < 3), nao apenas
  -- "nada divide": o run de 6 pixels tem que se dividir em degraus e o de
  -- 2, na mesma folha com a mesma opcao ligada, nao. Nao ha um pixel "do
  -- meio" distinto das duas bordas num run de largura 2: dividir so
  -- custaria quad sem nenhum degrau possivel.
  local cellW, cellH = 16, 16
  local pixels = {}
  paint(pixels, cellW, cellW, 0, 1, 7, 1)
  paint(pixels, cellW, cellW, 0, 2, 7, 1)
  for lx = 6, 11 do paint(pixels, cellW, cellW, 0, lx, 7, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", front_shape = 0.12 }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  check(frontQuadIndexAt(got, 1, 3, 8, 9) ~= nil,
        "run de 2 pixels continua inteiro num quad so, mesmo com FRONT SHAPE ligado")
  eq(countFrontQuadsInRange(got, 1, 3), 1,
     "run de 2 pixels nao se divide -- contagem exata")
  eq(countFrontQuadsInRange(got, 6, 12), 6,
     "run de 2 pixels nao se divide -- contagem exata (controle: o run de 6 pixels na mesma folha se divide)")
end

do
  -- teste obrigatorio 3: "o shade e simetrico em torno do centro do run".
  -- Run de largura impar (5 pixels, 4 a 8): a borda esquerda (pixel 4) e a
  -- borda direita (pixel 8) tem que sair no MESMO shade, e o centro (pixel
  -- 6) tem que sair mais claro que as bordas, senao o degrau nao aconteceu
  -- de verdade.
  local cellW, cellH = 16, 16
  local pixels = {}
  for lx = 4, 8 do paint(pixels, cellW, cellW, 0, lx, 7, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", front_shape = 0.12 }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local left = frontQuadShadeAt(got, 4, 5, 8, 9)
  local right = frontQuadShadeAt(got, 8, 9, 8, 9)
  local center = frontQuadShadeAt(got, 6, 7, 8, 9)
  check(left ~= nil and right ~= nil and center ~= nil,
        "teste encontra os tres quads do run (borda esquerda, centro, borda direita)")
  eq(left, right, "o primeiro e o ultimo pixel do run tem o mesmo shade")
  check(center and left and center > left,
        "o centro do run sai mais claro que as bordas -- o degrau aconteceu")
end

do
  -- v1.6.0: a mesma simetria vale espelhada (mascara desenhada do lado
  -- direito da celula em vez do esquerdo), provando que o shade depende so
  -- do centro do PROPRIO run (a e b), nunca de uma coordenada absoluta de
  -- tela nem de estar no lado leste ou oeste da celula.
  local cellW, cellH = 16, 16
  local pixels = {}
  for lx = 9, 13 do paint(pixels, cellW, cellW, 0, lx, 7, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", front_shape = 0.12 }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local left = frontQuadShadeAt(got, 9, 10, 8, 9)
  local right = frontQuadShadeAt(got, 13, 14, 8, 9)
  check(left ~= nil and right ~= nil,
        "teste encontra as duas bordas do run espelhado")
  eq(left, right,
     "o shade simetrico nao depende de estar no lado leste ou oeste da celula")
end

do
  -- teste obrigatorio 4 (pose 1 de 4: frente, parado, frame 0): a piscada
  -- continua funcionando com FRONT SHAPE ligado. O olho continua seu
  -- proprio quad (main.lua ~1417-1428), com shade plano, nunca escalonado;
  -- o segmento de 6 pixels antes dele se divide em degraus ao redor dele.
  local cellW, cellH = 16, 16
  local pixels = {}
  paintBlinkFaceWide(pixels, cellW, cellW, 0)
  local closedTime, openTime = blinkTimes("red")
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle,
    { depth = 2, shape = "slab", blink = "on", front_shape = 0.12 }))
  local def = { image = "red.png", frames = 1 }
  withLoveTime(openTime, function()
    local got = modules.SpriteBillboards.mesh(def, 0)
    local leftEye = frontQuadIndexAt(got, 6, 7, 8, 9)
    check(leftEye ~= nil,
          "de frente parado: olho continua proprio quad com FRONT SHAPE ligado")
    check(allUvAt(got, leftEye, 6.5 / 16, 7.5 / 16),
          "de frente parado, olho aberto aponta para o proprio texel")
  end)
  withLoveTime(closedTime, function()
    local got = modules.SpriteBillboards.mesh(def, 0)
    local leftEye = frontQuadIndexAt(got, 6, 7, 8, 9)
    check(allUvAt(got, leftEye, 6.5 / 16, 8.5 / 16),
          "de frente parado, a piscada continua acontecendo com a opcao ligada")
  end)
  local got = modules.SpriteBillboards.mesh(def, 0)
  check(countFrontQuadsInRange(got, 0, 6) > 1,
        "o segmento antes do olho se divide em degraus sem quebrar a piscada")
end

do
  -- teste obrigatorio 4 (pose 2 de 4: frente, andando, frame 3). Frame 3 e
  -- o frame 0 descido uma linha, o mesmo passo de caminhada que o resto da
  -- suite ja usa para BLINK.
  local cellW, cellH = 16, 18
  local sheetW = cellW * 6
  local pixels = {}
  paintBlinkFaceWide(pixels, sheetW, cellW, 0, 0)
  paintBlinkFaceWide(pixels, sheetW, cellW, 3, 1)
  local closedTime, openTime = blinkTimes("red")
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle,
    { depth = 2, shape = "slab", blink = "on", front_shape = 0.12 }))
  local def = { image = "red.png", frames = 6, frameWidth = cellW }
  withLoveTime(openTime, function()
    local walk = modules.SpriteBillboards.mesh(def, 3)
    local eye = frontQuadIndexAt(walk, 6, 7, 9, 10)
    check(eye ~= nil,
          "de frente andando: olho continua proprio quad com FRONT SHAPE ligado")
    check(allUvAt(walk, eye, (3 * cellW + 6.5) / sheetW, 8.5 / cellH),
          "de frente andando, olho aberto aponta para o proprio texel")
  end)
  withLoveTime(closedTime, function()
    local walk = modules.SpriteBillboards.mesh(def, 3)
    local eye = frontQuadIndexAt(walk, 6, 7, 9, 10)
    check(allUvAt(walk, eye, (3 * cellW + 6.5) / sheetW, 9.5 / cellH),
          "de frente andando, a piscada continua acontecendo com a opcao ligada")
  end)
end

do
  -- teste obrigatorio 4 (pose 3 de 4 e 4 de 4: perfil parado, frame 2, e
  -- perfil andando, frame 5). paintBlinkSide ja produz um segmento de 3
  -- pixels depois do olho (6 a 8), no limiar de degrau, sem precisar de
  -- fixture nova.
  local cellW, cellH = 16, 16
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do paintBlinkSide(pixels, sheetW, cellW, frame) end
  local closedTime, openTime = blinkTimes("red")
  local handle, modules = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handle,
    { depth = 2, shape = "slab", blink = "on", front_shape = 0.12 }))
  local def = { image = "red.png", frames = 6, frameWidth = cellW }
  withLoveTime(openTime, function()
    local side = modules.SpriteBillboards.mesh(def, 2)
    local sideEye = frontQuadIndexAt(side, 5, 6, 8, 9)
    check(sideEye ~= nil,
          "de perfil parado: olho continua proprio quad com FRONT SHAPE ligado")
    check(allUvAt(side, sideEye, (2 * cellW + 5.5) / sheetW, 7.5 / cellH),
          "de perfil parado, olho aberto aponta para o proprio texel")
    local sideWalk = modules.SpriteBillboards.mesh(def, 5)
    local sideWalkEye = frontQuadIndexAt(sideWalk, 5, 6, 8, 9)
    check(allUvAt(sideWalk, sideWalkEye, (5 * cellW + 5.5) / sheetW, 7.5 / cellH),
          "de perfil andando, olho aberto aponta para o proprio texel")
  end)
  withLoveTime(closedTime, function()
    local side = modules.SpriteBillboards.mesh(def, 2)
    local sideEye = frontQuadIndexAt(side, 5, 6, 8, 9)
    check(allUvAt(side, sideEye, (2 * cellW + 5.5) / sheetW, 8.5 / cellH),
          "de perfil parado, a piscada continua acontecendo com a opcao ligada")
    local sideWalk = modules.SpriteBillboards.mesh(def, 5)
    local sideWalkEye = frontQuadIndexAt(sideWalk, 5, 6, 8, 9)
    check(allUvAt(sideWalk, sideWalkEye, (5 * cellW + 5.5) / sheetW, 8.5 / cellH),
          "de perfil andando, a piscada continua acontecendo com a opcao ligada")
  end)
  local side = modules.SpriteBillboards.mesh(def, 2)
  check(countFrontQuadsInRange(side, 6, 9) > 1,
        "o segmento depois do olho de perfil se divide em degraus sem quebrar a piscada")
end

do
  -- ACHADO (pente fino de olho novo): emitFrontRun calculava `center` e
  -- `half` a partir do SEGMENTO recebido por chamada (a, b), nao do run
  -- opaco inteiro (lx, lx2). O laco que corta o run nos olhos (main.lua,
  -- logo abaixo da definicao de emitFrontRun) chama emitFrontRun uma vez
  -- por pedaco, entao cada pedaco era tratado como se fosse um run
  -- inteiro, com sua propria "borda mais escura" -- inclusive no pixel que
  -- so esta colado no olho e nao perto de nenhuma borda real da silhueta.
  -- Isso desenhava um anel escuro em volta de cada olho: vale para
  -- qualquer folha com marca de olho, em toda pose que pisca, e independe
  -- da opcao BLINK, porque o corte por isEye nunca consulta blinkValue --
  -- por isso este teste nao liga BLINK. Nem a silhueta, nem a contagem de
  -- quads, nem a estrutura tonal pegam isso: so o shade de pixels
  -- especificos fica errado, por isso nenhum teste anterior encontrou o
  -- defeito.
  --
  -- paintBlinkFaceWide pinta a linha inteira (lx 0 a 15) como um unico run
  -- opaco, com os olhos do "red" (EYE_MARKS.red, lx 6 e 9) cortando as
  -- CHAMADAS a emitFrontRun em tres pedacos sem cortar o run em si. Forca
  -- 0.22 (HIGH), a mesma da reproducao do revisor.
  local cellW, cellH = 16, 16
  local pixels = {}
  paintBlinkFaceWide(pixels, cellW, cellW, 0)
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", front_shape = 0.22 }))
  local got = modules.SpriteBillboards.mesh({ image = "red.png", frames = 1 }, 0)
  local trueEdgeLeft = frontQuadShadeAt(got, 0, 1, 8, 9)
  local trueEdgeRight = frontQuadShadeAt(got, 15, 16, 8, 9)
  local eyeAdjacentLeft = frontQuadShadeAt(got, 5, 6, 8, 9)
  local eyeAdjacentRight = frontQuadShadeAt(got, 10, 11, 8, 9)
  check(trueEdgeLeft ~= nil and trueEdgeRight ~= nil
        and eyeAdjacentLeft ~= nil and eyeAdjacentRight ~= nil,
        "teste encontra os quatro quads (duas bordas reais, dois pixels colados nos olhos)")
  eq(trueEdgeLeft, trueEdgeRight,
     "as duas bordas reais da silhueta saem no mesmo shade, o mais escuro do run")
  check(eyeAdjacentLeft > trueEdgeLeft,
        "o pixel colado no olho esquerdo sai mais claro que a borda real da silhueta, "
        .. "nao no mesmo tom escuro")
  check(eyeAdjacentRight > trueEdgeRight,
        "o pixel colado no olho direito sai mais claro que a borda real da silhueta, "
        .. "nao no mesmo tom escuro")
  eq(eyeAdjacentLeft, eyeAdjacentRight,
     "os dois pixels colados nos olhos saem simetricos entre si")
end

-- v1.6.0: TOP DOME. Volume na face de TOPO do SLAB em degraus alinhados ao
-- pixel, opcao nova de menu com default OFF. Os seis testes abaixo sao os
-- obrigatorios da spec da rodada; a row/step/persist e as duas variantes de
-- cacheKey (SLAB separa, CARVED ignora) ja foram cobertas mais acima, junto
-- das rows e cacheKeys das outras opcoes. Todas as folhas pintam so a linha
-- ly = 7 (o mesmo ly que FRONT SHAPE ja usa), entao nenhuma linha acima
-- existe e todo pixel pintado sai como face de topo, sem precisar de uma
-- fixture nova por teste.

do
  -- teste obrigatorio 1: "com a opcao desligada, a malha e byte a byte a de
  -- hoje". Um run de largura 6 (acima do limiar de degrau) continua com
  -- TODOS os pixels de topo no mesmo shade -- topShade() de sempre --
  -- tanto com top_dome = "off" explicito quanto sem a chave (default). Se o
  -- degrau vazasse por baixo do OFF, os pixels de borda sairiam mais
  -- escuros que o do centro.
  local cellW, cellH = 16, 16
  local pixels = {}
  for lx = 4, 9 do paint(pixels, cellW, cellW, 0, lx, 7, 1) end
  local def = { image = "sheet.png", frames = 1 }
  local topY = cellH - 7

  local handleOff, modulesOff = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handleOff, { depth = 2, shape = "slab", top_dome = "off" }))
  local gotOff = modulesOff.SpriteBillboards.mesh(def, 0)

  local handleDefault, modulesDefault = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handleDefault, { depth = 2, shape = "slab" }))
  local gotDefault = modulesDefault.SpriteBillboards.mesh(def, 0)

  eq(vertexSignature(gotOff), vertexSignature(gotDefault),
     "TOP DOME OFF explicito e o default (sem a chave) produzem a mesma malha, byte a byte")

  local edge = topQuadShadeAt(gotOff, 4, 5, topY)
  local center = topQuadShadeAt(gotOff, 6, 7, topY)
  local other = topQuadShadeAt(gotOff, 9, 10, topY)
  check(edge ~= nil and center ~= nil and other ~= nil,
        "teste encontra os quads de topo do run")
  eq(edge, center, "TOP DOME desligado: shade constante em todo o run, sem degrau")
  eq(center, other, "TOP DOME desligado: shade constante em todo o run, sem degrau (borda direita)")
  eq(edge, 0.82, "TOP DOME desligado devolve o shade de topo de hoje (TOP EDGE default ON)")
end

do
  -- teste obrigatorio 2: "a contagem de quads nao muda com a opcao ligada"
  -- -- e o que separa esta mudanca da anterior. FRONT SHAPE ACRESCENTA
  -- quads ao dividir o run frontal quando ligado (de 1 quad para ate 6); a
  -- face de topo ja saia por pixel MESMO ANTES desta feature (o laco
  -- `for sx = lx, lx2 do if not at(sx, ly - 1)`), entao ligar TOP DOME so
  -- troca o shade de um quad que ja existia, nunca adiciona um novo.
  local cellW, cellH = 16, 16
  local pixels = {}
  for lx = 4, 9 do paint(pixels, cellW, cellW, 0, lx, 7, 1) end
  local def = { image = "sheet.png", frames = 1 }

  local handleOff, modulesOff = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handleOff, { depth = 2, shape = "slab", top_dome = "off" }))
  local gotOff = modulesOff.SpriteBillboards.mesh(def, 0)

  local handleOn, modulesOn = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handleOn, { depth = 2, shape = "slab", top_dome = 0.30 }))
  local gotOn = modulesOn.SpriteBillboards.mesh(def, 0)

  eq(quadCount(gotOn), quadCount(gotOff),
     "TOP DOME ligado nao muda a contagem de quads")
  eq(positionSignature(gotOn), positionSignature(gotOff),
     "TOP DOME ligado nao move nenhum vertice nem UV -- so troca o shade")
  check(vertexSignature(gotOn) ~= vertexSignature(gotOff),
        "controle: o shade realmente mudou (senao os dois testes acima estariam provando o nada)")
end

do
  -- teste obrigatorio 3: "o shade do topo e simetrico em torno do centro do
  -- run". Run de largura impar (5 pixels, 4 a 8): a borda esquerda (pixel
  -- 4) e a borda direita (pixel 8) tem que sair no MESMO shade, e o centro
  -- (pixel 6) tem que sair mais claro que as bordas, senao o degrau nao
  -- aconteceu de verdade.
  local cellW, cellH = 16, 16
  local pixels = {}
  for lx = 4, 8 do paint(pixels, cellW, cellW, 0, lx, 7, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", top_dome = 0.30 }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local topY = cellH - 7
  local left = topQuadShadeAt(got, 4, 5, topY)
  local right = topQuadShadeAt(got, 8, 9, topY)
  local center = topQuadShadeAt(got, 6, 7, topY)
  check(left ~= nil and right ~= nil and center ~= nil,
        "teste encontra os tres quads de topo do run (borda esquerda, centro, borda direita)")
  eq(left, right, "o primeiro e o ultimo pixel do run de topo tem o mesmo shade")
  check(center and left and center > left,
        "o centro do run de topo sai mais claro que as bordas -- o degrau aconteceu")
end

do
  -- v1.6.0: a mesma simetria vale espelhada (mascara desenhada do lado
  -- direito da celula em vez do esquerdo), provando que o shade depende so
  -- do centro do PROPRIO run (a e b: lx, lx2 da linha), nunca de uma
  -- coordenada absoluta de tela nem de estar no lado leste ou oeste -- a
  -- restricao de simetria em X que a spec exige.
  local cellW, cellH = 16, 16
  local pixels = {}
  for lx = 9, 13 do paint(pixels, cellW, cellW, 0, lx, 7, 1) end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handle, { depth = 2, shape = "slab", top_dome = 0.30 }))
  local got = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local topY = cellH - 7
  local left = topQuadShadeAt(got, 9, 10, topY)
  local right = topQuadShadeAt(got, 13, 14, topY)
  check(left ~= nil and right ~= nil,
        "teste encontra as duas bordas do run de topo espelhado")
  eq(left, right,
     "o shade de topo simetrico nao depende de estar no lado leste ou oeste da celula")
end

do
  -- teste obrigatorio 4: "run de 2 pixels nao recebe degrau". A mesma linha
  -- tem dois runs separados por um vao: um de 2 pixels (1 a 2) e um de 6
  -- pixels (6 a 11, acima do limiar de degrau). O run curto tem que sair no
  -- MESMO shade ligado ou desligado (nao ha pixel "do meio" distinto das
  -- duas bordas num run de largura 2: dividir so custaria quad sem nenhum
  -- degrau possivel); o de 6 pixels, na mesma folha com a mesma opcao
  -- ligada, tem que degrauar de verdade -- controle de que a exclusao e uma
  -- REGRA (largura < 3), nao "nada degraua".
  local cellW, cellH = 16, 16
  local pixels = {}
  paint(pixels, cellW, cellW, 0, 1, 7, 1)
  paint(pixels, cellW, cellW, 0, 2, 7, 1)
  for lx = 6, 11 do paint(pixels, cellW, cellW, 0, lx, 7, 1) end
  local def = { image = "sheet.png", frames = 1 }
  local topY = cellH - 7

  local handleOff, modulesOff = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handleOff, { depth = 2, shape = "slab", top_dome = "off" }))
  local gotOff = modulesOff.SpriteBillboards.mesh(def, 0)

  local handleOn, modulesOn = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handleOn, { depth = 2, shape = "slab", top_dome = 0.30 }))
  local gotOn = modulesOn.SpriteBillboards.mesh(def, 0)

  local shortOff = topQuadShadeAt(gotOff, 1, 2, topY)
  local shortOn = topQuadShadeAt(gotOn, 1, 2, topY)
  check(shortOff ~= nil and shortOn ~= nil, "teste encontra os quads do run curto")
  eq(shortOn, shortOff,
     "run de 2 pixels nao recebe degrau -- mesmo shade ligado ou desligado")

  local longEdgeOff = topQuadShadeAt(gotOff, 6, 7, topY)
  local longEdgeOn = topQuadShadeAt(gotOn, 6, 7, topY)
  check(longEdgeOff ~= nil and longEdgeOn ~= nil,
        "teste encontra os quads da borda do run longo")
  check(longEdgeOn < longEdgeOff,
        "controle: o run de 6 pixels na mesma folha DEGRAUA -- a exclusao do curto e uma regra, nao coincidencia")
end

-- teste obrigatorio 5 ("a chave de cache muda com a forca") ja esta coberto
-- junto das outras cacheKeys, mais acima (cacheKey separa TOP DOME mesmo
-- sem limpar o cache, off/low/high).

do
  -- teste obrigatorio 6: "TOP EDGE e TOP DOME convivem". Os dois mexem no
  -- shade da MESMA face de topo; prova a ordem de aplicacao (TOP EDGE
  -- primeiro, como a BASE que topShadeDomo le de topShade(); TOP DOME
  -- degraua essa base, nunca a substitui) e que ligar um nao anula o outro.
  local cellW, cellH = 16, 16
  local pixels = {}
  for lx = 4, 9 do paint(pixels, cellW, cellW, 0, lx, 7, 1) end
  local def = { image = "sheet.png", frames = 1 }
  local topY = cellH - 7

  local handleEdgeOnly, modulesEdgeOnly = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handleEdgeOnly,
    { depth = 2, shape = "slab", top_edge = "on", top_dome = "off" }))
  local edgeOnly = modulesEdgeOnly.SpriteBillboards.mesh(def, 0)

  local handleBoth, modulesBoth = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handleBoth,
    { depth = 2, shape = "slab", top_edge = "on", top_dome = 0.30 }))
  local both = modulesBoth.SpriteBillboards.mesh(def, 0)

  local edgeOnlyCenter = topQuadShadeAt(edgeOnly, 6, 7, topY)
  local bothCenter = topQuadShadeAt(both, 6, 7, topY)
  local bothEdge = topQuadShadeAt(both, 4, 5, topY)
  check(edgeOnlyCenter ~= nil and bothCenter ~= nil and bothEdge ~= nil,
        "teste encontra os quads de topo nas duas malhas")

  eq(bothCenter, edgeOnlyCenter,
     "ligar TOP DOME nao muda o centro do run -- TOP EDGE continua valendo, nao foi anulado")
  check(bothEdge < bothCenter,
        "com os dois ligados, a borda do run sai mais escura que o centro -- TOP DOME continua valendo por cima do TOP EDGE, nao foi anulado")
  -- Mesma expressao, mesma ordem de operacoes que topShadeDomo usa
  -- internamente (base * (1 - domoStep * level / (TOP_DOME_STEPS - 1)),
  -- com level = 2 para o pixel de borda de um run de 6): prova a ORDEM de
  -- aplicacao, TOP EDGE como base multiplicada por TOP DOME, nao os dois
  -- competindo por cima do shade puro do host.
  local multiplier = 1 - 0.30 * 2 / 2
  eq(bothEdge, edgeOnlyCenter * multiplier,
     "TOP DOME multiplica a base que TOP EDGE ja escureceu, nunca a substitui")
end

-- v1.6.0: STEP WEIGHT. Cisalhamento em Z proporcional a altura do SLAB, so
-- nos frames de caminhada, para o solido acompanhar o passo que a arte ja
-- da sozinha. Os sete testes abaixo sao os obrigatorios da spec da rodada,
-- na mesma ordem; a row/step/persist e as duas variantes de cacheKey (SLAB
-- separa, CARVED ignora) ja foram cobertas mais acima, junto das rows e
-- cacheKeys das outras opcoes. Os dois ultimos blocos vao alem do
-- obrigatorio: cobrem a restricao "confirme quais frames sao de caminhada
-- pelo codigo, em vez de assumir 3, 4 e 5", com uma folha de 4 frames (o
-- indice 3 existe mas nao e caminhada) e uma folha de 8 (o indice 6 dobra
-- para o bucket parado por frame % 3, o mesmo bucket que carvedFrames ja
-- usa para CARVED).
--
-- Fixture comum aos testes 1 a 5: uma coluna de um pixel em lx = 7, pintada
-- em tres alturas isoladas (ly = 15 o pe, y local 0..1; ly = 8 o meio, y
-- local 7..8; ly = 0 o topo, y local 15..16, com cellH = 16), replicada em
-- todos os seis frames para que a pose parada (frame 0) e a de caminhada
-- (frame 3) partam da mesma arte.

do
  -- teste obrigatorio 1: "com a opcao desligada, a malha e byte a byte a de
  -- hoje". Lido no frame de CAMINHADA (3), o unico onde STEP WEIGHT teria
  -- algo a fazer -- se o cisalhamento vazasse por baixo do OFF, e ali que
  -- apareceria.
  local cellW, cellH = 16, 16
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do
    paint(pixels, sheetW, cellW, frame, 7, 15, 1)
    paint(pixels, sheetW, cellW, frame, 7, 8, 1)
    paint(pixels, sheetW, cellW, frame, 7, 0, 1)
  end
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }

  local handleOff, modulesOff = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handleOff, { depth = 2, shape = "slab", step_weight = "off" }))
  local gotOff = modulesOff.SpriteBillboards.mesh(def, 3)

  local handleDefault, modulesDefault = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handleDefault, { depth = 2, shape = "slab" }))
  local gotDefault = modulesDefault.SpriteBillboards.mesh(def, 3)

  eq(vertexSignature(gotOff), vertexSignature(gotDefault),
     "STEP WEIGHT OFF explicito e o default (sem a chave) produzem a mesma malha, "
     .. "byte a byte, no frame de caminhada")
end

do
  -- teste obrigatorio 2: "a pose parada nao se move com a opcao ligada --
  -- so a de caminhada muda". As duas metades sao necessarias para provar
  -- por reversao: um gate quebrado que cisalhasse TODO frame (nao so
  -- caminhada) passaria pela metade "caminhada muda" mas quebraria a
  -- metade "parada nao muda"; uma implementacao que nunca aplicasse forca
  -- alguma passaria pela metade "parada nao muda" mas quebraria "caminhada
  -- muda".
  local cellW, cellH = 16, 16
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do
    paint(pixels, sheetW, cellW, frame, 7, 15, 1)
    paint(pixels, sheetW, cellW, frame, 7, 8, 1)
    paint(pixels, sheetW, cellW, frame, 7, 0, 1)
  end
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }

  local handleOff, modulesOff = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handleOff, { depth = 2, shape = "slab", step_weight = "off" }))
  local standOff = modulesOff.SpriteBillboards.mesh(def, 0)
  local walkOff = modulesOff.SpriteBillboards.mesh(def, 3)

  local handleOn, modulesOn = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handleOn, { depth = 2, shape = "slab", step_weight = 0.5 }))
  local standOn = modulesOn.SpriteBillboards.mesh(def, 0)
  local walkOn = modulesOn.SpriteBillboards.mesh(def, 3)

  eq(vertexSignature(standOn), vertexSignature(standOff),
     "a pose parada (frame 0) nao se move com STEP WEIGHT ligado")
  check(vertexSignature(walkOn) ~= vertexSignature(walkOff),
        "controle: a pose de caminhada (frame 3) MUDA com STEP WEIGHT ligado -- "
        .. "senao as duas comparacoes acima nao provariam nada")
end

do
  -- teste obrigatorio 3: "o deslocamento e proporcional a altura -- o pe
  -- fica parado, o topo move o maximo". Mesma fixture de tres alturas,
  -- lida no frame de caminhada (3) com STEP WEIGHT: HIGH (forca 0.5).
  -- Valores exatos, nao so "maior que": a formula (z += forca * y / cellH)
  -- e linear por construcao, entao pe, meio e topo tem que bater o numero
  -- exato, nao so a ordem.
  local cellW, cellH = 16, 16
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do
    paint(pixels, sheetW, cellW, frame, 7, 15, 1)
    paint(pixels, sheetW, cellW, frame, 7, 8, 1)
    paint(pixels, sheetW, cellW, frame, 7, 0, 1)
  end
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }

  local handleOff, modulesOff = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handleOff, { depth = 2, shape = "slab", step_weight = "off" }))
  local off = modulesOff.SpriteBillboards.mesh(def, 3)

  local handleOn, modulesOn = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handleOn, { depth = 2, shape = "slab", step_weight = 0.5 }))
  local on = modulesOn.SpriteBillboards.mesh(def, 3)

  local footOff, footOn = vertexZAt(off, 7, 0, 0.90), vertexZAt(on, 7, 0, 0.90)
  local midOff, midOn = vertexZAt(off, 7, 8, 0.90), vertexZAt(on, 7, 8, 0.90)
  local topOff, topOn = vertexZAt(off, 7, 16, 0.90), vertexZAt(on, 7, 16, 0.90)
  check(footOff and footOn and midOff and midOn and topOff and topOn,
        "teste encontra os tres vertices de frente (pe Y=0, meio Y=8, topo Y=16) "
        .. "nas duas malhas")

  eq(footOn - footOff, 0, "o pe (Y = 0) nao se move -- cisalhamento zero na base")
  eq(midOn - midOff, 0.25, "o meio (Y = cellH / 2) move metade da forca -- proporcional a altura")
  eq(topOn - topOff, 0.5, "o topo (Y = cellH) move a forca inteira -- o deslocamento maximo")
end

do
  -- teste obrigatorio 4: "nenhuma coordenada X muda" -- a garantia contra
  -- o espelho do host, que so inverte sinal em X. Usa a malha inteira
  -- (frente, tras, laterais, topo, base), nao so os tres vertices de
  -- frente medidos no teste anterior.
  local cellW, cellH = 16, 16
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do
    for lx = 4, 10 do paint(pixels, sheetW, cellW, frame, lx, 7, 1) end
  end
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }

  local handleOff, modulesOff = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handleOff, { depth = 2, shape = "slab", step_weight = "off" }))
  local off = modulesOff.SpriteBillboards.mesh(def, 3)

  local handleOn, modulesOn = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handleOn, { depth = 2, shape = "slab", step_weight = 0.5 }))
  local on = modulesOn.SpriteBillboards.mesh(def, 3)

  eq(xSignature(on), xSignature(off),
     "nenhuma coordenada X muda -- mesma sequencia de vertices, so Z muda")
  check(vertexSignature(on) ~= vertexSignature(off),
        "controle: Z realmente mudou em algum vertice -- senao a comparacao de X "
        .. "acima nao provaria nada")
end

do
  -- teste obrigatorio 5: "a contagem de quads nao muda -- isto move
  -- vertice, nao cria face". Mesma fixture do teste anterior.
  local cellW, cellH = 16, 16
  local sheetW = cellW * 6
  local pixels = {}
  for frame = 0, 5 do
    for lx = 4, 10 do paint(pixels, sheetW, cellW, frame, lx, 7, 1) end
  end
  local def = { image = "sheet.png", frames = 6, frameWidth = cellW }

  local handleOff, modulesOff = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handleOff, { depth = 2, shape = "slab", step_weight = "off" }))
  local off = modulesOff.SpriteBillboards.mesh(def, 3)

  local handleOn, modulesOn = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handleOn, { depth = 2, shape = "slab", step_weight = 0.5 }))
  local on = modulesOn.SpriteBillboards.mesh(def, 3)

  eq(quadCount(on), quadCount(off), "STEP WEIGHT ligado nao muda a contagem de quads")
end

-- teste obrigatorio 6 ("a chave de cache muda com a forca") ja esta
-- coberto junto das outras cacheKeys, mais acima (cacheKey separa STEP
-- WEIGHT mesmo sem limpar o cache, off/low/high, e ignora a forca quando
-- SHAPE e CARVED).

do
  -- teste obrigatorio 7: "folha de 1 frame nao quebra". Uma folha de 1
  -- frame nao tem pose de caminhada (m.frames < 6), entao `andando` fica
  -- falso pelo bucket de frame, e a malha sai identica com a opcao ligada
  -- ou desligada -- nao so "nao lanca excecao".
  local cellW, cellH = 16, 16
  local pixels = {}
  for lx = 4, 10 do paint(pixels, cellW, cellW, 0, lx, 7, 1) end
  local def = { image = "sheet.png", frames = 1 }

  local handleOff, modulesOff = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handleOff, { depth = 2, shape = "slab", step_weight = "off" }))
  local off = modulesOff.SpriteBillboards.mesh(def, 0)

  local handleOn, modulesOn = makeVoxelHandle("1.6.0", pixels, cellW, cellH)
  loadWith(makeMod(handleOn, { depth = 2, shape = "slab", step_weight = 0.5 }))
  local on = modulesOn.SpriteBillboards.mesh(def, 0)

  check(off ~= nil and off.verts ~= nil,
        "folha de 1 frame continua construindo malha com STEP WEIGHT ligado")
  eq(vertexSignature(on), vertexSignature(off),
     "folha de 1 frame: sem pose de caminhada, a malha sai identica ligado ou desligado")
end

do
  -- restricao extra (nao numerada na spec, mas explicita: "confirme quais
  -- [frames] sao, pelo codigo, em vez de assumir 3, 4 e 5"). Uma folha de 4
  -- frames tem o indice 3 como frame VALIDO, mas nao como pose de
  -- caminhada estabelecida -- o bucket de seis frames (parada 0/1/2,
  -- caminhada 3/4/5) so vale a partir de seis frames. Uma implementacao
  -- ingenua que checasse so `frame == 3` (o palpite que a spec
  -- explicitamente pede para nao fazer) teria estourado o cisalhamento
  -- aqui; a guarda `m.frames >= 6` e o que separa as duas.
  local cellW, cellH = 16, 16
  local sheetW = cellW * 4
  local pixels = {}
  for frame = 0, 3 do
    paint(pixels, sheetW, cellW, frame, 7, 0, 1) -- topo: o ponto mais sensivel a um cisalhamento indevido
  end
  local def = { image = "sheet.png", frames = 4, frameWidth = cellW }

  local handleOff, modulesOff = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handleOff, { depth = 2, shape = "slab", step_weight = "off" }))
  local off = modulesOff.SpriteBillboards.mesh(def, 3)

  local handleOn, modulesOn = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handleOn, { depth = 2, shape = "slab", step_weight = 0.5 }))
  local on = modulesOn.SpriteBillboards.mesh(def, 3)

  eq(vertexSignature(on), vertexSignature(off),
     "folha de 4 frames, frame 3: sem pose de caminhada estabelecida (m.frames < 6), "
     .. "a malha sai identica ligado ou desligado")
end

do
  -- restricao extra, segunda metade: um frame acima de 5 dobra em bucket de
  -- 3 (frame % 3), o mesmo bucket que carvedFrames ja usa para CARVED
  -- (main.lua), entao nunca cai no bucket "andando" (posicao 3) mesmo numa
  -- folha com seis frames ou mais. Frame 6 numa folha de 8: 6 % 3 = 0, o
  -- bucket de frente PARADA, nao o de caminhada.
  local cellW, cellH = 16, 16
  local sheetW = cellW * 8
  local pixels = {}
  for frame = 0, 7 do
    paint(pixels, sheetW, cellW, frame, 7, 0, 1)
  end
  local def = { image = "sheet.png", frames = 8, frameWidth = cellW }

  local handleOff, modulesOff = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handleOff, { depth = 2, shape = "slab", step_weight = "off" }))
  local off = modulesOff.SpriteBillboards.mesh(def, 6)

  local handleOn, modulesOn = makeVoxelHandle("1.6.0", pixels, sheetW, cellH)
  loadWith(makeMod(handleOn, { depth = 2, shape = "slab", step_weight = 0.5 }))
  local on = modulesOn.SpriteBillboards.mesh(def, 6)

  eq(vertexSignature(on), vertexSignature(off),
     "frame 6 (acima de 5) dobra para o bucket parado por frame % 3, mesmo numa folha "
     .. "com oito frames")
end

-- ========================================================================
-- VIDA: BREATH, SWAY, MOTION LAG (canal novo em cima de Voxel3D.draw)
-- ========================================================================
--
-- O host so oferece o segundo ponto de patch quando makeVoxelHandle recebe
-- withDraw=true. Os testes abaixo cobrem o canal instalando, a row de LIFE
-- reportando cada estado, as tres rows do menu so aparecendo com o canal, e
-- o contrato de matriz (so a coluna 2 muda, os pes ficam parados, o
-- espelho inverte o cisalhamento, personalidade por folha, primeira
-- pessoa, sunModel, e a fase seguindo o relogio em vez da posicao).

do
  -- item 1: com host que desenha, o canal instala e troca o campo
  -- Voxel3D.draw pela funcao deste mod.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  local voxel3D = handle.exports.lib.require("Voxel3D")
  local originalDrawFn = voxel3D.draw
  loadWith(makeMod(handle))
  check(modules.Voxel3D.draw ~= originalDrawFn,
        "com host que desenha, o canal instala e troca Voxel3D.draw")
end

do
  -- item 2: sem canal (host sem draw), LIFE diz NO CHANNEL mesmo com host
  -- valido e patch feito.
  local pixels = {}
  pixels[0] = 1
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle))
  eq(lifeRowValue(mod), "NO CHANNEL",
     "host sem Voxel3D.draw: LIFE diz NO CHANNEL")
end

do
  -- item 2: com canal e as tres opcoes desligadas (default), LIFE diz OFF.
  local pixels = {}
  pixels[0] = 1
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  local mod = loadWith(makeMod(handle, soEsta()))
  eq(lifeRowValue(mod), "OFF",
     "host com canal, as tres opcoes desligadas: LIFE diz OFF")
end

do
  -- item 2: so BREATH ligado.
  local pixels = {}
  pixels[0] = 1
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  local mod = loadWith(makeMod(handle, { breath = 0.020 }))
  eq(lifeRowValue(mod), "BREATH", "so BREATH ligado: LIFE diz BREATH")
end

do
  -- item 2: as tres ligadas juntas, na ordem BREATH+SWAY+LAG.
  local pixels = {}
  pixels[0] = 1
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  local mod = loadWith(makeMod(handle,
    { breath = 0.020, sway = 0.20, lag = 0.6 }))
  eq(lifeRowValue(mod), "BREATH+SWAY+LAG",
     "as tres ligadas: LIFE junta os nomes com +")
end

do
  -- item 2, FOOTFALL: so FOOTFALL ligado, a row de LIFE diz STEP (o
  -- rotulo curto que lifeStatusValue usa para footfall, main.lua).
  local pixels = {}
  pixels[0] = 1
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  local mod = loadWith(makeMod(handle, soEsta({ footfall = 0.35 })))
  eq(lifeRowValue(mod), "STEP", "so FOOTFALL ligado: LIFE diz STEP")
end

do
  -- item 2, FOOTFALL: as quatro ligadas juntas, na ordem
  -- BREATH+SWAY+LAG+STEP.
  local pixels = {}
  pixels[0] = 1
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  local mod = loadWith(makeMod(handle,
    { breath = 0.020, sway = 0.20, lag = 0.6, footfall = 0.35 }))
  eq(lifeRowValue(mod), "BREATH+SWAY+LAG+STEP",
     "as quatro ligadas: LIFE junta os nomes com +, FOOTFALL por ultimo")
end

do
  -- item 3: sem canal, as tres rows de vida nao aparecem no menu.
  local pixels = {}
  pixels[0] = 1
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle))
  local rows = {}
  mod._rows["ui.options.rows"](function(_, r) return r end, {}, rows)
  local labels = {}
  for _, row in ipairs(rows) do labels[row.label] = true end
  check(not (labels.BREATH or labels.SWAY or labels["MOTION LAG"]
             or labels.FOOTFALL),
        "sem canal, nenhuma row de vida aparece no menu")
end

do
  -- CAMERA FIT: a tabela medida, e o que a row promete.
  --
  -- A recomendacao por degrau saiu do harness, nao de gosto: para cada camera,
  -- a maior espessura que ainda mantem a proporcao de arte do padrao de hoje
  -- (rung 35 com depth 3, que da 73.4%). Sai 1, 3, 5, 10.
  --
  -- O teste amarra as duas pontas que podem quebrar sem ninguem ver: a tabela
  -- continuar monotona (camera mais deitada nunca pode pedir MAIS espessura, ou
  -- a logica se inverteu) e a row ser uma ACAO e nao um ciclo, porque uma row
  -- com value e sem step nem activate e tratada como CANCEL pelo motor.
  local pixels = {}
  pixels[0] = 1
  for _, caso in ipairs({
    { angulo = 15, esperado = 1 }, { angulo = 35, esperado = 3 },
    { angulo = 50, esperado = 5 }, { angulo = 75, esperado = 10 },
    -- entre degraus, o preset escolhe o mais proximo
    { angulo = 20, esperado = 1 }, { angulo = 60, esperado = 5 },
  }) do
    local handle = makeVoxelHandle("1.6.0", pixels, 16, 16, math.rad(caso.angulo))
    local mod = loadWith(makeMod(handle, { depth = 1 }))
    local rows = {}
    mod._rows["ui.options.rows"](function(_, r) return r end, {}, rows)
    local fit
    for _, row in ipairs(rows) do
      if row.label == "CAMERA FIT" then fit = row end
    end
    check(fit ~= nil, "CAMERA FIT existe com a camera em " .. caso.angulo)
    if fit then
      local esperado = caso.esperado == 1 and "OK AT " .. caso.angulo
        or ("SET DEPTH " .. caso.esperado)
      eq(fit.value(), esperado,
        "camera em " .. caso.angulo .. " graus recomenda espessura "
        .. caso.esperado)
      eq(type(fit.activate), "function",
        "CAMERA FIT e uma ACAO: A aplica, e nao fecha o menu")
      eq(fit.step, nil, "CAMERA FIT nao cicla com esquerda e direita")
    end
  end
end

do
  -- OS DEFAULTS QUE O JOGADOR RECEBE SEM ESCOLHER NADA.
  --
  -- Nenhum teste cobria isto, e a falta apareceu do jeito mais caro possivel:
  -- mudar BLINK e BREATH para ligados quebrou oito checks de uma vez, todos de
  -- testes que falavam de OUTRA coisa e so dependiam do default por preguica.
  -- Agora os defaults tem um dono: este bloco. Qualquer mudanca neles falha
  -- AQUI, que e onde a decisao mora, e em lugar nenhum mais.
  local pixels = {}
  pixels[0] = 1
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  local mod = loadWith(makeMod(handle))
  local rows = {}
  mod._rows["ui.options.rows"](function(_, r) return r end, {}, rows)
  local valor = {}
  for _, row in ipairs(rows) do
    if row.value then valor[row.label] = row.value({}) end
  end
  eq(valor["VOXEL CHARS"], "3", "default de VOXEL CHARS: 3")
  eq(valor["SIDE COLOR"], "BODY", "default de SIDE COLOR: BODY")
  eq(valor["SHAPE"], "SLAB", "default de SHAPE: SLAB")
  eq(valor["GROUND SHADE"], "OFF", "default de GROUND SHADE: OFF")
  eq(valor["TOP EDGE"], "ON", "default de TOP EDGE: ON")
  -- Ligados por decisao do Kim em 2026-08-09: os dois ja tinham sido vistos e
  -- aprovados pela comunidade, entao entregar desligado passou a ser entregar
  -- menos do que a pessoa escolheria.
  eq(valor.BLINK, "ON", "default de BLINK: ON, a comunidade aprovou a feature")
  eq(valor.BREATH, "SUBTLE",
     "default de BREATH: SUBTLE, o menor nivel que ainda faz diferenca")
  -- Estas continuam desligadas: mudam a LEITURA da forma ou do movimento de um
  -- jeito que ninguem julgou ainda.
  for _, chave in ipairs({ "FRONT SHAPE", "TOP DOME", "STEP WEIGHT", "SWAY",
                           "MOTION LAG", "FOOTFALL" }) do
    eq(valor[chave], "OFF", "default de " .. chave .. ": OFF")
  end
end

do
  -- item 3: com canal, as tres rows aparecem depois de STEP WEIGHT, nesta
  -- ordem, com os rotulos certos.
  local pixels = {}
  pixels[0] = 1
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  local mod = loadWith(makeMod(handle))
  local rows = {}
  mod._rows["ui.options.rows"](function(_, r) return r end, {}, rows)
  eq(#rows, 17,
     "com canal, dezessete rows: STATUS, LIFE, CAMERA FIT e as catorze opcoes")
  eq(rows[12].label, "STEP WEIGHT", "STEP WEIGHT continua na mesma posicao")
  eq(rows[13].label, "BREATH", "BREATH aparece logo depois de STEP WEIGHT")
  eq(rows[14].label, "SWAY", "SWAY aparece depois de BREATH")
  eq(rows[15].label, "MOTION LAG", "MOTION LAG aparece depois de SWAY")
  eq(rows[16].label, "FOOTFALL", "FOOTFALL aparece depois de MOTION LAG")
end

do
  -- item 4: com as tres opcoes desligadas, o desenho passa direto: o
  -- original recebe a MESMA tabela de model, por identidade.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handle, soEsta()))
  local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local model = lifeModel(32, 48, false)
  modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
  local call = modules.Voxel3D.drawCalls[1]
  check(call.model == model,
        "as quatro opcoes desligadas: o original recebe a mesma tabela de model")
end

do
  -- item 5: uma malha que este mod nunca produziu passa direto, mesmo com
  -- BREATH ligado.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handle, { breath = 0.020 }))
  local foreignMesh = {}
  local model = lifeModel(32, 48, false)
  modules.Voxel3D.draw(foreignMesh, "tex", model, "pull", nil)
  local call = modules.Voxel3D.drawCalls[1]
  check(call.model == model,
        "malha estranha ao mod: o original recebe a mesma tabela de model, "
        .. "mesmo com BREATH ligado")
end

do
  -- item 6: so BREATH ligado muda so a coluna 2 (indices 2, 6, 10, 14),
  -- escalando pelo mesmo fator nas quatro linhas; a tabela do chamador nao
  -- e mutada.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handle, { breath = 0.020 }))
  local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local model = lifeModel(32, 48, false)
  modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
  local out = modules.Voxel3D.drawCalls[1].model
  check(out ~= model, "BREATH ligado: o original recebe uma tabela nova")
  for _, i in ipairs({ 1, 3, 4, 5, 7, 8, 9, 11, 12, 13, 15, 16 }) do
    eq(out[i], model[i], "BREATH so muda a coluna 2, indice " .. i .. " fica igual")
  end
  local s = out[2] / model[2]
  check(math.abs(s - 1) > 0.0001, "BREATH realmente escalou a coluna 2")
  check(close(out[6], model[6] * s), "coluna 2 escala pelo mesmo fator na linha 1")
  check(close(out[10], model[10] * s), "coluna 2 escala pelo mesmo fator na linha 2")
  check(close(out[14], model[14] * s), "coluna 2 escala pelo mesmo fator na linha 3")
  check(model[1] == 1 and model[2] == 2 and model[3] == 3 and model[4] == 32
    and model[5] == 5 and model[6] == 6 and model[7] == 7 and model[8] == 8
    and model[9] == 9 and model[10] == 10 and model[11] == 11 and model[12] == 56
    and model[13] == 13 and model[14] == 14 and model[15] == 15 and model[16] == 16,
    "a tabela original do chamador nao foi mutada")
end

do
  -- item 7: os pes nao se movem. A malha tem y local = 0 no chao, e local
  -- (0,0,0) cai exatamente na traducao (coluna 4: indices 4, 8, 12, 16),
  -- que a formula da coluna 2 nunca toca. Testado com as tres opcoes
  -- ligadas juntas, o caso de cisalhamento maximo.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handle, { breath = 0.035, sway = 0.45, lag = 1.2 }))
  local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local model = lifeModel(32, 48, false)
  modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
  local out = modules.Voxel3D.drawCalls[1].model
  check(out ~= model, "com as tres opcoes ligadas, o original recebe uma tabela nova")
  eq(out[4], model[4], "coluna 4 (traducao) da linha 0 fica intacta, os pes nao se movem")
  eq(out[8], model[8], "coluna 4 da linha 1 fica intacta")
  eq(out[12], model[12], "coluna 4 da linha 2 fica intacta")
  eq(out[16], model[16], "coluna 4 da linha 3 fica intacta")
end

do
  -- item 8: o espelho inverte o cisalhamento. Mesma posicao (px, py)
  -- recuperada dos dois jeitos (model[1] = 1 direto, model[1] = -1 com
  -- model[4] deslocado em +16), mesmo relogio: a contribuicao de kx (o
  -- termo que a coluna 2 ganha alem da escala, recuperado dividindo pelo
  -- proprio model[1]) sai com sinal oposto.
  local pixels = {}
  pixels[0] = 1
  local px, py = 32, 48

  local handleA, modulesA = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handleA, { sway = 0.45 }))
  local meshA = modulesA.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local modelA = lifeModel(px, py, false)
  modulesA.Voxel3D.draw(meshA, "tex", modelA, "pull", nil)
  local outA = modulesA.Voxel3D.drawCalls[1].model
  local kxA = (outA[2] - modelA[2]) / modelA[1]

  local handleB, modulesB = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handleB, { sway = 0.45 }))
  local meshB = modulesB.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local modelB = lifeModel(px, py, true)
  modulesB.Voxel3D.draw(meshB, "tex", modelB, "pull", nil)
  local outB = modulesB.Voxel3D.drawCalls[1].model
  local kxB = (outB[2] - modelB[2]) / modelB[1]

  check(math.abs(kxA) > 0.0001, "sem espelho, o balanco realmente contribuiu algo")
  check(close(kxA, -kxB), "com espelho, a contribuicao de kx sai com sinal oposto")
end

do
  -- item 9: personalidade por folha. poke_ball tem breath = 0: mesmo com
  -- BREATH em STRONG, a coluna 2 sai identica. Uma folha ausente da tabela
  -- usa multiplicador 1 e muda normalmente.
  local pixels = {}
  pixels[0] = 1

  local handleObj, modulesObj = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handleObj, { breath = 0.035 }))
  local ballMesh = modulesObj.SpriteBillboards.mesh(
    { image = "poke_ball.png", frames = 1 }, 0)
  local ballModel = lifeModel(32, 48, false)
  modulesObj.Voxel3D.draw(ballMesh, "tex", ballModel, "pull", nil)
  local ballOut = modulesObj.Voxel3D.drawCalls[1].model
  eq(ballOut[2], ballModel[2], "poke_ball nao respira: coluna 2 sai identica")
  eq(ballOut[6], ballModel[6], "poke_ball nao respira: coluna 2 (linha 1) sai identica")

  local handlePerson, modulesPerson = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handlePerson, { breath = 0.035 }))
  local personMesh = modulesPerson.SpriteBillboards.mesh(
    { image = "sheet.png", frames = 1 }, 0)
  local personModel = lifeModel(32, 48, false)
  modulesPerson.Voxel3D.draw(personMesh, "tex", personModel, "pull", nil)
  local personOut = modulesPerson.Voxel3D.drawCalls[1].model
  check(math.abs(personOut[2] - personModel[2]) > 0.0001,
        "folha ausente da tabela de personalidade usa multiplicador 1 e muda")
end

do
  -- item 10: model[1] fora de +-1 (mistura de yaw de primeira pessoa) faz
  -- passar direto, mesmo com BREATH ligado.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handle, { breath = 0.020 }))
  local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local model = lifeModel(32, 48, false)
  model[1] = 0.5
  modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
  local call = modules.Voxel3D.drawCalls[1]
  check(call.model == model,
        "model[1] nao e +-1: passa direto, mesma tabela por identidade")
end

do
  -- item 11: sunModel recebe a mesma escala s que o corpo, numa tabela
  -- nova. Sem sunModel, continua nil.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handle, { breath = 0.020 }))
  local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local model = lifeModel(32, 48, false)
  local sunModel = lifeModel(32, 48, false)
  modules.Voxel3D.draw(mesh, "tex", model, "pull", sunModel)
  local call = modules.Voxel3D.drawCalls[1]
  check(call.sunModel ~= sunModel, "sunModel: o original recebe uma tabela nova")
  local s = call.model[2] / model[2]
  check(close(call.sunModel[2], sunModel[2] * s),
        "sunModel escala pelo mesmo fator s que o corpo")

  local handleNil, modulesNil = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handleNil, { breath = 0.020 }))
  local meshNil = modulesNil.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local modelNil = lifeModel(32, 48, false)
  modulesNil.Voxel3D.draw(meshNil, "tex", modelNil, "pull", nil)
  eq(modulesNil.Voxel3D.drawCalls[1].sunModel, nil, "sem sunModel, continua nil")
end

do
  -- item 11, extra: sunModel usa kz = 0 sempre (main.lua diz isso
  -- explicitamente), mesmo quando o corpo tem kz != 0 por causa de MOTION
  -- LAG. Duas rodadas identicas, so o componente z de sunModel muda; se kz
  -- vazasse para sunModel, mudar esse componente mudaria o resultado
  -- junto.
  local function lagSunColumn2(sunZ)
    local pixels = {}
    pixels[0] = 1
    local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
      nil, nil, nil, nil, nil, true)
    loadWith(makeMod(handle, { lag = 1.2 }))
    local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
    withLoveTime(0, function()
      local model = lifeModel(0, 0, false)
      modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
    end)
    local out
    withLoveTime(0.1, function()
      local model = lifeModel(0, -6, false)
      local sunModel = lifeModel(0, -6, false)
      sunModel[3] = sunZ
      modules.Voxel3D.draw(mesh, "tex", model, "pull", sunModel)
      out = modules.Voxel3D.drawCalls[#modules.Voxel3D.drawCalls].sunModel
    end)
    return out[2]
  end
  local a = lagSunColumn2(500)
  local b = lagSunColumn2(-500)
  eq(a, b,
     "sunModel ignora kz: mudar o componente z de sunModel nao muda a coluna 2, "
     .. "mesmo com MOTION LAG ligado")
end

do
  -- item 12: a fase avanca com o RELOGIO, nao com a posicao. Mesmo
  -- personagem, mesma posicao, dois relogios diferentes: a escala muda.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handle, { breath = 0.020 }))
  local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local sA, sB
  withLoveTime(0, function()
    local model = lifeModel(0, 0, false)
    modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
    sA = modules.Voxel3D.drawCalls[#modules.Voxel3D.drawCalls].model[2] / model[2]
  end)
  withLoveTime(1.5, function()
    local model = lifeModel(0, 0, false)
    modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
    sB = modules.Voxel3D.drawCalls[#modules.Voxel3D.drawCalls].model[2] / model[2]
  end)
  check(not close(sA, sB),
        "mesmo personagem, mesma posicao, relogios diferentes: a escala muda")
end

do
  -- item 12, continuacao: a mesma fase, avancada pelo mesmo tempo, vale
  -- tanto parado quanto tendo andado um pouco dentro da mesma celula de
  -- 16px: a posicao nova NAO gera uma fase semeada do zero.
  local function laterScale(px1)
    local pixels = {}
    pixels[0] = 1
    local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
      nil, nil, nil, nil, nil, true)
    loadWith(makeMod(handle, { breath = 0.020 }))
    local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
    withLoveTime(0, function()
      local model = lifeModel(0, 0, false)
      modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
    end)
    local s
    withLoveTime(1.5, function()
      local model = lifeModel(px1, 0, false)
      modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
      s = modules.Voxel3D.drawCalls[#modules.Voxel3D.drawCalls].model[2] / model[2]
    end)
    return s
  end
  local sStill = laterScale(0)
  local sMoved = laterScale(4)
  check(close(sStill, sMoved),
        "personagem andou um pouco na mesma celula: a fase segue o tempo decorrido, "
        .. "nao a nova posicao")
end

do
  -- item 13: duas instancias da mesma folha, mesmo relogio, posicoes bem
  -- diferentes: escalas diferentes (fora de fase uma da outra).
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handle, { breath = 0.020 }))
  local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  withLoveTime(0, function()
    local model1 = lifeModel(0, 0, false)
    modules.Voxel3D.draw(mesh, "tex", model1, "pull", nil)
    local model2 = lifeModel(200, 0, false)
    modules.Voxel3D.draw(mesh, "tex", model2, "pull", nil)
    local calls = modules.Voxel3D.drawCalls
    local s1 = calls[1].model[2] / model1[2]
    local s2 = calls[2].model[2] / model2[2]
    check(not close(s1, s2),
          "duas posicoes bem diferentes, mesmo relogio: escalas diferentes")
  end)
end

do
  -- item 14: o reflexo na agua. O host desenha o mesmo personagem duas
  -- vezes por quadro com a MESMA matriz; a segunda chamada nao pode
  -- avancar nada de novo, entao as duas saidas saem iguais.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handle, { breath = 0.020 }))
  local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local model = lifeModel(40, 24, false)
  modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
  modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
  local calls = modules.Voxel3D.drawCalls
  check(sameMatrix(calls[1].model, calls[2].model),
        "duas chamadas na mesma posicao e no mesmo instante: as duas saidas saem iguais")
end

-- ========================================================================
-- VIDA: MAGNITUDE (nao so "mudou?", mas "mudou QUANTO?")
-- ========================================================================
--
-- O defeito que motivou este bloco: MOTION LAG cisalhava quase 45 graus no
-- nivel 0.70 antigo (faltava dividir por LIFE_CELL, igual SWAY ja fazia), e
-- os 465 checks acima mais os oito checks in-game passaram do mesmo jeito,
-- porque todos perguntavam "mudou?" e nenhum perguntava "mudou quanto?".
-- Quem pegou foi olhar um clipe. Os testes abaixo leem a MAGNITUDE real em
-- pixels de mundo a partir da saida da matriz, usando lifeProbeModel (que
-- isola s, kx e kz cada um numa linha, ver comentario da funcao).
--
-- O contrato em uma frase: o numero do menu e o deslocamento da CABECA em
-- pixels de mundo, e a cabeca esta em y = 16 no espaco local da malha (o
-- cisalhamento e proporcional a y, entao o deslocamento maximo, em y = 16,
-- e |kx| * 16).

do
  -- item 1: a escala de BREATH bate com o nivel escolhido. O desvio maximo
  -- de s em relacao a 1, varrendo um ciclo inteiro do relogio, tem que ser
  -- o proprio valor do nivel (0.010 SUBTLE, 0.020 NORMAL, 0.035 STRONG),
  -- com 5% de folga. Confere tambem que STRONG sai 3.5x SUBTLE, a
  -- proporcao que nenhum teste antigo checava.
  local levels = {
    { name = "SUBTLE", value = 0.010 },
    { name = "NORMAL", value = 0.020 },
    { name = "STRONG", value = 0.035 },
  }
  local peaks = {}
  for _, level in ipairs(levels) do
    local pixels = {}
    pixels[0] = 1
    local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
      nil, nil, nil, nil, nil, true)
    loadWith(makeMod(handle, { breath = level.value }))
    local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
    local peak = 0
    withDrivenClock(function(setClock)
      -- BREATH_PERIOD (main.lua) e 3.1s; 400 quadros a 1/60 cobrem quase
      -- 6.7s, mais de dois ciclos inteiros, sem depender do valor exato da
      -- constante.
      for frame = 0, 400 do
        setClock(frame / 60)
        local model = lifeProbeModel(0, 0, false)
        modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
        local out = modules.Voxel3D.drawCalls[#modules.Voxel3D.drawCalls].model
        local d = math.abs(out[6] - 1)
        if d > peak then peak = d end
      end
    end)
    peaks[level.name] = peak
    check(closePercent(peak, level.value, 0.05),
          "BREATH " .. level.name .. ": desvio maximo de s bate com o nivel, 5% de folga")
  end
  check(closePercent(peaks.STRONG / peaks.SUBTLE, 3.5, 0.05),
        "BREATH STRONG sai 3.5x SUBTLE, a proporcao que nenhum teste antigo checava")
end

do
  -- item 2: o deslocamento da cabeca de SWAY (|kx| * 16 no pico do ciclo)
  -- bate com o nivel escolhido, 5% de folga.
  local levels = { { name = "SUBTLE", value = 0.20 }, { name = "NORMAL", value = 0.45 } }
  for _, level in ipairs(levels) do
    local pixels = {}
    pixels[0] = 1
    local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
      nil, nil, nil, nil, nil, true)
    loadWith(makeMod(handle, { sway = level.value }))
    local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
    local peak = 0
    withDrivenClock(function(setClock)
      -- SWAY_PERIOD (main.lua) e 6.2s; 500 quadros a 1/60 cobrem quase
      -- 8.3s, mais de um ciclo inteiro.
      for frame = 0, 500 do
        setClock(frame / 60)
        local model = lifeProbeModel(0, 0, false)
        modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
        local out = modules.Voxel3D.drawCalls[#modules.Voxel3D.drawCalls].model
        local d = math.abs(out[2]) * 16
        if d > peak then peak = d end
      end
    end)
    check(closePercent(peak, level.value, 0.05),
          "SWAY " .. level.name .. ": deslocamento maximo da cabeca bate com o nivel, 5% de folga")
  end
end

do
  -- item 3: MOTION LAG, o teste que teria pego o defeito. Personagem
  -- andando 1 px por quadro (16 px em 16 quadros, a velocidade de
  -- caminhada do jogo), relogio avancando 1/60 por quadro, 40 quadros:
  -- tempo de sobra pra mola assentar. O pico de |kx| * 16 tem que ficar
  -- perto do nivel, com folga para o passar-do-ponto da mola (~8%,
  -- documentado em main.lua): aceita ate 1.4x, reprova acima disso. Com o
  -- bug antigo (multiplicar por LIFE_CELL em vez de dividir) o pico sairia
  -- uma ordem de grandeza maior (16x maior, ~19px em vez de ~1.3px no
  -- nivel NORMAL) e o teste de 1.4x reprovaria.
  local levels = { { name = "SUBTLE", value = 0.6 }, { name = "NORMAL", value = 1.2 } }
  for _, level in ipairs(levels) do
    local pixels = {}
    pixels[0] = 1
    local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
      nil, nil, nil, nil, nil, true)
    loadWith(makeMod(handle, { lag = level.value }))
    local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
    local peak = 0
    withDrivenClock(function(setClock)
      for frame = 0, 40 do
        setClock(frame / 60)
        local model = lifeProbeModel(frame, 0, false)
        modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
        local out = modules.Voxel3D.drawCalls[#modules.Voxel3D.drawCalls].model
        local d = math.abs(out[2]) * 16
        if d > peak then peak = d end
      end
    end)
    check(peak <= level.value * 1.4,
          "MOTION LAG " .. level.name .. ": pico nao passa de 1.4x o nivel")
    check(peak >= level.value * 0.5,
          "MOTION LAG " .. level.name .. ": pico chega perto do nivel, nao fica muito abaixo")
  end
end

do
  -- item 4 (e item 9 da rodada de FOOTFALL): teto absoluto de seguranca,
  -- independente de nivel e personalidade. As QUATRO opcoes no maximo
  -- (BREATH STRONG, SWAY NORMAL, MOTION LAG NORMAL, FOOTFALL NORMAL) na
  -- folha mais agressiva de LIFE_PERSONALITY (main.lua): swimmer tem a
  -- maior soma breath (1.10) + sway (1.60) = 2.70 da tabela (a segunda
  -- maior, fisher, fica em 1.05 + 1.25 = 2.30); MOTION LAG e FOOTFALL nao
  -- tem entrada customizada pra gente, entao valem multiplicador 1 em
  -- qualquer folha de personagem, igual em todas.
  -- Anda na diagonal por 500 quadros (cobre o ciclo inteiro de BREATH e
  -- SWAY, mantem a mola de LAG excitada o tempo todo, e passa por dezenas
  -- de ciclos da passada de FOOTFALL) e guarda o pico dos quatro, cada um
  -- em pixels de mundo. `sx` (a escala em X que FOOTFALL introduziu) e
  -- lido de out[1] / model[1], igual ao contrato do pe (mais abaixo).
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handle,
    { breath = 0.035, sway = 0.45, lag = 1.2, footfall = 0.7 }))
  local mesh = modules.SpriteBillboards.mesh({ image = "swimmer.png", frames = 1 }, 0)
  local maxS, maxKx, maxKz, maxSx = 0, 0, 0, 0
  withDrivenClock(function(setClock)
    for frame = 0, 500 do
      setClock(frame / 60)
      local model = lifeProbeModel(frame, frame, false)
      modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
      local out = modules.Voxel3D.drawCalls[#modules.Voxel3D.drawCalls].model
      maxS = math.max(maxS, math.abs(out[6] - 1) * 16)
      maxKx = math.max(maxKx, math.abs(out[2]) * 16)
      maxKz = math.max(maxKz, math.abs(out[10]) * 16)
      maxSx = math.max(maxSx, math.abs(out[1] / model[1] - 1) * 16)
    end
  end)
  check(maxS < 3, "teto de seguranca: |s - 1| * 16 fica abaixo de 3px mesmo no maximo")
  check(maxKx < 3, "teto de seguranca: |kx| * 16 fica abaixo de 3px mesmo no maximo")
  check(maxKz < 3, "teto de seguranca: |kz| * 16 fica abaixo de 3px mesmo no maximo")
  check(maxSx < 3, "teto de seguranca: |sx - 1| * 16 fica abaixo de 3px mesmo no maximo")
end

do
  -- item 5: a personalidade ESCALA a amplitude, nao so liga e desliga.
  -- guard tem breath = 0.80 em LIFE_PERSONALITY; uma folha ausente da
  -- tabela usa multiplicador 1. As duas tem o mesmo rate (guard: 1.00 na
  -- tabela; ausente: default 1) e a mesma posicao (0, 0), entao a fase
  -- avanca igual nas duas e a razao entre as amplitudes vale em qualquer
  -- instante onde o seno nao esta perto de zero -- varre o relogio e
  -- compara no instante de maior amplitude da folha sem personalidade.
  local pixels = {}
  pixels[0] = 1

  local handleGuard, modulesGuard = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handleGuard, { breath = 0.035 }))
  local guardMesh = modulesGuard.SpriteBillboards.mesh(
    { image = "guard.png", frames = 1 }, 0)

  local handlePlain, modulesPlain = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handlePlain, { breath = 0.035 }))
  local plainMesh = modulesPlain.SpriteBillboards.mesh(
    { image = "sheet.png", frames = 1 }, 0)

  local bestPlainAmp, bestGuardAmp = 0, 0
  withDrivenClock(function(setClock)
    for frame = 0, 400 do
      setClock(frame / 60)
      local guardModel = lifeProbeModel(0, 0, false)
      modulesGuard.Voxel3D.draw(guardMesh, "tex", guardModel, "pull", nil)
      local plainModel = lifeProbeModel(0, 0, false)
      modulesPlain.Voxel3D.draw(plainMesh, "tex", plainModel, "pull", nil)
      local sGuard = modulesGuard.Voxel3D.drawCalls[#modulesGuard.Voxel3D.drawCalls].model[6]
      local sPlain = modulesPlain.Voxel3D.drawCalls[#modulesPlain.Voxel3D.drawCalls].model[6]
      local ampPlain = math.abs(sPlain - 1)
      if ampPlain > bestPlainAmp then
        bestPlainAmp = ampPlain
        bestGuardAmp = math.abs(sGuard - 1)
      end
    end
  end)
  check(bestPlainAmp > 0.001,
        "controle: a folha sem personalidade realmente respirou alguma coisa neste teste")
  check(closePercent(bestGuardAmp, bestPlainAmp * 0.80, 0.05),
        "guard (breath 0.80 na tabela) respira proporcionalmente menos que uma folha ausente")
end

-- ========================================================================
-- VIDA: FOOTFALL (quarta opcao, a primeira que mexe na coluna 1 e na
-- coluna 4 da matriz)
-- ========================================================================
--
-- O item 1 (a row aparecendo e sumindo com o canal, contagem em 15, ordem
-- depois de MOTION LAG) ja esta coberto nos dois primeiros blocos da secao
-- "VIDA: BREATH, SWAY, MOTION LAG" acima (e a linha de STATUS ganhou dois
-- blocos extras logo depois do "as tres ligadas juntas", cobrindo STEP
-- sozinho e as quatro juntas). O teto absoluto (item 9) foi incorporado
-- direto no teste de teto ja existente na secao MAGNITUDE, que agora roda
-- com FOOTFALL NORMAL ligado e mede tambem |sx - 1| * 16.
--
-- O que falta e o proprio de FOOTFALL: nao achatar parado, achatar andando
-- na medida certa, preservar volume, e sobretudo o contrato de que a
-- escala em X tem pivo no CENTRO da celula (o pe nao escorrega) e nao na
-- borda (que tem que se mexer, senao o contrato anterior nao provaria
-- nada). Ver o comentario de lifeApply em main.lua para a algebra completa.

do
  -- item 2: parado nao achata. Personagem sem se mover (mesma posicao em
  -- todo quadro), relogio andando: sem deslocamento nao ha velocidade
  -- (`inst.velocidade` fica em 0, nunca sai do 0 porque o filtro so
  -- persegue o alvo que e a propria velocidade instantanea), e sem
  -- velocidade `achata` e zero POR CONSTRUCAO (amp * 0 * pulso = 0). `s` e
  -- `sx` tem que ficar EXATAMENTE 1 em todo quadro, sem folga nenhuma: e o
  -- check que impede a feature de aparecer quando ninguem esta andando.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handle, soEsta({ footfall = 0.7 })))
  local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local maxDevS, maxDevSx = 0, 0
  withDrivenClock(function(setClock)
    for frame = 0, 60 do
      setClock(frame / 60)
      local model = lifeProbeModel(50, 50, false)
      modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
      local out = modules.Voxel3D.drawCalls[#modules.Voxel3D.drawCalls].model
      maxDevS = math.max(maxDevS, math.abs(out[6] - 1))
      maxDevSx = math.max(maxDevSx, math.abs(out[1] / model[1] - 1))
    end
  end)
  check(maxDevS < 1e-9,
        "parado: s fica exatamente 1 em todo quadro, mesmo com o relogio andando")
  check(maxDevSx < 1e-9,
        "parado: sx fica exatamente 1 em todo quadro, mesmo com o relogio andando")
end

do
  -- item 3: andando achata, e a amplitude bate com o nivel. Mesma rotina de
  -- conducao da rodada de MOTION LAG (posicao andando 1 px por quadro, o
  -- relogio avancando 1/60 por quadro), mas a leitura e diferente: a
  -- formula usa `amp = footfall / LIFE_CELL` direto sobre a escala `s`
  -- (nao existe um segundo "*16" de volta, como existe para o cisalhamento
  -- de MOTION LAG), entao o desvio maximo de `s` em relacao a 1 tem que se
  -- aproximar do proprio nivel dividido por 16, nao do nivel puro.
  local levels = { { name = "SUBTLE", value = 0.35 }, { name = "NORMAL", value = 0.7 } }
  local peaks = {}
  for _, level in ipairs(levels) do
    local pixels = {}
    pixels[0] = 1
    local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
      nil, nil, nil, nil, nil, true)
    loadWith(makeMod(handle, soEsta({ footfall = level.value })))
    local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
    local peak = 0
    withDrivenClock(function(setClock)
      -- 64 quadros cobrem quatro celulas inteiras de 16px andados (a fase
      -- da passada da uma volta inteira por celula), tempo de sobra para a
      -- velocidade suavizada (filtro de fator 0.25 por quadro) saturar bem
      -- antes do primeiro pico do pulso, em andado = 8.
      for frame = 0, 64 do
        setClock(frame / 60)
        local model = lifeProbeModel(frame, 0, false)
        modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
        local out = modules.Voxel3D.drawCalls[#modules.Voxel3D.drawCalls].model
        local d = math.abs(out[6] - 1)
        if d > peak then peak = d end
      end
    end)
    peaks[level.name] = peak
    local want = level.value / 16
    check(peak <= want * 2,
          "FOOTFALL " .. level.name .. ": pico de |s - 1| nao passa do dobro de nivel/16")
    check(peak >= want * 0.5,
          "FOOTFALL " .. level.name .. ": pico chega perto de nivel/16, nao fica muito abaixo")
  end
  check(closePercent(peaks.NORMAL / peaks.SUBTLE, 2.0, 0.05),
        "FOOTFALL NORMAL sai 2x SUBTLE, a mesma proporcao dos dois niveis do menu")
end

do
  -- item 4: o VOLUME e preservado. Em todo quadro da caminhada, o que `s`
  -- perde em altura tem que reaparecer em `sx` como largura, exatamente:
  -- main.lua faz `s = s - achata` e `sx = 1 + achata` a partir do MESMO
  -- `achata`, entao (1 - s) e (sx - 1) tem que ser o mesmo numero. E o
  -- check que impede alguem no futuro de mexer num lado da conta e
  -- esquecer o outro.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handle, soEsta({ footfall = 0.7 })))
  local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local worstGap = 0
  withDrivenClock(function(setClock)
    for frame = 0, 64 do
      setClock(frame / 60)
      local model = lifeProbeModel(frame, 0, false)
      modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
      local out = modules.Voxel3D.drawCalls[#modules.Voxel3D.drawCalls].model
      local s = out[6]
      local sx = out[1] / model[1]
      local gap = math.abs((1 - s) - (sx - 1))
      if gap > worstGap then worstGap = gap end
    end
  end)
  check(worstGap < 0.0001,
        "volume preservado: (1 - s) e (sx - 1) batem em todo quadro, dentro de erro numerico")
end

do
  -- item 5 e 6: o PE NAO ESCORREGA (o contrato central de FOOTFALL) e a
  -- BORDA ANDA (o complemento que prova que o teste anterior nao passaria
  -- de gratis). Personagem andando ate um quadro com sx claramente fora de
  -- 1 (o pico do pulso, em andado = 16, com a velocidade ja saturada).
  --
  -- O centro do pe, local (8, 0, z), e o PIVO da escala em X: tem que
  -- mapear para o MESMO ponto de mundo com e sem a escala. Local
  -- (x, y, z) vira mundo, por linha, como m[c+1]*x + m[c+2]*y + m[c+3]*z +
  -- m[c+4] (c = 4*(linha-1)); com y = 0 isso e 8*col1 + z*col3 + col4 na
  -- linha 1 (indices 1, 2, 3, 4). Confere para dois valores de z.
  --
  -- A borda esquerda, local (0, 0, 0), so sobra col4: ela TEM que se mexer
  -- quando sx muda, senao o check do pe passaria com uma escala que na
  -- pratica nao faz nada (ex.: sx preso em 1 por um bug em outro lugar).
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handle, soEsta({ footfall = 0.7 })))
  local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local model, out
  withDrivenClock(function(setClock)
    for frame = 0, 16 do
      setClock(frame / 60)
      model = lifeModel(frame, 0, false)
      modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
      out = modules.Voxel3D.drawCalls[#modules.Voxel3D.drawCalls].model
    end
  end)
  local sx = out[1] / model[1]
  check(math.abs(sx - 1) > 0.01,
        "controle: sx realmente saiu de 1 neste quadro, senao o contrato abaixo nao testa nada")

  for _, z in ipairs({ 0, 5 }) do
    local antes = 8 * model[1] + z * model[3] + model[4]
    local depois = 8 * out[1] + z * out[3] + out[4]
    check(close(antes, depois),
          "pe nao escorrega (z=" .. z .. "): o centro do pe local (8,0,z) mapeia "
          .. "para o mesmo ponto de mundo com e sem a escala em X")
  end

  check(not close(model[4], out[4]),
        "a borda anda: o ponto local (0,0,0) SE MOVE quando sx muda, senao o check "
        .. "do pe passaria com uma escala que nao faz nada")
end

do
  -- item 7: a FASE vem da DISTANCIA, nao do relogio.
  --
  -- Parte 1: duas instancias, o MESMO tempo decorrido, distancias
  -- percorridas diferentes (velocidades diferentes): pontos diferentes do
  -- pulso, entao `s` sai diferente entre as duas.
  local function walkS(speed, frames)
    local pixels = {}
    pixels[0] = 1
    local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
      nil, nil, nil, nil, nil, true)
    loadWith(makeMod(handle, soEsta({ footfall = 0.7 })))
    local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
    local s
    withDrivenClock(function(setClock)
      for frame = 0, frames do
        setClock(frame / 60)
        local model = lifeProbeModel(frame * speed, 0, false)
        modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
        s = modules.Voxel3D.drawCalls[#modules.Voxel3D.drawCalls].model[6]
      end
    end)
    return s
  end
  local sSlow = walkS(1, 20)
  local sFast = walkS(2.5, 20)
  check(not close(sSlow, sFast),
        "mesmo tempo decorrido, distancias percorridas diferentes: `s` sai diferente "
        .. "(fases diferentes do pulso da passada)")

  -- Parte 2, complemento da anterior (e do item 2 acima): a mesma instancia
  -- PARADA nao muda de fase so porque o relogio andou. Mesma posicao, dois
  -- relogios bem diferentes (os mesmos valores do teste de fase de BREATH,
  -- mais acima nesta suite): `s` sai IGUAL, porque `andado` nunca mexeu.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handle, soEsta({ footfall = 0.7 })))
  local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local sA, sB
  withLoveTime(0, function()
    local model = lifeProbeModel(0, 0, false)
    modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
    sA = modules.Voxel3D.drawCalls[#modules.Voxel3D.drawCalls].model[6]
  end)
  withLoveTime(1.5, function()
    local model = lifeProbeModel(0, 0, false)
    modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
    sB = modules.Voxel3D.drawCalls[#modules.Voxel3D.drawCalls].model[6]
  end)
  check(close(sA, sB),
        "parado, relogio bem diferente: `s` fica igual, a fase nao mexeu junto")
end

do
  -- item 8: personalidade multiplica. Nenhuma folha de LIFE_PERSONALITY
  -- (main.lua) tem uma entrada `footfall` ainda, entao o check aqui vai na
  -- direcao oposta do de BREATH/guard mais acima nesta suite: confirma que
  -- o multiplicador AUSENTE vale 1, tanto para uma folha de todo fora da
  -- tabela (sheet.png) quanto para uma folha PRESENTE na tabela mas sem o
  -- campo footfall (guard.png, que tem rate/breath/sway mas nao footfall).
  -- A formula em main.lua e `pessoa and pessoa.footfall or 1`, e os dois
  -- casos caem no mesmo `or 1` final. Se um dia alguma folha ganhar
  -- footfall proprio na tabela, troque este check por um que compare a
  -- amplitude escalada, no mesmo espirito do teste BREATH/guard.
  local function peakS(image)
    local pixels = {}
    pixels[0] = 1
    local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
      nil, nil, nil, nil, nil, true)
    loadWith(makeMod(handle, soEsta({ footfall = 0.7 })))
    local mesh = modules.SpriteBillboards.mesh({ image = image, frames = 1 }, 0)
    local peak = 0
    withDrivenClock(function(setClock)
      for frame = 0, 32 do
        setClock(frame / 60)
        local model = lifeProbeModel(frame, 0, false)
        modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
        local out = modules.Voxel3D.drawCalls[#modules.Voxel3D.drawCalls].model
        local d = math.abs(out[6] - 1)
        if d > peak then peak = d end
      end
    end)
    return peak
  end
  local peakPlain = peakS("sheet.png")
  local peakGuard = peakS("guard.png")
  check(peakPlain > 0.001,
        "controle: a folha sem personalidade realmente achatou alguma coisa neste teste")
  check(closePercent(peakGuard, peakPlain, 0.01),
        "guard (na tabela, mas sem campo footfall) achata igual a uma folha ausente: "
        .. "o multiplicador ausente vale 1 nos dois casos")
end

-- ==========================================================================
-- PRIMEIRA PESSOA
-- ==========================================================================
-- Desde a v1.3.0 o mod devolvia o card plano sempre que a primeira pessoa
-- estivesse ativa, para nao produzir os espetos pretos que o Colonel_Aureliano
-- reportou. Isso agora e uma OPCAO, porque lendo o host o defeito nao e da
-- camera, e da distancia: o shader empurra cada vertice ao longo do proprio
-- raio ate o olho por `pull` unidades, e quem esta a menos de `pull` do olho
-- vai parar atras dele.
--
-- Entao o contrato desta secao e:
--   CARD continua exatamente como era, e e o padrao;
--   SOLID so existe se o canal de desenho existir para limitar o pull;
--   e o pull repassado NUNCA pode chegar no olho, para nenhuma distancia.

do
  -- 1. CARD em primeira pessoa devolve o card original, como sempre devolveu.
  local pixels = {}
  pixels[0] = 1
  local handle, modules, original = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, 1, nil, nil, true)
  loadWith(makeMod(handle, soEsta()))
  local def = { image = "sheet.png", frames = 1 }
  local mesh = modules.SpriteBillboards.mesh(def, 0)
  check(mesh and mesh.original == true,
        "FIRST PERSON CARD (o padrao) devolve o card original, contrato da v1.3.0")
  local _ = original
end

do
  -- 2. SOLID com canal devolve a NOSSA malha, que e a feature pedida.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, 1, nil, nil, true)
  loadWith(makeMod(handle, soEsta({ first_person = "solid" })))
  local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  check(mesh and mesh.original ~= true,
        "FIRST PERSON SOLID devolve o solido em primeira pessoa")
end

do
  -- 3. SOLID SEM canal continua caindo no card. Sem Voxel3D.draw nao ha como
  --    limitar o pull, e prometer solido ali seria devolver os espetos.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, 1, nil, nil, nil)
  loadWith(makeMod(handle, soEsta({ first_person = "solid" })))
  local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  check(mesh and mesh.original == true,
        "SOLID num host sem canal de desenho ainda devolve o card: sem o canal "
        .. "nao ha como limitar o pull")
end

do
  -- 4. A CONTA DO PULL, amarrada na geometria e nao num numero escolhido.
  --
  --    O olho fica a D unidades da ancora da matriz. O teto do pull e
  --    D - raio - folga, porque o vertice mais proximo esta a D - raio e ele
  --    precisa sobrar folga depois de andar `pull` na direcao do olho.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, 1, nil, nil, true)
  loadWith(makeMod(handle, soEsta({ first_person = "solid" })))
  local def = { image = "sheet.png", frames = 1 }
  local mesh = modules.SpriteBillboards.mesh(def, 0)
  local model = lifeModel(0, 0, false)

  local function pullEm(D, pedido)
    modules.Voxel3D.drawCalls = {}
    modules.Voxel3D.eye = { model[4], model[8], model[12] + D }
    modules.Voxel3D.draw(mesh, "tex", model, pedido, nil)
    return modules.Voxel3D.drawCalls[1].pull
  end

  check(close(pullEm(100, 6), 6),
        "longe do olho o pull passa inteiro: a 100 unidades nada precisa ceder")
  check(close(pullEm(30, 6), 6),
        "a 30 unidades o teto ainda e 14, maior que o pull real de 6")
  check(close(pullEm(20, 6), 4),
        "a 20 unidades o teto e 4 e o pull cede para 4")
  check(close(pullEm(16, 6), 0),
        "a 16 unidades o teto e zero: o pull acaba antes de empurrar")
  check(close(pullEm(3, 6), 0),
        "colado no olho, que e o card do proprio jogador na transicao, o pull e "
        .. "zero e nao negativo")

  -- E a invariante, varrida, que e o que impede uma edicao futura de reabrir o
  -- defeito: para NENHUMA distancia o pull repassado pode alcancar o olho.
  local furou = nil
  for D = 0, 80 do
    local p = pullEm(D, 6)
    local vertice = D - 14
    if p > 6 + 1e-9 or p > math.max(0, vertice - 2) + 1e-9 or p < 0 then
      furou = furou or D
    end
  end
  check(furou == nil,
        "varrendo 0 a 80 unidades, o pull repassado nunca passa do pedido nem "
        .. "alcanca o olho (primeira falha em D=" .. tostring(furou) .. ")")
end

do
  -- 5. FORA da primeira pessoa nada muda. O conserto nao pode custar nada a
  --    quem nunca entrou nessa camera, que e quase todo mundo.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, 0, nil, nil, true)
  loadWith(makeMod(handle, soEsta({ first_person = "solid" })))
  local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local model = lifeModel(0, 0, false)
  modules.Voxel3D.eye = { 0, 8, 9 }
  modules.Voxel3D.draw(mesh, "tex", model, 6, nil)
  check(close(modules.Voxel3D.drawCalls[1].pull, 6),
        "fora da primeira pessoa o pull passa intocado, mesmo com o olho colado")
end

do
  -- 6. STATUS nao pode dizer FIRST PERSON quando o solido esta saindo: a linha
  --    existe para contar o que esta acontecendo, e em SOLID nao esta.
  local pixels = {}
  pixels[0] = 1
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, 1, nil, nil, true)
  local modCard = loadWith(makeMod(handle, soEsta()))
  eq(statusRowValue(modCard), "FIRST PERSON",
     "em CARD a row de STATUS avisa que o card plano esta saindo")

  local handle2 = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, 1, nil, nil, true)
  local modSolid = loadWith(makeMod(handle2, soEsta({ first_person = "solid" })))
  check(statusRowValue(modSolid) ~= "FIRST PERSON",
        "em SOLID a row de STATUS nao diz FIRST PERSON, porque o card nao saiu")
end

-- ==========================================================================
-- WHAT IS ALIVE
-- ==========================================================================
-- Pikon reported the town map on the rival's table swaying. Kim's rule: people
-- and Pokemon move, objects hold still. The mod carries a list of OBJECTS, not
-- of characters, so anything it has never heard of is treated as alive; that
-- is what keeps another mod's Pokemon sprites breathing.
--
-- These checks pin both directions, because a rule tested on one side only
-- passes when the rule is "nothing ever moves".

do
  local pixels = {}
  pixels[0] = 1

  -- Sways or not, decided by the sheet the mesh came from. Returns whether the
  -- original draw got a NEW matrix, which is what the life channel does.
  local function mexe(folha)
    local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
      nil, nil, nil, nil, nil, true)
    loadWith(makeMod(handle, soEsta({ sway = 0.7, breath = 0.035 })))
    local mesh = modules.SpriteBillboards.mesh(
      { image = folha .. ".png", frames = 1 }, 0)
    local model = lifeModel(32, 48, false)
    modules.Voxel3D.draw(mesh, "tex", model, 6, nil)
    local call = modules.Voxel3D.drawCalls[1]
    return call and call.model ~= model
  end

  -- The seven objects measured as one-frame sheets that are furniture.
  for _, folha in ipairs({ "boulder", "clipboard", "fossil", "old_amber",
                           "paper", "poke_ball", "pokedex" }) do
    check(mexe(folha) == false,
          folha .. " nao mexe: objeto parado nao respira nem balanca")
  end

  -- The two one-frame sheets that are alive and merely still. A sleeping
  -- Snorlax that breathes is the reading we want, and it is the case a
  -- frame-count rule would have got wrong.
  for _, folha in ipairs({ "snorlax", "gambler_asleep" }) do
    check(mexe(folha) == true,
          folha .. " mexe: esta parado porque esta dormindo, nao porque e movel")
  end

  -- Characters, and the default for anything unknown. The unknown case is the
  -- one that protects other mods: overworld_wild_spawns registers hundreds of
  -- Pokemon sheets this mod has never seen, and a Pokemon should breathe.
  for _, folha in ipairs({ "red", "nurse", "oak",
                           "uma_folha_que_nunca_existiu" }) do
    check(mexe(folha) == true,
          folha .. " mexe: personagem, ou desconhecido, que e tratado como vivo")
  end
end

T.finish("voxel_chars_test")
