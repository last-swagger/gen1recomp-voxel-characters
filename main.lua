-- Voxel Characters: personagens como slabs de pixels, sem invadir o Voxel Mod.
--
-- O Dramatic Shape desenha os personagens como cards planos. Isso e
-- uma escolha deliberada dele; este mod so troca a funcao publica que ja e
-- capturada por campo (`SpriteBillboards.mesh`) quando o jogador escolhe uma
-- espessura. A sombra e o fantasma continuam no alias original.
--
-- NAO PATCHEIE `shadowQuad`. Isso nao e economia, e requisito. A silhueta de
-- oclusao do jogador (`VoxelScene.drawGhost`) desenha essa malha com o teste
-- de profundidade INVERTIDO por `Voxel3D.beginGhost`, e o autor do Dramatic
-- Shape documenta o porque em VoxelScene.lua:390-396: "a mesh carrying both
-- front and back faces would read its own back faces as 'behind something'
-- and repaint the figure on open ground, occluded or not". Nosso slab tem
-- exatamente front e back. Trocar o shadowQuad por ele pinta o jogador como
-- fantasma em campo aberto e ainda borra em manchas por duplo blend.
--
-- O preco de manter o card plano no passe de sol e a franja de auto-sombra
-- nas faces laterais e de fundo (README, secao "Sombra do slab"). E o lado
-- certo do trade: franja sutil contra jogador repintado na tela inteira.

local mod = ...

local Semver = require("src.mods.Semver")
local Assets = require("src.render.Assets")

local SUPPORTED = ">=1.5.0 <2.0.0"
local KEY = "depth"
local VALUES = { "off", 1, 2, 3, 5, 10 }
local LABELS = { "OFF", "1", "2", "3", "5", "10" }
local DEFAULT_DEPTH = 3
local DEFAULT_INDEX = 4  -- posicao de 3 em VALUES
-- DECISAO: a luz do Dramatic Shape vem do sudeste. Frente e topo ficam
-- claros, tras e baixo escurecem por virarem contra a luz, e as laterais
-- usam um meio-termo para o slab ler como volume sem depender de sombra real.
local OBJ_SHADE = { front = 1.0, back = 0.68, side = 0.78, top = 1.0, bottom = 0.55 }
local SIDE_INSET = 0.03
local RUN_UV_INSET = 0.05
local PITCH_BUCKET = math.pi / 180
local MAX_MESHES = 64

mod.options:define({
  {
    key = KEY,
    type = "choice",
    label = "VOXEL CHARS",
    choices = {
      { "OFF", "off" }, { "1", 1 }, { "2", 2 },
      { "3", 3 }, { "5", 5 }, { "10", 10 },
    },
    default = 3,
    help = "Extrudes overworld character sprites. Depth 1-5 stays inside the voxel pull budget; 10 may clip into walls.",
  },
})

local SpriteBillboards, Voxel3D, ImageCache
local VoxelState, FirstPerson, VoxelScene
local originalMesh
local meshes, masks = {}, {}
local meshOrder = {}
local depthValue
local optionsRegistered = false

local function indexOf(value)
  for i, v in ipairs(VALUES) do
    if v == value then return i end
  end
  return DEFAULT_INDEX
end

local function readDepth()
  local ok, value = pcall(mod.options.get, mod.options, KEY)
  if ok then return VALUES[indexOf(value)] end
  return DEFAULT_DEPTH
end

local function releaseMesh(mesh)
  if mesh and mesh ~= false and mesh.release then pcall(mesh.release, mesh) end
end

local function clearMeshCache()
  for _, mesh in pairs(meshes) do releaseMesh(mesh) end
  meshes, meshOrder = {}, {}
end

local function clearCache()
  clearMeshCache()
  masks = {}
end

local function setDepth(value)
  local nextValue = VALUES[indexOf(value)]
  if depthValue ~= nextValue then clearCache() end
  depthValue = nextValue
  return depthValue
end

setDepth(readDepth())
Assets.register(clearCache)

