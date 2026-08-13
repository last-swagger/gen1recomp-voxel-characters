-- THE SAME CHARACTER, DRAWN FROM TWO SHEETS, HAS TO BE THE SAME PICTURE.
--
--   luajit mods/voxel_characters/tools/hd_equivalence.lua
--
-- From the repo root. Plain LuaJIT: no LOVE, no display, no PNG decoder, no
-- sprite on disk. It builds its own art in memory, twice.
--
-- WHY THIS GATE EXISTS. HD SPRITE feeds the builders a 64 px cell instead of a
-- 16 px one and `escalaParaTile` divides every vertex by four on the way out.
-- Everything expressed as a FRACTION of the cell survives that untouched;
-- everything expressed in SHEET PIXELS does not, and silently does a quarter of
-- its job instead of failing. Five such constants were found in one audit
-- (GROUND SHADE's rise, STEP WEIGHT's shear, the anchors' cell height, the
-- authored region rows, and the saved blink rows), on top of the four that had
-- already been found one at a time by people looking at a screen. There is no
-- reason to think a sixth cannot be written tomorrow, and no eye is going to
-- catch "a quarter as much contact shade" in a moving game.
--
-- THE INVARIANT, stated so it can be argued with: a character built from 16 px
-- art and the same character built from an EXACT nearest-neighbour enlargement
-- of that art must paint the same picture. The enlargement adds no information,
-- so any difference in the result is the mod reacting to resolution, and a mod
-- that reacts to resolution has a constant in the wrong unit.
--
-- HOW "the same picture" IS MEASURED. Both meshes are sampled on ONE common
-- world lattice. For every lattice ray, in each of the three axis directions,
-- the gate records the ordered list of surfaces it pierces, and for each hit:
--
--   the plane position       where the surface actually is;
--   the ORIGINAL sheet pixel the UV lands in, never the UV itself;
--   the interpolated shade   at that exact point, not the quad's constant;
--   the band                 the surface was sorted into for PART LAG.
--
-- The UV is compared as a SOURCE PIXEL and not as a number on purpose.
-- `RUN_UV_INSET` is a fraction of a TEXEL and correctly stays one, so the
-- enlarged sheet insets by a quarter as much in source coordinates. That is the
-- inset doing its job at both resolutions, and comparing raw UVs would call it
-- a defect.
--
-- Every quad is treated as a PARALLELOGRAM rather than a rectangle. STEP WEIGHT
-- shears one surface in Z as a function of height, and a gate that assumed
-- axis-aligned rectangles would either miss it or invent differences.
--
-- WHAT IS DELIBERATELY HELD OFF, and would be wrong to "fix":
--
--   FRONT SHAPE and TOP DOME are resolution-ADAPTIVE by design. Both normalise
--   the shade step against the run's OWN width, so a 4 pixel run gets 4 steps
--   and its enlargement gets 16. That is a genuinely different and better
--   picture, not a defect, so both are held OFF in every configuration here.
--   `emitFrontRun`'s `lx2 - lx < 2` guard is the same story: a run too short to
--   have a middle at 16 px has one at 64 px.
--
--   The `center` and `hand` anchors are not resolution-invariant and no scale
--   factor makes them so. Both are UNWEIGHTED means over vertices, and an
--   enlarged sheet has sixteen times as many top-face vertices per source pixel
--   while merged front runs and side runs still contribute two. The mean moves
--   because the weights moved, not because the body did. Only the extremes and
--   the bands are asserted.
--
--   `head` and `feet` DO carry x and z here, and that is only sound because
--   this fixture's topmost and bottommost rows are each a single run: every
--   family of vertices on such a row means to the same point, the run's centre,
--   so the mean survives the reweighting. On art whose feet are two separate
--   runs it would not, which is why the fixture is built the way it is and why
--   this note is here rather than in a commit message.
--
-- `escalaParaTile` assumes a SQUARE cell. That holds today (all 67 ROM sheets
-- are 16 wide and hd/red.png is 64x384) and this gate does not test otherwise.
--
-- HOW THE HD SHEET GETS IN. Through the same door `hdDataFor` uses: the gate
-- answers `love.filesystem.getInfo` for `hd/red.png` and hands back its own
-- ImageData from `love.image.newImageData`. The offline LOVE stub's
-- `newImageData` always returns a fixed 8x8, so there is no other way to give
-- the mod a real enlarged sheet without a PNG decoder, and going through the
-- mod's own door means the gate exercises the real HD path rather than a
-- parallel one built for it.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local MOD = "mods/voxel_characters"
local MAIN = os.getenv("VOXEL_CHARS_MAIN") or (MOD .. "/main.lua")

