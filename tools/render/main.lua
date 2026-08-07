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
local MAIN_PATH = ROOT .. "mods/voxel_characters/main.lua"
local SPRITE_DIR = "assets/generated/sprites/"

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
  })
  local chunk = assert(loadfile(MAIN_PATH))
  chunk(mod)
  local SpriteBillboards = handle.exports.lib.require("SpriteBillboards")
  local mesh = SpriteBillboards.mesh(def, frame)
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

local KINDS = { "front", "back", "side", "top", "bottom" }
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
  return "side"
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
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 t = Texel(tex, tc);
  if (t.a < 0.5) discard;
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

function love.load(argv)
  parseArgs(argv)

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
    local path = SPRITE_DIR .. sprite .. ".png"
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
        if shape == "flat" then
          mesh = flatCard(data, def.frames, frame)
        else
          mesh, why = buildGeometry(data, def, frame, shape, depth,
                                    opts.side_color)
        end
        local sheetW, sheetH = data:getDimensions()
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
            kinds = kinds, quadKinds = quadKinds, role = role,
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
  state.shader = love.graphics.newShader(SHADER)
  local pal = PALETTES[opts.palette] or PALETTES.obj
  for i = 1, 4 do state.shader:send("pal" .. (i - 1), pal[i]) end
  state.bg = numbers(opts.bg)
  state.frames = 0

  local quads = 0
  for _, row in ipairs(rows) do
    if row.mesh then
      quads = quads + math.floor(#row.mesh.verts / 4)
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

local function drawCell(row, yaw, x, y, size, asProvenance)
  if not row.mesh then return end
  local b = bounds(row.mesh.verts)
  -- Pivot on each mesh's own bounding box in X and Y, and on z = 0, the plane
  -- the flat card occupies. The mod drops the sprite cell's empty padding
  -- (`lx - m.minX`), so a cell-relative pivot would offset every mod mesh
  -- against the card. Mod-vs-mod diffs are therefore exact; a diff against
  -- FLAT still carries whatever padding the sheet had, so read that one as a
  -- reference image, not as a number.
  local cam = {
    yaw = yaw, pitch = row.pitch,
    cx = (b.minX + b.maxX) / 2,
    cy = (b.minY + b.maxY) / 2,
    cz = 0,
    scale = size / VIEW_UNITS,
    screenX = x + size / 2,
    screenY = y + size / 2,
    width = state.width, height = state.height, flipY = asProvenance,
    -- generous so nothing clips; the depth test only needs ordering
    depthRange = math.max(64, (b.maxY - b.minY) * 2),
  }
  local verts = project(row.mesh.verts, cam)
  if asProvenance then
    for i, v in ipairs(verts) do
      v[6] = KIND_INDEX[row.kinds[math.floor((i - 1) / 4) + 1]]
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
local function computeMetrics()
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
      local text = string.format("%s  frame %d  %s  %s%s", row.sprite,
        row.frame, row.shape:upper(), row.pitchLabel,
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
      if opts.metrics == "1" then computeMetrics() end
    end)
  elseif state.frames > 6 then
    love.event.quit()
  end
end

function love.keypressed(key)
  if key == "escape" then love.event.quit() end
end
