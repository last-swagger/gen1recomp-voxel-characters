-- Offline render harness for the Voxel Characters mod.
--
-- Loads mods/voxel_characters/main.lua under a stub of the host mod API and of
-- the Dramatic Shape namespace, builds the real geometry from the player's own
-- generated sprite sheets, and rasterizes it to a PNG contact sheet.
--
-- The point is a feedback loop that does not need a human at the keyboard:
-- every visual defect this mod has shipped so far was found by someone
-- watching a video. This lets the geometry be looked at directly, from any
-- angle, for every character, in seconds.
--
-- Run from the gen1recomp root:
--   love mods/voxel_characters/tools/render sprite=red shapes=slab,carved
--
-- The PNG lands in the LOVE save directory, path printed on stdout.

package.path = "./?.lua;./?/init.lua;" .. package.path

local ROOT = "./"
-- Por padrao mede o mod da arvore de trabalho, mas aceita apontar para outro
-- arquivo por VOXEL_CHARS_MAIN. Isso existe para poder renderizar o ANTES de
-- verdade a partir de uma tag ja lancada (`git show v1.4.1:main.lua > /tmp/x`)
-- em vez de ilustrar de memoria o que uma correcao mudou: comparativo de
-- release e afirmacao publica, e afirmacao publica precisa de medicao.
local MAIN_PATH = os.getenv("VOXEL_CHARS_MAIN")
  or (ROOT .. "mods/voxel_characters/main.lua")
local SPRITE_DIR = "assets/generated/sprites/"
-- Sobrescrito por `spritedir=`, para uma folha candidata poder ser renderizada
-- lado a lado com a original sem escrever nada no cache do jogador.

--------------------------------------------------------------------------
-- arguments
--------------------------------------------------------------------------

local opts = {
  sprite = "red",
  shapes = "slab,carved,carved_plus",
  frames = "0",
  yaws = "0,30,60,90",
  -- The Voxel Mod's own ladder, VoxelState.ANGLES_DEG = {0,35,15,35,50,75}.
  -- Its angle is measured from top-down: 0 lays the card flat on the ground
  -- (leanCorrection returns pi/2) and 90 stands it upright. A camera pitch
  -- above the horizon is therefore 90 minus that, which is what `rungs`
  -- converts. Judging geometry at a pitch nobody visits is how you fix the
  -- wrong thing.
  rungs = "15,35,50,75",
  pitch = "",
  depth = "3",
  side_color = "body",
  out = "sheet.png",
  bg = "0.32,0.34,0.38",
  cell = "220",
  label = "1",
  palette = "obj",
  diff = "0",
  metrics = "0",
  ao = "0",
  recess = "",
  outline = "back",
  depthmap = "",
  shade = "",
  spritedir = "",
  aostrength = "",
  ground = "",
  blink = "",
  blinktime = "",
  blinkscan = "",
  selftest = "",
  topedge = "",
}

local function parseArgs(argv)
  for _, a in ipairs(argv or {}) do
    local k, v = a:match("^([%w_]+)=(.*)$")
    if k then opts[k] = v end
  end
end