-- The fixture is called `red` so it inherits the two tables the mod keys by
-- sheet name and that a synthetic name would silently skip: `EYE_MARKS.red`
-- and `EYE_SIDE_MARKS.red` (which is what makes BLINK reachable at all), and
-- `authored/sheets/red.lua`'s measured region bounds. The PIXELS below are not
-- Ash's; they only have to put an eye-toned texel under each of those marks.
local BASE = "red"
local IMAGE = "red.png"
local HD_PATH = MOD .. "/hd/" .. BASE .. ".png"
local K = 4          -- the enlargement, matching the real hd/red.png (64x384)
local CELL = 16
local FRAMES = 6

-- ---------------------------------------------------------------- the art
--
-- Sixteen rows per frame, six frames down a 16x96 sheet, the same layout the
-- ROM's own sheets use. `#` is the outline tone, which is also the eye tone
-- because that is what the eye is in Gen 1 art and because `blinkBodyTexel`
-- only searches outward from a texel the mask calls OUTLINE.
--
-- TWO PROPERTIES OF THIS SHAPE ARE LOAD-BEARING and the rest is arbitrary:
-- the topmost and bottommost occupied rows are each a SINGLE run (see the
-- note on the head and feet anchors above), and the outline is one pixel
-- thick everywhere, so its enlargement is four, which is the case that
-- `BODY_SEARCH_LIMIT` exists for.
local PARADO = {
  "................",
  "....########....",
  "...#oooooooo#...",
  "...#o++++++o#...",
  "...#o++++++o#...",
  "...#o++++++o#...",
  "...#o++++++o#...",
  "...#++++++++#...",
  "...#++++++++#...",
  "..#oooooooooo#..",
  "..#o++++++++o#..",
  "..#oooooooooo#..",
  "...####..####...",
  "...#oo#..#oo#...",
  "...#oo####oo#...",
  "...##########...",
}

-- Row 7 is the face, and it is the only row that differs between the three
-- poses: front carries both eye marks, the profile carries the side one, and
-- the back carries none, which is exactly why the mod refuses to blink a back.
local ROSTO = {
  [0] = "...#+##++#++#...",   -- front:  marks at x=6 and x=9, plus x=5
  [1] = "...#++++++++#...",   -- back:   no face
  [2] = "...#+#++++++#...",   -- side:   mark at x=5
}

local TONS = {
  ["#"] = 0.06,   -- outline, the darkest tone: this is what `outlineLuma` finds
  ["o"] = 0.45,
  ["+"] = 0.85,
}

-- The walking pose is the standing pose ONE ROW LOWER, which is the real bob
-- the sheets have (authored/sheets/red.lua records it as `bob = 1`) and the
-- displacement `poseOffset` exists to measure. Without it the scan window would
-- never be exercised and its HD scaling would be untested.
local function quadroPixels(frame)
  local pose = frame % 3
  local andando = frame >= 3
  local linhas = {}
  for ly = 0, CELL - 1 do
    local origem = andando and (ly - 1) or ly
    local texto
    if origem < 0 or origem >= CELL then
      texto = string.rep(".", CELL)
    elseif origem == 7 then
      texto = ROSTO[pose]
    else
      texto = PARADO[origem + 1]
    end
    linhas[ly] = texto
  end
  return linhas
end

