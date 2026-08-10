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

-- Sibling modules, split out of this file (roadmap item 19): LOVE loads
-- tools/render/ as the game, so require() finds these with no configuration.
-- Lab and Features are wired up with the harness's shared state further
-- down, once that state (drawCell, buildGeometry, ...) exists to hand over.
local AO = require("ao_proto")
local Lab = require("lab")
local Features = require("features")

-- ERRO VAI PARA O STDOUT E MATA O PROCESSO, em vez de abrir janela e esperar.
--
-- Por padrao o LOVE trata erro abrindo uma tela azul com a mensagem e ESPERANDO
-- TECLA. De dentro de um script isso e indistinguivel de trabalho pesado: a
-- ferramenta so morre no timeout, com log vazio, e a causa fica escrita numa
-- janela que ninguem esta olhando. Aconteceu tres vezes numa sessao.
--
-- Tentei antes resolver FOTOGRAFANDO a tela para ler a mensagem. Foi pior: numa
-- maquina de trabalho a foto pega o que estiver na frente, e pegou conversa
-- pessoal duas vezes. As imagens foram apagadas e a ideia foi abandonada. A
-- mensagem tem que sair por onde o script ja le, que e o stdout.
function love.errorhandler(msg)
  msg = tostring(msg)
  io.stdout:write("ERRO DE LOVE: " .. msg .. "\n")
  io.stdout:write(debug.traceback("", 2) .. "\n")
  io.stdout:flush()
  os.exit(1)
end
love.errhand = love.errorhandler   -- LOVE 0.x/11.x usam nomes diferentes

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
  -- `labpares=<arquivo>` faz o laboratorio oferecer os pares que o juiz pediu,
  -- em vez de sortear. Ver labParDoArquivo.
  labpares = "",
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
  if tonumber(opts.aostrength) then AO.setAoStrength(tonumber(opts.aostrength)) end
  -- Congela o relogio antes de qualquer malha ser construida. O piscar e uma
  -- janela de 0,12 s num periodo com fase por folha; em vez de replicar a
  -- formula, que seria testar a implementacao contra ela mesma, o gate
  -- renderiza uma tira de instantes e olha qual fecha o olho.
  if tonumber(opts.blinktime) then
    local t = tonumber(opts.blinktime)
    love.timer.getTime = function() return t end
  end
  AO.setRecessOverride(tonumber(opts.recess))
  AO.setOutlineFront(opts.outline == "front")
  if opts.depthmap ~= "" then
    local chunk = assert(loadfile(opts.depthmap), "depthmap ilegivel")
    AO.setDepthMap(chunk())
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
          mesh, reliefSolid = AO.sculptMesh(data, def.frames, frame, "naive")
        elseif shape == "sculptc" then
          mesh, reliefSolid = AO.sculptMesh(data, def.frames, frame, "contour")
        else
          mesh, why = buildGeometry(data, def, frame, shape, depth,
                                    opts.side_color)
        end
        local sheetW, sheetH = data:getDimensions()
        local occ = reliefSolid or ((shape == "slab")
          and AO.slabOccupancy(data, def.frames, frame, sheetW,
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
      local f = AO.quadAO(row.mesh.verts, i, row.occ)
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

-- Wire up the Lab and Features modules with the state and helpers they need,
-- now that all of it exists: drawCell just above is the last piece either
-- one reads. LAB_SCHEMA is exposed as a getter rather than a value because
-- buildGeometry keeps reassigning it as the mod re-registers per build.
local ctx = {
  opts = opts,
  state = state,
  SPRITE_DIR = SPRITE_DIR,
  SHADER = SHADER,
  PALETTES = PALETTES,
  loadImageData = loadImageData,
  buildGeometry = buildGeometry,
  classifyMesh = classifyMesh,
  drawCell = drawCell,
  fail = fail,
  getLabSchema = function() return LAB_SCHEMA end,
}
Lab.init(ctx)
Features.init(ctx)

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
  if opts.lab == "1" then return love.labupdate(dt) end
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