local function splitList(s)
  local out = {}
  for piece in tostring(s):gmatch("[^,]+") do
    out[#out + 1] = piece:match("^%s*(.-)%s*$")
  end
  return out
end

local function numbers(s)
  local out = {}
  for _, piece in ipairs(splitList(s)) do out[#out + 1] = tonumber(piece) end
  return out
end

--------------------------------------------------------------------------
-- host stubs
--
-- Same shape as tests/voxel_chars_test.lua, with two differences: the image
-- comes from a real PNG instead of a synthetic pixel table, and newMesh keeps
-- the raw vertex list instead of building a GPU mesh. Keeping the verts is
-- what lets one built mesh be drawn under many cameras: main.lua caches by
-- (def, frame, depth, pitch), so a camera baked into the mesh would be
-- silently reused by the next cell.
--------------------------------------------------------------------------

local function loadImageData(path)
  local f = assert(io.open(path, "rb"), "cannot open " .. path)
  local bytes = f:read("*a")
  f:close()
  local fd = love.filesystem.newFileData(bytes, path:match("[^/]+$"))
  return love.image.newImageData(fd)
end

local function makeVoxelHandle(imageData)
  local modules = {}
  local V = {}
  local original = function(def, frame)
    return { original = true, def = def, frame = frame }
  end
  function V.require(name)
    if modules[name] then return modules[name] end
    if name == "Voxel3D" then
      modules[name] = {
        FORMAT = {
          { "VertexPosition", "float", 3 },
          { "VertexTexCoord", "float", 2 },
          { "VertexShade", "float", 1 },
        },
        -- Mirrors Voxel3D.lua:412-420 statement for statement. The test
        -- suite's stub packs these into two multiple assignments, which in
        -- LuaJIT leaves holes (1 2 3 nil nil nil 7 ...) because `#map` is
        -- resolved before the assignments land. No test asserts on the map,
        -- so that never surfaced.
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
          local copy = {}
          for i, v in ipairs(verts) do
            copy[i] = { v[1], v[2], v[3], v[4], v[5], v[6] }
          end
          local mapCopy = {}
          for i, n in ipairs(map or {}) do mapCopy[i] = n end
          return {
            verts = copy,
            map = mapCopy,
            -- O mod aplica a piscada com pcall(mesh.setVertex, ...). Sem
            -- este metodo no stub a chamada falha em silencio e o harness
            -- nunca ve piscada nenhuma, o que parece o recurso nao funcionar.
            -- Duas formas, como o Mesh do LOVE: uma tabela de atributos, ou
            -- os atributos soltos. O mod tenta a forma de tabela primeiro e
            -- so cai para a solta se ela falhar, entao um stub que aceita
            -- qualquer coisa guarda a TABELA dentro do vertice e o erro
            -- aparece longe daqui, em quem faz aritmetica com a posicao.
            setVertex = function(self, i, a, b, c, d, e, f)
              if type(i) ~= "number" or i < 1 or i > #self.verts then
                error("setVertex: indice fora da faixa", 0)
              end
              if type(a) == "table" then
                self.verts[i] = { a[1], a[2], a[3], a[4], a[5], a[6] }
              else
                self.verts[i] = { a, b, c, d, e, f }
              end
            end,
            setVertexMap = function(self, m) self.map = m end,
            setTexture = function(self, tex) self.texture = tex end,
            release = function(self) self.released = true end,
          }
        end,
      }
    elseif name == "ImageCache" then
      modules[name] = { get = function() return imageData end }
    elseif name == "SpriteBillboards" then
      modules[name] = { mesh = original, shadowQuad = original }
    elseif name == "VoxelState" then
      modules[name] = { angle = math.pi / 2 }
    elseif name == "VoxelScene" then
      -- pi/2 pins leanCorrection() to zero, so the geometry arrives upright
      -- and this harness owns the camera outright.
      modules[name] = { spriteLean = math.pi / 2 }
    elseif name == "FirstPerson" then
      modules[name] = { cardBlend = function() return 0 end }
    else
      error("unexpected module " .. tostring(name))
    end
    return modules[name]
  end
  return { id = "DRAMATIC_SHAPE", version = "1.5.0", exports = { lib = V } }
end

local function makeMod(handle, stored)
  local schema, rows, events = nil, {}, {}
  local function noop() end
  local mod = {
    id = "voxel_characters",
    version = "0.0.0",
    path = "mods/voxel_characters",
    options = {},
    hooks = {},
    events = {},
    log = { info = noop, warn = noop, error = noop },
  }
  function mod.options:define(s) schema = s end
  function mod.options:get(key)
    if stored and stored[key] ~= nil then return stored[key] end
    for _, row in ipairs(schema or {}) do
      if row.key == key then return row.default end
    end
  end
  function mod.hooks:wrap(name, fn) rows[name] = fn end
  function mod.events:on(name, fn) events[name] = fn end
  function mod.find(id)
    if id == "DRAMATIC_SHAPE" then return handle end
  end
  mod._rows, mod._events = rows, events
  return mod
end

-- The original flat card, built here rather than through the mod, so a sheet
-- can put "what the Voxel Mod draws today" next to "what we draw instead".
-- Without it a misread of the sprite layout would look like a geometry defect.
local function flatCard(imageData, frames, frame)
  local sheetW, sheetH = imageData:getDimensions()
  local cellH = sheetH / frames
  local u0, u1 = 0, 1
  -- Y up, matching the mod: buildSlabMesh emits `lowY - ly`, so the sprite's
  -- bottom row sits at y = 0 and the sheet's v runs the other way.
  local vTop, vBottom = frame * cellH / sheetH, (frame + 1) * cellH / sheetH
  return {
    verts = {
      { 0, 0, 0, u0, vBottom, 1 },
      { sheetW, 0, 0, u1, vBottom, 1 },
      { sheetW, cellH, 0, u1, vTop, 1 },
      { 0, cellH, 0, u0, vTop, 1 },
    },
    map = { 1, 2, 3, 1, 3, 4 },
  }
end

local function buildGeometry(imageData, def, frame, shape, depth, sideColor)
  package.loaded["src.render.Assets"] = nil
  package.loaded["src.mods.Semver"] = nil
  local handle = makeVoxelHandle(imageData)
  local mod = makeMod(handle, {
    depth = depth, shape = shape, side_color = sideColor,
    ground_shade = opts.ground ~= "" and opts.ground or nil,
    blink = opts.blink ~= "" and "on" or nil,
    top_edge = opts.topedge ~= "" and opts.topedge or nil,
  })
  local chunk = assert(loadfile(MAIN_PATH))
  chunk(mod)
  local SpriteBillboards = handle.exports.lib.require("SpriteBillboards")
  local mesh
  local mesh = SpriteBillboards.mesh(def, frame)

  -- Procura o instante em que a piscada fecha, sem replicar a formula de fase
  -- do mod, o que seria testar a implementacao contra ela mesma. A malha e
  -- cacheada e mutada no lugar, entao rechamar com outro relogio e barato.
  if opts.blinkscan == "1" and mesh and mesh.verts then
    local realTime = love.timer.getTime
    local function uvSig(mm)
      local t = {}
      for i = 1, #mm.verts do
        local v = mm.verts[i]
        t[i] = string.format("%.5f_%.5f", v[4] or -1, v[5] or -1)
      end
      return table.concat(t, "|")
    end
    love.timer.getTime = function() return 0 end
    local open = uvSig(SpriteBillboards.mesh(def, frame))
    local hit
    for step = 1, 1000 do
      local t = step * 0.01
      love.timer.getTime = function() return t end
      if uvSig(SpriteBillboards.mesh(def, frame)) ~= open then hit = t break end
    end
    love.timer.getTime = realTime
    print(hit and string.format("BLINKSCAN fecha em t=%.2f s", hit)
               or "BLINKSCAN nao fecha em 10 s")
  end

  if mesh and mesh.original then
    return nil, "fell back to the flat card"
  end
  return mesh
end

--------------------------------------------------------------------------
-- camera
--
-- Vertices arrive in sprite-pixel space: x right, y down, z depth. They are
-- transformed here rather than in a shader so the projection is inspectable
-- from Lua and cannot silently disagree with a matrix upload convention.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- provenance
--
-- Every visible pixel came from one of five surfaces, and only two of them
-- carry the artist's pixels. Front and back sample the original sprite; side,
-- top and bottom are invented by this mod. A metric built on RGB cannot tell
-- them apart, because all five draw from the same four-tone palette. This
-- classifies per quad instead.
--
-- Classification is GEOMETRIC, from the quad's winding, verified statement by
-- statement against both builders (main.lua:637-651 for SLAB, :955-978 for
-- CARVED). Both agree:
--
--   +Z front    -Z back    +/-X side    -Y top    +Y bottom
--
-- The Y signs read backwards and that is fine: what matters is that they are
-- consistent and derived from geometry, not from OBJ_SHADE. Per-vertex ambient
-- occlusion would make the shade channel useless as a label, and AO is the
-- next thing we want to try.
--------------------------------------------------------------------------

local KINDS = { "front", "back", "side", "top", "bottom", "side_e", "side_w" }
-- Proveniencia so distingue arte de superficie inventada, entao os dois lados
-- contam como um. A separacao existe para o sombreamento, nao para a metrica.
local PROV_KIND = { side_e = "side", side_w = "side" }
-- Voxel3D.FACE_SHADE do host, o valor que cada face do MUNDO recebe.
local HOST_SHADE = {
  front = 0.90, back = 0.68, top = 1.00, bottom = 0.55,
  side_e = 0.84, side_w = 0.72,
}
local SHADE_OVERRIDE = nil
local KIND_INDEX = {}
for i, k in ipairs(KINDS) do KIND_INDEX[k] = i end

-- Original art versus surface this mod invented.
local IS_ART = { front = true, back = true }

-- buildCarvedMesh rotates the whole mesh per role about the vertical axis
-- (main.lua:920-932): role 1 is a half turn, role 2 a quarter turn. Undoing it
-- puts every mesh back in one frame of reference before the normal is read.
local ROLE_TURN = { [0] = 0, [1] = math.pi, [2] = math.pi / 2 }

local function classifyQuad(v1, v2, v3, turn)
  local e1x, e1y, e1z = v2[1] - v1[1], v2[2] - v1[2], v2[3] - v1[3]
  local e2x, e2y, e2z = v3[1] - v1[1], v3[2] - v1[2], v3[3] - v1[3]
  local nx = e1y * e2z - e1z * e2y
  local ny = e1z * e2x - e1x * e2z
  local nz = e1x * e2y - e1y * e2x
  if turn and turn ~= 0 then
    local c, s = math.cos(-turn), math.sin(-turn)
    nx, nz = nx * c - nz * s, nx * s + nz * c
  end
  local ax, ay, az = math.abs(nx), math.abs(ny), math.abs(nz)
  if ay >= ax and ay >= az then
    return ny < 0 and "top" or "bottom"
  elseif az >= ax then
    return nz > 0 and "front" or "back"
  end
  -- Leste e oeste separados. O mod hoje pinta os dois com um valor so, e o
  -- mundo em volta usa 0.84 contra 0.72: a luz do host vem do sudeste e as
  -- duas faces de um bloco nao recebem igual.
  return nx > 0 and "side_e" or "side_w"
end

-- Independent second opinion, from the shade constants in main.lua:44. It
-- cannot separate front from top (both 1.0), so it only ever contradicts the
-- geometry on the other three. A disagreement means one of the two readings is
-- stale, which is exactly what should stop a run rather than skew a metric.
local SHADE_KIND = { [0.68] = "back", [0.78] = "side", [0.55] = "bottom" }

local function classifyMesh(mesh, role)
  local turn = ROLE_TURN[role or 0] or 0
  local kinds, counts, conflicts = {}, {}, 0
  for _, k in ipairs(KINDS) do counts[k] = 0 end
  for i = 1, #mesh.verts, 4 do
    local v1, v2, v3 = mesh.verts[i], mesh.verts[i + 1], mesh.verts[i + 2]
    local kind = classifyQuad(v1, v2, v3, turn)
    local expected = SHADE_KIND[v1[6]]
    if expected and expected ~= kind then conflicts = conflicts + 1 end
    kinds[(i - 1) / 4 + 1] = kind
    counts[kind] = counts[kind] + 1
  end
  return kinds, counts, conflicts
end

--------------------------------------------------------------------------
-- ambient occlusion, as a question rather than a feature
--
-- The Voxel Mod already bakes per-vertex AO into every surface of the world
-- (ChunkMesher.lua:260-340) and our characters are the only thing in the
-- diorama without it: five flat constants against a world with a dark seam in
-- every corner. This computes the same thing for a slab so the answer can be
-- looked at before any of it is proposed for the mod itself.
--
-- Constants and the corner rule are the host's, not invented here. The rule
-- that matters is the last clause: a diagonal wedged behind both of its edges
-- adds nothing, because the corner is already as enclosed as it can get, and
-- counting it again is what turns an ordinary inside corner black.
--------------------------------------------------------------------------

-- Varrido por `aostrength=`. O valor 2.4 e o do host para o MUNDO, onde as
-- superficies sao grandes e as quinas raras. Um personagem de 16 pixels tem
-- outra escala de detalhe, e nao ha razao para a mesma forca servir aos dois.
local AO_STRENGTH = 2.4
local AO_STEP = 0.09 * AO_STRENGTH
local AO_GROUND = 0.12 * AO_STRENGTH
local function setAoStrength(v)
  AO_STRENGTH = v
  AO_STEP = 0.09 * v
  AO_GROUND = 0.12 * v
end
local AO_RISE = 6
local AO_FLOOR = 0.25

-- Occupancy of a SLAB, rebuilt from the sheet rather than from the mesh: the
-- mesh only carries exposed faces, and AO needs to know about the voxels that
-- are NOT exposed, which are exactly the ones doing the occluding.
local function slabOccupancy(data, frames, frame, cellW, cellH, depth)
  local sheetW, sheetH = data:getDimensions()
  local fy = frame * cellH
  local opaque = {}
  for ly = 0, cellH - 1 do
    for lx = 0, cellW - 1 do
      local ok, _, _, _, a = pcall(data.getPixel, data, lx, fy + ly)
      opaque[ly * cellW + lx] = ok and (a or 0) >= 0.5
    end
  end
  local cellBottom = cellH - 1
  -- Takes a voxel CENTRE in mesh space and answers whether it is solid.
  return function(cx, cy, cz)
    local lx = math.floor(cx)
    local ly = cellBottom - math.floor(cy)
    local k = math.floor(-cz)
    if k < 0 or k >= depth then return false end
    if lx < 0 or lx >= cellW or ly < 0 or ly >= cellH then return false end
    return opaque[ly * cellW + lx] or false
  end
end

local function normalise(x, y, z)
  local n = math.sqrt(x * x + y * y + z * z)
  if n < 1e-9 then return 0, 0, 0 end
  return x / n, y / n, z / n
end

-- One quad's four AO factors, in its own vertex order.
local function quadAO(verts, i, solid)
  local v1, v2, v3 = verts[i], verts[i + 1], verts[i + 2]
  local e1x, e1y, e1z = v2[1] - v1[1], v2[2] - v1[2], v2[3] - v1[3]
  local e2x, e2y, e2z = v3[1] - v1[1], v3[2] - v1[2], v3[3] - v1[3]
  local nx, ny, nz = normalise(
    e1y * e2z - e1z * e2y, e1z * e2x - e1x * e2z, e1x * e2y - e1y * e2x)

  -- Which way is out? Ask the geometry instead of trusting winding: sample the
  -- voxel on each side of the face centre and step away from the solid one.
  local cx, cy, cz = 0, 0, 0
  for j = i, i + 3 do
    cx, cy, cz = cx + verts[j][1] / 4, cy + verts[j][2] / 4, cz + verts[j][3] / 4
  end
  if solid(cx + nx * 0.5, cy + ny * 0.5, cz + nz * 0.5) then
    nx, ny, nz = -nx, -ny, -nz
  end

  local out = {}
  for j = 0, 3 do
    local v = verts[i + j]
    local prev = verts[i + (j + 3) % 4]
    local nxt = verts[i + (j + 1) % 4]
    local a1x, a1y, a1z = normalise(prev[1] - v[1], prev[2] - v[2], prev[3] - v[3])
    local a2x, a2y, a2z = normalise(nxt[1] - v[1], nxt[2] - v[2], nxt[3] - v[3])
    -- Outward from the face, and away from the quad's interior: the two edge
    -- neighbours and the diagonal between them.
    local ox, oy, oz = v[1] + nx * 0.5, v[2] + ny * 0.5, v[3] + nz * 0.5
    local a = solid(ox - a1x * 0.5, oy - a1y * 0.5, oz - a1z * 0.5)
    local b = solid(ox - a2x * 0.5, oy - a2y * 0.5, oz - a2z * 0.5)
    local d = solid(ox - (a1x + a2x) * 0.5, oy - (a1y + a2y) * 0.5,
                    oz - (a1z + a2z) * 0.5)
    local k = 0
    if a then k = k + 1 end
    if b then k = k + 1 end
    if d and not (a and b) then k = k + 1 end
    local f = math.max(AO_FLOOR, 1 - AO_STEP * k)
    -- Ground contact: the floor blocks half the sky, so the closer a vertex
    -- sits to it the less ambient light reaches it. This is what plants a
    -- character on the ground instead of leaving it pasted over the top.
    if v[2] < AO_RISE then
      local t = v[2] / AO_RISE
      f = f * (1 - AO_GROUND * (1 - t))
    end
    out[j + 1] = f
  end
  return out
end

-- PROTOTIPO: laje esculpida, fora do mod.
--
-- Testa uma hipotese medida: AO nao rende quase nada numa laje porque uma
-- extrusao nao tem concavidade em profundidade, e um casco visual nao pode ter
-- nenhuma, porque interseccao de silhuetas e convexa naquele eixo. Se a
-- hipotese estiver certa, dar RELEVO A SUPERFICIE FRONTAL deve fazer o mesmo
-- AO, com as mesmas constantes, saltar aos olhos.
--
-- Duas fontes de profundidade, nenhuma confiavel sozinha:
--
--   VISTA LATERAL  informacao ortografica real, mas usada como escala metrica
--                  da um cubo de 13 voxels num sprite de 16 de largura. Aqui
--                  ela entra como TETO por linha, nao como medida.
--   TOM            cobre cada pixel, mas em arte Gen 1 marca contorno E
--                  volume, e o proprio README deste mod ja avisa disso. Aqui
--                  ele so DISTRIBUI o teto que a vista lateral concedeu.
--
-- `mode` escolhe como o contorno e tratado: "naive" deixa o tom mandar, e o
-- contorno, por ser o tom mais escuro, recua ao maximo. "contour" reconhece
-- que o contorno e borda de silhueta, nao fundo de vale, e da a ele o recuo
-- do vizinho interno. A diferenca entre os dois e a ambiguidade do tom,
-- isolada e desenhavel.
local RECESS_MAX = 3
local BUDGET_MIN, BUDGET_MAX = 2, 6
-- Varridos por argumento para a amplitude do relevo poder ser procurada em vez
-- de escolhida: `recess=N` e `outline=front|back`.
local RECESS_OVERRIDE, OUTLINE_FRONT = nil, false
-- Mapa de profundidade externo: uma tabela 16x16 de inteiros, -1 para
-- transparente, produzida por um agente que olhou o sprite. Substitui o tom
-- como fonte de recuo. O tom cobre cada pixel mas confunde contorno com
-- volume; a pergunta que isto testa e se um agente separa os dois melhor.
local DEPTH_MAP = nil

local function sculptMesh(data, frames, frame, mode)
  local sheetW, sheetH = data:getDimensions()
  local cellW, cellH = sheetW, sheetH / frames
  local function texel(f, lx, ly)
    if lx < 0 or lx >= cellW or ly < 0 or ly >= cellH then return nil end
    if f < 0 or f >= frames then return nil end
    local ok, r, g, b, a = pcall(data.getPixel, data, lx, f * cellH + ly)
    if not (ok and (a or 0) >= 0.5) then return nil end
    return 0.299 * r + 0.587 * g + 0.114 * b
  end

  -- Teto de profundidade por linha, da vista lateral. Frame 2 e o personagem
  -- de perfil; a largura dele naquela linha e a espessura real do corpo ali.
  local sideFrame = frames >= 3 and 2 or nil
  local budget = {}
  for ly = 0, cellH - 1 do
    local lo, hi = nil, nil
    if sideFrame then
      for lx = 0, cellW - 1 do
        if texel(sideFrame, lx, ly) then
          lo = lo or lx
          hi = lx
        end
      end
    end
    local b = (lo and hi) and (hi - lo + 1) or BUDGET_MIN
    budget[ly] = math.max(BUDGET_MIN, math.min(BUDGET_MAX, b))
  end

  -- Faixa de tons do corpo, medida na folha inteira, com o contorno de fora.
  local outline, bodyMin, bodyMax = nil, 1, 0
  for f = 0, frames - 1 do
    for ly = 0, cellH - 1 do
      for lx = 0, cellW - 1 do
        local L = texel(f, lx, ly)
        if L then outline = outline and math.min(outline, L) or L end
      end
    end
  end
  for f = 0, frames - 1 do
    for ly = 0, cellH - 1 do
      for lx = 0, cellW - 1 do
        local L = texel(f, lx, ly)
        if L and math.abs(L - outline) > 1e-5 then
          bodyMin = math.min(bodyMin, L)
          bodyMax = math.max(bodyMax, L)
        end
      end
    end
  end
  local span = math.max(1e-6, bodyMax - bodyMin)

  local function recessRaw(lx, ly)
    local L = texel(frame, lx, ly)
    if not L then return nil end
    if DEPTH_MAP then
      local row = DEPTH_MAP[ly + 1]
      local v = row and row[lx + 1]
      if v and v >= 0 then return v end
      return 0
    end
    local maxR = RECESS_OVERRIDE or RECESS_MAX
    local isOutline = math.abs(L - outline) <= 1e-5
    if isOutline then
      -- O contorno cerca o personagem inteiro. Recua-lo levanta uma parede de
      -- cratera em volta de tudo, e a figura vira mascara: medido, nao suposto.
      if OUTLINE_FRONT then return 0 end
      if mode == "contour" then return nil end
      return maxR
    end
    -- Claro fica na frente, escuro recua.
    return math.floor((1 - (L - bodyMin) / span) * maxR + 0.5)
  end

  local recess = {}
  for ly = 0, cellH - 1 do
    for lx = 0, cellW - 1 do
      recess[ly * cellW + lx] = recessRaw(lx, ly)
    end
  end
  if mode == "contour" then
    -- O contorno herda o recuo do vizinho de corpo mais proximo, em vez de
    -- virar o fundo de um vale que o artista nunca desenhou.
    for ly = 0, cellH - 1 do
      for lx = 0, cellW - 1 do
        if texel(frame, lx, ly) and not recess[ly * cellW + lx] then
          local best
          for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local r = recess[(ly + d[2]) * cellW + (lx + d[1])]
            if r and (not best or r < best) then best = r end
          end
          recess[ly * cellW + lx] = best or RECESS_MAX
        end
      end
    end
  end

  local cellBottom = cellH - 1
  local function column(lx, ly)
    if lx < 0 or lx >= cellW or ly < 0 or ly >= cellH then return nil end
    local r = recess[ly * cellW + lx]
    if not r then return nil end
    local b = budget[ly]
    r = math.min(r, b - 1)
    if r < 0 then r = 0 end
    return r, b            -- ocupa k de r ate b-1
  end
  local function solid(cx, cy, cz)
    local lx, ly = math.floor(cx), cellBottom - math.floor(cy)
    local k = math.floor(-cz)
    local r, b = column(lx, ly)
    if not r then return false end
    return k >= r and k < b
  end

  -- As faces inventadas (lateral, topo, base) nao podem usar o texel do
  -- proprio pixel: o contorno cerca a figura, e pintar as paredes com ele
  -- reproduz exatamente as faces pretas que a comunidade reportou na v1.0.0 e
  -- que a v1.1.0 consertou com busca por texel de corpo. Sem isto o prototipo
  -- julgaria a ideia com um bug de tres versoes atras embutido.
  local function bodyTexelNear(lx, ly)
    local L = texel(frame, lx, ly)
    if not L or math.abs(L - outline) > 1e-5 then return lx, ly end
    for step = 1, 4 do
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local bx, by = lx + d[1] * step, ly + d[2] * step
        local BL = texel(frame, bx, by)
        if BL and math.abs(BL - outline) > 1e-5 then return bx, by end
      end
    end
    return lx, ly
  end

  local verts, idx = {}, {}
  local function quad(c, lx, ly, shade, invented)
    if invented then lx, ly = bodyTexelNear(lx, ly) end
    local u = (lx + 0.5) / sheetW
    local v = (frame * cellH + ly + 0.5) / sheetH
    local n = #verts / 4
    for i = 1, 4 do
      verts[#verts + 1] = { c[i][1], c[i][2], c[i][3], u, v, shade }
    end
    local base = n * 4
    idx[#idx + 1] = base + 1; idx[#idx + 1] = base + 2; idx[#idx + 1] = base + 3
    idx[#idx + 1] = base + 1; idx[#idx + 1] = base + 3; idx[#idx + 1] = base + 4
  end
  local SH = { front = 1.0, back = 0.68, side = 0.78, top = 1.0, bottom = 0.55 }
  for ly = 0, cellH - 1 do
    for lx = 0, cellW - 1 do
      local r, b = column(lx, ly)
      if r then
        local x0, x1 = lx, lx + 1
        local y0, y1 = cellBottom - ly, cellBottom - ly + 1
        for k = r, b - 1 do
          local z0, z1 = -k, -k - 1
          if not solid(lx + 0.5, y0 + 0.5, z0 + 0.5) then
            quad({ { x0, y0, z0 }, { x1, y0, z0 }, { x1, y1, z0 }, { x0, y1, z0 } },
                 lx, ly, SH.front)
          end
          if not solid(lx + 0.5, y0 + 0.5, z1 - 0.5) then
            quad({ { x1, y0, z1 }, { x0, y0, z1 }, { x0, y1, z1 }, { x1, y1, z1 } },
                 lx, ly, SH.back)
          end
          if not solid(lx - 0.5, y0 + 0.5, z0 - 0.5) then
            quad({ { x0, y0, z1 }, { x0, y0, z0 }, { x0, y1, z0 }, { x0, y1, z1 } },
                 lx, ly, SH.side, true)
          end
          if not solid(lx + 1.5, y0 + 0.5, z0 - 0.5) then
            quad({ { x1, y0, z0 }, { x1, y0, z1 }, { x1, y1, z1 }, { x1, y1, z0 } },
                 lx, ly, SH.side, true)
          end
          if not solid(lx + 0.5, y1 + 0.5, z0 - 0.5) then
            quad({ { x0, y1, z1 }, { x1, y1, z1 }, { x1, y1, z0 }, { x0, y1, z0 } },
                 lx, ly, SH.top, true)
          end
          if not solid(lx + 0.5, y0 - 0.5, z0 - 0.5) then
            quad({ { x0, y0, z0 }, { x1, y0, z0 }, { x1, y0, z1 }, { x0, y0, z1 } },
                 lx, ly, SH.bottom, true)
          end
        end
      end
    end
  end
  return { verts = verts, map = idx }, solid
end

local function bounds(verts)
  local b = {
    minX = math.huge, maxX = -math.huge,
    minY = math.huge, maxY = -math.huge,
    minZ = math.huge, maxZ = -math.huge,
  }
  for _, v in ipairs(verts) do
    b.minX, b.maxX = math.min(b.minX, v[1]), math.max(b.maxX, v[1])
    b.minY, b.maxY = math.min(b.minY, v[2]), math.max(b.maxY, v[2])
    b.minZ, b.maxZ = math.min(b.minZ, v[3]), math.max(b.maxZ, v[3])
  end
  return b
end

-- Model units of vertical view. A Gen 1 sprite cell is 16 px tall, so this
-- leaves margin for the pitch foreshortening without rescaling per cell:
-- every cell in a sheet must be measurable against every other one.
local VIEW_UNITS = 22

local function project(verts, cam)
  local out = {}
  local cy, cs = math.cos(cam.yaw), math.sin(cam.yaw)
  local cp, sp = math.cos(cam.pitch), math.sin(cam.pitch)
  for i, v in ipairs(verts) do
    local x, y, z = v[1] - cam.cx, v[2] - cam.cy, v[3] - cam.cz
    local rx = x * cy - z * cs
    local rz = x * cs + z * cy
    local ry2 = y * cp - rz * sp
    local rz2 = y * sp + rz * cp
    local px = cam.screenX + rx * cam.scale
    local py = cam.screenY - ry2 * cam.scale  -- model Y is up, screen Y is down
    -- Negated: the mod puts the front face at z = 0 and extrudes toward
    -- negative z, so without this the "less" depth test keeps the BACK of the
    -- slab. That renders the sprite art at OBJ_SHADE.back (0.68) and reads as
    -- a colour bug in the mod, which is what it looked like until FLAT and
    -- SLAB were put side by side at yaw 0.
    -- This shader returns clip space untouched, bypassing LOVE's transform, so
    -- nothing compensates for a canvas rendering bottom up. Without the flip
    -- the provenance pass is vertically mirrored against the visible one and
    -- every row is scored against a different row's pixels.
    local ndcY = 1 - py / cam.height * 2
    if cam.flipY then ndcY = -ndcY end
    out[i] = {
      px / cam.width * 2 - 1,
      ndcY,
      math.max(-0.999, math.min(0.999, -rz2 / cam.depthRange)),
      v[4], v[5], v[6],
    }
  end
  return out
end

--------------------------------------------------------------------------
-- render
--------------------------------------------------------------------------

-- The generated sheets are the Game Boy's four shades as grey (255/170/85/0);
-- the engine colourises at draw time. Doing the same four-entry lookup here is
-- what makes a render comparable to a screenshot instead of to a mask.
local SHADER = [[
varying float vShade;
#ifdef VERTEX
attribute float VertexShade;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vShade = VertexShade;
  return vertex_position;
}
#endif
#ifdef PIXEL
uniform vec3 pal0;
uniform vec3 pal1;
uniform vec3 pal2;
uniform vec3 pal3;
// When set, vShade carries a surface class instead of a light factor and the
// pass paints flat identity colours. Alpha discard still runs, so the
// silhouette of the provenance pass matches the visible one exactly.
uniform float provenance;
// Quando ligado, vShade carrega a celula de origem da face de topo,
// codificada como (lx + ly*16)/255, e o passe pinta isso em cinza. Serve para
// separar "a cor mudou" de "a superficie mudou de dono" entre duas poses.
uniform float cellid;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 t = Texel(tex, tc);
  if (t.a < 0.5) discard;
  if (cellid > 0.5) {
    if (vShade < 0.0) discard;
    return vec4(vShade, vShade, vShade, 1.0);
  }
  if (provenance > 0.5) {
    int k = int(vShade + 0.5);
    if (k == 1) return vec4(0.0, 1.0, 0.0, 1.0);  // front, original art
    if (k == 2) return vec4(0.0, 0.5, 0.0, 1.0);  // back, original art
    if (k == 3) return vec4(1.0, 0.0, 0.0, 1.0);  // side, invented
    if (k == 4) return vec4(0.0, 0.0, 1.0, 1.0);  // top, invented
    return vec4(1.0, 1.0, 0.0, 1.0);              // bottom, invented
  }
  float g = t.r;
  vec3 c = pal3;
  if (g > 0.833) c = pal0;
  else if (g > 0.5) c = pal1;
  else if (g > 0.167) c = pal2;
  return vec4(c * vShade, 1.0);
}
#endif
]]

-- Game Boy OBJ palette for the player and most overworld people, taken from
-- the note in src/render/PaletteFX.lua:107.
local PALETTES = {
  obj = { { 1, 1, 1 }, { 1, 0.518, 0.518 }, { 0.580, 0.227, 0.227 }, { 0, 0, 0 } },
  grey = { { 1, 1, 1 }, { 0.667, 0.667, 0.667 }, { 0.333, 0.333, 0.333 }, { 0, 0, 0 } },
}

local state = {}

local function fail(msg)
  print("ERROR: " .. msg)
  love.event.quit(1)
end

-- ------------------------------------------------------------- autoteste
--
-- O harness e a regua desta base, e por muito tempo ninguem conferiu a regua.
-- Dez defeitos numa unica sessao foram DELE se passando por defeito do mod:
-- sinal de profundidade invertido, que fazia a arte aparecer no shade de tras
-- e lia como bug de cor; pitch medido da ponta errada do ladder; Y-down contra
-- um mod Y-up; canvas que renderiza de baixo para cima, fazendo cada linha ser
-- pontuada contra os pixels de outra; pivo por bbox escondendo desalinhamento;
-- contagem de frames fixa em 6; stub sem setVertex; stub aceitando a forma
-- errada de setVertex; e amostragem grossa demais para uma janela de 0,12 s.
--
-- Cada um custou um ciclo inteiro de diagnostico apontado para o lugar errado.
-- Estas assercoes rodam em segundos e falham no lugar certo.
local function selftest()
  local fails, checks = 0, 0
  local function check(ok, name, detail)
    checks = checks + 1
    if not ok then
      fails = fails + 1
      print("FAIL " .. name .. (detail and ("  " .. detail) or ""))
    end
  end

  local data = loadImageData(SPRITE_DIR .. "red.png")
  local sheetW, sheetH = data:getDimensions()

  -- 1. Contagem de frames vem da altura, como o engine faz, nunca de constante.
  check(math.floor(sheetH / 16) == 6, "frames vem da altura da folha",
        "red.png deu " .. tostring(sheetH / 16))

  -- 2. setVertex do stub aceita as DUAS formas do Mesh do LOVE. O mod tenta a
  --    de tabela primeiro; um stub permissivo guarda a tabela dentro do
  --    vertice e o erro aparece longe, em quem faz aritmetica com posicao.
  local probe = makeVoxelHandle(data).exports.lib.require("Voxel3D")
    .newMesh({ { 1, 2, 3, 4, 5, 6 } }, { 1, 2, 3, 1, 3, 4 })
  probe:setVertex(1, { 9, 8, 7, 6, 5, 4 })
  check(probe.verts[1][1] == 9 and probe.verts[1][4] == 6,
        "setVertex aceita a forma de tabela")
  probe:setVertex(1, 1, 2, 3, 4, 5, 6)
  check(probe.verts[1][1] == 1 and probe.verts[1][4] == 4,
        "setVertex aceita a forma de escalares")

  -- 3. Convencao de eixos: o mod emite Y para cima e a frente em z = 0. Se
  --    qualquer um dos dois inverter, isto pega antes de virar diagnostico.
  local def = { image = SPRITE_DIR .. "red.png", frames = 6 }
  local mesh = buildGeometry(data, def, 0, "slab", 3, "body")
  check(mesh ~= nil, "malha SLAB constroi")
  if mesh then
    local b = bounds(mesh.verts)
    check(b.maxZ == 0, "frente esta em z = 0", "maxZ=" .. tostring(b.maxZ))
    check(b.minZ < 0, "corpo extruda para z negativo",
          "minZ=" .. tostring(b.minZ))
    check(b.minY == 0, "pe do sprite esta em y = 0",
          "minY=" .. tostring(b.minY))
    -- classificacao de face por winding, base de toda metrica de proveniencia
    local kinds = classifyMesh(mesh, 0)
    local seen = {}
    for _, k in ipairs(kinds) do seen[k] = true end
    check(seen.front and seen.back and seen.top,
          "classificacao acha frente, tras e topo")
  end

  print(string.format("autoteste do harness: %d/%d", checks - fails, checks))
  return fails == 0
end

function love.load(argv)
  parseArgs(argv)
  if opts.selftest == "1" then
    local ok = selftest()
    return love.event.quit(ok and 0 or 1)
  end
  -- Antes de qualquer malha ser construida: estes parametros mudam geometria.
  if opts.shade == "host" then SHADE_OVERRIDE = HOST_SHADE end
  if tonumber(opts.aostrength) then setAoStrength(tonumber(opts.aostrength)) end
  -- Congela o relogio antes de qualquer malha ser construida. O piscar e uma
  -- janela de 0,12 s num periodo com fase por folha; em vez de replicar a
  -- formula, que seria testar a implementacao contra ela mesma, o gate
  -- renderiza uma tira de instantes e olha qual fecha o olho.
  if tonumber(opts.blinktime) then
    local t = tonumber(opts.blinktime)
    love.timer.getTime = function() return t end
  end
  RECESS_OVERRIDE = tonumber(opts.recess)
  OUTLINE_FRONT = opts.outline == "front"
  if opts.depthmap ~= "" then
    local chunk = assert(loadfile(opts.depthmap), "depthmap ilegivel")
    DEPTH_MAP = chunk()
  end

  local sprites = splitList(opts.sprite)
  local shapes = splitList(opts.shapes)
  local frames = numbers(opts.frames)
  local yaws = numbers(opts.yaws)
  local cell = tonumber(opts.cell) or 220
  local depth = tonumber(opts.depth) or 3

  -- Every combination is one cell. Columns are yaw, so a row reads as one
  -- turntable; rows are (sprite, frame, shape), so a defect that only shows
  -- in one builder sits directly above the builder that does not have it.
  local pitches = {}
  if opts.pitch ~= "" then
    for _, p in ipairs(numbers(opts.pitch)) do
      pitches[#pitches + 1] = { deg = p, label = string.format("pitch %d", p) }
    end
  else
    for _, rung in ipairs(numbers(opts.rungs)) do
      pitches[#pitches + 1] = { deg = 90 - rung, label = "rung " .. rung }
    end
  end

  local rows = {}
  for _, sprite in ipairs(sprites) do
    local path = (opts.spritedir ~= "" and opts.spritedir or SPRITE_DIR)
      .. sprite .. ".png"
    local ok, data = pcall(loadImageData, path)
    if not ok then return fail("no sprite at " .. path) end
    -- The engine derives frame count from sheet height, not from a constant
    -- (src/import/RomExtractor.lua:481, src/render/SpriteRenderer.lua:86).
    -- Hardcoding 6 turns nurse.png (16x48, three frames) into six 8px frames
    -- and boulder.png (16x16, one frame) into six 2px ones, which is precisely
    -- the three-frame carve path this mod added in v1.2.0.
    local sw, sh = data:getDimensions()
    local def = { image = path, frames = math.max(1, math.floor(sh / 16)) }
    local texture = love.graphics.newImage(data)
    texture:setFilter("nearest", "nearest")
    for _, frame in ipairs(frames) do
      for _, shape in ipairs(shapes) do
        local mesh, why
        local wantAO = shape:find("_ao") ~= nil
        shape = shape:gsub("_ao$", "")
        local reliefSolid
        if wantAO then end
        if shape == "flat" then
          mesh = flatCard(data, def.frames, frame)
        elseif shape == "sculpt" then
          mesh, reliefSolid = sculptMesh(data, def.frames, frame, "naive")
        elseif shape == "sculptc" then
          mesh, reliefSolid = sculptMesh(data, def.frames, frame, "contour")
        else
          mesh, why = buildGeometry(data, def, frame, shape, depth,
                                    opts.side_color)
        end
        local sheetW, sheetH = data:getDimensions()
        local occ = reliefSolid or ((shape == "slab")
          and slabOccupancy(data, def.frames, frame, sheetW,
                            sheetH / def.frames, depth) or nil)
        -- Only the carved builders rotate per role; buildSlabMesh emits every
        -- frame in the same frame of reference (main.lua:608-613).
        local role = (shape == "carved" or shape == "carved_plus")
          and (frame % 3) or 0
        local kinds, quadKinds, conflicts
        if mesh then
          kinds, quadKinds, conflicts = classifyMesh(mesh, role)
          if conflicts > 0 then
            print(string.format(
              "WARNING %s f%d %s: %d quads where winding and OBJ_SHADE disagree",
              sprite, frame, shape, conflicts))
          end
        end
        for _, pitch in ipairs(pitches) do
          rows[#rows + 1] = {
            sprite = sprite, frame = frame, shape = shape,
            pitch = math.rad(pitch.deg), pitchLabel = pitch.label,
            mesh = mesh, why = why, texture = texture,
            cellW = sheetW, cellH = sheetH / def.frames,
            kinds = kinds, quadKinds = quadKinds, role = role, occ = occ,
            ao = wantAO,
            shapeLabel = shape:upper() .. (wantAO and "+AO" or ""),
          }
        end
      end
    end
  end
  if #rows == 0 then return fail("nothing to render") end

  local labelH = opts.label == "1" and 18 or 0
  local width = cell * #yaws
  local height = (cell + labelH) * #rows
  love.window.setMode(width, height, { depth = 24, vsync = 0 })

  state.rows, state.yaws, state.cell, state.labelH = rows, yaws, cell, labelH
  state.width, state.height = width, height
  state.ao = opts.ao == "1"
  state.shader = love.graphics.newShader(SHADER)
  local pal = PALETTES[opts.palette] or PALETTES.obj
  for i = 1, 4 do state.shader:send("pal" .. (i - 1), pal[i]) end
  state.bg = numbers(opts.bg)
  state.frames = 0

  local quads = 0
  for _, row in ipairs(rows) do
    if row.mesh then
      quads = quads + math.floor(#row.mesh.verts / 4)
      if row.quadKinds then
        local t = {}
        for _, k in ipairs(KINDS) do t[#t + 1] = k .. "=" .. row.quadKinds[k] end
        print("    quads por face: " .. table.concat(t, "  "))
      end
      local b = bounds(row.mesh.verts)
      print(string.format(
        "%s f%d %-12s quads=%4d  x[%.1f..%.1f] y[%.1f..%.1f] z[%.1f..%.1f] idx=%d",
        row.sprite, row.frame, row.shape, math.floor(#row.mesh.verts / 4),
        b.minX, b.maxX, b.minY, b.maxY, b.minZ, b.maxZ, #row.mesh.map))
    else
      print(string.format("%s f%d %-12s NO MESH (%s)",
        row.sprite, row.frame, row.shape, tostring(row.why)))
    end
  end
  print(string.format("cells=%d quads=%d canvas=%dx%d",
    #rows * #yaws, quads, width, height))
end

local function drawCell(row, yaw, x, y, size, asProvenance, asCellId)
  if not row.mesh then return end
  local b = bounds(row.mesh.verts)
  -- Pivot on the sprite CELL, and on z = 0, the plane the flat card occupies.
  --
  -- This used to pivot on each mesh's own bounding box, because until v1.3.0
  -- the mod dropped the cell's empty padding and rebased geometry on the
  -- opaque bounds. That made a cell pivot wrong and a bbox pivot merely
  -- approximate: a sheet whose art is off centre inside its cell, like
  -- snorlax, still read as misaligned against the card. Now that the mod
  -- emits in cell coordinates on both axes, the cell is the shared frame of
  -- reference and the comparison against FLAT is exact rather than indicative.
  local cam = {
    yaw = yaw, pitch = row.pitch,
    cx = (row.cellW or (b.minX + b.maxX)) / 2,
    cy = (row.cellH or (b.minY + b.maxY)) / 2,
    cz = 0,
    scale = size / VIEW_UNITS,
    screenX = x + size / 2,
    screenY = y + size / 2,
    width = state.width, height = state.height, flipY = asProvenance,
    -- generous so nothing clips; the depth test only needs ordering
    depthRange = math.max(64, (b.maxY - b.minY) * 2),
  }
  local verts = project(row.mesh.verts, cam)
  if SHADE_OVERRIDE and not asProvenance then
    for i = 1, #row.mesh.verts, 4 do
      local v = SHADE_OVERRIDE[row.kinds[(i - 1) / 4 + 1]]
      if v then
        for j = 0, 3 do verts[i + j][6] = v end
      end
    end
  end
  if (state.ao or row.ao) and row.occ and not asProvenance then
    local hist, n, sum, minf = {}, 0, 0, 1
    for i = 1, #row.mesh.verts, 4 do
      local f = quadAO(row.mesh.verts, i, row.occ)
      for j = 0, 3 do
        verts[i + j][6] = verts[i + j][6] * f[j + 1]
        local bucket = math.floor(f[j + 1] * 20 + 0.5) / 20
        hist[bucket] = (hist[bucket] or 0) + 1
        n, sum = n + 1, sum + f[j + 1]
        if f[j + 1] < minf then minf = f[j + 1] end
      end
    end
    if not state.aoReported then
      state.aoReported = true
      local keys = {}
      for k in pairs(hist) do keys[#keys + 1] = k end
      table.sort(keys)
      local parts = {}
      for _, k in ipairs(keys) do
        parts[#parts + 1] = string.format("%.2f:%d(%.0f%%)", k, hist[k],
          hist[k] / n * 100)
      end
      print(string.format("AO em %d vertices  media %.3f  minimo %.3f",
        n, sum / n, minf))
      print("  distribuicao  " .. table.concat(parts, "  "))
    end
  end
  if asCellId then
    local cellBottom = (row.cellH or 16) - 1
    for i = 1, #row.mesh.verts, 4 do
      local kind = row.kinds[(i - 1) / 4 + 1]
      local val = -1
      if kind == "top" then
        local q = row.mesh.verts
        local minX = math.min(q[i][1], q[i+1][1], q[i+2][1], q[i+3][1])
        local qy = q[i][2]
        local lx = math.floor(minX + 0.001)
        local ly = cellBottom + 1 - math.floor(qy + 0.001)
        if lx >= 0 and lx < 16 and ly >= 0 and ly < 16 then
          val = (lx + ly * 16) / 255
        end
      end
      for j = 0, 3 do verts[i + j][6] = val end
    end
  end
  if asProvenance then
    for i, v in ipairs(verts) do
      local k = row.kinds[math.floor((i - 1) / 4) + 1]
      v[6] = KIND_INDEX[PROV_KIND[k] or k]
    end
  end
  local mesh = love.graphics.newMesh(
    { { "VertexPosition", "float", 3 },
      { "VertexTexCoord", "float", 2 },
      { "VertexShade", "float", 1 } },
    verts, "triangles", "static")
  mesh:setVertexMap(row.mesh.map)
  mesh:setTexture(row.texture)
  love.graphics.draw(mesh)
  mesh:release()
end

-- Render the same sheet with identity colours instead of art, read it back,
-- and count. This is the fitness function: a number for how much of what the
-- player sees is the artist's work and how much is surface this mod made up.
local function computeMetrics(screen)
  local w, h = state.width, state.height
  local colour = love.graphics.newCanvas(w, h)
  local depth = love.graphics.newCanvas(w, h,
    { format = "depth24", readable = false })
  love.graphics.setCanvas({ colour, depthstencil = depth })
  love.graphics.clear(0, 0, 0, 0, true, true)
  love.graphics.setDepthMode("less", true)
  love.graphics.setShader(state.shader)
  state.shader:send("provenance", 1)
  local cell, labelH = state.cell, state.labelH
  for r, row in ipairs(state.rows) do
    local y = (r - 1) * (cell + labelH) + labelH
    for c, yawDeg in ipairs(state.yaws) do
      drawCell(row, math.rad(yawDeg), (c - 1) * cell, y, cell, true)
    end
  end
  state.shader:send("provenance", 0)
  love.graphics.setShader()
  love.graphics.setDepthMode("always", false)
  love.graphics.setCanvas()

  local img = colour:newImageData()
  local function kindAt(r, g, b, a)
    if a < 0.5 then return nil end
    if g > 0.75 and r < 0.25 then return "front" end
    if g > 0.25 and r < 0.25 and b < 0.25 then return "back" end
    if r > 0.75 and g > 0.75 then return "bottom" end
    if r > 0.75 then return "side" end
    if b > 0.75 then return "top" end
    return nil
  end

  if opts.histogram == "1" then
    local seen = {}
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r, g, b, a = img:getPixel(x, y)
        local key = string.format("%.2f,%.2f,%.2f,%.2f", r, g, b, a)
        seen[key] = (seen[key] or 0) + 1
      end
    end
    local list = {}
    for k, v in pairs(seen) do list[#list + 1] = { k, v } end
    table.sort(list, function(p, q) return p[2] > q[2] end)
    print("provenance canvas colours:")
    for i = 1, math.min(#list, 10) do
      print(string.format("  %s  x%d", list[i][1], list[i][2]))
    end
  end

  -- Silhouette leak: pixels this mod draws that the original card for the SAME
  -- frame does not cover. At zero pitch and zero yaw the two silhouettes must
  -- agree, because the slab is built over the union of every walk frame and
  -- relies on the shader's alpha discard to clip each frame back down. A face
  -- whose UV resolves into another frame escapes that clip, and the report from
  -- the field is "all of Red's sprites appear at once while walking sideways".
  local flatAt = {}
  for r, row in ipairs(state.rows) do
    if row.shape == "flat" then
      flatAt[row.sprite .. "|" .. row.frame .. "|" .. row.pitchLabel] = r
    end
  end
  if next(flatAt) then
    print("")
    print("silhouette against the original card, same frame")
    print("  leak   drawn where the card is empty; must be 0 at yaw 0 pitch 0")
    print("  miss   card covers it, this mod does not")
    for r, row in ipairs(state.rows) do
      local fr = flatAt[row.sprite .. "|" .. row.frame .. "|" .. row.pitchLabel]
      if fr and fr ~= r then
        local yF = (fr - 1) * (cell + labelH) + labelH
        local yR = (r - 1) * (cell + labelH) + labelH
        for c, yawDeg in ipairs(state.yaws) do
          local x0 = (c - 1) * cell
          local leak, miss, both = 0, 0, 0
          for y = 0, cell - 1 do
            for x = 0, cell - 1 do
              local _, _, _, af = img:getPixel(x0 + x, yF + y)
              local _, _, _, ar = img:getPixel(x0 + x, yR + y)
              local inF, inR = af >= 0.5, ar >= 0.5
              if inR and not inF then leak = leak + 1
              elseif inF and not inR then miss = miss + 1
              elseif inF then both = both + 1 end
            end
          end
          local union = leak + miss + both
          print(string.format(
            "  %-11s %-9s yaw %2d   leak %5d   miss %5d   IoU %.3f",
            row.shape, row.pitchLabel, yawDeg, leak, miss,
            union > 0 and both / union or 0))
        end
      end
    end
  end

  -- Silhouette of every row against row 1. Two walk frames of the same builder
  -- must NOT have the same outline: if they do, the shell being drawn is the
  -- union of every pose rather than the pose being asked for.
  do
    local y1 = labelH
    print("")
    print("silhouette against row 1")
    for r = 2, #state.rows do
      local row = state.rows[r]
      local yR = (r - 1) * (cell + labelH) + labelH
      for c, yawDeg in ipairs(state.yaws) do
        local x0 = (c - 1) * cell
        local diff, both = 0, 0
        for y = 0, cell - 1 do
          for x = 0, cell - 1 do
            local _, _, _, a1 = img:getPixel(x0 + x, y1 + y)
            local _, _, _, a2 = img:getPixel(x0 + x, yR + y)
            local in1, in2 = a1 >= 0.5, a2 >= 0.5
            if in1 ~= in2 then diff = diff + 1
            elseif in1 then both = both + 1 end
          end
        end
        print(string.format("  row %d %-11s f%d yaw %2d   differing %5d   IoU %.4f",
          r, row.shape, row.frame, yawDeg, diff,
          (diff + both) > 0 and both / (diff + both) or 0))
      end
    end
  end

  -- Cruza proveniencia com a imagem visivel: para cada tipo de face, quanto
  -- dela chega ao olho como o tom mais escuro. O contorno Gen 1 e preto e
  -- cerca a figura inteira; se ele domina as faces inventadas, o personagem le
  -- como bloco escuro por mais volume que tenha.
  if screen then
    print("")
    print("share of each face kind that reaches the eye as the darkest tone")
    for r, row in ipairs(state.rows) do
      local y0 = (r - 1) * (cell + labelH) + labelH
      for c, yawDeg in ipairs(state.yaws) do
        local x0 = (c - 1) * cell
        local dark, tot, darkAll, totAll = {}, {}, 0, 0
        for _, k in ipairs(KINDS) do dark[k], tot[k] = 0, 0 end
        for y = 0, cell - 1 do
          for x = 0, cell - 1 do
            local kind = kindAt(img:getPixel(x0 + x, y0 + y))
            if kind then
              local sr, sg, sb = screen:getPixel(x0 + x, y0 + y)
              local isDark = (sr + sg + sb) / 3 < 0.12
              tot[kind] = tot[kind] + 1
              totAll = totAll + 1
              if isDark then
                dark[kind] = dark[kind] + 1
                darkAll = darkAll + 1
              end
            end
          end
        end
        if totAll > 0 then
          local parts = {}
          for _, k in ipairs({ "front", "top", "side", "bottom" }) do
            if tot[k] > 0 then
              parts[#parts + 1] = string.format("%s %.0f%%", k,
                dark[k] / tot[k] * 100)
            end
          end
          print(string.format("  %-11s yaw %2d   preto total %.1f%%   (%s)",
            row.shape, yawDeg, darkAll / totAll * 100,
            table.concat(parts, "  ")))
        end
      end
    end
  end

  -- Identidade da celula que gerou cada pixel de topo. Separa "a cor mudou"
  -- de "a superficie mudou de dono", que sao defeitos diferentes.
  if screen and #state.rows > 1 then
    local cbuf = love.graphics.newCanvas(w, h)
    local cdep = love.graphics.newCanvas(w, h, { format = "depth24", readable = false })
    love.graphics.setCanvas({ cbuf, depthstencil = cdep })
    love.graphics.clear(0, 0, 0, 0, true, true)
    love.graphics.setDepthMode("less", true)
    love.graphics.setShader(state.shader)
    state.shader:send("cellid", 1)
    for r, row in ipairs(state.rows) do
      local y = (r - 1) * (cell + labelH) + labelH
      for c, yawDeg in ipairs(state.yaws) do
        drawCell(row, math.rad(yawDeg), (c - 1) * cell, y, cell, false, true)
      end
    end
    state.shader:send("cellid", 0)
    love.graphics.setShader()
    love.graphics.setDepthMode("always", false)
    love.graphics.setCanvas()
    local cimg = cbuf:newImageData()
    print("")
    print("origem da face de topo, linha 1 contra as outras")
    local y1 = labelH
    for r = 2, #state.rows do
      local row = state.rows[r]
      local yR = (r - 1) * (cell + labelH) + labelH
      for c, yawDeg in ipairs(state.yaws) do
        local x0 = (c - 1) * cell
        local both, sameCell, diffCell = 0, 0, 0
        for y = 0, cell - 1 do
          for x = 0, cell - 1 do
            local _, _, _, a1 = cimg:getPixel(x0 + x, y1 + y)
            local _, _, _, a2 = cimg:getPixel(x0 + x, yR + y)
            if a1 >= 0.5 and a2 >= 0.5 then
              both = both + 1
              local v1 = select(1, cimg:getPixel(x0 + x, y1 + y))
              local v2 = select(1, cimg:getPixel(x0 + x, yR + y))
              if math.abs(v1 - v2) < 0.002 then sameCell = sameCell + 1
              else diffCell = diffCell + 1 end
            end
          end
        end
        if both > 0 then
          print(string.format(
            "  f%d yaw %2d   topo em ambas %5d   mesma celula %5d   celula diferente %5d (%.1f%%)",
            row.frame, yawDeg, both, sameCell, diffCell, diffCell / both * 100))
        end
      end
    end
    cbuf:release(); cdep:release()
  end

  -- Estabilidade de cor da face de topo entre poses. O report do Angelus e
  -- "o topo da cabeca pisca enquanto anda": se a MESMA posicao de tela for
  -- face de topo em duas poses e a cor mudar, isso e o piscar, medido.
  if screen and #state.rows > 1 then
    print("")
    print("cor da face de topo na mesma posicao, linha 1 contra as outras")
    local y1 = labelH
    for r = 2, #state.rows do
      local row = state.rows[r]
      local yR = (r - 1) * (cell + labelH) + labelH
      for c, yawDeg in ipairs(state.yaws) do
        local x0 = (c - 1) * cell
        local both, differ = 0, 0
        for y = 0, cell - 1 do
          for x = 0, cell - 1 do
            local k1 = kindAt(img:getPixel(x0 + x, y1 + y))
            local k2 = kindAt(img:getPixel(x0 + x, yR + y))
            if k1 == "top" and k2 == "top" then
              both = both + 1
              local a1, b1, c1 = screen:getPixel(x0 + x, y1 + y)
              local a2, b2, c2 = screen:getPixel(x0 + x, yR + y)
              if math.abs(a1 - a2) + math.abs(b1 - b2) + math.abs(c1 - c2) > 0.06 then
                differ = differ + 1
              end
            end
          end
        end
        if both > 0 then
          print(string.format(
            "  %-11s f%d yaw %2d   topo em ambas %5d   cor diferente %5d  (%.1f%%)",
            row.shape, row.frame, yawDeg, both, differ, differ / both * 100))
        end
      end
    end
  end

  print("")
  print("provenance at the visible pixel level")
  print("  art%   share of drawn pixels sampling the original sprite art")
  print("  top%   share taken by upward faces, which carry no art at all")
  for r, row in ipairs(state.rows) do
    local y0 = (r - 1) * (cell + labelH) + labelH
    for c, yawDeg in ipairs(state.yaws) do
      local x0 = (c - 1) * cell
      local n = {}
      for _, k in ipairs(KINDS) do n[k] = 0 end
      local drawn = 0
      for y = 0, cell - 1 do
        for x = 0, cell - 1 do
          local kind = kindAt(img:getPixel(x0 + x, y0 + y))
          if kind then n[kind] = n[kind] + 1; drawn = drawn + 1 end
        end
      end
      if drawn > 0 then
        local art = (n.front + n.back) / drawn * 100
        print(string.format(
          "  %-11s %-9s yaw %2d   art %5.1f%%   top %5.1f%%   side %5.1f%%   base %5.1f%%",
          row.shape, row.pitchLabel, yawDeg, art, n.top / drawn * 100,
          n.side / drawn * 100, n.bottom / drawn * 100))
      end
    end
  end
  colour:release()
  depth:release()
end

function love.draw()
  -- The window carries its own depth buffer (conf.lua sets t.window.depth),
  -- so the whole sheet is one depth-tested pass with no canvas juggling.
  love.graphics.clear(state.bg[1], state.bg[2], state.bg[3], 1, true, true)
  love.graphics.setDepthMode("less", true)
  love.graphics.setShader(state.shader)
  love.graphics.setColor(1, 1, 1, 1)

  local cell, labelH = state.cell, state.labelH
  for r, row in ipairs(state.rows) do
    local y = (r - 1) * (cell + labelH) + labelH
    for c, yawDeg in ipairs(state.yaws) do
      drawCell(row, math.rad(yawDeg), (c - 1) * cell, y, cell)
    end
  end

  love.graphics.setShader()
  love.graphics.setDepthMode("always", false)
  for r, row in ipairs(state.rows) do
    local y = (r - 1) * (cell + labelH)
    if labelH > 0 then
      love.graphics.setColor(0, 0, 0, 0.55)
      love.graphics.rectangle("fill", 0, y, state.width, labelH)
      love.graphics.setColor(1, 1, 1, 1)
      local text = string.format("%s  frame %d  %s%s  %s%s", row.sprite,
        row.frame, row.shapeLabel or row.shape:upper(), "", row.pitchLabel,
        row.why and ("  [" .. row.why .. "]") or "")
      love.graphics.print(text, 6, y + 2)
    end
  end
end

-- Compare every row against row 1, cell for cell. The eye cannot be trusted
-- with a 16x16 sprite blown up 16 times: judging these by looking already
-- produced one wrong diagnosis in this file's own history. A count of
-- differing pixels can be asserted on.
local function reportDiff(img)
  local cell, labelH = state.cell, state.labelH
  local base = state.rows[1]
  print(string.format("baseline row 1: %s frame %d %s %s",
    base.sprite, base.frame, base.shape:upper(), base.pitchLabel))
  for r = 2, #state.rows do
    local row = state.rows[r]
    for c = 1, #state.yaws do
      local x0 = (c - 1) * cell
      local y0 = (r - 1) * (cell + labelH) + labelH
      local b0 = labelH
      local differing, opaque = 0, 0
      for y = 0, cell - 1 do
        for x = 0, cell - 1 do
          local ar, ag, ab = img:getPixel(x0 + x, b0 + y)
          local br, bg, bb = img:getPixel(x0 + x, y0 + y)
          local d = math.abs(ar - br) + math.abs(ag - bg) + math.abs(ab - bb)
          if d > 0.02 then differing = differing + 1 end
          opaque = opaque + 1
        end
      end
      print(string.format("row %d yaw %d  %-12s %-9s  differing %5d / %d  (%.1f%%)",
        r, state.yaws[c], row.shape, row.pitchLabel, differing, opaque,
        differing / opaque * 100))
    end
  end
end

function love.update()
  state.frames = (state.frames or 0) + 1
  if state.frames == 3 then
    love.graphics.captureScreenshot(function(img)
      img:encode("png", opts.out)
      print("WROTE " .. love.filesystem.getSaveDirectory() .. "/" .. opts.out)
      if opts.diff == "1" and #state.rows > 1 then reportDiff(img) end
      if opts.metrics == "1" then computeMetrics(img) end
    end)
  elseif state.frames > 6 then
    love.event.quit()
  end
end

function love.keypressed(key)
  if key == "escape" then love.event.quit() end
end