-- The two sheets, as flat pixel tables the ImageData shim reads. The HD one is
-- an EXACT nearest-neighbour enlargement built from the same rows: one source
-- pixel becomes a K by K block of the identical colour, which adds no
-- information and is the whole basis of the invariant.
local function montaFolhas()
  local rom, hd = {}, {}
  local romW, romH = CELL, CELL * FRAMES
  local hdW, hdH = CELL * K, CELL * FRAMES * K
  for frame = 0, FRAMES - 1 do
    local linhas = quadroPixels(frame)
    for ly = 0, CELL - 1 do
      local texto = linhas[ly]
      for lx = 0, CELL - 1 do
        local ch = texto:sub(lx + 1, lx + 1)
        local tom = TONS[ch]
        local y = frame * CELL + ly
        rom[y * romW + lx] = tom and { tom, tom, tom, 1 } or nil
        if tom then
          for j = 0, K - 1 do
            for i = 0, K - 1 do
              local hy = y * K + j
              hd[hy * hdW + lx * K + i] = { tom, tom, tom, 1 }
            end
          end
        end
      end
    end
  end
  return { pixels = rom, w = romW, h = romH },
         { pixels = hd, w = hdW, h = hdH }
end

local FOLHA_ROM, FOLHA_HD = montaFolhas()

local function imageData(folha)
  return {
    getDimensions = function() return folha.w, folha.h end,
    getPixel = function(_, x, y)
      local p = folha.pixels[y * folha.w + x]
      if not p then return 0, 0, 0, 0 end
      return p[1], p[2], p[3], p[4]
    end,
  }
end

-- ------------------------------------------------------- the mod, loaded
--
-- A trimmed copy of the offline suite's host and mod shims. Trimmed rather
-- than shared because tests/voxel_chars_test.lua keeps them local and running
-- the whole suite to borrow two tables would cost more than these forty lines.
local function fakeMesh(verts, map)
  return {
    verts = verts,
    map = map,
    setVertex = function(self, index, row, ...)
      if type(row) == "table" then
        self.verts[index] = { row[1], row[2], row[3], row[4], row[5], row[6] }
      else
        self.verts[index] = { row, ... }
      end
    end,
    setVertexMap = function(self, m) self.map = m end,
    setTexture = function(self, tex) self.texture = tex end,
    setDrawRange = function() end,
    release = function() end,
  }
end

local function hostHandle(dados)
  local modules = {}
  local V = {}
  local function original(def, frame)
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
          return fakeMesh(verts, map)
        end,
      }
    elseif name == "ImageCache" then
      modules[name] = { get = function() return dados end }
    elseif name == "SpriteBillboards" then
      modules[name] = { mesh = original, shadowQuad = original }
    elseif name == "VoxelState" then
      -- PITCH ZERO ON PURPOSE. `leanCorrection` returns pi/2 minus this, so
      -- pi/2 makes the correction exactly 0 and `p()` stops mixing y into z.
      -- The comparison is about the mod's own arithmetic, and a rotation
      -- shared by both sides would only add floating point noise to it.
      modules[name] = { angle = math.pi / 2 }
    elseif name == "VoxelScene" then
      modules[name] = {}
    elseif name == "FirstPerson" then
      modules[name] = { cardBlend = function() return 0 end }
    else
      error("unexpected module " .. tostring(name))
    end
    return modules[name]
  end
  return { id = "DRAMATIC_SHAPE", version = "1.7.0", exports = { lib = V } },
         modules
end

local function fakeMod(handle, stored)
  local schema
  local mod = {
    id = "voxel_characters",
    version = "1.0.0",
    path = MOD,
    options = {},
    hooks = {},
    events = {},
    log = { info = function() end, warn = function() end,
            error = function() end },
  }
  function mod.options:define(s) schema = s end
  function mod.options:get(key)
    if stored and stored[key] ~= nil then return stored[key] end
    for _, row in ipairs(schema or {}) do
      if row.key == key then return row.default end
    end
  end
  function mod.hooks:wrap() end
  function mod.events:on() end
  function mod.find(id)
    if id == handle.id then return handle end
  end
  return mod
end

-- EVERY OPTION PINNED, none inherited. A gate that lets a shipped default
-- through is a gate that changes meaning the day somebody changes the default,
-- which has already happened once on this branch (39 geometry checks went red
-- in one afternoon for that reason). FRONT SHAPE and TOP DOME are off here for
-- the reason argued in the header, not for convenience.
local BASE_OPCOES = {
  depth = 3, side_color = "outline", shape = "slab", ground_shade = "off",
  blink = "off", top_edge = "off", front_shape = "off", top_dome = "off",
  step_weight = "off", authored_regions = "off", grid_chars = "off",
  breath = "off", sway = "off", lag = "off", footfall = "off",
  attention = "off", part_lag = "off", first_person = "card", demo_fx = "off",
}

