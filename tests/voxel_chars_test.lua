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

-- v1.4.2, fine-tooth comb (item 5): lock on the lorelei pixel snapshot.
-- The real art test below does not read assets/generated/sprites/lorelei.png
-- at run time (there is no PNG decoder available inside plain luajit, only
-- inside real love), so the pixels were extracted once and turned into
-- fixed paint() calls. Without the lock, if the art is redrawn the suite
-- stays green against stale pixels and the eye mark could end up closing
-- over skin with no test catching it, the v1.4.1 defect all over again.
-- FNV-1a instead of sha256 because it needs no cryptography library, just
-- bit.bxor (LuaJIT builtin) and file reading; it is an integrity
-- checksum, not security, so the theoretical collision does not matter
-- here. If this check fails, the art changed: run
-- tools/render (real, with a real PNG) to re-extract the pixels and
-- update both the snapshot and this number.
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

-- v1.6.0: like vertexSignature, but without the shade column (v[6]). TOP
-- DOME and TOP EDGE only ever change shade, never vertex position or UV;
-- this signature proves the geometry byte for byte identical while the
-- shade changes freely on top of it.
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

-- v1.6.0: like frontVertexShadeAt, but returns Z instead of shade and does
-- not require Z == 0: STEP WEIGHT shears Z proportionally to height (Y), so
-- a front vertex is no longer exactly on the Z = 0 plane when the option is
-- on -- and the sheared position itself is what the test wants to read.
-- `shade` disambiguates between front (0.90), back (0.68), side (0.78), top
-- (1.00) and bottom (0.55) when (x, y) coincides between different faces.
local function vertexZAt(mesh, x, y, shade)
  for _, v in ipairs(mesh.verts) do
    if close(v[1], x) and close(v[2], y)
        and (not shade or close(v[6], shade)) then
      return v[3]
    end
  end
end

-- v1.6.0: like positionSignature, but only the X column (v[1]), in the same
-- vertex emission order. STEP WEIGHT shears Z proportionally to height and
-- never touches X -- the guarantee against the host's mirroring, which only
-- flips the sign on X. Comparing this signature between the mesh with the
-- option on and off proves X identical vertex by vertex, not just "the same
-- silhouette by coincidence".
local function xSignature(mesh)
  local out = {}
  for i, v in ipairs(mesh.verts) do
    out[i] = ("%.4f"):format(v[1])
  end
  return table.concat(out, ";")
end

-- v1.6.0: like frontFaceZAt, but without requiring shade == 0.90, because a
-- stepped FRONT SHAPE quad can come out darker than the usual flat shade.
-- Finds the front quad (z1, flat at z = 0) by its X/Y bounds and returns
-- the shade it got, to compare edges and center of a run.
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

-- v1.6.0: counts how many front quads (z1, flat at z = 0) have some edge
-- within [minX, maxX], to prove that a segment split (more than one quad)
-- or did not (just one).
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

-- v1.6.0: like frontQuadShadeAt, but for the TOP face (flat on Y, with
-- extent on Z): finds the quad at the given Y height and X bounds and
-- returns the shade it got, without requiring a specific value -- the
-- goal is to compare different shades between edge and center of a TOP
-- DOME run.
local function topQuadShadeAt(mesh, minX, maxX, y)
  for i = 1, #mesh.verts, 4 do
    local b = quadBoundsAt(mesh, i)
    if close(b.minX, minX) and close(b.maxX, maxX)
        and close(b.minY, y) and close(b.maxY, y) and b.maxZ > b.minZ then
      return mesh.verts[i][6]
    end
  end
end

-- Options table refactor: main.lua no longer keeps a dedicated upvalue per
-- option (depthValue, sideColorValue, ...). Every resolved value now lives
-- in a single table, `optionState` (an upvalue of voxelMesh, indexed by the
-- option key: "depth", "side_color", ...). The nine helpers below keep the
-- same purpose as always (change the resolved value WITHOUT going through
-- setOption, so without triggering the clearCache/clearMeshCache that
-- setOption triggers), except now they find `optionState` (the TABLE, an
-- object by reference) and write directly into the field, instead of
-- overwriting a scalar upvalue via debug.setupvalue.
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

-- life: builds a 16-number world matrix, row-major, in the same
-- format VoxelScene.billboardMatrix delivers (translation in the 4th column
-- of each row). model[1] does double duty, exactly like in the host: mirror
-- sign AND row 0's x in the shear formula. The other 15 cells
-- are fixed, distinct numbers (each cell is worth its own index, except
-- for the three contract cells: model[1], model[4] and model[12]), so the
-- tests can tell "this cell changed" from "this cell did not change"
-- without needing to inspect anything beyond the matrix itself.
local function lifeModel(px, py, mirrored)
  local sign = mirrored and -1 or 1
  return {
    sign, 2, 3, mirrored and (px + 16) or px,
    5, 6, 7, 8,
    9, 10, 11, py + 8,
    13, 14, 15, 16,
  }
end

-- compares two 16-number matrices cell by cell, with the same
-- tolerance as `close`.
local function sameMatrix(a, b)
  for i = 1, 16 do
    if not close(a[i], b[i]) then return false end
  end
  return true
end

-- life, magnitude: same idea as withLoveTime, but for a SEQUENCE of
-- instants instead of just one. `fn` receives `setClock`, which the test
-- calls on every simulated frame before drawing. Restores love.timer.getTime
-- at the end, even if `fn` throws.
local function withDrivenClock(fn)
  local prev = love.timer.getTime
  local now = 0
  love.timer.getTime = function() return now end
  local ok, err = pcall(fn, function(value) now = value end)
  love.timer.getTime = prev
  if not ok then error(err) end
end

-- life, magnitude: compares two numbers with RELATIVE tolerance (a
-- fraction of `want`). The menu levels range from 0.010 (BREATH SUBTLE) to
-- 1.2 (MOTION LAG NORMAL); a fixed absolute tolerance like `close`'s does
-- not work at both extremes.
local function closePercent(got, want, pct)
  return math.abs(got - want) <= math.abs(want) * pct
end

