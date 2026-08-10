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
-- Caminho errado nao pode virar processo pendurado. Sob o `love`, um assert
-- que falha abre a janela de erro padrao em vez de sair, e quem chamou por
-- pipe (o check.sh faz isso) nao recebe NADA: o processo trava e so morre com
-- kill. Medido numa revisao. Entao a checagem e explicita e antes de tudo.
do
  local f = io.open(MAIN_PATH, "r")
  if f then f:close() else
    io.stderr:write("VOXEL_CHARS_MAIN aponta para arquivo inexistente: "
      .. MAIN_PATH .. "\n")
    os.exit(2)
  end
end
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
  opt = "",
  lab = "",
  -- `labshot=arquivo.png` abre o laboratorio, fotografa e sai. Existe para o
  -- laboratorio poder ser CHECADO sem ninguem apertar tecla: uma ferramenta
  -- interativa que ninguem testa quebra calada.
  labshot = "",
  labab = "",
  -- Onde as escolhas caem, e uma escolha simulada para o gate. O arquivo e
  -- parametrizavel porque o gate NAO pode escrever escolha inventada no
  -- arquivo que vai treinar o juiz: seria envenenar o dado com a propria
  -- ferramenta de teste.
  labfile = "escolhas.txt",
  labpick = "",
  -- `features=<arquivo>` le uma linha por variante (folha TAB chave:valor,...)
  -- e imprime uma linha TSV de features por variante. E a metade cara do
  -- juiz: exige LOVE, sprite de verdade e o mod carregado. A metade barata,
  -- que ajusta o modelo, roda em luajit puro em tools/juiz.
  features = "",
}