local function opcoesCom(extra, hd)
  local o = {}
  for k, v in pairs(BASE_OPCOES) do o[k] = v end
  for k, v in pairs(extra or {}) do o[k] = v end
  o.hd_sprite = hd and "on" or "off"
  return o
end

-- Loads a FRESH copy of main.lua. Fresh because every cache the mod keeps
-- (masks, meshes, hd data, pose offsets) is a chunk local, so two option sets
-- in one load would read each other's leftovers.
-- THE DOOR STAYS OPEN FOR THE WHOLE RUN, not only across the load. `hdDataFor`
-- is called lazily, from inside `maskFor`, which does not run until the first
-- mesh is asked for. Restoring the stubs at the end of the load left the mod
-- looking for `hd/red.png` through the untouched LOVE stub, finding nothing,
-- and quietly building the ROM mesh twice: the gate then agreed with itself.
local DADOS_ROM = imageData(FOLHA_ROM)
local DADOS_HD = imageData(FOLHA_HD)
do
  local fsAntes = love.filesystem.getInfo
  local imgAntes = love.image.newImageData
  love.filesystem.getInfo = function(caminho, ...)
    -- ONLY the HD sheet. `authoredRegions` reads through this same call and
    -- must be left to fall through to its plain `io.open` path, which is the
    -- one that actually resolves from the repo root.
    if caminho == HD_PATH then return { type = "file" } end
    return fsAntes(caminho, ...)
  end
  love.image.newImageData = function(a, ...)
    if a == HD_PATH then return DADOS_HD end
    return imgAntes(a, ...)
  end
end

local function carrega(opcoes, hd)
  local handle, modules = hostHandle(DADOS_ROM)
  local mod = fakeMod(handle, opcoes)
  package.loaded["src.render.Assets"] = nil
  package.loaded["src.mods.Semver"] = nil
  local ok, err = pcall(function()
    local chunk = assert(loadfile(MAIN))
    chunk(mod)
  end)
  if not ok then error(err) end
  if modules.SpriteBillboards.mesh == nil then
    error("the mod did not patch SpriteBillboards.mesh")
  end
  return mod, modules
end

local DEF = { image = IMAGE, frames = FRAMES }

-- ------------------------------------------------------------- sampling
--
-- R samples per WORLD unit along each in-plane axis. A world unit is one source
-- pixel at either resolution, because the enlarged mesh has already been scaled
-- back onto the same tile. The half-offsets keep every sample away from a quad
-- edge: source quads meet at integers and enlarged ones at quarters, and
-- (i + 0.5)/4 is never either.
local R = 4

local function eixoDominante(nx, ny, nz)
  local ax, ay, az = math.abs(nx), math.abs(ny), math.abs(nz)
  if ax >= ay and ax >= az then return 1 end
  if ay >= az then return 2 end
  return 3
end

-- The two in-plane axes for each dominant axis, in a fixed order so the two
-- meshes are always projected the same way.
local NO_PLANO = { [1] = { 2, 3 }, [2] = { 1, 3 }, [3] = { 1, 2 } }

-- Which band a quad ended up in, or 0 when the builder produced no bands
-- (CARVED does not band its mesh). `faixas` is in VERTEX indices, 1-based,
-- which is what mesh:setDrawRange takes.
local function bandaDoQuad(faixas, q)
  if not faixas then return 0 end
  local primeiroVert = q * 4 + 1
  for i, faixa in ipairs(faixas) do
    if primeiroVert >= faixa.primeiro
       and primeiroVert < faixa.primeiro + faixa.quantos then
      return i
    end
  end
  return -1
end