-- life, magnitude: unlike lifeModel (which only needs to prove "this
-- cell changed" or "did not change"), the magnitude tests need to read s, kx
-- and kz separately from the OUTPUT. This matrix isolates the three into one
-- row each, straight from the lifeApply formula (out[c+2] = m[c+2]*s + m[c+1]*kx +
-- m[c+3]*kz):
--   row 0 (c=0): m[1]=sign (contract), m[2]=0, m[3]=0 -> out[2] = sign*kx
--   row 1 (c=4): m[5]=0, m[6]=1, m[7]=0 -> out[6] = s
--   row 2 (c=8): m[9]=0, m[10]=0, m[11]=1 -> out[10] = kz
-- (row 3 is read by nobody, it is just filler). The contracts of
-- model[1] (mirror sign), model[4] (px) and model[12] (py + 8) still
-- hold.
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

-- v1.4.2: same sheet as paintBlinkFace, shifted down `dy` rows, to
-- simulate the walk step (frame 3 = frame 0 shifted down one row in the
-- real art).
local function paintBlinkFaceShifted(pixels, sheetW, cellW, frame, dy)
  local skin = rgba(0.80, 0.55, 0.40, 1)
  local eye = rgba(0.05, 0.05, 0.05, 1)
  for lx = 5, 10 do paint(pixels, sheetW, cellW, frame, lx, 7 + dy, skin) end
  paint(pixels, sheetW, cellW, frame, 6, 7 + dy, eye)
  paint(pixels, sheetW, cellW, frame, 9, 7 + dy, eye)
  paint(pixels, sheetW, cellW, frame, 6, 8 + dy, skin)
  paint(pixels, sheetW, cellW, frame, 9, 8 + dy, skin)
end

-- v1.4.2: same silhouette (same opacity, same cells) as
-- paintBlinkFaceShifted, but with no eye-tone pixel at all: simulates a
-- head genuinely redrawn, where poseOffset still finds the right offset
-- (the silhouette matches) but the eye mark does not carry over because the
-- tone changed.
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

-- v1.6.0: same sheet as paintBlinkFace, but with the skin band stretched
-- across the whole cell on both sides of the eyes, to guarantee that at
-- least one segment around an eye passes the 3-pixel threshold and
-- actually enters the FRONT SHAPE step path (paintBlinkFace alone only
-- produces 1- and 2-pixel segments, too short to split).
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
    -- The real host's mesh is a LOVE Mesh, which has setDrawRange. Without it
    -- here, PART LAG's per-band path was silently unreachable offline: the
    -- code checks for the method before using it, correctly, and the mock
    -- simply did not have it, so the suite could only ever exercise the
    -- single-matrix fallback. Recording the calls as well, because "was the
    -- range cleared afterwards" is a real question: the range is sticky on a
    -- mesh shared between every character using that sheet.
    setDrawRange = function(self, primeiro, quantos)
      self.drawRanges = self.drawRanges or {}
      self.drawRanges[#self.drawRanges + 1] = { primeiro, quantos }
      self.rangeAtual = primeiro and { primeiro, quantos } or nil
    end,
    setVertexMap = function(self, m) self.map = m end,
    setTexture = function(self, tex) self.texture = tex end,
    release = function(self) self.released = true end,
  }
end

-- cardBlend and omitFirstPerson support defect 3 (main.lua:1043+, runs
-- before SLAB and CARVED). cardBlend controls the return of the
-- FirstPerson.cardBlend() stub; omitFirstPerson removes the module from the
-- namespace, to prove the host version where FirstPerson does not even
-- exist.
--
-- withDraw supports the life channel (main.lua, lifeDrawWrap): without it
-- the mock's Voxel3D has no `draw` field, same as the usual host in this
-- file, so drawWrap stays false and LIFE reads NO CHANNEL. With it, the
-- mock gains a `draw` that just records the call (mesh, texture, model,
-- pull, sunModel) into Voxel3D.drawCalls, for the tests to read afterward,
-- and returns "drew" to simulate some return value from the host.
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
  function mod.options:define(s)
    schema = s
    -- Item 16: exposed on the mod table too (not just the closure-local
    -- above) so callers can read the schema back after loadWith returns,
    -- and derive real maxima instead of hand-copying them.
    mod._schema = s
  end
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

-- SO_ESTA: fixes every life option at OFF and turns on only the ones
-- requested.
--
-- Exists because changing a product DEFAULT broke eight checks at once, and
-- they broke for the right reason: they tested one option and left the
-- others at default, so the day BREATH started spawning on, a test about
-- FOOTFALL started measuring both combined. A test about one thing fixes
-- every other one; default is the business of the test that covers default,
-- and no other one.
local function soEsta(extra)
  local o = { blink = "off", breath = "off", sway = "off", lag = "off",
              footfall = "off" }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end

-- v1.4.2: reads the current value of the STATUS row, recalculated every
-- time (never cached), the same way the options menu would read it.
local function statusRowValue(mod)
  local rows = {}
  mod._rows["ui.options.rows"](function(_, r) return r end, {}, rows)
  for _, row in ipairs(rows) do
    if row.label == "STATUS" then return row.value() end
  end
end

-- life: same idea as statusRowValue, for the LIFE row.
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

-- v1.4.2: decide by capability, not by version number. Kim's measurement
-- before this change: "banana" (unreadable version) was ACCEPTED and
-- "1.3.1" (readable version, but out of range, with the whole API present)
-- was REJECTED. The tests below swap that inversion around.

do
  -- host with an out-of-range version and the whole API is accepted, with
  -- a warning. Tests the exact number Kim measured (1.3.1 against the range
  -- >=1.7.0 <2.0.0).
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
  -- host with an unreadable version and the whole API is accepted. This is
  -- the test that represents Angelus's report (host DRAMALESS_SHAPE
  -- 1.6.2.ST).
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
  -- The REAL, current version of Dramaless Shape, pinned here on purpose.
  --
  -- The original Dramatic Shape repository went dark for the second time,
  -- and this fork became the host most of the community runs. The range
  -- `>=1.5.0 <2.0.0` covers 1.6.4 today; if someone tightens that range in a
  -- future pass without noticing, the mod starts logging "untested version"
  -- for the most used host that exists, and nobody finds out because
  -- nothing breaks. This test exists to break before that happens.
  --
  -- Checked against the real release: id DRAMALESS_SHAPE, api 2, and the
  -- six modules we consume present, with SpriteBillboards.mesh still a
  -- table field.
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
  -- no host: the STATUS row appears saying NO HOST (instead of the old
  -- blank, which cost Colonel_Aureliano twenty minutes on a clean reinstall
  -- and made Angelus think it was Wilds of Kanto).
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
  -- the out-of-range fork is now accepted right away (first in the
  -- HOSTS list), so the legacy host is never even tried. Before this change
  -- the fork was rejected and the legacy host took over; today neither one
  -- is rejected for version.
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
  -- no usable host now only happens from a capability failure, not a
  -- version one: all three ids exist, but each one is missing a different
  -- module. The log has to say which one was missing in each.
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
  -- host without Voxel3D is rejected and the log says which module was
  -- missing.
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
  -- host whose SpriteBillboards.mesh is not a function is rejected.
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
  -- host whose require blows up is rejected without bringing down the
  -- loading of the whole mod (the hole in the original main.lua 1750). pcall
  -- around loadWith proves the whole chunk does not throw.
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
  -- BLOCKING finding from the fine-tooth comb: patch() has to be atomic.
  -- SpriteBillboards write-protected: an empty proxy whose __index reads
  -- from a hidden table (so .mesh exists and the capability probe accepts
  -- the host, because probeHost only READS .mesh, never tests writing) and
  -- whose __newindex throws on ANY assignment (so the sheet never
  -- accumulates real keys, unlike a normal __newindex that only fires on a
  -- new key). patch()'s second risky write (spriteBillboards.mesh =
  -- installed) throws; without an atomic commit, SpriteBillboards had
  -- already been set and STATUS read REPLACED for a substitution that
  -- never happened, worse than NO HOST because it points the investigation
  -- at another, nonexistent mod. With an atomic commit, no module upvalue
  -- is touched.
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
  -- fine-tooth comb, item 1: the partial write cannot stay in the host
  -- table. The blocker covered "both writes fail" (a host that blocks
  -- everything); this one covers the more plausible case, a host that
  -- protects only the `mesh` key (already existing, never becomes a raw
  -- key, always goes through __newindex) and allows a new key (this is how
  -- a public API defends itself without locking out extension). The first
  -- write (__voxelCharactersOriginal, a new key) succeeds; the second
  -- (.mesh) throws. Without undoing the first, __voxelCharactersOriginal
  -- would stay written into the host table forever, even though the patch
  -- never took, contradicting the README ("does not modify the Voxel
  -- Mod").
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
  -- fine-tooth comb, item 1, repatch case: if __voxelCharactersOriginal
  -- genuinely already existed (a previous successful patch) and the second
  -- write fails, the previous value has to come back, never turn into nil.
  -- Erasing a legitimate __voxelCharactersOriginal would break the chaining
  -- that warnChainedMesh depends on to detect who patched before us.
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
  -- v1.6.0: the FRONT SHAPE row, in the same pattern as the others:
  -- default OFF (house rule), four steps (OFF, LOW 0.12, MED 0.17, HIGH
  -- 0.22), step changes and persists in the save and in the loader.
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
  -- v1.6.0: the TOP DOME row, in the same pattern as the others: default
  -- OFF (house rule), two steps (OFF, LOW 0.15, HIGH 0.30 -- only the two
  -- measured points, no interpolated MED), step changes and persists in
  -- the save and in the loader.
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
  -- v1.6.0: the STEP WEIGHT row, in the same pattern as the others:
  -- default OFF (house rule -- and on top of that, it is the first option
  -- in this branch that moves a vertex instead of shade, so the
  -- conservatism weighs even more), two steps (OFF, LOW 0.25, HIGH 0.5),
  -- step changes and persists in the save and in the loader.
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
  -- FIRST PERSON had behavior (Voxel3D.lua above) but had no MENU row
  -- tested -- the only option in the mod in that situation, until an audit
  -- pointed out the gap (see the rows[17] test further below, which only
  -- covers POSITION, not step nor persistence). Same pattern as the
  -- others: default CARD (house rule: nobody has seen the solid in first
  -- person yet), two steps (CARD, SOLID). LIFE_OPTION_KEYS requires the
  -- second patch point (Voxel3D.draw) for the row to appear, which is why
  -- the handle asks for withDraw=true. Tested in both directions: with
  -- only two levels, cycling forward only never exercises `dir = -1` in
  -- `(i + dir - 1) % #levels`, and a bug there (for example a flipped sign
  -- that only shows up going backward) would go unnoticed.
  local pixels = {}
  pixels[0] = 1
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
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
  -- FOUND BY INDEX AND NOT BY POSITION, because adding PART LAG in front of
  -- FIRST PERSON moved this row and broke twelve checks at once. A test that
  -- hardcodes a row number is a test that fails every time a menu grows.
  local option
  for _, r in ipairs(rows) do
    if r.label == "FIRST PERSON" then option = r break end
  end
  eq(option.label, "FIRST PERSON", "row de FIRST PERSON fica depois de FOOTFALL")
  eq(option.value(), "CARD", "FIRST PERSON default e CARD")
  check(option.step(game, 1), "step de FIRST PERSON informa mudanca")
  eq(option.value(), "SOLID", "FIRST PERSON alterna para SOLID")
  eq(game.save.options.modOptions.voxel_characters.first_person, "solid",
     "FIRST PERSON persiste no save")
  eq(game.mods.modOptions.voxel_characters.first_person, "solid",
     "FIRST PERSON persiste no loader")
  eq(emitted[1].payload.value, "solid", "FIRST PERSON emite o valor novo")
  check(option.step(game, 1), "FIRST PERSON da a volta pra frente")
  eq(option.value(), "CARD", "FIRST PERSON volta para CARD depois de SOLID")
  eq(game.save.options.modOptions.voxel_characters.first_person, "card",
     "FIRST PERSON persiste CARD no save depois da volta pra frente")
  check(option.step(game, -1), "step de FIRST PERSON pra tras informa mudanca")
  eq(option.value(), "SOLID",
     "FIRST PERSON ciclando pra tras a partir de CARD da a volta para SOLID")
  eq(game.save.options.modOptions.voxel_characters.first_person, "solid",
     "FIRST PERSON persiste SOLID no save ciclando pra tras")
  check(option.step(game, -1), "step de FIRST PERSON pra tras informa mudanca de novo")
  eq(option.value(), "CARD",
     "FIRST PERSON ciclando pra tras de SOLID volta para CARD")
  eq(game.save.options.modOptions.voxel_characters.first_person, "card",
     "FIRST PERSON persiste CARD no save ciclando pra tras")
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
  -- The pixel lives in frame 5 (row 80 of a vertical sheet, 16px per
  -- frame), not in frame 0: since v1.3.0 the SLAB mask is per current frame
  -- (defect 1), so an opaque pixel only in frame 0 would no longer be
  -- enough to prove that frame 5 builds a mesh.
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
  local last
  for i = 2, 65 do
    last = modules.SpriteBillboards.mesh({ image = ("sheet-%03d.png"):format(i),
                                           frames = 1 }, 0)
  end
  check(first.released, "LRU solta a malha mais antiga ao passar de 64 entradas")
  -- ONLY THE OLDEST ONE. Without this pair, releasing on every insertion
  -- passes: the test only asked whether the first one dropped, never
  -- whether the last one stayed. A cache that releases everything has a
  -- zero hit rate and rebuilds the mesh per character per frame, which is
  -- exactly the cost the cache exists to avoid.
  check(last ~= nil and not last.released,
        "LRU nao solta a mais recente junto: soltar tudo tambem passaria acima")
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
  -- As of v1.3.0 the SLAB geometry is per current frame (defect 1), no
  -- longer the union, so the standing pose (rows 1-3) needs to cover the
  -- row that walking (rows 1-2) queries as its role-0 reference: without
  -- that overlap the reference lookup fails and falls back to the frame
  -- itself, which would only prove trivial stability.
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

-- v1.4.2: poseOffset compensates for the offset between the standing
-- and walking pose before reading the reference (AngelusRole: "when a
-- character's head is set to use the body color, the top of the head
-- flickers while walking"). The classification tests above use only 3
-- tones and did not catch the defect because the outline's body lookup
-- fell into the same range by coincidence; the tests below isolate the
-- offset itself.

do
  -- poseOffset finds a one-row offset: frame 3 is frame 0 shifted down
  -- one row. Three tones (not just 2) so that any wrong offset, not just
  -- "no offset", resolves to a tone different from the standing top.
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
  -- dark anchor to pin outlineLuma away from the test's tones, otherwise
  -- the test's own darkest tone (red) becomes the outline just by being
  -- the minimum.
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
  -- poseOffset returns zero when the poses coincide: the case of the 6
  -- sheets that do not shift. Checks top AND bottom because, alone, each
  -- one masks one of the two wrong signals via the uncompensated fallback
  -- (top does not catch a wrong dy=-1, bottom does not catch a wrong
  -- dy=+1); the two together catch both.
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
  -- poseOffset breaks ties deterministically: a sheet where frame 3 has a
  -- single opaque pixel and frame 0 has two, one row above it and one row
  -- below it, so dy=-1 and dy=1 tie on |dx|+|dy|. The canonical scan always
  -- runs from 0 (the lower index) to 3, so the "tie, lower dy" rule decides
  -- poseOffset(0,3) = (0,-1); the real call is in the opposite direction,
  -- poseOffset(3,0), which is the negative by construction: (0,1).
  -- Compensated, row 2 of frame 3 points to row 3 of frame 0 (toneQ), not
  -- row 1 (fine-tooth comb, item 2: before canonicalization, each
  -- direction scanned toward its own side and "lower dy" picked -1 in BOTH
  -- directions, breaking poseOffset(A,B) == -poseOffset(B,A)). Runs the
  -- same sheet under two different image names (the ImageCache stub
  -- ignores the name and returns the same pixels) to force two masks and
  -- two independent scans, proving the tie-break does not depend on
  -- caching or on incidental scan order.
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
  -- the top face is a horizontal plane: Y is constant (cellBottom - ly + 1),
  -- not a range, so minY and maxY have to be the same value.
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
  -- fine-tooth comb, item 4: the test above (and the one repeating
  -- across two scans) only proves REPEATABILITY, which stays true even if
  -- the explicit tie-break block is deleted (lens C removed the whole
  -- block, leaving only `score > bestScore`, and the whole suite passed:
  -- without the block, a tie becomes "whichever the loop finds first
  -- stays", which IS deterministic, except it follows LOOP ORDER (dy from
  -- -3 to 3 on the outside, dx from -2 to 2 on the inside: a tie "wins" on
  -- the lower dy, without looking at |dx|+|dy|), not the documented policy
  -- (lowest |dx|+|dy| first). Dataset that tells the two apart: A opaque
  -- only at (0,3); B opaque at (2,0) [dx=2,dy=-3, the FIRST candidate the
  -- loop visits, |dx|+|dy|=5] and at (0,4) [dx=0,dy=1, visited much later,
  -- |dx|+|dy|=1]. The two tie at score=1, and only these two score. Loop
  -- order would pick (2,-3) because dy=-3 comes first; the documented
  -- policy picks (0,1) because |dx|+|dy|=1 is lower than 5. Only a test
  -- that expects (0,1) catches a future dev deleting the tie-break block
  -- in a refactor.
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
  -- the crown's top face resolves to the same texel in both frames: the
  -- test that represents Angelus's report. A 3-column sheet with a one-row
  -- offset; takes the top face of the middle column in the standing frame
  -- and in the walking frame and proves it points to the same tone.
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
  -- the top face is a horizontal plane: Y is constant (cellBottom - ly + 1),
  -- not a range, so minY and maxY have to be the same value.
  local standU, standV = horizontalFaceUvInBounds(stand, 1.0, 1, 2,
    cellBottom - 0 + 1, cellBottom - 0 + 1)
  local walkU, walkV = horizontalFaceUvInBounds(walk, 1.0, 1, 2,
    cellBottom - 1 + 1, cellBottom - 1 + 1)
  check(standU and walkU and close(standU, walkU) and close(standV, walkV),
        "a face de topo da coroa resolve para o mesmo texel nos dois frames")
end

do
  -- the equivalent of the crown test for the side face (sideUv). A
  -- single 2-pixel column (body tone and outline) that shifts down a row
  -- while walking; without compensation, the unsuccessful reference lookup
  -- falls back to the outline instead of the body, because the
  -- 1-pixel-wide sheet has no neighboring column for the internal search
  -- to reach.
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

-- Round 2, "the same defect you just fixed, in buildCarvedMesh"
-- (v1.4.2): CARVED's topUv and sideUv have the same reference-frame lookup
-- structure the SLAB had, without compensating for the step. The
-- classification test above does not catch this for the same reason as
-- the SLAB: only 2 tones, so the body lookup falls into the same range by
-- coincidence.

do
  -- CARVED's crown top face AND side face both resolve to the same texel
  -- in both frames. Three views (front, back, profile), with a one-row
  -- offset in all of them; the profile view paints only column 0 on
  -- purpose, so there is only one side face per row (without this, several
  -- depths would give several side faces at the same edge and the test
  -- would not know which one to check).
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

  -- "confirm that the compensation enters texture space and not
  -- geometry space": frame 3 (role 0) and frame 4 (role 1) have the SAME
  -- pose.front/back/side (CARVED only rotates the mesh per role, it does
  -- not rebuild the texture), so the emitted UV sequence has to be
  -- identical between the two, even with the geometry rotated 180 degrees
  -- in the world.
  local mesh4 = modules.SpriteBillboards.mesh(def, 4)
  eq(quadCount(walk), quadCount(mesh4),
     "CARVED: role 0 e role 1 do mesmo pose tem a mesma contagem de quads")
  eq(uvSignature(walk), uvSignature(mesh4),
     "CARVED: a compensacao entra no espaco de textura, nao no espaco de geometria")
end

do
  -- poseOffset only compensates between frames of the SAME role:
  -- comparing the front mask with the profile mask measures a silhouette
  -- difference, not a step, and would return a number that looks like an
  -- offset but is actually garbage. Extracts poseOffset from inside
  -- buildCarvedMesh (upvalue) and calls it directly, without going through
  -- the mesh: CARVED's correct wiring never calls poseOffset with frames
  -- from different roles, so testing only through the mesh would never
  -- exercise this branch.
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

  -- frame 0 (front, role 0): just one pixel, in the corner.
  paint(pixels, sheetW, cellW, 0, 0, 0, 1)
  -- frame 2 (profile, role 2): an adversarial shape coincidence. A solid
  -- block 2 rows below the front pixel; if poseOffset compared front with
  -- profile by mask overlap, dx=0,dy=2 would "find" 100% intersection, a
  -- confident and completely wrong reading.
  paint(pixels, sheetW, cellW, 2, 0, 2, 1)
  local fakeM = {
    data = fakeImage(pixels, sheetW, cellH),
    sheetW = sheetW, sheetH = cellH,
    frames = 6, cellW = cellW, cellH = cellH, columns = 6,
  }
  local guardDx, guardDy = poseOffsetFn(fakeM, 0, 2)
  eq(guardDx, 0, "poseOffset entre roles diferentes nao compensa em X")
  eq(guardDy, 0, "poseOffset entre roles diferentes nao compensa em Y")

  -- control: the same pair of indices, but from the SAME role (0 and 3,
  -- both front), still finds the real offset. Proves the guard does not
  -- block the legitimate case.
  paint(pixels, sheetW, cellW, 3, 0, 1, 1)
  local sameRoleDx, sameRoleDy = poseOffsetFn(fakeM, 0, 3)
  eq(sameRoleDx, 0, "poseOffset entre frames do mesmo role ainda acha X")
  eq(sameRoleDy, 1, "poseOffset entre frames do mesmo role ainda acha Y")
end

do
  -- fine-tooth comb, item 2: poseOffset(a,b) has to be exactly the
  -- negative of poseOffset(b,a), even with a genuine score tie on +dy and
  -- -dy. Reviewer's dataset: A (frame 0) opaque only at ly=2; B (frame 3,
  -- same role as A) opaque at ly=1 and ly=3. dy=-1 and dy=1 tie (each one
  -- aligns A with one of B's two pixels). Without canonicalizing the pair
  -- to the lower frame index before scanning, each direction would scan
  -- toward its own side and the "lower dy" rule would pick -1 in BOTH
  -- directions, breaking the symmetry; this matters because the eye
  -- compensation asks for poseOffset(refFrame, frame) and the geometry
  -- asks for poseOffset(frame, frameIndex), opposite directions of the
  -- same pair.
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
  -- v1.6.0, mandatory test 5: "the cache key changes with strength".
  -- Without this the option changes nothing on screen: it is literally the
  -- defect Colonel_Aureliano reported in v1.4.0 (changing the option in the
  -- menu changed nothing, because the mesh kept coming from the old
  -- cache).
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
  -- v1.6.0, mandatory test 5: "the cache key changes with strength".
  -- Without this the option changes nothing on screen: it is literally the
  -- defect Colonel_Aureliano reported in v1.4.0 (changing the option in the
  -- menu changed nothing, because the mesh kept coming from the old
  -- cache).
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
  -- v1.6.0, mandatory test 6: "the cache key changes with strength".
  -- Without this the option changes nothing on screen until the LRU
  -- recycles by chance, the same defect Colonel_Aureliano reported in
  -- v1.4.0. Proof by reversal: without `stepWeightPart` in cacheKey,
  -- off/low/high collapse into the SAME key and `Voxel3D.created` stays at
  -- 1, not 3.
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
  -- STEP WEIGHT, like FRONT SHAPE and TOP DOME, only exists for SLAB:
  -- CARVED builds from the visual voxel hull, without the `p()` that
  -- applies the shear. The key ignores the strength on purpose outside
  -- SLAB, so as not to duplicate identical meshes just because the menu
  -- changed level.
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
  -- v1.4.2: blinking now also happens in the walking pose when the mark
  -- transfers. paintBlinkSide paints the same texel in every frame, with no
  -- offset at all between the standing pose (2) and the walking one (5), so
  -- poseOffset(2, 5) measures (0, 0) and the profile mark transfers
  -- trivially: frame 5 has to blink exactly like frame 2. Frame 1 (back)
  -- stays without a mark, and without blinking, because that part did not
  -- change.
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
  -- Proves the measurement existed before comparing: both sides only
  -- get a value inside a withLoveTime, and `nil == nil` would satisfy the
  -- eq without anything having been measured.
  check(backOpen ~= nil and backClosed ~= nil,
        "houve medicao dos dois lados para: " .. "piscar continua nao acontecendo no frame 1")
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
  -- Proves the measurement existed before comparing: both sides only
  -- get a value inside a withLoveTime, and `nil == nil` would satisfy the
  -- eq without anything having been measured.
  check(openSig ~= nil and closedSig ~= nil,
        "houve medicao dos dois lados para: " .. "folha sem entrada lateral nao pisca de perfil")
  check(openSig ~= nil and closedSig ~= nil,
        "houve medicao dos dois lados para: " .. "folha sem entrada lateral nao pisca de perfil")
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
  -- Proves the measurement existed before comparing: both sides only
  -- get a value inside a withLoveTime, and `nil == nil` would satisfy the
  -- eq without anything having been measured.
  check(openSig ~= nil and closedSig ~= nil,
        "houve medicao dos dois lados para: " .. "folha cujo olho nao acha corpo em 4 pixels nao pisca")
  check(openSig ~= nil and closedSig ~= nil,
        "houve medicao dos dois lados para: " .. "folha cujo olho nao acha corpo em 4 pixels nao pisca")
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
  check(openSig ~= nil and closedSig ~= nil,
        "houve medicao dos dois lados para: " .. "BLINK desligado nao muda nenhum UV")
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
  check(openMesh ~= nil and closedMesh ~= nil,
        "houve medicao dos dois lados para: " .. "o cacheKey nao muda com o estado de piscada")
  eq(openMesh, closedMesh, "o cacheKey nao muda com o estado de piscada")
  eq(modules.Voxel3D.created, 1,
     "estado de piscada troca UV sem criar outra malha")
end

-- v1.4.2, "characters only blink standing still": the walking pose
-- (frames 3 and 5) starts blinking when the eye mark transfers, measured
-- sheet by sheet and pose by pose via poseOffset, never through a
-- hand-written table. Frame 3 already bit this project once in v1.4.1
-- (blink validated only on frame 0, closing the "eye" over skin on frame 3
-- because the face shifts down a row while walking); the two frame-3 tests
-- below are the most important ones in the batch.

do
  -- the walking pose blinks when the eye transfers: frame 3 is frame 0
  -- shifted down one row (the walk step), the front mark transfers, and
  -- frame 3's eye quad points to the right texel, both open and closed.
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
  -- the walking pose does NOT blink when the eye does not transfer: frame
  -- 3 has the same silhouette shifted down one row (poseOffset still finds
  -- (0, 1)), but the head was redrawn with a different tone where the eye
  -- would be. The sheet stays open-eyed in this pose, exactly like today:
  -- no half-blinking eye. This is the test that prevents the v1.4.1
  -- regression.
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
  -- Proves the measurement existed before comparing: both sides only
  -- get a value inside a withLoveTime, and `nil == nil` would satisfy the
  -- eq without anything having been measured.
  check(openSig ~= nil and closedSig ~= nil,
        "houve medicao dos dois lados para: " .. "a pose andando nao pisca quando o olho nao transfere")
  check(openSig ~= nil and closedSig ~= nil,
        "houve medicao dos dois lados para: " .. "a pose andando nao pisca quando o olho nao transfere")
  eq(openSig, closedSig, "a pose andando nao pisca quando o olho nao transfere")
end

do
  -- the front equivalent for the profile: frame 5 is frame 2 shifted down
  -- one row, the profile mark transfers, frame 5 blinks at the right
  -- coordinate.
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
  -- the profile equivalent of the non-transferring test: frame 5 with the
  -- redrawn head stays open-eyed, even with the silhouette matching.
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
  -- lorelei blinks front and profile, against the real (not synthetic)
  -- art: pixels extracted from assets/generated/sprites/lorelei.png
  -- (16x16, 6 frames), frames 0, 2, 3 and 5. Measured before writing this:
  -- the black at (5..10, 7) in frame 0 reappears black one row below in
  -- frame 3, and the black at (5, 6) in frame 2 reappears black one row
  -- below in frame 5, so both marks transfer.
  -- sha256 of the source PNG at the moment of extraction (human check):
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

  -- WHERE the UV changed, not just THAT it changed.
  --
  -- The two checks above compare the signature of the WHOLE mesh, so they
  -- would pass with the closed eye pointing at any wrong texel. And this is
  -- the only REAL ART sheet in the blink test, and the one that guards the
  -- v1.4.1 regression: closing the eye over skin.
  --
  -- TWO WRONG ATTEMPTS BEFORE THIS ONE, both noted because the second one
  -- almost turned into a bug report:
  --
  --   Searching for the eye quad by GEOMETRY failed because the conversion
  --   between the sheet row and the mesh y depends on the builder.
  --
  --   Searching by a point UV also failed, and then I dumped the mesh's
  --   UVs, looked at the first 40 IN ALPHABETICAL ORDER and saw all of
  --   them at u from 0.026 to 0.05, which is frame ZERO, with the mesh
  --   requested for frame 3. I wrote in the roadmap that either the mod
  --   was serving the wrong UV or the sheet was assembled wrong. I was
  --   wrong: those were the SIDE and TOP faces, which sample a body texel
  --   from wherever they find one, and sorting by u puts the smallest ones
  --   first. Measuring only the FRONT faces: 22 quads, u from 0.5214 to
  --   0.6151, within the frame 3 range (0.5000 to 0.6667). No defect.
  --
  --   And the point search fails for a legitimate reason: the SLAB emits a
  --   RUN, one quad per horizontal run of texels, so the open eye's quad
  --   does not have a single UV.
  --
  -- So it locates without naming the quad: counts how many FRONT faces
  -- change UV when closing. It has to be FEW, the size of the eye, not the
  -- whole mesh.
  local frenteMudou, frenteTotal = 0, 0
  withLoveTime(openTime, function()
    local aberta = modules.SpriteBillboards.mesh(def, 3)
    local uvAberta = {}
    for i = 1, #aberta.verts, 4 do
      if close(aberta.verts[i][6], 0.90) then
        frenteTotal = frenteTotal + 1
        uvAberta[i] = string.format("%.5f,%.5f", aberta.verts[i][4],
                                    aberta.verts[i][5])
      end
    end
    withLoveTime(closedTime, function()
      local fechada = modules.SpriteBillboards.mesh(def, 3)
      for i, uv in pairs(uvAberta) do
        local v = fechada.verts[i]
        if v and string.format("%.5f,%.5f", v[4], v[5]) ~= uv then
          frenteMudou = frenteMudou + 1
        end
      end
    end)
  end)
  check(frenteTotal > 10, string.format(
    "a lorelei tem faces de frente para medir (%d)", frenteTotal))
  check(frenteMudou >= 1 and frenteMudou <= 6, string.format(
    "a piscada da lorelei mexe em POUCAS faces de frente, do tamanho do olho: "
    .. "%d de %d", frenteMudou, frenteTotal))
end

do
  -- monster and bike_shop_clerk tied among three candidates in the mark
  -- detection score (no evidence); they are left without an entry on
  -- purpose and stay open-eyed in every pose, even with dark pixels at the
  -- position other sheets would use as an eye.
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

-- v1.3.0 defect 1 (SLAB): the mask now becomes the current frame's, not
-- the union of every frame. A 6-frame sheet (frameWidth=cellW forces
-- horizontal layout) with a pixel exclusive to frame 0 (lx=0), a pixel
-- exclusive to frame 3 (lx=1), and an always-opaque anchor (lx=3) just to
-- keep the mesh alive in every frame.
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

  -- If `at()` regressed to `m.mask` (the union), the pixel exclusive to
  -- frame 0 would leak into frame 3 and the assertion above would fail.
  -- This one covers the opposite direction: the pixel exclusive to frame 3
  -- has to appear in it, it cannot be cut off by mistake.
  check(frontFaceZAt(f3, 1, 2, 0, 1) ~= nil,
        "geometria SLAB nao usa o frame errado no lugar do frame corrente (pixel proprio do frame 3 aparece)")
  -- In a 6-frame sheet, roleForFrame(3, 6) = 0, so role 0's color
  -- reference is frame 0 itself (referenceFramesForRole). If `at()` were
  -- swapped to query that reference instead of the requested frame, the
  -- pixel exclusive to frame 3 would disappear (frame 0 does not have
  -- it), and this assertion would catch it.
  check(frontFaceZAt(f0, 1, 2, 0, 1) == nil,
        "geometria SLAB nao usa o frame errado no lugar do frame corrente (frame 0 nao tem o pixel do frame 3)")

  local sideAtF0 = sideFaceUvAt(f0, 0, 0, 0, 1)
  local sideAtF3 = sideFaceUvAt(f3, 0, 0, 0, 1)
  check(sideAtF0 ~= nil,
        "face lateral SLAB some quando o pixel some no frame (existe enquanto o pixel existe)")
  check(sideAtF3 == nil,
        "face lateral SLAB some quando o pixel some no frame")
end

-- v1.3.0 defect 2 (SLAB): X now becomes relative to the sprite's cell,
-- not to the opaque bbox. First column (lx=0) entirely transparent; the
-- art starts at lx=1, and the mesh has to preserve that offset instead of
-- re-anchoring at X=0 the way the opaque bbox would.
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

-- v1.3.0 defect 2b (SLAB): the Y axis has the same rule as X. The host
-- pivots the lean on the ground, so y = 0 is the BOTTOM row of the CELL,
-- not the lowest opaque row of the art. A two-row cell with art only in
-- the top row: the mesh has to float one pixel above the ground, the way
-- the original card does, instead of re-anchoring the feet on the art
-- itself. That is 8 of the 67 real sheets, poke_ball.png among them, by 2
-- pixels.
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

-- v1.3.0 defect B (SLAB): vertically adjacent side faces can merge into
-- a single face when the resolved sampling is exactly the same. The
-- infinite height here is intentional: in the stub, it makes both texel
-- centers land on the same numeric V without changing the cell's finite
-- geometry.
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

-- v1.3.0 defect 2 (CARVED): the same X anchor as SLAB. The hull uses
-- the three views, but the emitted space still has to be the sprite's
-- cell space. First column transparent in every view; an opaque bbox
-- would re-anchor the mesh at X=0.
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

-- v1.3.0 defect A (CARVED): the front/back mirror uses the same cell
-- axis as the per-role rotation. The sheet is asymmetric within the cell:
-- the extra column at lx=5 would move the bbox axis to 6 and erase the
-- back role's legitimate voxel if `mirrorX` were not `cellW - 1 - lx`.
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
  -- The old value, X 1..2, was the logical column before role 1's
  -- rotation: it passed because the hull mirrored X once in `solid` and
  -- again in p(). The screen needs to receive column 4..5, where frame 1
  -- has art.
  check(close(b.minX, 4) and close(b.maxX, 5),
        "espelho CARVED posiciona o role de costas no mesmo eixo da celula")
end

-- Role 1 needs an asymmetric sheet to expose the double mirror: on a
-- symmetric sheet, validating one column and drawing the other produces
-- the same result. Here the back frame has art at lx=4; role 1 also has
-- to appear on screen column 4, because p() already does the single
-- presentation mirror.
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

-- v1.3.0 defect 2b (CARVED): the same Y anchor as SLAB. An empty
-- baseboard in the cell has to stay empty in the hull too, instead of
-- pulling the art down to the ground.
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
  -- The old X, 1..2, was the front's logical space leaking into the
  -- assertion. In role 1 p()'s rotation presents that voxel in the back
  -- column, so the absolute position preserved in the cell is 2..3.
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

-- v1.3.0 defect 3 (SLAB and CARVED, the guard runs in voxelMesh before
-- both): first person falls back to the original card instead of the
-- solid, because the host's first-person shader moves vertices
-- individually and a volume crosses the near plane.
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

-- v1.4.2, "a third-party mod brings down the whole game's voxel mode"
-- (AngelusRole): the host concatenates `def.image .. "#" .. frame` with no
-- type guard (DramaticShapeVoxelMod/lib/SpriteBillboards.lua:65); a nil
-- frame from ANY entity mod throws there, with no pcall, inside the host's
-- draw loop, and brings down the game's voxel mode entirely until a
-- restart. The default test stub (`original`) never throws, so the tests
-- below install an "original" that reproduces the real host's arithmetic,
-- otherwise they would measure the wrong thing and pass both before and
-- after the fix.

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
  -- this is the likely path of the report: def with a valid image, nil
  -- frame. depth=off forces the first of the five points with no pcall,
  -- before any internal frame normalization happens.
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
  -- test that represents Angelus's report: forces the host's mocked
  -- original to throw (here via the first-person path, one of the five
  -- points) and proves the wrapper returns nil, it does not propagate the
  -- exception.
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
  -- the warning fires only once: the same failure path, called three
  -- times.
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

-- v1.4.2, AngelusRole/Tyler Durden/TwoTracks: the STATUS row. The tests
-- below cover the four patch states (NO HOST already covered above,
-- ACTIVE, REPLACED, FIRST PERSON) and the three draw outcomes TwoTracks
-- exposed (mask_failed, build_failed, exception in the outer wrapper),
-- including the requirement not to get stuck in error over a single bad
-- sheet (item C) and log latching per distinct cause (item D).

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
  -- this is the test that represents TwoTracks's report: another mod
  -- swaps SpriteBillboards.mesh AFTER our patch, without calling
  -- shadowQuad nor writing to cardBlend (the two hypotheses the
  -- investigation ruled out).
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
  -- the existing rows keep appearing in the same order, after STATUS
  -- and LIFE.
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

  -- PRESSING A ON A READ-ONLY ROW CANNOT CLOSE THE MENU.
  --
  -- OptionsMenu:update (src/ui/OptionsMenu.lua:549-566) resolves A, left
  -- and right in the same branch, in this order: `activate`, else `step`,
  -- else, if it was A, treats it as CANCEL and pops the menu. STATUS and
  -- LIFE have `value` and nothing else, so they fell into the third case:
  -- A on top of them used to close the whole options screen. And A is the
  -- first key anyone presses on a row they do not recognize, which is
  -- exactly the audience for the STATUS row.
  --
  -- The test ties down the engine's CONTRACT, not our implementation:
  -- every row that offers `value` without `step` needs `activate`,
  -- otherwise the engine confuses it with CANCEL.
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
  -- a mask that fails turns into an error STATUS and logs once with the
  -- message. def without image: maskFor returns nil without throwing, on
  -- every call, so consecutiveDrawFailures climbs on every call, not just
  -- the first.
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
  -- a mesh that fails turns into an error STATUS and logs once with the
  -- original message. A broken Voxel3D.newMesh forces buildSlabMesh to
  -- throw at the end of construction, with maskFor already having worked.
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
  -- an exception in the outermost wrapper turns into an error STATUS and
  -- logs once with the original message. Breaks cacheKey (an upvalue of
  -- voxelMesh) to force an exception that no internal pcall in voxelMesh
  -- catches, only the wrapper.
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
  -- item C: a sprite that fails in the middle of several that work does
  -- not leave STATUS stuck in error. One bad sheet for every four good
  -- ones, 20 draws total (4 bad, 16 good): within ANY window of 8
  -- consecutive draws of this pattern there are at most 2 failures, 25%,
  -- well below the 50% that escalates STATUS.
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
  -- fine-tooth comb, item 1: a counter of CONSECUTIVE failures can be
  -- defeated by interleaving (the player's sprite draws fine every frame,
  -- an NPC from a broken source fails interleaved, and no run of failures
  -- ever reaches the limit, even with half the screen falling back to a
  -- flat card). Strict good/bad alternation, 16 draws (8 good, 8 bad): the
  -- window of the last 8 ends up half failures, and STATUS escalates even
  -- with no unbroken run of failures.
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
  -- distinct causes (two sheets broken in different ways) each log their
  -- own turn, they do not collapse into one.
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
  -- fine-tooth comb, item 2: the STATUS label shows the window's
  -- DOMINANT cause, not the most recent one. Seven mask_failed failures
  -- and one exception last (on a different sheet): the label has to be
  -- MASK ERROR (the cause of 7 of the window's 8 draws), not DRAW ERROR
  -- (the last one, but only 1 of 8). The label is this row's product: it
  -- is what tells the player what is happening without needing to ask for
  -- a log.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle, { depth = 2 }))
  local badDef = { frames = 6 } -- no image: mask_failed every time
  for _ = 1, 7 do
    modules.SpriteBillboards.mesh(badDef, 0)
  end
  -- breaks cacheKey (an upvalue of voxelMesh) just to force an exception
  -- on the eighth draw, on a sheet different from the first seven.
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

-- v1.6.0: FRONT SHAPE. Volume on the SLAB's front face in pixel-aligned
-- steps, a new menu option with default OFF. The five tests below are the
-- mandatory ones from the round's spec; the row/step/persist and the two
-- cacheKey variants (SLAB separates, CARVED ignores) were already covered
-- further above, together with the rows and cacheKeys of the other
-- options.

do
  -- mandatory test 1: "with the option off, the mesh is byte for byte
  -- today's". A run of width 6 (well above the step threshold) still
  -- comes out as a SINGLE quad, at the usual OBJ_SHADE.front shade,
  -- whether with front_shape = "off" explicit or without the key
  -- (default). If the step leaked under OFF, this run would break into
  -- several quads or change shade.
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
  -- mandatory test 2: "a 2-pixel run does not split -- exact count".
  -- The same row has two runs separated by a gap: one of 2 pixels (1 to
  -- 2) and one of 6 pixels (6 to 11, well above the step threshold). The
  -- test proves excluding short runs is a RULE (width < 3), not just
  -- "nothing splits": the 6-pixel run has to split into steps and the
  -- 2-pixel one, on the same sheet with the same option on, does not.
  -- There is no "middle" pixel distinct from the two edges in a width-2
  -- run: splitting would only cost a quad with no possible step.
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
  -- mandatory test 3: "the shade is symmetric around the run's center".
  -- Odd-width run (5 pixels, 4 to 8): the left edge (pixel 4) and the
  -- right edge (pixel 8) have to come out at the SAME shade, and the
  -- center (pixel 6) has to come out lighter than the edges, otherwise
  -- the step did not really happen.
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
  -- v1.6.0: the same symmetry holds mirrored (mask drawn on the right
  -- side of the cell instead of the left), proving the shade depends only
  -- on the center of the run ITSELF (a and b), never on an absolute
  -- screen coordinate nor on being on the east or west side of the cell.
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
  -- mandatory test 4 (pose 1 of 4: front, standing, frame 0): blinking
  -- keeps working with FRONT SHAPE on. The eye keeps its own quad
  -- (main.lua ~1417-1428), with flat shade, never stepped; the 6-pixel
  -- segment before it splits into steps around it.
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
  -- mandatory test 4 (pose 2 of 4: front, walking, frame 3). Frame 3 is
  -- frame 0 shifted down one row, the same walk step the rest of the
  -- suite already uses for BLINK.
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
  -- mandatory test 4 (poses 3 of 4 and 4 of 4: profile standing, frame
  -- 2, and profile walking, frame 5). paintBlinkSide already produces a
  -- 3-pixel segment after the eye (6 to 8), right at the step threshold,
  -- with no new fixture needed.
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
  -- FINDING (fine-tooth comb, fresh eyes): emitFrontRun computed
  -- `center` and `half` from the SEGMENT received per call (a, b), not
  -- from the whole opaque run (lx, lx2). The loop that cuts the run at
  -- the eyes (main.lua, right below emitFrontRun's definition) calls
  -- emitFrontRun once per piece, so each piece was treated as if it were
  -- a whole run, with its own "darkest edge" -- including on the pixel
  -- that is merely glued to the eye and not near any real silhouette
  -- edge. This drew a dark ring around every eye: it applies to any sheet
  -- with an eye mark, in every pose that blinks, and is independent of
  -- the BLINK option, because the isEye cut never queries blinkValue --
  -- that is why this test does not turn on BLINK. Neither the
  -- silhouette, nor the quad count, nor the tonal structure catch this:
  -- only the shade of specific pixels comes out wrong, which is why no
  -- earlier test found the defect.
  --
  -- paintBlinkFaceWide paints the whole row (lx 0 to 15) as a single
  -- opaque run, with the "red" eyes (EYE_MARKS.red, lx 6 and 9) cutting
  -- the CALLS to emitFrontRun into three pieces without cutting the run
  -- itself. Forces 0.22 (HIGH), the same value from the reviewer's repro.
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

-- v1.6.0: TOP DOME. Volume on the SLAB's TOP face in pixel-aligned
-- steps, a new menu option with default OFF. The six tests below are the
-- mandatory ones from the round's spec; the row/step/persist and the two
-- cacheKey variants (SLAB separates, CARVED ignores) were already covered
-- further above, together with the rows and cacheKeys of the other
-- options. All sheets paint only row ly = 7 (the same ly FRONT SHAPE
-- already uses), so no row above it exists and every painted pixel comes
-- out as a top face, with no need for a new fixture per test.

do
  -- mandatory test 1: "with the option off, the mesh is byte for byte
  -- today's". A run of width 6 (above the step threshold) still has ALL
  -- the top pixels at the same shade -- the usual topShade() -- whether
  -- with top_dome = "off" explicit or without the key (default). If the
  -- step leaked under OFF, the edge pixels would come out darker than
  -- the center one.
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
  -- mandatory test 2: "the quad count does not change with the option
  -- on" -- which is what sets this change apart from the previous one.
  -- FRONT SHAPE ADDS quads by splitting the front run when on (from 1
  -- quad to up to 6); the top face already came out per pixel EVEN
  -- BEFORE this feature (the loop `for sx = lx, lx2 do if not at(sx, ly
  -- - 1)`), so turning on TOP DOME only changes the shade of a quad that
  -- already existed, never adds a new one.
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
  -- mandatory test 3: "the top shade is symmetric around the run's
  -- center". Odd-width run (5 pixels, 4 to 8): the left edge (pixel 4)
  -- and the right edge (pixel 8) have to come out at the SAME shade, and
  -- the center (pixel 6) has to come out lighter than the edges,
  -- otherwise the step did not really happen.
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
  -- v1.6.0: the same symmetry holds mirrored (mask drawn on the right
  -- side of the cell instead of the left), proving the shade depends only
  -- on the center of the run ITSELF (a and b: the row's lx, lx2), never
  -- on an absolute screen coordinate nor on being on the east or west
  -- side -- the X-symmetry restriction the spec requires.
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
  -- mandatory test 4: "a 2-pixel run gets no step". The same row has
  -- two runs separated by a gap: one of 2 pixels (1 to 2) and one of 6
  -- pixels (6 to 11, above the step threshold). The short run has to come
  -- out at the SAME shade on or off (there is no "middle" pixel distinct
  -- from the two edges in a width-2 run: splitting would only cost a quad
  -- with no possible step); the 6-pixel one, on the same sheet with the
  -- same option on, has to genuinely step -- a control proving the
  -- exclusion is a RULE (width < 3), not "nothing steps".
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

-- mandatory test 5 ("the cache key changes with strength") is already
-- covered together with the other cacheKeys, further above (cacheKey
-- separates TOP DOME even without clearing the cache, off/low/high).

do
  -- mandatory test 6: "TOP EDGE and TOP DOME coexist". Both touch the
  -- shade of the SAME top face; proves the order of application (TOP
  -- EDGE first, as the BASE that topShadeDomo reads from topShade(); TOP
  -- DOME steps that base, never replaces it) and that turning one on
  -- does not cancel the other.
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
  -- Same expression, same order of operations topShadeDomo uses
  -- internally (base * (1 - domoStep * level / (TOP_DOME_STEPS - 1)),
  -- with level = 2 for a 6-run's edge pixel): proves the ORDER of
  -- application, TOP EDGE as the base multiplied by TOP DOME, not the two
  -- competing on top of the host's raw shade.
  local multiplier = 1 - 0.30 * 2 / 2
  check(close(bothEdge, edgeOnlyCenter * multiplier),
     "TOP DOME multiplica a base que TOP EDGE ja escureceu, nunca a substitui")
end

-- v1.6.0: STEP WEIGHT. Shear on Z proportional to the SLAB's height,
-- only on walking frames, so the solid follows the step the art already
-- gives on its own. The seven tests below are the mandatory ones from the
-- round's spec, in the same order; the row/step/persist and the two
-- cacheKey variants (SLAB separates, CARVED ignores) were already covered
-- further above, together with the rows and cacheKeys of the other
-- options. The last two blocks go beyond the mandatory ones: they cover
-- the restriction "confirm which frames are walking frames from the
-- code, instead of assuming 3, 4 and 5", with a 4-frame sheet (index 3
-- exists but is not a walking frame) and an 8-frame sheet (index 6 folds
-- back into the standing bucket via frame % 3, the same bucket
-- carvedFrames already uses for CARVED).
--
-- Fixture common to tests 1 through 5: a single-pixel column at lx = 7,
-- painted at three isolated heights (ly = 15 the foot, local y 0..1; ly =
-- 8 the middle, local y 7..8; ly = 0 the top, local y 15..16, with cellH =
-- 16), replicated across all six frames so the standing pose (frame 0)
-- and the walking one (frame 3) start from the same art.

do
  -- mandatory test 1: "with the option off, the mesh is byte for byte
  -- today's". Read on the WALKING frame (3), the only one where STEP
  -- WEIGHT would have anything to do -- if the shear leaked under OFF,
  -- that is where it would show up.
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
  -- mandatory test 2: "the standing pose does not move with the option
  -- on -- only the walking one changes". Both halves are needed to prove
  -- by reversal: a broken gate that sheared EVERY frame (not just
  -- walking) would pass the "walking changes" half but break the
  -- "standing does not change" half; an implementation that never
  -- applied any strength at all would pass the "standing does not
  -- change" half but break "walking changes".
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
  -- mandatory test 3: "the offset is proportional to height -- the
  -- foot stays put, the top moves the most". Same three-height fixture,
  -- read on the walking frame (3) with STEP WEIGHT: HIGH (strength 0.5).
  -- Exact values, not just "greater than": the formula (z += strength * y
  -- / cellH) is linear by construction, so foot, middle and top have to
  -- hit the exact number, not just the order.
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
  -- mandatory test 4: "no X coordinate changes" -- the guarantee against
  -- the host's mirroring, which only flips the sign on X. Uses the whole
  -- mesh (front, back, sides, top, bottom), not just the three front
  -- vertices measured in the previous test.
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
  -- mandatory test 5: "the quad count does not change -- this moves a
  -- vertex, it does not create a face". Same fixture as the previous test.
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

-- mandatory test 6 ("the cache key changes with strength") is
-- already covered together with the other cacheKeys, further above
-- (cacheKey separates STEP WEIGHT even without clearing the cache,
-- off/low/high, and ignores the strength when SHAPE is CARVED).

do
  -- mandatory test 7: "a 1-frame sheet does not break". A 1-frame
  -- sheet has no walking pose (m.frames < 6), so `andando` (walking) comes
  -- out false from the frame bucket, and the mesh comes out identical
  -- with the option on or off -- not just "does not throw".
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
  -- extra restriction (not numbered in the spec, but explicit: "confirm
  -- which [frames] are, from the code, instead of assuming 3, 4 and 5"). A
  -- 4-frame sheet has index 3 as a VALID frame, but not as an established
  -- walking pose -- the six-frame bucket (standing 0/1/2, walking 3/4/5)
  -- only applies from six frames on. A naive implementation that checked
  -- only `frame == 3` (the guess the spec explicitly asks not to make)
  -- would have applied the shear here; the `m.frames >= 6` guard is what
  -- tells the two apart.
  local cellW, cellH = 16, 16
  local sheetW = cellW * 4
  local pixels = {}
  for frame = 0, 3 do
    paint(pixels, sheetW, cellW, frame, 7, 0, 1) -- top: the point most sensitive to an undue shear
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
  -- extra restriction, second half: a frame above 5 folds into a
  -- bucket of 3 (frame % 3), the same bucket carvedFrames already uses for
  -- CARVED (main.lua), so it never lands in the "walking" bucket (position
  -- 3) even on a sheet with six frames or more. Frame 6 on an 8-frame
  -- sheet: 6 % 3 = 0, the front STANDING bucket, not the walking one.
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
-- LIFE: BREATH, SWAY, MOTION LAG (new channel on top of Voxel3D.draw)
-- ========================================================================
--
-- The host only offers the second patch point when makeVoxelHandle
-- receives withDraw=true. The tests below cover the channel installing,
-- the LIFE row reporting each state, the three menu rows only appearing
-- with the channel, and the matrix contract (only column 2 changes, the
-- feet stay put, the mirror flips the shear, per-sheet personality, first
-- person, sunModel, and the phase following the clock instead of
-- position).

do
  -- item 1: with a host that draws, the channel installs and swaps the
  -- Voxel3D.draw field for this mod's function.
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
  -- item 2: without a channel (host without draw), LIFE says NO CHANNEL
  -- even with a valid host and patch done.
  local pixels = {}
  pixels[0] = 1
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16)
  local mod = loadWith(makeMod(handle))
  eq(lifeRowValue(mod), "NO CHANNEL",
     "host sem Voxel3D.draw: LIFE diz NO CHANNEL")
end

do
  -- item 2: with a channel and the three options off (default), LIFE
  -- says OFF.
  local pixels = {}
  pixels[0] = 1
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  local mod = loadWith(makeMod(handle, soEsta()))
  eq(lifeRowValue(mod), "OFF",
     "host com canal, as tres opcoes desligadas: LIFE diz OFF")
end

do
  -- item 2: only BREATH on.
  local pixels = {}
  pixels[0] = 1
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  local mod = loadWith(makeMod(handle, { breath = 0.020 }))
  eq(lifeRowValue(mod), "BREATH", "so BREATH ligado: LIFE diz BREATH")
end

do
  -- item 2: all three on together, in the order BREATH+SWAY+LAG.
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
  -- item 2, FOOTFALL: only FOOTFALL on, the LIFE row says STEP (the
  -- short label lifeStatusValue uses for footfall, main.lua).
  local pixels = {}
  pixels[0] = 1
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  local mod = loadWith(makeMod(handle, soEsta({ footfall = 0.35 })))
  eq(lifeRowValue(mod), "STEP", "so FOOTFALL ligado: LIFE diz STEP")
end

do
  -- item 2, FOOTFALL: all four on together, in the order
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
  -- item 3: without a channel, the three life rows do not appear in
  -- the menu.
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
  -- CAMERA FIT: the measured table, and what the row promises.
  --
  -- The per-step recommendation came from the harness, not from taste:
  -- for each camera, the largest thickness that still keeps today's art
  -- proportion (rung 35 with depth 3, which gives 73.4%). It comes out 1,
  -- 3, 5, 10.
  --
  -- The test ties down the two ends that could break without anyone
  -- noticing: the table staying monotonic (a flatter camera can never ask
  -- for MORE thickness, or the logic inverted) and the row being an
  -- ACTION and not a cycle, because a row with value and no step nor
  -- activate gets treated as CANCEL by the engine.
  local pixels = {}
  pixels[0] = 1
  for _, caso in ipairs({
    { angulo = 15, esperado = 1 }, { angulo = 35, esperado = 3 },
    { angulo = 50, esperado = 5 }, { angulo = 75, esperado = 10 },
    -- between steps, the preset picks the closest one
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
  -- THE DEFAULTS THE PLAYER GETS WITHOUT CHOOSING ANYTHING.
  --
  -- No test covered this, and the gap showed up in the most expensive way
  -- possible: changing BLINK and BREATH to on broke eight checks at once,
  -- all from tests that were about SOMETHING ELSE and only depended on
  -- the default out of laziness. Now the defaults have an owner: this
  -- block. Any change to them fails HERE, which is where the decision
  -- lives, and nowhere else.
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
  -- Turned on by Kim's decision on 2026-08-09: both had already been
  -- seen and approved by the community, so shipping them off became
  -- shipping less than the person would have chosen.
  eq(valor.BLINK, "ON", "default de BLINK: ON, a comunidade aprovou a feature")
  eq(valor.BREATH, "SUBTLE",
     "default de BREATH: SUBTLE, o menor nivel que ainda faz diferenca")
  -- Starts at CARD, which has been the behavior since v1.3.0. That
  -- players have ASKED for the solid in first person counts as a
  -- request, not as approval: nobody has seen it yet.
  eq(valor["FIRST PERSON"], "CARD",
     "default de FIRST PERSON: CARD, ninguem viu o solido nessa camera ainda")
  -- These stay off: they change the READING of the shape or of the
  -- movement in a way nobody has judged yet.
  for _, chave in ipairs({ "FRONT SHAPE", "TOP DOME", "STEP WEIGHT", "SWAY",
                           "MOTION LAG", "FOOTFALL", "ATTENTION", "PART LAG" }) do
    eq(valor[chave], "OFF", "default de " .. chave .. ": OFF")
  end
end

do
  -- item 3: with a channel, the three rows appear after STEP WEIGHT, in
  -- this order, with the right labels.
  local pixels = {}
  pixels[0] = 1
  local handle = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  local mod = loadWith(makeMod(handle))
  local rows = {}
  mod._rows["ui.options.rows"](function(_, r) return r end, {}, rows)
  eq(#rows, 19,
     "com canal, dezenove rows: STATUS, LIFE, CAMERA FIT e as dezesseis opcoes")
  eq(rows[12].label, "STEP WEIGHT", "STEP WEIGHT continua na mesma posicao")
  eq(rows[13].label, "BREATH", "BREATH aparece logo depois de STEP WEIGHT")
  eq(rows[14].label, "SWAY", "SWAY aparece depois de BREATH")
  eq(rows[15].label, "MOTION LAG", "MOTION LAG aparece depois de SWAY")
  eq(rows[16].label, "FOOTFALL", "FOOTFALL aparece depois de MOTION LAG")
  -- The FIRST PERSON row only got a test after an audit pointed out it
  -- was the only option in the mod with no MENU coverage: it had
  -- behavior, not a row. And that is how the in-game gate's inventory
  -- went stale without anyone noticing.
  eq(rows[17].label, "ATTENTION", "ATTENTION aparece depois de FOOTFALL")
  eq(rows[18].label, "PART LAG", "PART LAG aparece depois de ATTENTION")
  eq(rows[19].label, "FIRST PERSON", "FIRST PERSON aparece depois de PART LAG")
end

do
  -- item 4: with the three options off, the draw passes straight
  -- through: the original receives the SAME model table, by identity.
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
  -- item 5: a mesh this mod never produced passes straight through,
  -- even with BREATH on.
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
  -- item 6: only BREATH on changes only column 2 (indices 2, 6, 10,
  -- 14), scaling by the same factor across the four rows; the caller's
  -- table is not mutated.
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
  -- item 7: the feet do not move. The mesh has local y = 0 at the
  -- ground, and local (0,0,0) lands exactly on the translation (column 4:
  -- indices 4, 8, 12, 16), which the column-2 formula never touches.
  -- Tested with the three options on together, the maximum shear case.
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
  -- item 8: the mirror flips the shear. Same position (px, py)
  -- recovered both ways (model[1] = 1 direct, model[1] = -1 with
  -- model[4] offset by +16), same clock: kx's contribution (the term
  -- column 2 gains besides the scale, recovered by dividing by model[1]
  -- itself) comes out with the opposite sign.
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
  -- item 9: per-sheet personality. poke_ball has breath = 0: even with
  -- BREATH at STRONG, column 2 comes out identical. A sheet absent from
  -- the table uses multiplier 1 and changes normally.
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
  -- item 10: model[1] outside of +-1 (first-person yaw blending) makes
  -- it pass straight through, even with BREATH on.
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
  -- item 11: sunModel receives the same scale s as the body, in a new
  -- table. Without sunModel, it stays nil.
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
  -- item 11, extra: sunModel always uses kz = 0 (main.lua says this
  -- explicitly), even when the body has kz != 0 because of MOTION LAG. Two
  -- identical runs, only sunModel's z component changes; if kz leaked into
  -- sunModel, changing that component would change the result along with
  -- it.
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
  -- item 12: the phase advances with the CLOCK, not with position. Same
  -- character, same position, two different clocks: the scale changes.
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
  -- item 12, continued: the same phase, advanced by the same amount of
  -- time, holds both standing still and having walked a bit within the
  -- same 16px cell: the new position does NOT seed a phase from zero.
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
  -- item 13: two instances of the same sheet, same clock, very
  -- different positions: different scales (out of phase with each other).
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
  -- item 14: the reflection in the water. The host draws the same
  -- character twice per frame with the SAME matrix; the second call cannot
  -- advance anything new, so both outputs come out equal.
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
-- LIFE: MAGNITUDE (not just "did it change?", but "how MUCH did it
-- change?")
-- ========================================================================
--
-- The defect that motivated this block: MOTION LAG was shearing almost 45
-- degrees at the old 0.70 level (it was missing dividing by LIFE_CELL, the
-- way SWAY already did), and the 465 checks above plus the eight in-game
-- checks passed just the same, because all of them asked "did it change?"
-- and none asked "how much did it change?". What caught it was watching a
-- clip. The tests below read the real MAGNITUDE in world pixels from the
-- matrix output, using lifeProbeModel (which isolates s, kx and kz each
-- into its own row, see the function's comment).
--
-- The contract in one sentence: the menu number is the HEAD's displacement
-- in world pixels, and the head sits at y = 16 in the mesh's local space
-- (the shear is proportional to y, so the maximum displacement, at y =
-- 16, is |kx| * 16).

do
  -- item 1: BREATH's scale matches the chosen level. The maximum
  -- deviation of s from 1, sweeping a whole clock cycle, has to be the
  -- level's own value (0.010 SUBTLE, 0.020 NORMAL, 0.035 STRONG), with 5%
  -- slack. Also checks that STRONG comes out 3.5x SUBTLE, the ratio no
  -- earlier test checked.
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
      -- BREATH_PERIOD (main.lua) is 3.1s; 400 frames at 1/60 cover almost
      -- 6.7s, more than two whole cycles, without depending on the
      -- constant's exact value.
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
  -- item 2: SWAY's head displacement (|kx| * 16 at the cycle's peak)
  -- matches the chosen level, 5% slack.
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
      -- SWAY_PERIOD (main.lua) is 6.2s; 500 frames at 1/60 cover almost
      -- 8.3s, more than one whole cycle.
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
  -- item 3: MOTION LAG, the test that would have caught the defect.
  -- Character walking 1 px per frame (16 px over 16 frames, the game's
  -- walk speed), clock advancing 1/60 per frame, 40 frames: plenty of
  -- time for the spring to settle. The peak of |kx| * 16 has to land near
  -- the level, with slack for the spring's overshoot (~8%, documented in
  -- main.lua): accepts up to 1.4x, fails above that. With the old bug
  -- (multiplying by LIFE_CELL instead of dividing) the peak would come
  -- out an order of magnitude larger (16x larger, ~19px instead of
  -- ~1.3px at the NORMAL level) and the 1.4x test would fail.
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
  -- item 4 (and item 9 of the FOOTFALL round): the absolute safety
  -- ceiling, independent of level and personality. All FOUR options at
  -- maximum (BREATH STRONG, SWAY NORMAL, MOTION LAG NORMAL, FOOTFALL
  -- NORMAL) on LIFE_PERSONALITY's most aggressive sheet (main.lua):
  -- swimmer has the highest breath (1.10) + sway (1.60) = 2.70 sum in the
  -- table (the second highest, fisher, comes in at 1.05 + 1.25 = 2.30);
  -- MOTION LAG and FOOTFALL have no custom entry for us, so they carry
  -- multiplier 1 on any character sheet, the same across all of them.
  -- Walks diagonally for 500 frames (covers the whole BREATH and SWAY
  -- cycle, keeps LAG's spring excited the whole time, and passes through
  -- dozens of FOOTFALL stride cycles) and keeps the peak of all four,
  -- each in world pixels. `sx` (the X scale FOOTFALL introduced) is read
  -- from out[1] / model[1], the same as the foot contract (further
  -- below).
  --
  -- item 16: the four maxima below used to be written by hand, and a
  -- hand-written number keeps testing an old ceiling forever if somebody
  -- raises it in the menu (main.lua, OPTIONS) without touching this file:
  -- exactly the shape of the MOTION LAG defect this test exists to catch,
  -- 465 checks that all asked "did something change" and none asked "by
  -- how much". So the maxima are read back from the schema the mod itself
  -- registers (mod.options:define, captured on mod._schema above) instead:
  -- for each life option, the largest numeric level it offers.
  local function maxNumericLevel(schema, key)
    local max = nil
    for _, row in ipairs(schema) do
      if row.key == key then
        for _, level in ipairs(row.choices) do
          if type(level[2]) == "number" and (max == nil or level[2] > max) then
            max = level[2]
          end
        end
      end
    end
    return max
  end
  local probePixels = {}
  probePixels[0] = 1
  local probeHandle = makeVoxelHandle("1.6.0", probePixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  local probeMod = loadWith(makeMod(probeHandle))
  -- WHICH OPTIONS GET SWEPT, and the default is now INCLUDE.
  --
  -- item 16 fixed the NUMBERS: the maxima are read from the schema instead of
  -- being copied here by hand. It did not fix the LIST. These four keys were
  -- written out, and by the time ATTENTION and PART LAG shipped on this
  -- branch, the "absolute ceiling no future level can break" was sweeping four
  -- of six life options. The derived number was right and the set it applied
  -- to was stale, which is the same defect one level up from the one item 16
  -- closed.
  --
  -- So the set is derived too: every option that offers a numeric level, minus
  -- the ones that move a VERTEX rather than the draw matrix. Those are named
  -- explicitly below, which flips the failure mode: a new option is swept
  -- unless somebody writes down why it is exempt, instead of escaping the
  -- ceiling by nobody remembering this file exists.
  local NOT_LIFE = {
    depth = true,        -- extrudes the mesh; no matrix term
    front_shape = true,  -- shade only, geometry identical at any strength
    top_dome = true,     -- shade only
    step_weight = true,  -- shears a vertex at build time, not at draw time
  }
  local ceilings = {}
  for _, row in ipairs(probeMod._schema) do
    if not NOT_LIFE[row.key] then
      local m = maxNumericLevel(probeMod._schema, row.key)
      if m then ceilings[row.key] = m end
    end
  end
  local sweptCount = 0
  for key in pairs(ceilings) do
    sweptCount = sweptCount + 1
    assert(ceilings[key] ~= nil,
      "safety ceiling: the schema offers a numeric maximum for " .. key)
  end
  -- If this ever reads fewer options than the mod has life levels, the sweep
  -- shrank without anyone noticing, which is exactly how it got to four.
  check(sweptCount >= 6,
    "safety ceiling: sweeps every life option with a numeric level, not a hand-written subset")

  -- WHAT THIS CEILING CAN AND CANNOT BOUND, both measured rather than argued.
  --
  -- It bounds AMPLITUDE. Raising ATTENTION's top level from 1.0 to 3.5 now
  -- trips "|kx| * 16 stays under 3px"; 2.0 does not, which is right, since 2
  -- is under the 3px bar. Before the eye was added above, neither did.
  --
  -- It cannot bound a DELAY, and PART LAG is a delay in seconds. Raising its
  -- top level from 0.16 to 2.0 changes when the head arrives, not how far it
  -- goes, so no amplitude assertion here reacts; what catches that is PART
  -- LAG's own pair of tests, which fail because the bands stop differing.
  -- Recorded so nobody reads "swept" as "bounded" for every option alike.

  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handle, ceilings))
  local mesh = modules.SpriteBillboards.mesh({ image = "swimmer.png", frames = 1 }, 0)

  -- AN EYE STANDING NEXT TO THE CHARACTER, or ATTENTION contributes nothing
  -- and sweeping it proves nothing.
  --
  -- Adding `attention` to the swept set above was necessary and not
  -- sufficient: ATTENTION only leans when somebody is close, and this harness
  -- never placed anyone. Measured while writing this, the option's level was
  -- raised from 1.0 to 3.5 and every ceiling assertion still passed, because
  -- the term was multiplied by an attention that never woke up. A branch
  -- nothing exercises looks exactly like one that works.
  --
  -- 10 world units is the distance ATTENTION's own tests use for "close".
  -- Nothing else in this sweep reads the eye, so this only adds the one term
  -- that was missing.
  modules.Voxel3D.eye = { 10, 0, 0 }

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
  check(maxS < 3, "safety ceiling: |s - 1| * 16 stays under 3px even at maximum")
  check(maxKx < 3, "safety ceiling: |kx| * 16 stays under 3px even at maximum")
  check(maxKz < 3, "safety ceiling: |kz| * 16 stays under 3px even at maximum")
  check(maxSx < 3, "safety ceiling: |sx - 1| * 16 stays under 3px even at maximum")
end

do
  -- item 5: personality SCALES the amplitude, it does not just turn it
  -- on and off. guard has breath = 0.80 in LIFE_PERSONALITY; a sheet
  -- absent from the table uses multiplier 1. Both have the same rate
  -- (guard: 1.00 in the table; absent: default 1) and the same position
  -- (0, 0), so the phase advances the same in both and the ratio between
  -- the amplitudes holds at any instant where the sine is not near zero
  -- -- sweeps the clock and compares at the instant of highest amplitude
  -- for the sheet without personality.
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
-- LIFE: FOOTFALL (fourth option, the first one that touches column 1
-- and column 4 of the matrix)
-- ========================================================================
--
-- Item 1 (the row appearing and disappearing with the channel, count at
-- 15, order after MOTION LAG) is already covered in the first two blocks
-- of the "LIFE: BREATH, SWAY, MOTION LAG" section above (and the STATUS
-- line gained two extra blocks right after "the three on together",
-- covering STEP alone and all four together). The absolute ceiling (item
-- 9) was folded directly into the ceiling test already in the MAGNITUDE
-- section, which now runs with FOOTFALL NORMAL on and also measures
-- |sx - 1| * 16.
--
-- What is missing is what is specific to FOOTFALL: not flattening while
-- standing, flattening the right amount while walking, preserving volume,
-- and above all the contract that the X scale pivots on the CENTER of the
-- cell (the foot does not slip) and not on the edge (which has to move,
-- otherwise the previous contract would not prove anything). See the
-- lifeApply comment in main.lua for the full algebra.

do
  -- item 2: standing still does not flatten. Character not moving (same
  -- position every frame), clock ticking: with no displacement there is
  -- no velocity (`inst.velocidade` stays at 0, never leaves 0 because the
  -- filter only chases the target, which is the instantaneous velocity
  -- itself), and with no velocity `achata` (flatten) is zero BY
  -- CONSTRUCTION (amp * 0 * pulse = 0). `s` and `sx` have to stay EXACTLY
  -- 1 on every frame, with no slack at all: this is the check that stops
  -- the feature from showing up when nobody is walking.
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
  -- item 3: walking flattens, and the amplitude matches the level. Same
  -- driving routine as the MOTION LAG round (position walking 1 px per
  -- frame, the clock advancing 1/60 per frame), but the reading is
  -- different: the formula uses `amp = footfall / LIFE_CELL` directly on
  -- the scale `s` (there is no second "*16" back, the way there is for
  -- MOTION LAG's shear), so the maximum deviation of `s` from 1 has to
  -- approach the level itself divided by 16, not the raw level.
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
      -- 64 frames cover four whole 16px cells walked (the stride phase
      -- goes one full turn per cell), plenty of time for the smoothed
      -- velocity (filter factor 0.25 per frame) to saturate well before
      -- the pulse's first peak, at walked = 8.
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
  -- item 4: VOLUME is preserved. On every frame of the walk, what `s`
  -- loses in height has to reappear in `sx` as width, exactly: main.lua
  -- does `s = s - achata` and `sx = 1 + achata` from the SAME `achata`
  -- (flatten), so (1 - s) and (sx - 1) have to be the same number. This
  -- is the check that stops someone in the future from touching one side
  -- of the arithmetic and forgetting the other.
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
  -- items 5 and 6: THE FOOT DOES NOT SLIP (FOOTFALL's central
  -- contract) and THE EDGE MOVES (the complement that proves the previous
  -- test would not pass for free). Character walking up to a frame with
  -- sx clearly off of 1 (the pulse's peak, at walked = 16, with velocity
  -- already saturated).
  --
  -- The foot's center, local (8, 0, z), is the PIVOT of the X scale: it
  -- has to map to the SAME world point with and without the scale. Local
  -- (x, y, z) becomes world, per row, as m[c+1]*x + m[c+2]*y + m[c+3]*z +
  -- m[c+4] (c = 4*(row-1)); with y = 0 that is 8*col1 + z*col3 + col4 in
  -- row 1 (indices 1, 2, 3, 4). Checks for two values of z.
  --
  -- The left edge, local (0, 0, 0), only has col4 left: it HAS to move
  -- when sx changes, otherwise the foot check would pass with a scale
  -- that in practice does nothing (e.g. sx stuck at 1 by a bug somewhere
  -- else).
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
  -- item 7: the PHASE comes from DISTANCE, not from the clock.
  --
  -- Part 1: two instances, the SAME elapsed time, different distances
  -- traveled (different speeds): different points in the pulse, so `s`
  -- comes out different between the two.
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

  -- Part 2, complement to the previous one (and to item 2 above): the
  -- same STANDING instance does not change phase just because the clock
  -- ticked. Same position, two very different clocks (the same values
  -- from the BREATH phase test, further above in this suite): `s` comes
  -- out EQUAL, because `andado` (walked) never moved.
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
  -- item 8: personality multiplies. No LIFE_PERSONALITY sheet
  -- (main.lua) has a `footfall` entry yet, so the check here goes in the
  -- opposite direction from BREATH/guard further above in this suite: it
  -- confirms the ABSENT multiplier is worth 1, both for a sheet
  -- completely outside the table (sheet.png) and for a sheet PRESENT in
  -- the table but without the footfall field (guard.png, which has
  -- rate/breath/sway but not footfall). The formula in main.lua is
  -- `pessoa and pessoa.footfall or 1`, and both cases fall into the same
  -- final `or 1`. If some sheet ever gets its own footfall entry in the
  -- table, swap this check for one that compares the scaled amplitude, in
  -- the same spirit as the BREATH/guard test.
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
-- FIRST PERSON
-- ==========================================================================
-- Since v1.3.0 the mod returned the flat card whenever first person was
-- active, to avoid producing the black spikes Colonel_Aureliano reported.
-- That is now an OPTION, because reading the host the defect is not the
-- camera's, it is distance's: the shader pushes every vertex along its own
-- ray toward the eye by `pull` units, and whoever is closer than `pull` to
-- the eye ends up behind it.
--
-- So this section's contract is:
--   CARD stays exactly as it was, and is the default;
--   SOLID only exists if the draw channel exists to limit the pull;
--   and the passed-through pull can NEVER reach the eye, at any distance.

do
  -- 1. CARD in first person returns the original card, as it always
  -- did.
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
  -- 2. SOLID with a channel returns OUR mesh, which is the requested
  -- feature.
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
  -- 3. SOLID WITHOUT a channel still falls back to the card. Without
  --    Voxel3D.draw there is no way to limit the pull, and promising
  --    solid there would bring back the spikes.
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
  -- 4. THE PULL ARITHMETIC, tied to the geometry and not to a chosen
  --    number.
  --
  --    The eye sits D units from the matrix's anchor. The pull ceiling is
  --    D - radius - margin, because the closest vertex is at D - radius
  --    and it needs margin left over after moving `pull` toward the eye.
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

  -- And the invariant, swept, which is what stops a future edit from
  -- reopening the defect: for NO distance can the passed-through pull
  -- reach the eye.
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
  -- 5. OUTSIDE first person nothing changes. The fix cannot cost
  --    anything to whoever never enters that camera, which is almost
  --    everyone.
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
  -- 6. STATUS cannot say FIRST PERSON when the solid is being drawn:
  --    the line exists to report what is happening, and in SOLID that is
  --    not it.
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

-- ==========================================================================
-- THE AXIS: how much the body moves IN THE WORLD, not how much the matrix
-- changes
-- ==========================================================================
-- THIS BLOCK EXISTS BECAUSE IT WAS MISSING, and its absence hid a defect
-- in production. Every life-channel test so far asserts about the MATRIX:
-- that column 2 scaled, that the deviation matches the menu level. None of
-- them composed the matrix with the rotation the BUILDER had already baked
-- into the vertex.
--
-- The builder returns `p(x,y,z) = Rx(corr)*(x,y,z)` with `corr = pi/2 -
-- camera angle`, and the host undoes it with `Rx(angulo - pi/2)`. Net
-- result: upright. But the life channel POST-multiplies, so its
-- transformation happens in MESH space, which is rotated by the pitch,
-- and not in character space.
--
-- The effect is a conjugation: world = Rx(t) * S * Rx(-t) * point. For
-- BREATH, which scales y, the head's rise in the world comes out
-- `16*eps*cos^2(corr)` instead of `16*eps`, and a z drift of
-- `-16*eps*sin(corr)*cos(corr)` shows up that nobody asked for.
--
-- Measured at the standard rung (35): 33% of what was promised, plus
-- 0.075 px of drift.
-- FROM THE SHARED MODULE, not from a copy here (roadmap T1.1).
--
-- This construction used to be written out in this file. The laboratory needs
-- the same synthetic host matrix to preview the matrix-only options, and a
-- second copy of it is the copy that goes stale: the lab would drift from what
-- the suite proves, and the drift would be invisible, because both would still
-- look self-consistent. One definition, two readers.
--
-- The suite reaching into tools/ is unusual and deliberate. The alternative is
-- the lab reaching into tests/, which is worse, or two copies, which is the
-- thing being avoided.
local HostMatrix = dofile("mods/voxel_characters/tools/render/host_matrix.lua")
local rotX = HostMatrix.rotX
local aplicaMatriz = HostMatrix.apply

do
  local pixels = {}
  pixels[0] = 1

  -- Head displacement IN THE WORLD, with BREATH on, for one camera
  -- rung. Reproduces the whole chain: the vertex leaves the builder
  -- already counter-rotated, the host's matrix undoes it, and the life
  -- channel stepped in the middle post-multiplying.
  -- ENVELOPE, not an instant. `s = 1 + amp*sin(phase)`, so measuring at
  -- any given moment returns anything between -amp and +amp. Sweeps a
  -- whole period and keeps the extreme, which is what the amplitude
  -- controls. This is the same discipline the in-game probe already
  -- uses, and the first version of this test did not: it failed the
  -- correct fix.
  -- `hostFn` is what makes this the T1.1 gate as well as the conjugation one:
  -- the matrix under test is supplied, so the SAME measurement can be run
  -- against the shared synthetic host the laboratory uses and against a wrong
  -- one, and the two answers compared.
  local function subidaDaCabeca(rungDeg, amp, hostFn)
    local angulo = math.rad(rungDeg)
    local corr = HostMatrix.correction(rungDeg)
    local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
      angulo, nil, nil, nil, nil, true)
    loadWith(makeMod(handle, soEsta({ breath = amp })))
    local mesh = modules.SpriteBillboards.mesh(
      { image = "sheet.png", frames = 1 }, 0)
    local host = (hostFn or HostMatrix.forRung)(rungDeg)

    -- The head in CHARACTER coordinates, carried into mesh space by the
    -- same Rx(corr) the builder applies.
    local cx, cy, cz = 0, 16, 0
    local mx, my, mz = HostMatrix.toMeshSpace(corr, cx, cy, cz)
    local _, y0, z0 = aplicaMatriz(host, mx, my, mz)

    local topoY, topoZ = 0, 0
    for i = 0, 40 do
      withLoveTime(i * 0.15, function()
        modules.Voxel3D.drawCalls = {}
        modules.Voxel3D.draw(mesh, "tex", host, 6, nil)
        local saida = modules.Voxel3D.drawCalls[1].model
        local _, y1, z1 = aplicaMatriz(saida, mx, my, mz)
        if math.abs(y1 - y0) > math.abs(topoY) then topoY = y1 - y0 end
        if math.abs(z1 - z0) > math.abs(topoZ) then topoZ = z1 - z0 end
      end)
    end
    return math.abs(topoY), math.abs(topoZ)
  end

  local AMP = 0.010          -- BREATH SUBTLE, the shipped default
  local PROMETIDO = 16 * AMP -- what main.lua's comment claims: 0.16 px

  -- THE CONTRACT: the head's rise has to be the same at all four rungs,
  -- and it has to be the announced one. An effect whose intensity depends
  -- on where the camera is is not an effect, it is an accident of the
  -- assembly.
  local pior, piorRung = 0, nil
  for _, rung in ipairs({ 15, 35, 50, 75 }) do
    local dy = subidaDaCabeca(rung, AMP)
    local erro = math.abs(dy - PROMETIDO) / PROMETIDO
    if erro > pior then pior, piorRung = erro, rung end
  end
  check(pior < 0.10, string.format(
    "BREATH sobe a cabeca o mesmo em todos os degraus de camera "
    .. "(pior erro %.0f%% no rung %s, teto 10%%)", pior * 100,
    tostring(piorRung)))

  -- T1.1: THE SAME MEASUREMENT, WITH A WRONG SYNTHETIC HOST.
  --
  -- The check above passes with the shared matrix. On its own that does not
  -- prove the check can tell a wrong matrix from a right one, and the whole
  -- risk of giving the laboratory a synthetic host is that a fabricated matrix
  -- shows a lie confidently. So the obvious wrong answer is measured too: the
  -- identity, which is what a lab that "just draws it" would effectively use.
  --
  -- With identity the displacement is read in MESH space instead of world, so
  -- it comes out scaled by the camera angle: large at one rung, small at
  -- another. That rung dependence is the signature of operating in the wrong
  -- space, and it is exactly what the contract above forbids.
  local piorErrado, piorErradoRung = 0, nil
  for _, rung in ipairs(HostMatrix.RUNGS) do
    local dy = subidaDaCabeca(rung, AMP, function() return rotX(0) end)
    local erro = math.abs(dy - PROMETIDO) / PROMETIDO
    if erro > piorErrado then piorErrado, piorErradoRung = erro, rung end
  end
  check(piorErrado > 0.10, string.format(
    "T1.1: the 4-rung contract REJECTS a wrong synthetic host "
    .. "(identity gives %.0f%% error at rung %s, and the gate needs to see it)",
    piorErrado * 100, tostring(piorErradoRung)))

  -- And the shared matrix is the one the laboratory will read, not a copy of
  -- it. If these ever stop being the same object, the lab drifts from what is
  -- proved here and nothing else would notice.
  do
    local a = HostMatrix.forRung(35)
    local b = rotX(math.rad(35) - math.pi / 2)
    local igual = true
    for i = 1, 16 do
      if math.abs(a[i] - b[i]) > 1e-12 then igual = false break end
    end
    check(igual, "T1.1: HostMatrix.forRung is the host matrix the suite proves")
  end

  -- And the axis has to be CLEAN: scaling on y cannot push the body
  -- forward or backward. Drift on z is the symptom of operating in the
  -- wrong space, and it is what stops directional secondary motion from
  -- existing.
  local piorZ, piorZRung = 0, nil
  for _, rung in ipairs({ 15, 35, 50, 75 }) do
    local _, dz = subidaDaCabeca(rung, AMP)
    if math.abs(dz) > piorZ then piorZ, piorZRung = math.abs(dz), rung end
  end
  check(piorZ < PROMETIDO * 0.10, string.format(
    "BREATH nao empurra o corpo em z (pior deriva %.4f px no rung %s, "
    .. "teto %.4f)", piorZ, tostring(piorZRung), PROMETIDO * 0.10))
end

-- ==========================================================================
-- MOTION LAG: DIRECTION, not just magnitude
-- ==========================================================================
-- Mutation testing found a hole here: main.lua's lifeApply computes
-- `a22 = s * c * c + n * n - kz * n * c`. Flip that minus to a plus and the
-- WHOLE suite above still passes, because every MOTION LAG check up to this
-- point only asserts the MAGNITUDE of the shear. None of them asks which way
-- the body leans, so the body could lean INTO the step it is taking instead
-- of trailing behind it, and nothing would notice.
--
-- This is the same family of defect as the AXIS block above: BREATH once
-- sheared the body 45 degrees under a live camera and passed 465 offline
-- checks plus eight in-game checks, because every one of them asked "did
-- something change?" and none asked "in which direction, and by how much?"
--
-- A test that compares two opposite velocities to EACH OTHER is not enough:
-- flipping the sign inverts both readings together, so "these two are
-- opposite" still holds even with the bug. This test is ABSOLUTE instead: it
-- drives the character to a known, nonzero velocity and asserts that the top
-- of the body ends up on the side OPPOSITE the direction of travel, the way
-- a person's torso trails when they start walking (main.lua's lifeAdvance,
-- "the body lags behind while accelerating").
--
-- Needs a camera pitch away from top-down (corr ~= 0): the mutated term is
-- multiplied by n * c (sin(corr) * cos(corr)), which is zero at a straight
-- overhead camera, so the sign error is invisible there, same as the AXIS
-- defect above. Rung 35 is main.lua's own "standard rung" (see the comment
-- above lifeApply), and checked on paper against the L' formula it is one of
-- the rungs where the sign error actually FLIPS the sign of the world
-- displacement, rather than merely shrinking it (rung 75, for example, only
-- shrinks it, and a sign-only check would miss the defect there).
do
  local pixels = {}
  pixels[0] = 1
  local rungDeg = 35
  local angulo = math.rad(rungDeg)

  -- The same rotation the AXIS block's `host` uses for this camera pitch,
  -- but carrying its own translation this time: MOTION LAG needs real
  -- position tracking, since main.lua reads px, py straight from model[4]
  -- and model[12].
  local function cameraModel(px, py)
    local m = rotX(angulo - math.pi / 2)
    m[4] = px
    m[12] = py + 8
    return m
  end

  -- Drives the character with a known velocity: at rest at the origin, then
  -- moved along z only, well inside LIFE_MATCH_RADIUS (main.lua, 24px) so
  -- the SAME instance keeps tracking it and lifeAdvance's spring
  -- (LAG_STIFFNESS / LAG_DAMPING) actually has a velocity to chase. Same
  -- two-frame shape as lagSunColumn2 above.
  local function topLagAgainstTravel(dz)
    local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
      angulo, nil, nil, nil, nil, true)
    loadWith(makeMod(handle, soEsta({ lag = 1.2 })))
    local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
    withLoveTime(0, function()
      modules.Voxel3D.draw(mesh, "tex", cameraModel(0, 0), "pull", nil)
    end)
    local output
    withLoveTime(0.1, function()
      modules.Voxel3D.draw(mesh, "tex", cameraModel(0, dz), "pull", nil)
      output = modules.Voxel3D.drawCalls[#modules.Voxel3D.drawCalls].model
    end)

    -- Top of the body (mesh y = 16) and the base (mesh y = 0), read
    -- straight out of the matrix the mod handed to Voxel3D.draw: no
    -- re-deriving character space, just the output matrix, as the task
    -- describes.
    local _, _, topZ = aplicaMatriz(output, 0, 16, 0)
    local _, _, baseZ = aplicaMatriz(output, 0, 0, 0)

    -- The camera pitch alone (no life effect at all) already tilts a
    -- y = 16 point away from a y = 0 point in world Z, by exactly
    -- sin(angulo - pi/2) * 16: that is geometry, not motion, and it does
    -- not depend on which way the character is walking. Subtracting it
    -- isolates the part MOTION LAG itself is responsible for.
    local staticTiltZ = math.sin(angulo - math.pi / 2) * 16
    return (topZ - baseZ) - staticTiltZ
  end

  -- Moving toward NEGATIVE z (0 -> -6): the travel direction is -1 along
  -- z, so "against travel" means a POSITIVE lag displacement, and the
  -- projection onto the travel direction must come out negative.
  local lagTowardNegZ = topLagAgainstTravel(-6)
  check(math.abs(lagTowardNegZ) > 0.05, string.format(
    "MOTION LAG has a real, non-negligible effect on the top of the body "
    .. "(got %.5f); a near-zero reading would pass the direction check for "
    .. "the wrong reason", lagTowardNegZ))
  check(lagTowardNegZ * -1 < 0, string.format(
    "MOTION LAG: walking toward -z, the top of the body leans AGAINST "
    .. "travel (displacement %.5f, expected positive, i.e. against -z)",
    lagTowardNegZ))

  -- Moving toward POSITIVE z (0 -> 6): the travel direction flips to +1,
  -- and the lag displacement must flip with it (the body always trails,
  -- whichever way it walks). Each reading is checked against its OWN
  -- travel direction here, never against the other reading, which is the
  -- exact comparison the task warns is not enough.
  local lagTowardPosZ = topLagAgainstTravel(6)
  check(math.abs(lagTowardPosZ) > 0.05,
    "MOTION LAG has a real, non-negligible effect walking the other way too")
  check(lagTowardPosZ * 1 < 0, string.format(
    "MOTION LAG: walking toward +z, the top of the body leans AGAINST "
    .. "travel (displacement %.5f, expected negative, i.e. against +z)",
    lagTowardPosZ))
end

do
  -- ATTENTION (roadmap item 10): the character leans toward the eye, and
  -- NEVER turns. The in-game clip is the wrong gate for this one and that was
  -- measured, not assumed: across three runs the effect swung from 27 to 35 dB
  -- because it depends on where the player happens to be standing relative to
  -- the NPCs, which the scene controls and the tool does not. The maths gets
  -- measured here, where the eye can be placed exactly.
  local pixels = {}
  pixels[0] = 1
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handle, { attention = 1.0 }))
  local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)

  local function kxComOlhoEm(ex)
    modules.Voxel3D.eye = { ex, 0, 0 }
    local out
    withDrivenClock(function(setClock)
      -- Two frames: attention EASES in rather than snapping, so a single
      -- frame reads the start of the ramp and says almost nothing.
      for f = 0, 40 do
        setClock(f / 60)
        local model = lifeProbeModel(0, 0, false)
        modules.Voxel3D.draw(mesh, "tex", model, "pull", nil)
        out = modules.Voxel3D.drawCalls[#modules.Voxel3D.drawCalls].model
      end
    end)
    return out[2]
  end

  local perto = kxComOlhoEm(10)
  local longe = kxComOlhoEm(200)

  check(math.abs(perto) > math.abs(longe),
        "ATTENTION: leans more with the eye close than with it far")
  -- NOT ZERO, and the first version of this check demanded zero and failed
  -- correctly. Attention EASES out: once a character has noticed you, walking
  -- away makes it settle back over about a third of a second rather than
  -- snapping upright, which is the entire reason the ease is there. So the
  -- assertion is that it decays, and by how much.
  -- MEASURED, not chosen: over the 0.68 s this sweep covers, the lean falls
  -- from 0.0545 to 0.0210, which is 39%. The bound is set at half, which is
  -- comfortably above the measurement and still fails if the decay stops
  -- working. Demanding a quarter would be writing the threshold to match one
  -- run of one sweep length.
  check(math.abs(longe) < math.abs(perto) * 0.5,
        "ATTENTION: the lean falls by more than half when the eye leaves")

  -- THE DIRECTION, absolute and not relative. A test comparing two opposite
  -- eye positions to each other passes just as happily with the sign flipped,
  -- which is the exact trap the MOTION LAG direction test documents.
  local dir = kxComOlhoEm(10)
  local dirNeg = kxComOlhoEm(-10)
  check(dir > 0, "ATTENTION: leans toward an eye on the positive side")
  check(dirNeg < 0, "ATTENTION: leans toward an eye on the negative side")

  -- THE CEILING. 1.0 is the strongest level the menu offers and it is HEAD
  -- displacement in world pixels, so the shear times the cell height must not
  -- exceed it by more than rounding.
  check(math.abs(dir) * 16 < 1.2,
        "ATTENTION: the strongest level stays under 1.2 px of head movement")
  modules.Voxel3D.eye = nil
end

do
  -- PART LAG (roadmap item 9): the head arrives late.
  --
  -- Measured on the DRAW CALLS rather than on one matrix, because the whole
  -- feature is that there is now more than one: with bands on, each band is
  -- drawn with its own transform, and the thing to prove is that they DIFFER
  -- and that the head is the one lagging.
  local pixels = {}
  for i = 0, 255 do pixels[i] = 1 end
  local handle, modules = makeVoxelHandle("1.6.0", pixels, 16, 16,
    nil, nil, nil, nil, nil, true)
  loadWith(makeMod(handle, { sway = 0.45, part_lag = 0.16 }))
  local mesh = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)

  local chamadas = 0
  local kxPorBanda = {}
  withDrivenClock(function(setClock)
    for f = 0, 60 do
      setClock(f / 60)
      local antes = #modules.Voxel3D.drawCalls
      modules.Voxel3D.draw(mesh, "tex", lifeProbeModel(0, 0, false), "pull", nil)
      chamadas = #modules.Voxel3D.drawCalls - antes
      if f == 60 then
        for i = antes + 1, #modules.Voxel3D.drawCalls do
          kxPorBanda[#kxPorBanda + 1] = modules.Voxel3D.drawCalls[i].model[2]
        end
      end
    end
  end)

  check(chamadas > 1,
        "PART LAG: the mesh is drawn once per band, not once in total")

  -- The bands must not all carry the same shear, or the delay did nothing.
  local iguais = true
  for i = 2, #kxPorBanda do
    if math.abs(kxPorBanda[i] - kxPorBanda[1]) > 1e-9 then iguais = false end
  end
  check(not iguais and #kxPorBanda > 1,
        "PART LAG: the bands carry DIFFERENT shear, so one of them is late")

  -- THE RANGE MUST BE CLEARED. It is sticky on the mesh OBJECT, and that mesh
  -- is shared by every character using this sheet in the frame, so a range
  -- left set draws the next character as one band of itself. This is the one
  -- blocker from the old list that survived, and it survives as a rule that
  -- has to be checked rather than as a reason not to build the feature.
  check(mesh.rangeAtual == nil,
        "PART LAG: the draw range is cleared after the last band")

  -- AND IT NEEDS SOMETHING TO DELAY. With every other life option off the
  -- shear is constant, and a delayed constant is the same constant, so the
  -- feature correctly does nothing. The clip guard found this by refusing to
  -- publish it, and it belongs in the suite rather than in somebody's memory.
  loadWith(makeMod(handle, { part_lag = 0.16 }))
  local mesh2 = modules.SpriteBillboards.mesh({ image = "sheet.png", frames = 1 }, 0)
  local kx2 = {}
  withDrivenClock(function(setClock)
    for f = 0, 60 do
      setClock(f / 60)
      local antes = #modules.Voxel3D.drawCalls
      modules.Voxel3D.draw(mesh2, "tex", lifeProbeModel(0, 0, false), "pull", nil)
      if f == 60 then
        for i = antes + 1, #modules.Voxel3D.drawCalls do
          kx2[#kx2 + 1] = modules.Voxel3D.drawCalls[i].model[2]
        end
      end
    end
  end)
  local todosIguais = true
  for i = 2, #kx2 do
    if math.abs(kx2[i] - kx2[1]) > 1e-9 then todosIguais = false end
  end
  check(todosIguais,
        "PART LAG: with nothing to delay, every band gets the same transform")
end

T.finish("voxel_chars_test")