local function writeOption(game, value)
  local id = mod.id
  local opts = game and game.save and game.save.options
  if opts then
    opts.modOptions = opts.modOptions or {}
    opts.modOptions[id] = opts.modOptions[id] or {}
    opts.modOptions[id][KEY] = value
  end
  local loader = game and game.mods
  if loader then
    loader.modOptions = loader.modOptions or {}
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id][KEY] = value
  end
  if loader and loader.events then
    loader.events:emit("mod.options_changed",
      { mod = id, key = KEY, value = value })
  end
end

local function row()
  return {
    id = mod.id .. ":" .. KEY,
    label = "VOXEL CHARS",
    value = function() return LABELS[indexOf(depthValue or readDepth())] end,
    step = function(game, dir)
      local i = indexOf(depthValue or readDepth())
      i = ((i + (dir or 1) - 1) % #VALUES) + 1
      local value = setDepth(VALUES[i])
      writeOption(game, value)
      return true
    end,
  }
end

local function registerOptionsRows()
  if optionsRegistered then return end
  optionsRegistered = true
  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    out[#out + 1] = row()
    return out
  end)

  mod.events:on("mod.options_changed", function(payload)
    if payload and payload.mod == mod.id and payload.key == KEY then
      setDepth(payload.value)
    end
  end)
end

local function warnChainedMesh()
  if SpriteBillboards.__voxelCharactersOriginal then return end
  if SpriteBillboards.shadowQuad
      and SpriteBillboards.mesh ~= SpriteBillboards.shadowQuad then
    mod.log:warn("SpriteBillboards.mesh was already patched; chaining over %s",
      tostring(SpriteBillboards.mesh))
  end
end

local function intField(def, ...)
  for i = 1, select("#", ...) do
    local v = tonumber(def and def[select(i, ...)])
    if v and v > 0 then return math.floor(v) end
  end
end

local function spriteLayout(def, sheetW, sheetH)
  local frames = intField(def, "frames")
  if not (frames and sheetW and sheetH and sheetW > 0 and sheetH > 0) then
    return nil
  end

  local frameW = intField(def, "frameW", "frameWidth", "cellW", "cellWidth",
                          "spriteW", "spriteWidth")
  local frameH = intField(def, "frameH", "frameHeight", "cellH", "cellHeight",
                          "spriteH", "spriteHeight")
  local columns = intField(def, "columns", "cols", "framesPerRow")

  if frameW or columns then
    frameW = frameW or (columns and math.floor(sheetW / columns))
    if not (frameW and frameW > 0 and frameW <= sheetW) then return nil end
    columns = columns or math.max(1, math.floor(sheetW / frameW))
    if columns < 1 then return nil end
    local rows = math.ceil(frames / columns)
    frameH = frameH or math.floor(sheetH / rows)
    if not (frameH and frameH > 0 and frameH <= sheetH) then return nil end
    if (columns - 1) * frameW + frameW > sheetW then return nil end
    if (rows - 1) * frameH + frameH > sheetH then return nil end
    return { frames = frames, w = frameW, h = frameH, columns = columns }
  end

  -- Sem metadados de celula, so ha duas folhas derivaveis sem adivinhar:
  -- uma coluna vertical como o motor vanilla, ou uma linha horizontal. Folhas
  -- com padding ou grade ambigua degradam para o card original.
  local vertical = (sheetH % frames == 0)
    and { frames = frames, w = sheetW, h = sheetH / frames, columns = 1 }
  local horizontal = (sheetW % frames == 0)
    and { frames = frames, w = sheetW / frames, h = sheetH, columns = frames }
  if frames == 1 and vertical then return vertical end
  if vertical and not horizontal then return vertical end
  if horizontal and not vertical then return horizontal end
  if vertical and horizontal then
    local vScore = math.abs(vertical.w - vertical.h)
    local hScore = math.abs(horizontal.w - horizontal.h)
    if vScore < hScore then return vertical end
    if hScore < vScore then return horizontal end
  end
  return nil
end

local function frameOrigin(layout, frame)
  local col = frame % layout.columns
  local row = math.floor(frame / layout.columns)
  local w, h = layout.w or layout.cellW, layout.h or layout.cellH
  return col * w, row * h
end

local function alphaAt(data, x, y)
  local ok, _, _, _, a = pcall(data.getPixel, data, x, y)
  return ok and (a or 0) >= 0.5
end

local function maskFor(def)
  if not (def and def.image) then return nil end
  local data = ImageCache.get(def.image)
  if not data then return nil end
  local sheetW, sheetH = data:getDimensions()
  local layout = spriteLayout(def, sheetW, sheetH)
  if not layout then return nil end
  local frames = layout.frames
  local key = table.concat({
    def.image, sheetW, sheetH, frames, layout.w, layout.h, layout.columns,
  }, "#")
  if masks[key] ~= nil then return masks[key] or nil end

  local mask = {}
  local minX, maxX, minY, maxY = layout.w, -1, layout.h, -1
  for f = 0, frames - 1 do
    local fx, fy = frameOrigin(layout, f)
    if fx + layout.w <= sheetW and fy + layout.h <= sheetH then
      for ly = 0, layout.h - 1 do
        for lx = 0, layout.w - 1 do
          if alphaAt(data, fx + lx, fy + ly) then
            mask[ly * layout.w + lx] = true
            if lx < minX then minX = lx end
            if lx > maxX then maxX = lx end
            if ly < minY then minY = ly end
            if ly > maxY then maxY = ly end
          end
        end
      end
    end
  end

  if maxX < minX or maxY < minY then
    masks[key] = false
    return nil
  end

  local out = {
    mask = mask, minX = minX, maxX = maxX, minY = minY, maxY = maxY,
    sheetW = sheetW, sheetH = sheetH, frames = frames,
    cellW = layout.w, cellH = layout.h, columns = layout.columns,
  }
  masks[key] = out
  return out
end

-- O lean real e `leanAngle()` da VoxelScene, que da precedencia a
-- `VoxelScene.spriteLean` sobre `VoxelState.angle` (VoxelScene.lua:283-285).
-- Hoje so o VR seta esse campo, para 75 graus (VR.lua:281); ler apenas o
-- `angle` deixaria o corpo tombado pela diferenca dentro do headset.
local function leanCorrection()
  local a = 0
  local pinned
  if VoxelScene then
    local ok, value = pcall(function() return VoxelScene.spriteLean end)
    if ok then pinned = tonumber(value) end
  end
  if pinned then
    a = pinned
  elseif VoxelState then
    local ok, value = pcall(function() return VoxelState.angle end)
    if ok then a = tonumber(value) or 0 end
  end
  local b = 0
  if FirstPerson and FirstPerson.cardBlend then
    local ok, value = pcall(FirstPerson.cardBlend)
    if ok then b = math.max(0, math.min(1, tonumber(value) or 0)) end
  end
  return (math.pi / 2 - a) * (1 - b)
end

-- DECISAO: o tween de rung dura 0,25 s; a 60 fps ele gerava cerca de
-- 15 pitches distintos, cada um com chave propria. O bucket de 1 grau
-- reduz a transicao a 2 ou 3 malhas visiveis sem deslocamento perceptivel,
-- e o LRU de 64 mantem uma rota com 8 tipos e 6 frames em dezenas de
-- meshes, nao milhares, mesmo subindo e descendo escadas repetidamente.
local function quantizeCorrection(angle)
  return math.floor(((angle or 0) / PITCH_BUCKET) + 0.5) * PITCH_BUCKET
end

local function pitchKey(angle)
  return tostring(math.floor(((angle or 0) / PITCH_BUCKET) + 0.5))
end

local function touchMeshKey(key)
  for i = #meshOrder, 1, -1 do
    if meshOrder[i] == key then
      table.remove(meshOrder, i)
      break
    end
  end
  meshOrder[#meshOrder + 1] = key
end

local function rememberMesh(key, mesh)
  meshes[key] = mesh
  touchMeshKey(key)
  while #meshOrder > MAX_MESHES do
    local oldKey = table.remove(meshOrder, 1)
    local old = meshes[oldKey]
    meshes[oldKey] = nil
    releaseMesh(old)
  end
end

local function buildMesh(def, frame, depth, correction, m)
  m = m or maskFor(def)
  if not m then return nil end
  frame = tonumber(frame) or 0
  if frame < 0 or frame >= m.frames then frame = 0 end
  local fx, fy = frameOrigin(m, frame)
  if fx + m.cellW > m.sheetW or fy + m.cellH > m.sheetH then return nil end

  local z0, z1 = -depth, 0
  local baseY, lowY = 0, m.maxY
  local verts, idx = {}, {}
  local c, s = math.cos(correction or 0), math.sin(correction or 0)

  local function at(lx, ly)
    if lx < m.minX or lx > m.maxX or ly < m.minY or ly > m.maxY then return false end
    return m.mask[ly * m.cellW + lx] or false
  end

  local function uv(lx, ly)
    return (fx + lx + 0.5) / m.sheetW, (fy + ly + 0.5) / m.sheetH
  end

  local function sameUv(lx, ly)
    local u, v = uv(lx, ly)
    return { u, v, u, v, u, v, u, v }
  end

  local function rectUv(lx, ly, lx2, order)
    local u0 = (fx + lx + RUN_UV_INSET) / m.sheetW
    local u1 = (fx + lx2 + 1 - RUN_UV_INSET) / m.sheetW
    local v0 = (fy + ly + RUN_UV_INSET) / m.sheetH
    local v1 = (fy + ly + 1 - RUN_UV_INSET) / m.sheetH
    if order == "back" then
      return { u1, v1, u0, v1, u0, v0, u1, v0 }
    elseif order == "top" then
      return { u0, v0, u1, v0, u1, v1, u0, v1 }
    end
    return { u0, v1, u1, v1, u1, v0, u0, v0 }
  end

  local function p(x, y, z)
    -- A matriz do Dramatic Shape inclina o card no X, pivotando nos pes.
    -- A malha solida chega contra-rotacionada no mesmo pivo; depois do lean
    -- externo, o corpo volta a ficar de pe.
    return { x, y * c - z * s, y * s + z * c }
  end

  local function quad(c1, c2, c3, c4, uv4, shade)
    local n = #verts / 4
    verts[#verts + 1] = { c1[1], c1[2], c1[3], uv4[1], uv4[2], shade }
    verts[#verts + 1] = { c2[1], c2[2], c2[3], uv4[3], uv4[4], shade }
    verts[#verts + 1] = { c3[1], c3[2], c3[3], uv4[5], uv4[6], shade }
    verts[#verts + 1] = { c4[1], c4[2], c4[3], uv4[7], uv4[8], shade }
    Voxel3D.pushQuad(idx, n)
  end

  -- DECISAO: laterais esquerda/direita continuam por pixel, porque a
  -- silhueta animada depende disso. Frente, tras, topo e base viram runs
  -- horizontais com UV retangular e inset de 0,05 texel; no red.png isso
  -- reduz a uniao de 189 pixels de 1.134 quads para 442 sem sair da celula
  -- do frame que o alpha discard recorta.
  for ly = m.minY, m.maxY do
    local lx = m.minX
    while lx <= m.maxX do
      if at(lx, ly) then
        local lx2 = lx
        while lx2 + 1 <= m.maxX and at(lx2 + 1, ly) do lx2 = lx2 + 1 end

        local x, y = lx - m.minX, lowY - ly
        local w = lx2 - lx + 1
        quad(p(x, y, z1), p(x + w, y, z1), p(x + w, y + 1, z1),
             p(x, y + 1, z1), rectUv(lx, ly, lx2), OBJ_SHADE.front)
        quad(p(x + w, y, z0), p(x, y, z0), p(x, y + 1, z0),
             p(x + w, y + 1, z0), rectUv(lx, ly, lx2, "back"),
             OBJ_SHADE.back)
        quad(p(x, y + 1 - SIDE_INSET, z0), p(x + w, y + 1 - SIDE_INSET, z0),
             p(x + w, y + 1 - SIDE_INSET, z1), p(x, y + 1 - SIDE_INSET, z1),
             rectUv(lx, ly, lx2, "top"), OBJ_SHADE.top)
        quad(p(x, y + SIDE_INSET, z1), p(x + w, y + SIDE_INSET, z1),
             p(x + w, y + SIDE_INSET, z0), p(x, y + SIDE_INSET, z0),
             rectUv(lx, ly, lx2), OBJ_SHADE.bottom)

        for sx = lx, lx2 do
          local px, sy = sx - m.minX, lowY - ly
          local uv4 = sameUv(sx, ly)
          quad(p(px + SIDE_INSET, sy, z0), p(px + SIDE_INSET, sy, z1),
               p(px + SIDE_INSET, sy + 1, z1), p(px + SIDE_INSET, sy + 1, z0),
               uv4, OBJ_SHADE.side)
          quad(p(px + 1 - SIDE_INSET, sy, z1), p(px + 1 - SIDE_INSET, sy, z0),
               p(px + 1 - SIDE_INSET, sy + 1, z0), p(px + 1 - SIDE_INSET, sy + 1, z1),
               uv4, OBJ_SHADE.side)
        end
        lx = lx2 + 1
      else
        lx = lx + 1
      end
    end
  end

  return Voxel3D.newMesh(verts, idx)
end

local function cacheKey(def, frame, depth, correction, layout)
  return table.concat({
    tostring(def and def.image or ""),
    tostring(def and def.frames or ""),
    tostring(frame or 0),
    tostring(depth),
    tostring(layout and layout.cellW or ""),
    tostring(layout and layout.cellH or ""),
    tostring(layout and layout.columns or ""),
    pitchKey(correction),
  }, "#")
end

local function voxelMesh(def, frame)
  local depth = depthValue or readDepth()
  if depth == "off" then return originalMesh(def, frame) end
  local correction = quantizeCorrection(leanCorrection())
  local okMask, m = pcall(maskFor, def)
  if not (okMask and m) then return originalMesh(def, frame) end
  local key = cacheKey(def, frame, depth, correction, m)
  if meshes[key] ~= nil then
    touchMeshKey(key)
  else
    local ok, mesh = pcall(buildMesh, def, frame, depth, correction, m)
    rememberMesh(key, (ok and mesh) or false)
  end
  return meshes[key] or originalMesh(def, frame)
end

local function patch(handle)
  local V = handle.exports.lib
  Voxel3D = V.require("Voxel3D")
  ImageCache = V.require("ImageCache")
  SpriteBillboards = V.require("SpriteBillboards")
  local okVoxel, voxel = pcall(V.require, "VoxelState")
  if okVoxel then VoxelState = voxel end
  local okFirst, first = pcall(V.require, "FirstPerson")
  if okFirst then FirstPerson = first end
  local okScene, scene = pcall(V.require, "VoxelScene")
  if okScene then VoxelScene = scene end
  warnChainedMesh()
  originalMesh = SpriteBillboards.__voxelCharactersOriginal or SpriteBillboards.mesh
  SpriteBillboards.__voxelCharactersOriginal = originalMesh
  SpriteBillboards.mesh = function(def, frame)
    local ok, mesh = pcall(voxelMesh, def, frame)
    if ok then return mesh end
    return originalMesh(def, frame)
  end
  registerOptionsRows()
  mod.log:info("patched Dramatic Shape character billboards")
end

local handle = mod.find("DRAMATIC_SHAPE")
if not (handle and handle.exports and handle.exports.lib) then return end

local okVersion, why = Semver.satisfies(handle.version, SUPPORTED)
if not okVersion then
  mod.log:warn("Dramatic Shape %s is outside supported range %s: %s",
    tostring(handle.version), SUPPORTED, tostring(why or "not supported"))
  return
end

local ok, err = pcall(patch, handle)
if not ok then
  mod.log:warn("could not patch Dramatic Shape character billboards: %s", tostring(err))
end