-- One mesh, sampled. `escalaUv` turns this sheet's UV back into SOURCE sheet
-- pixels: 1 for the ROM sheet, K for the enlarged one. Comparing the source
-- pixel rather than the UV is what lets the per-texel run inset stay per-texel.
local function amostra(mesh, faixas, escalaUv, sheetW, sheetH, problemas)
  local verts = mesh.verts
  local colunas = {}
  local quads = #verts / 4
  for q = 0, quads - 1 do
    local c1, c2, c3, c4 = verts[q * 4 + 1], verts[q * 4 + 2],
                           verts[q * 4 + 3], verts[q * 4 + 4]
    local e1 = { c2[1] - c1[1], c2[2] - c1[2], c2[3] - c1[3] }
    local e2 = { c4[1] - c1[1], c4[2] - c1[2], c4[3] - c1[3] }
    -- A PARALLELOGRAM, checked and not assumed. Every quad this mod emits is
    -- one, sheared or not, and a quad that is not would make the linear
    -- interpolation below a lie rather than an approximation.
    for k = 1, 3 do
      local esperado = c1[k] + e1[k] + e2[k]
      if math.abs(c3[k] - esperado) > 1e-9 then
        problemas[#problemas + 1] = string.format(
          "quad %d is not a parallelogram on axis %d (%.17g vs %.17g)",
          q, k, c3[k], esperado)
      end
    end
    local nx = e1[2] * e2[3] - e1[3] * e2[2]
    local ny = e1[3] * e2[1] - e1[1] * e2[3]
    local nz = e1[1] * e2[2] - e1[2] * e2[1]
    local A = eixoDominante(nx, ny, nz)
    local B, C = NO_PLANO[A][1], NO_PLANO[A][2]
    local f1b, f1c = e1[B], e1[C]
    local f2b, f2c = e2[B], e2[C]
    local det = f1b * f2c - f1c * f2b
    if math.abs(det) > 1e-12 then
      local minB = math.min(c1[B], c2[B], c3[B], c4[B])
      local maxB = math.max(c1[B], c2[B], c3[B], c4[B])
      local minC = math.min(c1[C], c2[C], c3[C], c4[C])
      local maxC = math.max(c1[C], c2[C], c3[C], c4[C])
      local banda = bandaDoQuad(faixas, q)
      for ib = math.ceil(minB * R - 0.5), math.floor(maxB * R - 0.5) do
        local b = (ib + 0.5) / R
        for ic = math.ceil(minC * R - 0.5), math.floor(maxC * R - 0.5) do
          local c = (ic + 0.5) / R
          local db, dc = b - c1[B], c - c1[C]
          local s = (db * f2c - dc * f2b) / det
          local t = (f1b * dc - f1c * db) / det
          if s >= 0 and s <= 1 and t >= 0 and t <= 1 then
            local a = c1[A] + s * e1[A] + t * e2[A]
            local u = c1[4] + s * (c2[4] - c1[4]) + t * (c4[4] - c1[4])
            local v = c1[5] + s * (c2[5] - c1[5]) + t * (c4[5] - c1[5])
            local sh = c1[6] + s * (c2[6] - c1[6]) + t * (c4[6] - c1[6])
            -- "%d" AND NOT CONCATENATION, because of negative zero.
            --
            -- `ib` and `ic` are lattice indices out of `math.ceil`, which
            -- returns a float: `math.ceil(-0.5)` is -0.0, and concatenating
            -- that spells "-0" while 0.0 spells "0". The same column then has
            -- two names, and a sample that both meshes really do have lands in
            -- two different buckets, which this gate reports as "surface only
            -- in ROM" plus "surface only in HD" for the same lattice point,
            -- same source pixel, same shade, same band.
            --
            -- Which of the two spellings comes out is not stable: on the mbp's
            -- LuaJIT (2.1.1785763465) the same tree, unchanged, printed OK,
            -- then 2 differences, then 50, then 98 across four runs, and 5 out
            -- of 5 OK under `luajit -joff`. On the Mac Studio's build
            -- (2.1.1782726002) it is 5 out of 5 OK with the JIT on. A gate that
            -- answers differently on two runs of the same bytes is not
            -- measuring the mod, and this one was one negative zero away from
            -- being trustworthy. Found 2026-08-13 while a red V10 was being
            -- recalibrated, on a full battery run that had to be repeated.
            --
            -- "%d" converts through an integer, where -0 and 0 are the same
            -- number and get the same name. Nothing else changes: no tolerance
            -- is widened and no comparison is loosened.
            local chave = string.format("%s:%d:%d", A, ib, ic)
            local col = colunas[chave]
            if not col then col = {}; colunas[chave] = col end
            col[#col + 1] = {
              a = a,
              px = math.floor(u * sheetW / escalaUv),
              py = math.floor(v * sheetH / escalaUv),
              sh = sh,
              banda = banda,
            }
          end
        end
      end
    end
  end
  local total = 0
  for _, col in pairs(colunas) do
    table.sort(col, function(x, y) return x.a < y.a end)
    total = total + #col
  end
  return colunas, total