-- O schema que o proprio mod registra, capturado na ultima construcao. O
-- laboratorio monta o menu dele a partir daqui em vez de manter uma copia:
-- tabela paralela apodrece, e ja apodreceu neste projeto (uma opcao nova ficou
-- sem medicao visual porque a ferramenta nao sabia que ela existia).
local LAB_SCHEMA = nil
local MOD_CHUNK = nil

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
  function mod.options:define(s) schema = s; mod._schema = s end
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
  local stored = {
    depth = depth, shape = shape, side_color = sideColor,
    ground_shade = opts.ground ~= "" and opts.ground or nil,
    blink = opts.blink ~= "" and "on" or nil,
    top_edge = opts.topedge ~= "" and opts.topedge or nil,
  }
  -- Passagem generica de opcao do mod: `opt=chave:valor,chave:valor`.
  --
  -- Antes disto, cada opcao nova do mod exigia editar este arquivo, e uma
  -- rodada de implementacao ficou sem medicao visual justamente porque a
  -- opcao nova nao tinha como chegar aqui e o implementador estava proibido
  -- de mexer na regua. Ferramenta que precisa ser editada a cada feature nao
  -- e ferramenta, e degrau.
  --
  -- Valor numerico e convertido, porque o mod guarda algumas opcoes como
  -- numero e outras como string (FRONT_SHAPE_VALUES = { "off", 0.12, ... }) e
  -- passar "0.12" onde ele espera 0.12 cai no default sem avisar.
  -- Chave desconhecida NAO pode passar em silencio: um erro de digitacao
  -- vira "medi com a opcao desligada e nao percebi", que e exatamente o erro
  -- que eu cometi ao passar `low` onde o mod guarda 0.12. A validacao roda
  -- depois que o mod se registra, porque so entao existe schema.
  local pedidas = {}
  for par in tostring(opts.opt):gmatch("[^,]+") do
    local chave, valor = par:match("^%s*([%w_]+)%s*:%s*(.-)%s*$")
    if chave then
      stored[chave] = tonumber(valor) or valor
      pedidas[#pedidas + 1] = chave
    else
      print("OPCAO MAL FORMADA, esperava chave:valor e veio: " .. tostring(par))
      love.event.quit(2)
    end
  end
  local mod = makeMod(handle, stored)
  -- O chunk e compilado UMA vez e reexecutado por construcao. Antes isto
  -- reparseava 2800 linhas a cada malha, o que ninguem notava com vinte
  -- celulas e domina o custo quando o laboratorio constroi centenas para
  -- descobrir quais opcoes mexem na geometria. Reexecutar e o que importa:
  -- cada execucao devolve um mod novo, com estado proprio.
  MOD_CHUNK = MOD_CHUNK or assert(loadfile(MAIN_PATH))
  MOD_CHUNK(mod)
  LAB_SCHEMA = mod._schema or LAB_SCHEMA
  if #pedidas > 0 then
    local conhecidas = {}
    for _, row in ipairs(mod._schema or {}) do
      if row.key then conhecidas[row.key] = true end
    end
    for _, chave in ipairs(pedidas) do
      if not conhecidas[chave] then
        print("OPCAO DESCONHECIDA: " .. chave ..
          "  (o mod nao define essa chave; a medicao sairia com o padrao " ..
          "e voce nao notaria)")
        love.event.quit(2)
      end
    end
  end
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
  if opts.lab == "1" then return love.labsetup() end
  if opts.features ~= "" then return love.features() end
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
  -- ARMADILHA 12, achada por um agente que prototipou e conferiu, e que eu
  -- reproduzi: uma forma FUNDA transborda a propria celula e invade a
  -- vizinha, contaminando a medicao dela. `red.png` no CARVED vai a z = -13
  -- num sprite de 16 de largura, e no `cell` grande a projecao disso passa da
  -- borda. Medido: com `cell=220`, que e o DEFAULT, o SLAB media 73.4%
  -- sozinho e 70.7% num contact sheet ao lado do CARVED. Em 140, 100, 80 e
  -- 60 nao vazava, o que e pior do que vazar sempre: o defeito so aparecia no
  -- default, e sumia assim que alguem tentava reproduzir com celula menor.
  --
  -- O recorte fecha isso por construcao, para toda medicao e todo desenho,
  -- em vez de virar mais uma regra de uso que alguem precisa lembrar. Cada
  -- celula so pode pintar dentro dela mesma.
  local prevScissor = { love.graphics.getScissor() }
  love.graphics.setScissor(x, y, size, size)
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
  love.graphics.setScissor(unpack(prevScissor))
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

  -- ESTRUTURA TONAL, por classe de face.
  --
  -- O art% acima e provenance PURA: ele conta de onde a superficie veio, e o
  -- passe que o mede reaproveita o canal de shade para carregar a classe da
  -- face, entao ele e cego a iluminacao POR CONSTRUCAO. Nenhuma opcao de
  -- sombreamento pode move-lo, nem em principio. Isso deixou duas features
  -- desta branch sem regua nenhuma, julgadas so no olho.
  --
  -- Isto mede outra coisa: quanta ESTRUTURA existe na superficie desenhada.
  -- Uma tampa chapada tem um nivel de tom so e amplitude zero. Um domo em
  -- degraus tem tres. Nao decide se ficou bonito, e nao tenta: essa licao ja
  -- foi paga quando um redesenho por IA satisfez toda restricao numerica e
  -- entregou arte pior. Serve para dizer O QUE MUDOU e para pegar regressao.
  print("")
  print("estrutura tonal na superficie desenhada, por classe de face")
  print("  niveis  quantos tons distintos aparecem (chapado = 1)")
  print("  ampl    diferenca entre o tom mais claro e o mais escuro")
  print("  desvio  desvio medio em torno do tom medio da classe")
  -- `desvio` existe porque `niveis` e `ampl` NAO distinguem forcas.
  -- Medido por uma revisao adversarial: FRONT SHAPE em 0.12, 0.17 e 0.22
  -- reportava `niveis 7 ampl 0.596` nos TRES, enquanto 2382 de 43600 pixels
  -- do quadro realmente diferiam entre a primeira e a ultima. Ou seja, a
  -- regua dizia "igual" com 5% da tela mudada.
  --
  -- A causa e que contar baldes e um teste de PRESENCA: assim que a terceira
  -- faixa de tom aparece, a contagem satura, e subir a forca so afasta os
  -- tons uns dos outros sem criar balde novo. `ampl` tambem satura, porque o
  -- pixel mais claro e o mais escuro costumam ser os mesmos texels em toda
  -- forca. O desvio medio nao satura: ele cresce junto com a separacao.
  for r, row in ipairs(state.rows) do
    local y0 = (r - 1) * (cell + labelH) + labelH
    for c, yawDeg in ipairs(state.yaws) do
      local x0 = (c - 1) * cell
      local tons, lo, hi, soma, cont = {}, {}, {}, {}, {}
      local vals = {}
      for _, k in ipairs(KINDS) do
        tons[k] = {}; lo[k] = 2; hi[k] = -1; soma[k] = 0; cont[k] = 0
        vals[k] = {}
      end
      for y = 0, cell - 1 do
        for x = 0, cell - 1 do
          local kind = kindAt(img:getPixel(x0 + x, y0 + y))
          if kind then
            local sr, sg, sb = screen:getPixel(x0 + x, y0 + y)
            local lum = sr * 0.3 + sg * 0.6 + sb * 0.1
            -- quantiza em 64 baldes: o adversario mostrou que contar valores
            -- unicos de ponto flutuante sempre devolve "muitos", tanto para um
            -- degrade bonito quanto para ruido, entao nao discrimina nada.
            tons[kind][math.floor(lum * 64 + 0.5)] = true
            if lum < lo[kind] then lo[kind] = lum end
            if lum > hi[kind] then hi[kind] = lum end
            soma[kind] = soma[kind] + lum
            cont[kind] = cont[kind] + 1
            vals[kind][cont[kind]] = lum
          end
        end
      end
      for _, k in ipairs({ "front", "top" }) do
        local n = 0
        for _ in pairs(tons[k]) do n = n + 1 end
        if n > 0 then
          local media = soma[k] / cont[k]
          local desvio = 0
          for i = 1, cont[k] do desvio = desvio + math.abs(vals[k][i] - media) end
          desvio = desvio / cont[k]
          print(string.format(
            "  %-11s %-9s yaw %2d   %-6s niveis %2d   ampl %.3f   desvio %.4f",
            row.shape, row.pitchLabel, yawDeg, k, n, hi[k] - lo[k], desvio))
        end
      end
    end
  end
  colour:release()
  depth:release()
end

--------------------------------------------------------------------------
-- FEATURES  (features=<arquivo>)
--------------------------------------------------------------------------
-- As grandezas que o juiz enxerga. Elas saem da MALHA e nao de um quadro
-- renderizado, o que e uma escolha e nao uma economia: medir na malha e
-- deterministico, nao depende de camera nem de relogio, e roda em milissegundos
-- por variante, entao trinta escolhas viram sessenta variantes em segundos e
-- da para reajustar o modelo sempre que a lista de features mudar.
--
-- A lista comeca pelas grandezas que este projeto ja mediu e que ja
-- explicaram alguma coisa:
--
--   fracao de topo   a lei que matou quatro tentativas de profundidade
--                    variavel: topo nao carrega arte e esta camera olha para
--                    ele. Se a preferencia do Kim ignorar isto, a lei vale
--                    menos do que a gente pensa, e isso e resultado
--   fracao de arte   frente e verso sao as unicas faces que o artista
--                    desenhou (IS_ART); o resto e superficie inventada
--   quads            custo e complexidade da forma
--   profundidade     o quanto o corpo sai do plano do sprite
--   tons             FRONT SHAPE e TOP DOME nao mexem em vertice, so em
--                    shade, entao sem estatistica de shade eles seriam
--                    invisiveis para o modelo
--
-- Nao ha art% de PIXEL aqui, que e a metrica com que este projeto sempre
-- julgou. Ela precisa do render de proveniencia, que precisa de grade e de
-- leitura de tela. Fica para a segunda passada, e ate la o baseline do juiz e
-- "a melhor feature sozinha", que e um adversario mais honesto do que parece:
-- se o modelo ajustado nao ganha de UMA coluna, ele nao aprendeu nada.
local FEATURE_NOMES = {
  "quads", "frente", "verso", "lado", "topo", "baixo",
  "arte", "profundidade", "shade_media", "shade_desvio", "shade_niveis",
}

local function featuresDaMalha(mesh, kinds)
  local f = {}
  for _, n in ipairs(FEATURE_NOMES) do f[n] = 0 end
  if not (mesh and mesh.verts and #mesh.verts > 0) then return f end
  local quads = math.floor(#mesh.verts / 4)
  f.quads = quads
  local conta = {}
  for _, k in ipairs(kinds or {}) do conta[k] = (conta[k] or 0) + 1 end
  local function frac(k) return quads > 0 and (conta[k] or 0) / quads or 0 end
  f.frente, f.verso = frac("front"), frac("back")
  f.lado = frac("side") + frac("side_e") + frac("side_w")
  f.topo, f.baixo = frac("top"), frac("bottom")
  f.arte = f.frente + f.verso
  local minZ, maxZ = math.huge, -math.huge
  local soma, n, tons = 0, 0, {}
  for i = 1, #mesh.verts do
    local v = mesh.verts[i]
    if v[3] < minZ then minZ = v[3] end
    if v[3] > maxZ then maxZ = v[3] end
    soma, n = soma + v[6], n + 1
    tons[math.floor(v[6] * 100 + 0.5)] = true
  end
  f.profundidade = (maxZ > -math.huge) and (maxZ - minZ) or 0
  f.shade_media = n > 0 and soma / n or 0
  local var = 0
  for i = 1, #mesh.verts do
    local d = mesh.verts[i][6] - f.shade_media
    var = var + d * d
  end
  f.shade_desvio = n > 0 and math.sqrt(var / n) or 0
  local c = 0
  for _ in pairs(tons) do c = c + 1 end
  f.shade_niveis = c
  return f
end

function love.features()
  -- Saida em linha e nao em bloco. Sem isto, um run interrompido no meio
  -- entrega um arquivo truncado NO MEIO DE UMA LINHA, e um leitor cuidadoso
  -- ainda pode ler as linhas inteiras que sobraram como se fossem o resultado.
  -- Aconteceu: o trailer.sh faz `pkill -x love` e matou uma extracao que
  -- rodava em paralelo, e o que ficou no arquivo parecia uma medicao curta em
  -- vez de uma medicao interrompida.
  io.stdout:setvbuf("line")
  local entrada = assert(io.open(opts.features, "r"),
    "nao consegui abrir " .. opts.features)
  local cab = { "folha", "estado" }
  for _, n in ipairs(FEATURE_NOMES) do cab[#cab + 1] = n end
  print("#" .. table.concat(cab, "\t"))
  local linhas = 0
  for linha in entrada:lines() do
    local folha, estado = linha:match("^(%S+)\t(.*)$")
    if folha then
      local path = SPRITE_DIR .. folha .. ".png"
      local ok, data = pcall(loadImageData, path)
      if not ok then
        io.stderr:write("sem folha: " .. path .. "\n")
      else
        local sw, sh = data:getDimensions()
        local def = { image = path, frames = math.max(1, math.floor(sh / 16)) }
        local valores = {}
        for par in estado:gmatch("[^,]+") do
          local k, v = par:match("^%s*([%w_]+)%s*:%s*(.-)%s*$")
          if k then valores[k] = tonumber(v) or v end
        end
        opts.opt = estado
        local shape = valores.shape or "slab"
        local depth = tonumber(valores.depth) or 3
        -- Relogio congelado: a piscada mexe UV e mudaria a assinatura de shade
        -- conforme a hora em que este comando rodou. Feature tem que ser
        -- funcao do estado, nao do momento.
        local relogio = love.timer.getTime
        love.timer.getTime = function() return 0 end
        local mesh = buildGeometry(data, def, 0, shape, depth,
                                   valores.side_color or "body")
        love.timer.getTime = relogio
        local kinds
        if mesh then
          local role = (shape == "carved" or shape == "carved_plus") and 0 or 0
          kinds = classifyMesh(mesh, role)
        end
        local f = featuresDaMalha(mesh, kinds)
        local saida = { folha, estado }
        for _, n in ipairs(FEATURE_NOMES) do
          saida[#saida + 1] = string.format("%.6f", f[n])
        end
        print(table.concat(saida, "\t"))
        linhas = linhas + 1
      end
    end
  end
  entrada:close()
  io.stderr:write(string.format("features de %d variantes\n", linhas))
  -- SAIR DE VERDADE, e este e o motivo de tres linhas em vez de uma.
  --
  -- love.event.quit() sozinho nao basta: ele so agenda a saida, e o quadro
  -- seguinte ainda chama love.draw, que aqui explode em state.bg (nil, porque
  -- o modo features nunca monta a cena). Erro em love.draw abre a tela de erro
  -- do LOVE, que espera uma tecla PARA SEMPRE.
  --
  -- E o pior: isso passou despercebido porque o primeiro teste deste modo
  -- terminava em `| head`, e o head fechando o cano matava o processo com
  -- SIGPIPE. A ferramenta parecia sair sozinha. Quem chamou sem cano ficou
  -- pendurado. Ja e a segunda vez neste projeto que um processo que nao
  -- termina se disfarca de processo que terminou.
  love.draw = function() end
  love.update = function() love.event.quit() end
  love.event.quit()
end

--------------------------------------------------------------------------
-- LABORATORIO  (lab=1)
--------------------------------------------------------------------------
-- Um editor de personagem: uma folha grande no meio, todas as opcoes do mod
-- na lateral, e navegacao pelas 67 folhas do jogo. Serve a tres coisas ao
-- mesmo tempo:
--
--   1. ver uma opcao mudar na hora, em vez de esperar um contact sheet;
--   2. ver a opcao em QUEM NAO E O RED, que e onde as regressoes moram
--      (nurse tem tres frames, boulder tem um, snorlax e mais largo);
--   3. registrar ESCOLHA, que e a unica coisa que nenhum numero aqui produz.
--
-- O terceiro e o motivo real. Este projeto ja mediu que um redesenho por IA
-- satisfaz toda restricao numerica e entrega arte pior, entao o gerador nao
-- pode ser treinado contra as reguas que a gente tem. Falta juiz, e juiz
-- comeca com alguem escolhendo entre dois.

local FACINGS = {
  { nome = "FRENTE", pose = 0, anda = 3 },
  { nome = "COSTAS", pose = 1, anda = 4 },
  { nome = "LADO",   pose = 2, anda = 5 },
}

local lab = {
  folhas = {}, i = 1, facing = 1, andando = false, tocando = true,
  rung = 35, yaw = 0, sel = 1, valores = {}, opcoes = {},
  row = nil, erro = nil, sujo = true, t = 0, construcoes = 0,
  -- modo escolha
  ab = false, par = nil, rowA = nil, rowB = nil, escolhas = 0, pulos = 0,
}

-- Onde as escolhas ficam. Uma linha por escolha, chave=valor, para o ajuste
-- do juiz poder ser refeito do zero e auditado depois.
--
-- Deliberadamente NAO grava feature nenhuma aqui: as features se recalculam
-- a partir do estado gravado, pela propria regua, quando for a hora. Gravar
-- numero medido junto congelaria a lista de features na primeira versao, e a
-- lista de features e exatamente o que vai mudar quando o juiz empacar.
-- Declarado aqui porque love.labsetup, mais abaixo, precisa chamar isto e o
-- modo escolha e definido depois dele.
local labMontaPar

local function labGrava(linha)
  local caminho = love.filesystem.getSaveDirectory() .. "/" .. opts.labfile
  local f = io.open(caminho, "a")
  if not f then print("NAO CONSEGUI GRAVAR A ESCOLHA em " .. caminho); return false end
  f:write(linha .. "\n")
  f:close()
  return true
end

local function labEstadoTexto(v)
  local partes = {}
  for _, o in ipairs(LAB_SCHEMA or {}) do
    partes[#partes + 1] = o.key .. "=" .. tostring(v[o.key])
  end
  return table.concat(partes, " ")
end

local function labFolhas()
  local out = {}
  local p = io.popen("ls " .. SPRITE_DIR .. " 2>/dev/null")
  if p then
    for linha in p:lines() do
      local nome = linha:match("^(.+)%.png$")
      if nome then out[#out + 1] = nome end
    end
    p:close()
  end
  table.sort(out)
  return out
end

-- Constroi a malha do estado atual. Passa TODA opcao pela passagem generica
-- `opt=`, entao uma opcao nova aparece aqui sem nenhuma linha nova.
local function labMalha(nomeFolha, frame, valores)
  local path = SPRITE_DIR .. nomeFolha .. ".png"
  local ok, data = pcall(loadImageData, path)
  if not ok then return nil, "sem folha: " .. path end
  local sw, sh = data:getDimensions()
  local def = { image = path, frames = math.max(1, math.floor(sh / 16)) }
  if frame >= def.frames then frame = frame % def.frames end
  local pares = {}
  for _, o in ipairs(LAB_SCHEMA or {}) do
    if valores[o.key] ~= nil then
      pares[#pares + 1] = o.key .. ":" .. tostring(valores[o.key])
    end
  end
  opts.opt = table.concat(pares, ",")
  local shape = valores.shape or "slab"
  local depth = tonumber(valores.depth) or 3
  local mesh, why = buildGeometry(data, def, frame, shape, depth,
                                  valores.side_color or "body")
  return {
    sprite = nomeFolha, frame = frame, shape = shape, mesh = mesh, why = why,
    texture = nil, data = data,
    cellW = sw, cellH = sh / def.frames, frames = def.frames,
    role = (shape == "carved" or shape == "carved_plus") and (frame % 3) or 0,
  }
end

-- Assinatura de uma malha, para responder "esta opcao muda a GEOMETRIA?".
local function labAssinatura(m)
  if not m or not m.verts then return "sem malha" end
  local s = #m.verts
  for i = 1, #m.verts do
    local v = m.verts[i]
    s = s + v[1] * 7 + v[2] * 13 + v[3] * 17 + v[4] * 23 + v[5] * 29 + v[6] * 31
  end
  return string.format("%d:%.4f", #m.verts, s)
end

-- Quais opcoes este laboratorio consegue mostrar, MEDIDO e nao suposto.
--
-- BREATH, SWAY, MOTION LAG e FOOTFALL nao mexem em vertice: eles
-- pos-multiplicam a matriz que o host passa para Voxel3D.draw, e aqui nao
-- existe host de verdade nem matriz. Um controle que nao faz nada e pior que
-- controle ausente, porque a pessoa mexe, nao ve efeito e conclui que a
-- feature esta quebrada. Entao em vez de manter uma lista escrita na mao
-- (que apodrece com a proxima opcao nova), a gente CONSTROI cada nivel e
-- compara: se nenhum nivel muda a malha, a opcao e de jogo, nao daqui.
--
-- A primeira versao disto errou DUAS opcoes de uma vez, e as duas por comparar
-- num ponto so em vez de nos eixos onde o efeito vive. Os eixos, agora
-- explicitos, cada um por um mecanismo lido no mod:
--
--   FRAME. STEP WEIGHT so desloca z quando `andando` (main.lua:1407). Medido
--   so na pose parada, ele nao muda nada e parecia opcao de jogo. Entao a
--   varredura inclui uma pose de caminhada.
--
--   RELOGIO. A piscada fecha por 0,12 s num periodo entre 3 e 6 s, com fase
--   por folha (main.lua:408, 1085-1096). Tres instantes escolhidos a esmo caem
--   fora quase sempre. Passo de 0,1 s cobre qualquer janela de 0,12 s, entao a
--   varredura ACHA a piscada em vez de torcer para acerta-la. Este projeto ja
--   concluiu que a piscada nao funcionava quando funcionava, exatamente assim.
--
-- Sai cedo na primeira diferenca, entao o custo real e alto so para a opcao
-- que de fato nao mexe na malha, que e o que se quer provar com cuidado.
local LAB_CLOCK_PASSO = 0.1
local LAB_CLOCK_ATE = 6.0

local function labClassifica(base)
  local relogio = love.timer.getTime
  local geometrica, construcoes = {}, 0
  for _, o in ipairs(LAB_SCHEMA or {}) do
    local muda = false
    local t = 0
    while t <= LAB_CLOCK_ATE and not muda do
      love.timer.getTime = function() return t end
      for _, frame in ipairs({ 0, 3 }) do
        local vista = nil
        for _, nivel in ipairs(o.choices or {}) do
          local v = {}
          for k, val in pairs(base) do v[k] = val end
          v[o.key] = nivel[2]
          local r = labMalha(lab.folhas[lab.i] or "red", frame, v)
          construcoes = construcoes + 1
          local a = labAssinatura(r and r.mesh)
          if vista and a ~= vista then muda = true break end
          vista = a
        end
        if muda then break end
      end
      t = t + LAB_CLOCK_PASSO
    end
    geometrica[o.key] = muda
  end
  love.timer.getTime = relogio
  return geometrica, construcoes
end

local function labRebuild()
  local f = FACINGS[lab.facing]
  local frame = (lab.andando and lab.tocando) and f.anda or f.pose
  local row, erro = labMalha(lab.folhas[lab.i], frame, lab.valores)
  lab.erro = erro
  if row then
    row.pitch = math.rad(90 - lab.rung)
    -- Textura por FOLHA, nao por quadro. Enquanto toca, isto era um upload de
    -- imagem por quadro para reenviar bytes identicos.
    lab.texturas = lab.texturas or {}
    local tex = lab.texturas[row.sprite]
    if not tex then
      tex = love.graphics.newImage(row.data)
      tex:setFilter("nearest", "nearest")
      lab.texturas[row.sprite] = tex
    end
    row.texture = tex
    if row.mesh then row.kinds = classifyMesh(row.mesh, row.role) end
    lab.row = row
    lab.construcoes = lab.construcoes + 1
  end
  lab.sujo = false
end

-- Global de proposito: love.load e definido ACIMA desta secao, entao um local
-- daqui nao existiria como upvalue la. Mesmo motivo de love.labdraw/labkeys.
function love.labsetup()
  lab.folhas = labFolhas()
  if #lab.folhas == 0 then return fail("nenhuma folha em " .. SPRITE_DIR) end
  for i, n in ipairs(lab.folhas) do if n == opts.sprite then lab.i = i end end

  -- Uma construcao so para o mod se registrar e o schema existir.
  labMalha(lab.folhas[lab.i], 0, {})
  if not LAB_SCHEMA then return fail("o mod nao registrou schema de opcoes") end
  for _, o in ipairs(LAB_SCHEMA) do lab.valores[o.key] = o.default end

  local t0 = love.timer.getTime()
  local geometrica, construcoes = labClassifica(lab.valores)
  local custo = love.timer.getTime() - t0
  local aqui, la = {}, {}
  for _, o in ipairs(LAB_SCHEMA) do
    if geometrica[o.key] then
      lab.opcoes[#lab.opcoes + 1] = o
      aqui[#aqui + 1] = o.key
    else
      la[#la + 1] = o.key
    end
  end
  print("laboratorio: " .. #lab.opcoes .. " opcoes mexem na malha e aparecem aqui")
  print("  aqui:  " .. table.concat(aqui, ", "))
  print("  sem efeito na malha: " .. table.concat(la, ", "))
  print(string.format("  classificacao: %d construcoes em %.1f s, varrendo o " ..
    "relogio ate %.1f s de %.2f em %.2f e as poses 0 e 3",
    construcoes, custo, LAB_CLOCK_ATE, LAB_CLOCK_PASSO, LAB_CLOCK_PASSO))
  print("  folhas: " .. #lab.folhas)

  love.window.setMode(1280, 800, { depth = 24, vsync = 1 })
  love.window.setTitle("voxel characters - laboratorio")
  state.width, state.height = 1280, 800
  state.bg = { 0.10, 0.11, 0.13 }
  state.shader = love.graphics.newShader(SHADER)
  local pal = PALETTES[opts.palette] or PALETTES.obj
  for i = 1, 4 do state.shader:send("pal" .. (i - 1), pal[i]) end
  state.rows = {}
  math.randomseed(os.time())
  labRebuild()
  if opts.labab == "1" then
    lab.ab = true
    labMontaPar()
    if lab.par then
      print(string.format("modo escolha: %s, %s, %s contra %s",
        lab.par.folha, lab.par.opcao.key, lab.par.rotuloA, lab.par.rotuloB))
    else
      print("modo escolha: NENHUM PAR (nenhuma opcao com dois niveis)")
    end
  end
end

--------------------------------------------------------------------------
-- MODO ESCOLHA (tecla t)
--------------------------------------------------------------------------
-- Duas variantes lado a lado, uma tecla escolhe, e a escolha vira linha de
-- arquivo. E a unica coisa que este projeto nao consegue computar.
--
-- Tres decisoes que nao sao obvias:
--
--   PAR DIFERE EM UMA OPCAO SO. Se os dois lados diferem em varias, a
--   escolha nao atribui credito a nenhuma delas, e o registro nao serve para
--   ajustar nada. Comparacao de estados inteiros vem depois, quando houver
--   juiz para propor os estados.
--
--   A FOLHA SORTEIA JUNTO. Toda opcao deste mod foi julgada no red, e o que
--   agrada no red pode nao agradar na nurse ou no snorlax. Se a folha nao
--   variar, o juiz aprende o gosto do Kim PARA O RED.
--
--   PULAR E RESPOSTA. Forcar escolha entre duas coisas indistinguiveis
--   injeta ruido com cara de sinal. "Nao vejo diferenca" e informacao: diz
--   que a distancia entre os dois niveis esta abaixo do limiar de quem olha.
-- Nem toda diferenca esta sempre na tela, e um par montado num instante em
-- que os dois lados sao IDENTICOS nao coleta preferencia, coleta moeda.
--
-- Dois casos, os dois medidos e nao supostos:
--   BLINK so difere durante 0,12 s de cada periodo de 3 a 6 s.
--   STEP WEIGHT so difere na pose de caminhada (main.lua:1407).
--
-- Entao antes de mostrar um par, procura uma condicao (pose, instante) em que
-- os dois lados de fato diferem, e CONGELA ali. Congelar e melhor que animar
-- aqui: a pergunta e qual dos dois, e a resposta nao pode depender do quadro
-- em que a pessoa apertou a tecla.
--
-- Achar em vez de calcular e deliberado. Replicar a formula de fase da
-- piscada seria testar a implementacao contra ela mesma, e este harness ja
-- resolve isso assim em outro lugar (blinkscan).
local function labCondicao(folha, o, va, vb)
  local relogio = love.timer.getTime
  local achou, sempre = nil, true
  for _, frame in ipairs({ 0, 3 }) do
    for i = 0, 60 do
      local t = i * 0.1
      love.timer.getTime = function() return t end
      local ra = labMalha(folha, frame, va)
      local rb = labMalha(folha, frame, vb)
      local difere = labAssinatura(ra and ra.mesh) ~= labAssinatura(rb and rb.mesh)
      if difere and not achou then achou = { frame = frame, t = t } end
      if not difere then sempre = false end
      if achou and not sempre then
        love.timer.getTime = relogio
        return achou, false
      end
    end
  end
  love.timer.getTime = relogio
  return achou, sempre
end

local function labSorteiaPar()
  local candidatas = {}
  for _, o in ipairs(lab.opcoes) do
    if #(o.choices or {}) > 1 then candidatas[#candidatas + 1] = o end
  end
  if #candidatas == 0 then return nil end
  local o = candidatas[math.random(#candidatas)]
  local a = math.random(#o.choices)
  local b = a
  while b == a do b = math.random(#o.choices) end
  local folha = lab.folhas[math.random(#lab.folhas)]
  local base = {}
  for _, oo in ipairs(LAB_SCHEMA) do base[oo.key] = lab.valores[oo.key] end
  local va, vb = {}, {}
  for k, v in pairs(base) do va[k] = v; vb[k] = v end
  va[o.key] = o.choices[a][2]
  vb[o.key] = o.choices[b][2]
  local cond, sempre = labCondicao(folha, o, va, vb)
  if not cond then
    -- Os dois niveis produzem a mesma malha NESTA folha em toda condicao
    -- varrida. Perguntar seria pedir para escolher entre duas imagens iguais.
    return nil
  end
  return {
    opcao = o, folha = folha,
    rotuloA = o.choices[a][1], rotuloB = o.choices[b][1],
    valoresA = va, valoresB = vb,
    congela = (not sempre) and cond or nil,
  }
end

-- Sorteia ate cair um par que de fato mostra diferenca. Tenta um numero fixo
-- de vezes e desiste em voz alta: laco sem teto num sorteio que pode nunca
-- acertar e como uma ferramenta trava sem ninguem entender por que.
local function labSorteiaParValido()
  for _ = 1, 40 do
    local p = labSorteiaPar()
    if p then return p end
  end
  print("modo escolha: 40 sorteios sem par visivel; ver a lista de opcoes")
  return nil
end

-- Reconstroi as malhas do par ATUAL. Separado do sorteio de proposito: a
-- animacao reconstroi todo quadro e nao pode trocar o par debaixo de quem
-- esta decidindo.
local function labConstroiPar()
  if not lab.par then return end
  local f = FACINGS[lab.facing]
  local frame = lab.andando and f.anda or f.pose
  local relogio
  if lab.par.congela then
    frame = lab.par.congela.frame
    relogio = love.timer.getTime
    local t = lab.par.congela.t
    love.timer.getTime = function() return t end
  end
  local function monta(valores)
    local r = labMalha(lab.par.folha, frame, valores)
    if r then
      r.pitch = math.rad(90 - lab.rung)
      lab.texturas = lab.texturas or {}
      local tex = lab.texturas[r.sprite]
      if not tex then
        tex = love.graphics.newImage(r.data)
        tex:setFilter("nearest", "nearest")
        lab.texturas[r.sprite] = tex
      end
      r.texture = tex
      if r.mesh then r.kinds = classifyMesh(r.mesh, r.role) end
    end
    return r
  end
  lab.rowA = monta(lab.par.valoresA)
  lab.rowB = monta(lab.par.valoresB)
  lab.construcoes = lab.construcoes + 2
  if relogio then love.timer.getTime = relogio end
end

function labMontaPar()
  lab.par = labSorteiaParValido()
  labConstroiPar()
end

local function labEscolhe(lado)
  local p = lab.par
  if not p then return end
  labGrava(string.format(
    "t=%s folha=%s pose=%s rung=%d yaw=%d opcao=%s a=%s b=%s escolha=%s | A: %s | B: %s",
    os.date("%Y-%m-%dT%H:%M:%S"), p.folha, FACINGS[lab.facing].nome,
    lab.rung, lab.yaw, p.opcao.key, tostring(p.valoresA[p.opcao.key]),
    tostring(p.valoresB[p.opcao.key]), lado,
    labEstadoTexto(p.valoresA), labEstadoTexto(p.valoresB)))
  if lado == "pulo" then lab.pulos = lab.pulos + 1
  else lab.escolhas = lab.escolhas + 1 end
  labMontaPar()
end

local function labCicla(o, dir)
  local idx = 1
  for i, nivel in ipairs(o.choices) do
    if nivel[2] == lab.valores[o.key] then idx = i end
  end
  idx = idx + dir
  if idx < 1 then idx = #o.choices end
  if idx > #o.choices then idx = 1 end
  lab.valores[o.key] = o.choices[idx][2]
  lab.sujo = true
end

local function labRotulo(o)
  for _, nivel in ipairs(o.choices) do
    if nivel[2] == lab.valores[o.key] then return nivel[1] end
  end
  return tostring(lab.valores[o.key])
end

local LAB_RUNGS = { 15, 35, 50, 75 }

function love.labkeys(key)
  -- Sob labshot a corrida e automatica e tem que ser reprodutivel. Uma tecla
  -- solta chegando na janela ja mudou o resultado uma vez: a corrida saiu com
  -- duas construcoes em vez de duzentas porque alguma coisa entregou `space`,
  -- e eu quase li isso como a reconstrucao estar lenta.
  if opts.labshot ~= "" then return end
  local n = #lab.folhas
  if key == "escape" then return love.event.quit() end

  if key == "t" then
    lab.ab = not lab.ab
    if lab.ab then labMontaPar() end
    return
  end
  if lab.ab then
    if key == "left" then return labEscolhe("A") end
    if key == "right" then return labEscolhe("B") end
    if key == "space" then return labEscolhe("pulo") end
    if key == "f" then
      lab.facing = lab.facing % #FACINGS + 1; return labMontaPar()
    end
    if key:match("^[1-4]$") then
      lab.rung = LAB_RUNGS[tonumber(key)]; return labMontaPar()
    end
    if key == "q" then lab.yaw = (lab.yaw - 15) % 360 end
    if key == "e" then lab.yaw = (lab.yaw + 15) % 360 end
    return
  end

  if key == "right" then lab.i = lab.i % n + 1; lab.sujo = true
  elseif key == "left" then lab.i = (lab.i - 2) % n + 1; lab.sujo = true
  elseif key == "down" then lab.sel = lab.sel % #lab.opcoes + 1
  elseif key == "up" then lab.sel = (lab.sel - 2) % #lab.opcoes + 1
  elseif key == "d" or key == "]" then labCicla(lab.opcoes[lab.sel], 1)
  elseif key == "a" or key == "[" then labCicla(lab.opcoes[lab.sel], -1)
  elseif key == "f" then
    lab.facing = lab.facing % #FACINGS + 1; lab.sujo = true
  elseif key == "space" then lab.tocando = not lab.tocando; lab.sujo = true
  elseif key == "q" then lab.yaw = (lab.yaw - 15) % 360
  elseif key == "e" then lab.yaw = (lab.yaw + 15) % 360
  elseif key == "r" then
    for _, o in ipairs(LAB_SCHEMA) do lab.valores[o.key] = o.default end
    lab.sujo = true
  elseif key:match("^[1-4]$") then
    lab.rung = LAB_RUNGS[tonumber(key)]; lab.sujo = true
  elseif key == "s" then
    local nome = string.format("lab_%s_%s.png", lab.row and lab.row.sprite or "x",
      os.date("%H%M%S"))
    love.graphics.captureScreenshot(function(img)
      img:encode("png", nome)
      print("FOTO " .. love.filesystem.getSaveDirectory() .. "/" .. nome)
    end)
  end
end

local function labTexto(x, y, s, cor)
  love.graphics.setColor(cor or { 1, 1, 1, 1 })
  love.graphics.print(s, x, y)
end

local function labDrawAB()
  local S, GY = 520, 130
  local AX, BX = 140, 680
  love.graphics.setDepthMode("always", false)
  love.graphics.setShader()
  for _, x in ipairs({ AX, BX }) do
    love.graphics.setColor(0.16, 0.17, 0.20, 1)
    love.graphics.rectangle("fill", x, GY, S, S)
  end
  for _, par in ipairs({ { AX, lab.rowA }, { BX, lab.rowB } }) do
    if par[2] and par[2].mesh then
      love.graphics.setDepthMode("less", true)
      love.graphics.setShader(state.shader)
      love.graphics.setColor(1, 1, 1, 1)
      drawCell(par[2], math.rad(lab.yaw), par[1], GY, S)
      love.graphics.setShader()
      love.graphics.setDepthMode("always", false)
    end
  end

  labTexto(AX, 26, "QUAL DOS DOIS?", { 0.9, 0.92, 0.95, 1 })
  labTexto(AX, 48,
    "seta esquerda escolhe A, seta direita escolhe B, espaco = nao vejo diferenca",
    { 0.55, 0.60, 0.70, 1 })
  local p = lab.par
  if p then
    labTexto(AX, 72, string.format(
      "%s, %s, rung %d, e o resto esta igual dos dois lados",
      p.folha, FACINGS[lab.facing].nome, lab.rung), { 0.5, 0.54, 0.60, 1 })
    labTexto(AX, GY - 24, "A", { 1, 1, 1, 1 })
    labTexto(BX, GY - 24, "B", { 1, 1, 1, 1 })
    labTexto(AX + 22, GY - 24, p.opcao.label .. "  " .. p.rotuloA,
      { 1, 0.9, 0.55, 1 })
    labTexto(BX + 22, GY - 24, p.opcao.label .. "  " .. p.rotuloB,
      { 1, 0.9, 0.55, 1 })
    if p.congela then
      labTexto(AX + 400, 72,
        "congelado no instante e na pose em que os dois diferem",
        { 0.55, 0.5, 0.35, 1 })
    end
  end
  labTexto(AX, GY + S + 24, string.format(
    "%d escolhas, %d pulos", lab.escolhas, lab.pulos), { 0.7, 0.73, 0.78, 1 })
  labTexto(AX, GY + S + 46,
    "f vira o personagem, 1-4 troca a camera, q/e gira, t volta ao editor",
    { 0.45, 0.48, 0.53, 1 })
end

function love.labdraw()
  love.graphics.clear(state.bg[1], state.bg[2], state.bg[3], 1, true, true)
  if lab.ab then return labDrawAB() end

  local VX, VY, VS = 330, 70, 620
  love.graphics.setDepthMode("always", false)
  love.graphics.setShader()
  love.graphics.setColor(0.16, 0.17, 0.20, 1)
  love.graphics.rectangle("fill", VX, VY, VS, VS)

  if lab.row and lab.row.mesh then
    love.graphics.setDepthMode("less", true)
    love.graphics.setShader(state.shader)
    love.graphics.setColor(1, 1, 1, 1)
    drawCell(lab.row, math.rad(lab.yaw), VX, VY, VS)
    love.graphics.setShader()
    love.graphics.setDepthMode("always", false)
  end

  -- coluna das opcoes
  labTexto(20, 20, "OPCOES", { 0.55, 0.60, 0.70, 1 })
  local y = 46
  for i, o in ipairs(lab.opcoes) do
    local sel = (i == lab.sel)
    if sel then
      love.graphics.setColor(0.20, 0.34, 0.52, 1)
      love.graphics.rectangle("fill", 12, y - 3, 296, 20)
    end
    labTexto(20, y, o.label, sel and { 1, 1, 1, 1 } or { 0.72, 0.75, 0.80, 1 })
    local r = labRotulo(o)
    love.graphics.setColor(sel and 1 or 0.85, sel and 0.92 or 0.85,
                           sel and 0.6 or 0.85, 1)
    love.graphics.print(r, 300 - love.graphics.getFont():getWidth(r), y)
    y = y + 21
  end

  y = y + 14
  labTexto(20, y, "NAO APARECEM AQUI", { 0.55, 0.60, 0.70, 1 }); y = y + 20
  labTexto(20, y, "respiracao, balanco, inercia e", { 0.5, 0.52, 0.56, 1 }); y = y + 16
  labTexto(20, y, "pisada mexem na MATRIZ, nao na", { 0.5, 0.52, 0.56, 1 }); y = y + 16
  labTexto(20, y, "malha. So no jogo: clip.sh", { 0.5, 0.52, 0.56, 1 })

  -- cabecalho do personagem
  local r = lab.row
  if r then
    labTexto(VX, 28, string.format("%s", r.sprite:upper()), { 1, 1, 1, 1 })
    local sub = string.format("%d de %d    %s    frame %d de %d    rung %d    yaw %d",
      lab.i, #lab.folhas, FACINGS[lab.facing].nome, r.frame, r.frames,
      lab.rung, lab.yaw)
    labTexto(VX, 46, sub, { 0.6, 0.64, 0.70, 1 })
    if r.mesh then
      local q = math.floor(#r.mesh.verts / 4)
      local topo = 0
      for _, k in ipairs(r.kinds or {}) do if k == "top" then topo = topo + 1 end end
      labTexto(VX + VS - 210, 28, string.format("%d quads, %d de topo", q, topo),
        { 0.55, 0.60, 0.70, 1 })
    elseif r.why then
      labTexto(VX + VS - 210, 28, "sem malha: " .. tostring(r.why), { 1, 0.6, 0.4, 1 })
    end
  end
  if lab.erro then labTexto(VX, VY + VS + 8, lab.erro, { 1, 0.5, 0.4, 1 }) end

  -- vizinhanca na lista de folhas, para nao navegar as cegas
  labTexto(980, 20, "PERSONAGENS", { 0.55, 0.60, 0.70, 1 })
  y = 46
  for d = -8, 8 do
    local j = (lab.i - 1 + d) % #lab.folhas + 1
    local sel = (d == 0)
    labTexto(980, y, lab.folhas[j],
      sel and { 1, 0.9, 0.55, 1 } or { 0.45, 0.48, 0.53, 1 })
    y = y + 17
  end

  labTexto(20, 760,
    "setas: <- -> personagem, cima/baixo opcao   a/d muda valor   f vira   " ..
    "espaco anda   q/e gira   1-4 camera   r reseta   s foto   esc sai",
    { 0.45, 0.48, 0.53, 1 })
  labTexto(1150, 780, string.format("%d fps", love.timer.getFPS()),
    { 0.35, 0.38, 0.43, 1 })
end

function love.draw()
  if opts.lab == "1" then return love.labdraw() end
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

function love.update(dt)
  if opts.lab == "1" then
    -- O passo alterna pose e caminhada. A piscada e uma janela curta com fase
    -- por folha, e ela vive na UV da malha, entao so aparece se a malha for
    -- reconstruida com o relogio andando: por isso reconstroi por quadro
    -- enquanto toca, e so quando muda alguma coisa enquanto parado.
    lab.t = lab.t + (dt or 0)
    if lab.tocando then lab.andando = (lab.t % 0.5) < 0.25 end
    if lab.ab then
      -- Os dois lados reconstroem no MESMO quadro, com o mesmo relogio: se um
      -- piscasse e o outro nao, a escolha seria sobre a piscada e nao sobre a
      -- opcao que o par diz estar comparando.
      if lab.tocando or lab.sujo then labConstroiPar() end
      lab.sujo = false
    elseif lab.tocando or lab.sujo then
      labRebuild()
    end
    if opts.labshot ~= "" then
      lab.quadros = (lab.quadros or 0) + 1
      if lab.quadros == 200 then
        love.graphics.captureScreenshot(function(img)
          img:encode("png", opts.labshot)
          print("LAB FOTO " .. love.filesystem.getSaveDirectory() .. "/" ..
                opts.labshot)
        end)
      elseif lab.quadros == 202 and opts.labpick ~= "" then
        -- Prova o caminho da gravacao inteiro, do par ate a linha no arquivo.
        labEscolhe(opts.labpick)
        print(string.format("escolha simulada gravada: %d escolhas, %d pulos",
          lab.escolhas, lab.pulos))
      elseif lab.quadros > 204 then
        print(string.format(
          "laboratorio ok: %d construcoes em %d quadros, %d fps, %d folhas, %d opcoes",
          lab.construcoes, lab.quadros, love.timer.getFPS(), #lab.folhas,
          #lab.opcoes))
        love.event.quit()
      end
    end
    return
  end
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
  if opts.lab == "1" then return love.labkeys(key) end
  if key == "escape" then love.event.quit() end
end