end

-- ------------------------------------------------------------ comparing
local function comparaColunas(romCols, hdCols, rotulo, difs, motivos)
  local vistas, ordem = {}, {}
  for chave in pairs(romCols) do vistas[chave] = true end
  for chave in pairs(hdCols) do vistas[chave] = true end
  -- SORTED, because the examples printed below are capped at six and a hash
  -- order would hand a different six to every run. Two failing runs of the same
  -- defect have to diff cleanly, or the first thing anybody does with the
  -- output is doubt it.
  for chave in pairs(vistas) do ordem[#ordem + 1] = chave end
  table.sort(ordem)
  local n = 0
  for _, chave in ipairs(ordem) do
    local a = romCols[chave] or {}
    local b = hdCols[chave] or {}
    local maior = math.max(#a, #b)
    for i = 1, maior do
      local x, y = a[i], b[i]
      local motivo
      if not x then motivo = "surface only in HD"
      elseif not y then motivo = "surface only in ROM"
      elseif math.abs(x.a - y.a) > 1e-9 then motivo = "plane position"
      elseif x.px ~= y.px or x.py ~= y.py then motivo = "source sheet pixel"
      elseif math.abs(x.sh - y.sh) > 1e-12 then motivo = "shade"
      elseif x.banda ~= y.banda then motivo = "band"
      end
      if motivo then
        n = n + 1
        motivos[motivo] = (motivos[motivo] or 0) + 1
        if #difs < 6 then
          difs[#difs + 1] = string.format("%s %s (%s) rom=%s hd=%s",
            rotulo, chave, motivo,
            x and string.format("a=%.6g px=%d,%d sh=%.9g band=%d",
              x.a, x.px, x.py, x.sh, x.banda) or "-",
            y and string.format("a=%.6g px=%d,%d sh=%.9g band=%d",
              y.a, y.px, y.py, y.sh, y.banda) or "-")
        end
      end
    end
  end
  return n
end

local function comparaAncoras(rom, hd, rotulo, difs, motivos)
  local n = 0
  if (rom == nil) ~= (hd == nil) then
    motivos["anchor presence"] = (motivos["anchor presence"] or 0) + 1
    difs[#difs + 1] = rotulo .. " anchors: present on only one side"
    return 1
  end
  if not rom then return 0 end
  -- Extremes and bands only: see the note on `center` and `hand` in the header.
  for _, nome in ipairs({ "feet", "head" }) do
    local a, b = rom[nome], hd[nome]
    for _, campo in ipairs({ "x", "y", "z" }) do
      if math.abs((a[campo] or 0) - (b[campo] or 0)) > 1e-9 then
        n = n + 1
        motivos["anchor " .. campo] = (motivos["anchor " .. campo] or 0) + 1
        if #difs < 6 then
          difs[#difs + 1] = string.format("%s anchor %s.%s rom=%.9g hd=%.9g",
            rotulo, nome, campo, a[campo] or 0, b[campo] or 0)
        end
      end
    end
    if a.band ~= b.band then
      n = n + 1
      motivos["anchor band"] = (motivos["anchor band"] or 0) + 1
      if #difs < 6 then
        difs[#difs + 1] = string.format("%s anchor %s.band rom=%s hd=%s",
          rotulo, nome, tostring(a.band), tostring(b.band))
      end
    end
  end
  return n
end

-- The band SPANS, as a physical extent rather than as a vertex count: the
-- enlarged mesh has four times the vertices, so `quantos` can never match, but
-- the slice of the body each band covers must.
local function faixaExtensao(mesh, faixas)
  if not faixas then return nil end
  local fora = {}
  for i, faixa in ipairs(faixas) do
    local minY, maxY = math.huge, -math.huge
    for v = faixa.primeiro, faixa.primeiro + faixa.quantos - 1 do
      local y = mesh.verts[v][2]
      if y < minY then minY = y end
      if y > maxY then maxY = y end
    end
    fora[i] = { minY = minY, maxY = maxY, vazia = faixa.quantos == 0 }
  end
  return fora
end

local function comparaFaixas(rom, hd, rotulo, difs, motivos)
  if (rom == nil) ~= (hd == nil) then
    motivos["band spans presence"] = (motivos["band spans presence"] or 0) + 1
    difs[#difs + 1] = rotulo .. " band spans: present on only one side"
    return 1
  end
  if not rom then return 0 end
  local n = 0
  if #rom ~= #hd then
    motivos["band count"] = (motivos["band count"] or 0) + 1
    return 1
  end
  for i = 1, #rom do
    local a, b = rom[i], hd[i]
    if a.vazia ~= b.vazia
       or (not a.vazia and (math.abs(a.minY - b.minY) > 1e-9
                            or math.abs(a.maxY - b.maxY) > 1e-9)) then
      n = n + 1
      motivos["band span"] = (motivos["band span"] or 0) + 1
      if #difs < 6 then
        difs[#difs + 1] = string.format(
          "%s band %d span rom=[%.9g,%.9g] hd=[%.9g,%.9g]",
          rotulo, i, a.minY or 0, a.maxY or 0, b.minY or 0, b.maxY or 0)
      end
    end
  end
  return n
end

-- ------------------------------------------------------ the clock sweep
--
-- BLINK is applied at DRAW time, per mesh, so a gate that builds a mesh and
-- looks at it once only ever sees an OPEN eye. That is not a hypothetical: the
-- first version of this gate did exactly that, and the mutation that breaks the
-- HD eye marks walked past it green.
--
-- The instants are found rather than computed. `blinkTiming` hashes the sheet
-- name into a period and a phase, and copying that arithmetic here would mean
-- the gate agreed with a copy of the mod instead of with the mod. So the sweep
-- drives the clock and reads the mod's own `blink_closed` edge.
local function instanteFechado(mod, modules)
  local eventos = mod._animEvents
  for passo = 0, 240 do
    local t = passo * 0.05
    love.timer.getTime = function() return t end
    for frame = 0, FRAMES - 1 do modules.SpriteBillboards.mesh(DEF, frame) end
    for _, nome in ipairs(eventos()) do
      if nome == "blink_closed" then return t end
    end
  end
  return nil
end

-- --------------------------------------------------------- the run itself
local CONFIGS = {
  { nome = "plain SLAB", opcoes = {} },
  { nome = "GROUND SHADE", opcoes = { ground_shade = "on" } },
  { nome = "SIDE COLOR: BODY + TOP EDGE",
    opcoes = { side_color = "body", top_edge = "on" } },
  { nome = "STEP WEIGHT: HIGH", opcoes = { step_weight = 0.5 } },
  { nome = "BLINK", opcoes = { blink = "on", side_color = "body" },
    piscar = true },
  { nome = "AUTHORED REGIONS", opcoes = { authored_regions = "on" } },
  -- CARVED+ builds a different mesh through a different function and is the
  -- only configuration that reaches CARVED_PLUS_RECESS_STEPS. One frame,
  -- because the enlarged hull is a 64x64x40 voxel field and six of them cost
  -- more time than the finding is worth.
  { nome = "CARVED+", opcoes = { shape = "carved_plus", side_color = "body" },
    frames = { 0 } },
}

local relogioAntes = love.timer.getTime
local problemas, difs, motivos = {}, {}, {}
local totalAmostras, totalDifs, totalQuads, totalQuadsHd = 0, 0, 0, 0
local fechados = 0

for _, cfg in ipairs(CONFIGS) do
  local modRom, modulesRom = carrega(opcoesCom(cfg.opcoes, false), false)
  local modHd, modulesHd = carrega(opcoesCom(cfg.opcoes, true), true)

  local relogios = { 0 }
  if cfg.piscar then
    local fechado = instanteFechado(modRom, modulesRom)
    if not fechado then
      problemas[#problemas + 1] = "the " .. cfg.nome ..
        " sweep never caught the eye shut; this gate would then only ever be " ..
        "comparing an open eye, which is how the HD eye marks went unmeasured"
    else
      fechados = fechados + 1
      relogios = { 0, fechado }
    end
    -- Drain both mailboxes so the sweep's own edges do not leak into the
    -- comparison below.
    modRom._animEvents()
    modHd._animEvents()
  end

  local quadros = cfg.frames or { 0, 1, 2, 3, 4, 5 }
  for _, t in ipairs(relogios) do
    love.timer.getTime = function() return t end
    for _, frame in ipairs(quadros) do
      local rotulo = string.format("%s frame %d t=%.2f", cfg.nome, frame, t)
      local meshRom = modulesRom.SpriteBillboards.mesh(DEF, frame)
      local meshHd = modulesHd.SpriteBillboards.mesh(DEF, frame)
      if not (meshRom and meshRom.verts) then
        problemas[#problemas + 1] = rotulo .. ": the ROM build produced no mesh"
      elseif not (meshHd and meshHd.verts) then
        problemas[#problemas + 1] = rotulo .. ": the HD build produced no mesh"
      else
        local faixasRom = modRom._bands(meshRom)
        local faixasHd = modHd._bands(meshHd)
        local colsRom, nRom = amostra(meshRom, faixasRom, 1,
          FOLHA_ROM.w, FOLHA_ROM.h, problemas)
        local colsHd = amostra(meshHd, faixasHd, K,
          FOLHA_HD.w, FOLHA_HD.h, problemas)
        totalAmostras = totalAmostras + nRom
        totalQuads = totalQuads + #meshRom.verts / 4
        totalQuadsHd = totalQuadsHd + #meshHd.verts / 4
        totalDifs = totalDifs
          + comparaColunas(colsRom, colsHd, rotulo, difs, motivos)
          + comparaAncoras(modRom._anchors(meshRom), modHd._anchors(meshHd),
              rotulo, difs, motivos)
          + comparaFaixas(faixaExtensao(meshRom, faixasRom),
              faixaExtensao(meshHd, faixasHd), rotulo, difs, motivos)
      end
    end
  end
end

love.timer.getTime = relogioAntes

-- A gate that measures nothing passes everything. Both floors below have been
-- reached by accident on this project already: a comparison against a file that
-- did not exist declared success, and a driver that produced no verdict counted
-- as a pass.
if totalAmostras < 10000 then
  problemas[#problemas + 1] = string.format(
    "only %d samples were taken; the fixture or the lattice is broken, and " ..
    "an empty comparison agrees with everything", totalAmostras)
end
if fechados == 0 then
  problemas[#problemas + 1] =
    "no configuration ever closed an eye, so BLINK went unmeasured"
end
-- PROOF THAT THE HD SHEET ACTUALLY ARRIVED. If the door into `hdDataFor` ever
-- stops working -- a renamed path, a changed LOVE stub -- the mod falls back to
-- the ROM sheet without complaint and this gate compares a mesh with itself,
-- which passes forever. A 64 px cell has sixteen source pixels where a 16 px
-- cell has one, so its mesh cannot be anywhere near the same size.
if totalQuadsHd <= totalQuads * 4 then
  problemas[#problemas + 1] = string.format(
    "the HD build produced %d quads against the ROM's %d; the enlarged sheet " ..
    "did not reach the mod and the two sides are the same mesh",
    totalQuadsHd, totalQuads)
end

print(string.format(
  "HD EQUIVALENCE: %d configurations, %d ROM quads against %d HD quads, " ..
  "%d samples on the common grid",
  #CONFIGS, totalQuads, totalQuadsHd, totalAmostras))
if totalDifs == 0 and #problemas == 0 then
  print("HD EQUIVALENCE OK: the enlarged sheet paints the same picture")
  os.exit(0)
end
for _, p in ipairs(problemas) do print("  " .. p) end
local ordem = {}
for motivo in pairs(motivos) do ordem[#ordem + 1] = motivo end
table.sort(ordem)
for _, motivo in ipairs(ordem) do
  print(string.format("  %-24s %d", motivo, motivos[motivo]))
end
for _, d in ipairs(difs) do print("  " .. d) end
print(string.format("HD EQUIVALENCE FAILED: %d differences", totalDifs))
os.exit(1)
