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
local SIDE_COLOR_KEY = "side_color"
local SHAPE_KEY = "shape"
local VALUES = { "off", 1, 2, 3, 5, 10 }
local LABELS = { "OFF", "1", "2", "3", "5", "10" }
local SIDE_COLOR_VALUES = { "body", "outline" }
local SIDE_COLOR_LABELS = { "BODY", "OUTLINE" }
local SHAPE_VALUES = { "slab", "carved", "carved_plus" }
local SHAPE_LABELS = { "SLAB", "CARVED", "CARVED+" }
local DEFAULT_DEPTH = 3
local DEFAULT_INDEX = 4  -- posicao de 3 em VALUES
local DEFAULT_SIDE_COLOR = "body"
local DEFAULT_SIDE_COLOR_INDEX = 1
local DEFAULT_SHAPE = "slab"
local DEFAULT_SHAPE_INDEX = 1
-- DECISAO: a luz do Dramatic Shape vem do sudeste. Frente e topo ficam
-- claros, tras e baixo escurecem por virarem contra a luz, e as laterais
-- usam um meio-termo para o slab ler como volume sem depender de sombra real.
local OBJ_SHADE = { front = 1.0, back = 0.68, side = 0.78, top = 1.0, bottom = 0.55 }
local SIDE_INSET = 0.03
local RUN_UV_INSET = 0.05
local PITCH_BUCKET = math.pi / 180
local MAX_MESHES = 64
-- DECISAO: quatro pixels cobre os contornos grossos de sprites Gen 1 sem
-- deixar uma busca em arte customizada atravessar para outra parte do corpo.
local BODY_SEARCH_LIMIT = 4
local LUMA_EPSILON = 0.00001
local CARVED_PLUS_RECESS_STEPS = 2

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
  {
    key = SIDE_COLOR_KEY,
    type = "choice",
    label = "SIDE COLOR",
    choices = {
      { "BODY", "body" }, { "OUTLINE", "outline" },
    },
    default = DEFAULT_SIDE_COLOR,
    help = "Colors new side, top, and bottom faces from body pixels or keeps the original outline pixels.",
  },
  {
    key = SHAPE_KEY,
    type = "choice",
    label = "SHAPE",
    choices = {
      { "SLAB", "slab" }, { "CARVED", "carved" },
      { "CARVED+", "carved_plus" },
    },
    default = DEFAULT_SHAPE,
    help = "SLAB keeps the v1.1.0 extrusion. CARVED builds visual-hull volume from three views. CARVED+ adds tone relief.",
  },
})

local SpriteBillboards, Voxel3D, ImageCache
local VoxelState, FirstPerson, VoxelScene
local originalMesh
local meshes, masks = {}, {}
local meshOrder = {}
local depthValue
local sideColorValue
local shapeValue
local optionsRegistered = false

local function indexOf(value)
  for i, v in ipairs(VALUES) do
    if v == value then return i end
  end
  return DEFAULT_INDEX
end

local function sideColorIndexOf(value)
  for i, v in ipairs(SIDE_COLOR_VALUES) do
    if v == value then return i end
  end
  return DEFAULT_SIDE_COLOR_INDEX
end

local function shapeIndexOf(value)
  for i, v in ipairs(SHAPE_VALUES) do
    if v == value then return i end
  end
  return DEFAULT_SHAPE_INDEX
end

local function readDepth()
  local ok, value = pcall(mod.options.get, mod.options, KEY)
  if ok then return VALUES[indexOf(value)] end
  return DEFAULT_DEPTH
end

local function readSideColor()
  local ok, value = pcall(mod.options.get, mod.options, SIDE_COLOR_KEY)
  if ok then return SIDE_COLOR_VALUES[sideColorIndexOf(value)] end
  return DEFAULT_SIDE_COLOR
end

local function readShape()
  local ok, value = pcall(mod.options.get, mod.options, SHAPE_KEY)
  if ok then return SHAPE_VALUES[shapeIndexOf(value)] end
  return DEFAULT_SHAPE
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

local function setSideColor(value)
  local nextValue = SIDE_COLOR_VALUES[sideColorIndexOf(value)]
  if sideColorValue ~= nextValue then clearMeshCache() end
  sideColorValue = nextValue
  return sideColorValue
end

local function setShape(value)
  local nextValue = SHAPE_VALUES[shapeIndexOf(value)]
  if shapeValue ~= nextValue then clearMeshCache() end
  shapeValue = nextValue
  return shapeValue
end

setDepth(readDepth())
setSideColor(readSideColor())
setShape(readShape())
Assets.register(clearCache)

local function writeOption(game, key, value)
  local id = mod.id
  local opts = game and game.save and game.save.options
  if opts then
    opts.modOptions = opts.modOptions or {}
    opts.modOptions[id] = opts.modOptions[id] or {}
    opts.modOptions[id][key] = value
  end
  local loader = game and game.mods
  if loader then
    loader.modOptions = loader.modOptions or {}
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id][key] = value
  end
  if loader and loader.events then
    loader.events:emit("mod.options_changed",
      { mod = id, key = key, value = value })
  end
end

local function depthRow()
  return {
    id = mod.id .. ":" .. KEY,
    label = "VOXEL CHARS",
    value = function() return LABELS[indexOf(depthValue or readDepth())] end,
    step = function(game, dir)
      local i = indexOf(depthValue or readDepth())
      i = ((i + (dir or 1) - 1) % #VALUES) + 1
      local value = setDepth(VALUES[i])
      writeOption(game, KEY, value)
      return true
    end,
  }
end

local function sideColorRow()
  return {
    id = mod.id .. ":" .. SIDE_COLOR_KEY,
    label = "SIDE COLOR",
    value = function()
      return SIDE_COLOR_LABELS[sideColorIndexOf(sideColorValue or readSideColor())]
    end,
    step = function(game, dir)
      local i = sideColorIndexOf(sideColorValue or readSideColor())
      i = ((i + (dir or 1) - 1) % #SIDE_COLOR_VALUES) + 1
      local value = setSideColor(SIDE_COLOR_VALUES[i])
      writeOption(game, SIDE_COLOR_KEY, value)
      return true
    end,
  }
end

local function shapeRow()
  return {
    id = mod.id .. ":" .. SHAPE_KEY,
    label = "SHAPE",
    value = function()
      return SHAPE_LABELS[shapeIndexOf(shapeValue or readShape())]
    end,
    step = function(game, dir)
      local i = shapeIndexOf(shapeValue or readShape())
      i = ((i + (dir or 1) - 1) % #SHAPE_VALUES) + 1
      local value = setShape(SHAPE_VALUES[i])
      writeOption(game, SHAPE_KEY, value)
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
    out[#out + 1] = depthRow()
    out[#out + 1] = sideColorRow()
    out[#out + 1] = shapeRow()
    return out
  end)

  mod.events:on("mod.options_changed", function(payload)
    if payload and payload.mod == mod.id and payload.key == KEY then
      setDepth(payload.value)
    elseif payload and payload.mod == mod.id and payload.key == SIDE_COLOR_KEY then
      setSideColor(payload.value)
    elseif payload and payload.mod == mod.id and payload.key == SHAPE_KEY then
      setShape(payload.value)
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

local function pixelAt(data, x, y)
  local ok, r, g, b, a = pcall(data.getPixel, data, x, y)
  if not ok then return nil end
  return r or 0, g or 0, b or 0, a or 0
end

local function luminance(r, g, b)
  return (r or 0) * 0.2126 + (g or 0) * 0.7152 + (b or 0) * 0.0722
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
  local outlineLuma
  local minX, maxX, minY, maxY = layout.w, -1, layout.h, -1
  for f = 0, frames - 1 do
    local fx, fy = frameOrigin(layout, f)
    if fx + layout.w <= sheetW and fy + layout.h <= sheetH then
      for ly = 0, layout.h - 1 do
        for lx = 0, layout.w - 1 do
          local r, g, b, a = pixelAt(data, fx + lx, fy + ly)
          if r and (a or 0) >= 0.5 then
            mask[ly * layout.w + lx] = true
            local luma = luminance(r, g, b)
            if not outlineLuma or luma < outlineLuma then outlineLuma = luma end
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
    data = data, outlineLuma = outlineLuma,
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

local function frameTexel(m, frame, lx, ly)
  if lx < 0 or lx >= m.cellW or ly < 0 or ly >= m.cellH then return false end
  frame = tonumber(frame) or 0
  if frame < 0 or frame >= m.frames then return false end
  local fx, fy = frameOrigin(m, frame)
  if fx + m.cellW > m.sheetW or fy + m.cellH > m.sheetH then return false end
  local r, g, b, a = pixelAt(m.data, fx + lx, fy + ly)
  if not r or (a or 0) < 0.5 then return false end
  local outline = m.outlineLuma
    and math.abs(luminance(r, g, b) - m.outlineLuma) <= LUMA_EPSILON
  return true, outline
end

local function roleForFrame(frame, frames)
  frame = tonumber(frame) or 0
  if frame < 0 or frame >= frames then frame = 0 end
  if frame > 5 then frame = frame % 3 end
  return frame % 3
end

local function referenceFramesForRole(frame, frames, role)
  role = role or roleForFrame(frame, frames)
  if frames >= 6 then return role, role + 3 end
  if frames >= 3 then return role, nil end
  return tonumber(frame) or 0, nil
end

local function bodyTexelInFrame(m, frameIndex, lx, ly, dx, dy, sideColor)
  if sideColor ~= DEFAULT_SIDE_COLOR then return lx, ly end
  local opaque, outline = frameTexel(m, frameIndex, lx, ly)
  if not (opaque and outline) then return lx, ly end
  for step = 1, BODY_SEARCH_LIMIT do
    local bx, by = lx + dx * step, ly + dy * step
    local bodyOpaque, bodyOutline = frameTexel(m, frameIndex, bx, by)
    if bodyOpaque and not bodyOutline then return bx, by end
  end
  return lx, ly
end

local function buildSlabMesh(def, frame, depth, correction, m, sideColor)
  m = m or maskFor(def)
  if not m then return nil end
  frame = tonumber(frame) or 0
  if frame < 0 or frame >= m.frames then frame = 0 end
  local fx, fy = frameOrigin(m, frame)
  if fx + m.cellW > m.sheetW or fy + m.cellH > m.sheetH then return nil end
  local refFrameA, refFrameB = referenceFramesForRole(frame, m.frames)

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

  local function bodyTexel(lx, ly, dx, dy)
    return bodyTexelInFrame(m, frame, lx, ly, dx, dy, sideColor)
  end

  local function sameUv(lx, ly)
    local u, v = uv(lx, ly)
    return { u, v, u, v, u, v, u, v }
  end

  local function sameFrameUv(frameIndex, lx, ly)
    local ffx, ffy = frameOrigin(m, frameIndex)
    local u = (ffx + lx + 0.5) / m.sheetW
    local v = (ffy + ly + 0.5) / m.sheetH
    return { u, v, u, v, u, v, u, v }
  end

  local function sideUv(lx, ly, dx)
    local function tryFrame(frameIndex)
      if not frameIndex then return nil end
      local bx, by = bodyTexelInFrame(m, frameIndex, lx, ly, dx, 0, sideColor)
      if frameTexel(m, frameIndex, bx, by) then
        return sameFrameUv(frameIndex, bx, by)
      end
    end
    return tryFrame(refFrameA) or tryFrame(refFrameB)
      or sameUv(bodyTexel(lx, ly, dx, 0))
  end

  local function rectFrameUv(frameIndex, lx, ly, lx2, order)
    local ffx, ffy = frameOrigin(m, frameIndex)
    local u0 = (ffx + lx + RUN_UV_INSET) / m.sheetW
    local u1 = (ffx + lx2 + 1 - RUN_UV_INSET) / m.sheetW
    local v0 = (ffy + ly + RUN_UV_INSET) / m.sheetH
    local v1 = (ffy + ly + 1 - RUN_UV_INSET) / m.sheetH
    if order == "back" then
      return { u1, v1, u0, v1, u0, v0, u1, v0 }
    elseif order == "top" then
      return { u0, v0, u1, v0, u1, v1, u0, v1 }
    end
    return { u0, v1, u1, v1, u1, v0, u0, v0 }
  end

  local function rectUv(lx, ly, lx2, order)
    return rectFrameUv(frame, lx, ly, lx2, order)
  end

  local function bodyRectLine(frameIndex, lx, ly, lx2, dy)
    local allOutline = true
    for sx = lx, lx2 do
      local opaque, outline = frameTexel(m, frameIndex, sx, ly)
      if not opaque then return nil end
      if not outline then allOutline = false end
    end
    if sideColor ~= DEFAULT_SIDE_COLOR or not allOutline then return ly end
    for step = 1, BODY_SEARCH_LIMIT do
      local by = ly + dy * step
      local ok = true
      for sx = lx, lx2 do
        local opaque, outline = frameTexel(m, frameIndex, sx, by)
        if not (opaque and not outline) then
          ok = false
          break
        end
      end
      if ok then return by end
    end
    return ly
  end

  local function bodyRectUv(lx, ly, lx2, order, dy)
    local function tryFrame(frameIndex)
      if not frameIndex then return nil end
      local by = bodyRectLine(frameIndex, lx, ly, lx2, dy)
      if by then return rectFrameUv(frameIndex, lx, by, lx2, order) end
    end
    return tryFrame(refFrameA) or tryFrame(refFrameB)
      or rectUv(lx, ly, lx2, order)
  end

  -- DECISAO: SLAB tambem precisa fixar a classificacao de cor das faces novas
  -- por role, nao pelo frame corrente. O bug medido no red.png vinha de usar
  -- a caminhada diretamente: 49/180 posicoes de face de topo alternavam entre
  -- parado e andando, 14 delas na regiao do bone. A causa direta e a linha 0
  -- do frame 3 ficar vazia porque o sprite desce uma linha inteira. Topo/base
  -- usam runs retangulares, entao so trocamos para a referencia quando a linha
  -- inteira esta opaca; laterais usam o mesmo texel fixo por pixel.

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
  -- do frame que o alpha discard recorta. A comunidade mediu que 34/34
  -- pixels de silhueta lateral de red.png vinham no tom mais escuro, mas
  -- um passo para dentro so 16/34 ainda eram contorno. Por isso BODY pinta
  -- faces novas com texel interno, enquanto frente e tras continuam sendo
  -- a arte original. Topo/base so deslocavam o UV quando o run inteiro e
  -- contorno e a mesma linha interna inteira tem corpo; se misturar tons,
  -- preservar o run vale mais que quebrar o merge. A partir da v1.2.2, essa
  -- decisao roda em frames de referencia fixos para o SLAB nao piscar.
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
             bodyRectUv(lx, ly, lx2, "top", 1), OBJ_SHADE.top)
        quad(p(x, y + SIDE_INSET, z1), p(x + w, y + SIDE_INSET, z1),
             p(x + w, y + SIDE_INSET, z0), p(x, y + SIDE_INSET, z0),
             bodyRectUv(lx, ly, lx2, nil, -1), OBJ_SHADE.bottom)

        for sx = lx, lx2 do
          local px, sy = sx - m.minX, lowY - ly
          quad(p(px + SIDE_INSET, sy, z0), p(px + SIDE_INSET, sy, z1),
               p(px + SIDE_INSET, sy + 1, z1), p(px + SIDE_INSET, sy + 1, z0),
               sideUv(sx, ly, 1), OBJ_SHADE.side)
          quad(p(px + 1 - SIDE_INSET, sy, z1), p(px + 1 - SIDE_INSET, sy, z0),
               p(px + 1 - SIDE_INSET, sy + 1, z0), p(px + 1 - SIDE_INSET, sy + 1, z1),
               sideUv(sx, ly, -1), OBJ_SHADE.side)
        end
        lx = lx2 + 1
      else
        lx = lx + 1
      end
    end
  end

  return Voxel3D.newMesh(verts, idx)
end

local function frameBounds(m, frame)
  if frame < 0 or frame >= m.frames then return nil end
  local minX, maxX, minY, maxY = m.cellW, -1, m.cellH, -1
  for ly = 0, m.cellH - 1 do
    for lx = 0, m.cellW - 1 do
      if frameTexel(m, frame, lx, ly) then
        if lx < minX then minX = lx end
        if lx > maxX then maxX = lx end
        if ly < minY then minY = ly end
        if ly > maxY then maxY = ly end
      end
    end
  end
  if maxX < minX or maxY < minY then return nil end
  return { minX = minX, maxX = maxX, minY = minY, maxY = maxY }
end

local function carvedFrames(frame, frames)
  frame = tonumber(frame) or 0
  if frame < 0 or frame >= frames then frame = 0 end
  -- DECISAO: sprites Gen 1 usam buckets de tres vistas:
  -- parado down/up/left e, quando existe, andando down/up/left. A auditoria
  -- contou 20/73 sprites com so tres frames; eles tem as tres vistas completas
  -- e devem usar CARVED. Frames acima de 5 caem explicitamente no bucket de
  -- tres para nao transformar frame futuro em role silenciosamente invalido.
  local bucketFrame = frame
  if bucketFrame > 5 then bucketFrame = bucketFrame % 3 end
  local pose = (bucketFrame >= 3 and frames >= 6) and 3 or 0
  local role = bucketFrame - pose
  return {
    front = pose,
    back = pose + 1,
    side = pose + 2,
    role = role,
  }
end

local function buildCarvedMesh(def, frame, depth, correction, m, sideColor, shape)
  m = m or maskFor(def)
  if not (m and m.frames >= 3) then return nil end
  local pose = carvedFrames(frame, m.frames)
  if pose.back >= m.frames or pose.side >= m.frames then return nil end
  local carvedPlus = shape == "carved_plus"

  local frontBounds = frameBounds(m, pose.front)
  local backBounds = frameBounds(m, pose.back)
  local sideBounds = frameBounds(m, pose.side)
  if not (frontBounds and backBounds and sideBounds) then return nil end
  local widthFrame = pose.role == 1 and pose.back or pose.front
  local widthBounds = pose.role == 1 and backBounds or frontBounds
  local widthFrameA, widthFrameB = referenceFramesForRole(frame, m.frames,
    pose.role == 1 and 1 or 0)

  local verts, idx = {}, {}
  local pitchC, pitchS = math.cos(correction or 0), math.sin(correction or 0)
  local lowY = m.maxY
  local depthPixels = sideBounds.maxX - sideBounds.minX + 1
  local widthPixels = m.maxX - m.minX + 1
  local frontBackMinX = math.min(frontBounds.minX, backBounds.minX)
  local frontBackMaxX = math.max(frontBounds.maxX, backBounds.maxX)
  local frontFrameA = 0
  local frontFrameB = m.frames >= 6 and 3 or nil
  local sideLineRecess = {}

  local function mirrorX(lx)
    return frontBackMinX + frontBackMaxX - lx
  end

  local function frontXFor(lx)
    return pose.role == 1 and mirrorX(lx) or lx
  end

  local function backXFor(lx)
    return pose.role == 1 and lx or mirrorX(lx)
  end

  local function frameLuma(frameIndex, lx, ly)
    if not frameIndex then return nil end
    if lx < 0 or lx >= m.cellW or ly < 0 or ly >= m.cellH then return nil end
    if frameIndex < 0 or frameIndex >= m.frames then return nil end
    local fx, fy = frameOrigin(m, frameIndex)
    local r, g, b, a = pixelAt(m.data, fx + lx, fy + ly)
    if not r or (a or 0) < 0.5 then return nil end
    return luminance(r, g, b)
  end

  local function maxRecessForLine(ly)
    if sideLineRecess[ly] ~= nil then return sideLineRecess[ly] end
    local farthest = -1
    for sx = sideBounds.minX, sideBounds.maxX do
      if frameTexel(m, pose.side, sx, ly) then
        farthest = math.max(farthest, sx - sideBounds.minX)
      end
    end
    local limit = math.max(0, math.min(CARVED_PLUS_RECESS_STEPS, farthest))
    sideLineRecess[ly] = limit
    return limit
  end

  local reliefMinLuma, reliefMaxLuma
  if carvedPlus then
    if m.reliefScanned then
      reliefMinLuma, reliefMaxLuma = m.reliefMinLuma, m.reliefMaxLuma
    else
      local function scanReliefFrame(frameIndex)
        if not frameIndex then return end
        for ly = 0, m.cellH - 1 do
          for lx = 0, m.cellW - 1 do
            local luma = frameLuma(frameIndex, lx, ly)
            if luma and not (m.outlineLuma
                and math.abs(luma - m.outlineLuma) <= LUMA_EPSILON) then
              reliefMinLuma = reliefMinLuma and math.min(reliefMinLuma, luma) or luma
              reliefMaxLuma = reliefMaxLuma and math.max(reliefMaxLuma, luma) or luma
            end
          end
        end
      end
      scanReliefFrame(frontFrameA)
      scanReliefFrame(frontFrameB)
      if not reliefMinLuma then
        for ly = 0, m.cellH - 1 do
          for lx = 0, m.cellW - 1 do
            local luma = frameLuma(frontFrameA, lx, ly) or frameLuma(frontFrameB, lx, ly)
            if luma then
              reliefMinLuma = reliefMinLuma and math.min(reliefMinLuma, luma) or luma
              reliefMaxLuma = reliefMaxLuma and math.max(reliefMaxLuma, luma) or luma
            end
          end
        end
      end
      m.reliefScanned = true
      m.reliefMinLuma, m.reliefMaxLuma = reliefMinLuma, reliefMaxLuma
    end
  end

  -- DECISAO: o frame lateral 2 e o personagem olhando para a esquerda.
  -- Nas folhas Gen 1 essa borda esquerda e o rosto. Por isso a coluna
  -- opaca mais a esquerda da vista lateral fica em z = 0, e as colunas
  -- seguintes caminham para z negativo, em direcao a nuca. No red.png o
  -- tronco medido e 14 colunas de frente e 11 de lado; a caixa opaca completa
  -- da lateral tem 13 colunas por incluir pixels fora do tronco. Em ambos os
  -- casos, profundidade vem da arte, nao do slider de slab.
  --
  -- DECISAO: v1.2.1 acrescenta a silhueta de costas na intersecao. Como frente
  -- e costas sao vistas opostas, a coluna X da vista traseira entra espelhada;
  -- sem esse espelho o casco perde quase tudo em sprites assimetricos. O eixo
  -- vem so do par frente/costas, nao do bbox global da folha: Kim mediu 12/40
  -- folhas de 6 frames em que a vista lateral alarga o bbox global
  -- (biker 0..15 contra frente 1..14; bird 0..15 contra 2..13;
  -- brunette_girl e cooltrainer_f 1..15 contra 2..13). Usar esse global
  -- cortava 3% a 8% dos voxels legitimos em 7/8 sprites auditados.
  --
  -- DECISAO: CARVED+ recua a superficie frontal por tom em so 2 passos. red.png
  -- tem 3 tons opacos de corpo alem do contorno; mais degraus so fingiriam uma
  -- precisao que a arte nao tem. A mesma arte usa tom para contorno e volume:
  -- onde o artista escureceu so para separar bone da testa, o relevo vira sulco.
  -- Por isso e um degrau proprio, nao o default. O recuo tambem e limitado pela
  -- profundidade real de cada linha lateral: sempre sobra pelo menos uma camada,
  -- porque sprite fino de mod externo nao pode virar um buraco atravessando o
  -- personagem.
  local function solid(lx, ly, sx)
    if lx < widthBounds.minX or lx > widthBounds.maxX then return false end
    if ly < widthBounds.minY or ly > widthBounds.maxY then return false end
    if sx < sideBounds.minX or sx > sideBounds.maxX then return false end
    local frontX = frontXFor(lx)
    if not frameTexel(m, pose.front, frontX, ly) then return false end
    if not frameTexel(m, pose.back, backXFor(lx), ly) then return false end
    if not frameTexel(m, pose.side, sx, ly) then return false end
    if carvedPlus and reliefMinLuma and reliefMaxLuma
        and reliefMaxLuma > reliefMinLuma + LUMA_EPSILON then
      local luma = frameLuma(frontFrameA, frontX, ly)
        or frameLuma(frontFrameB, frontX, ly)
      if luma then
        local dark = (reliefMaxLuma - luma) / (reliefMaxLuma - reliefMinLuma)
        local recess = math.max(0, math.min(maxRecessForLine(ly),
          math.floor(dark * CARVED_PLUS_RECESS_STEPS + 0.5)))
        if (sx - sideBounds.minX) < recess then return false end
      end
    end
    return true
  end

  local function uvFor(frameIndex, lx, ly)
    local fx, fy = frameOrigin(m, frameIndex)
    return (fx + lx + 0.5) / m.sheetW, (fy + ly + 0.5) / m.sheetH
  end

  local function sameUv(frameIndex, lx, ly)
    local u, v = uvFor(frameIndex, lx, ly)
    return { u, v, u, v, u, v, u, v }
  end

  local function opaqueFrame(preferred, fallback, lx, ly)
    if frameTexel(m, preferred, lx, ly) then return preferred end
    if fallback and frameTexel(m, fallback, lx, ly) then return fallback end
    return preferred
  end

  local function bodyTexel(frameIndex, lx, ly, dx, dy)
    return bodyTexelInFrame(m, frameIndex, lx, ly, dx, dy, sideColor)
  end

  local sideFrameA, sideFrameB = referenceFramesForRole(frame, m.frames, 2)

  local function sideUv(sx, ly)
    local middle = (sideBounds.minX + sideBounds.maxX) / 2
    local dx = sx <= middle and 1 or -1
    -- DECISAO: a casca lateral tem que ter classificacao estavel entre
    -- frames. No red.png, 161/378 posicoes laterais alternavam corpo/contorno
    -- porque a malha vinha da silhueta combinada, mas a busca de cor olhava
    -- so o frame corrente. Procuramos uma vez entre as vistas laterais da
    -- folha e fixamos o primeiro texel opaco encontrado; assim caminhar nao
    -- troca vermelho por preto na mesma posicao da face.
    local function tryFrame(sideFrame)
      if not sideFrame then return nil end
      local bx, by = bodyTexel(sideFrame, sx, ly, dx, 0)
      if frameTexel(m, sideFrame, bx, by) then
        return sameUv(sideFrame, bx, by)
      end
    end
    local uv = tryFrame(sideFrameA) or tryFrame(sideFrameB)
    if uv then return uv end
    return sameUv(pose.side, sx, ly)
  end

  local function topUv(lx, ly, dy)
    -- DECISAO: topo/base precisam de classificacao fixa como as laterais.
    -- O bug medido no red.png vinha de usar o frame corrente: 49/180 posicoes
    -- de face de topo alternavam parado/andando, 14 delas nas 6 linhas de cima
    -- do bone. A causa direta e a linha 0 existir no frame 0
    -- (".....######.....") e sumir no frame 3, porque o sprite inteiro desce uma
    -- linha ao andar. Tentar a vista de referencia e so cair para a caminhada
    -- quando ha opacidade fixa a cor da face no mesmo texel logico.
    local function tryFrame(frameIndex)
      if not frameIndex then return nil end
      local bx, by = bodyTexel(frameIndex, lx, ly, 0, dy)
      if frameTexel(m, frameIndex, bx, by) then
        return sameUv(frameIndex, bx, by)
      end
    end
    local uv = tryFrame(widthFrameA) or tryFrame(widthFrameB)
    if uv then return uv end
    return sameUv(widthFrame, lx, ly)
  end

  local function p(x, y, z)
    local ox, oz = x, z
    if pose.role == 1 then
      ox, oz = widthPixels - x, -depthPixels - z
    elseif pose.role == 2 then
      -- DECISAO: o role lateral tambem precisa compensar o pivo. Sem isso,
      -- red.png medido no main.lua real ia de Y [0, 13] na frente para
      -- Y [-14, 0] de lado: o z positivo entrava na contra-rotacao do lean
      -- como deslocamento vertical e metade das direcoes afundava no chao.
      -- A compensacao mantem o volume em z nao positivo, como frente e costas.
      ox, oz = -z, x - widthPixels
    end
    return { ox, y * pitchC - oz * pitchS, y * pitchS + oz * pitchC }
  end

  local function quad(c1, c2, c3, c4, uv4, shade)
    local n = #verts / 4
    verts[#verts + 1] = { c1[1], c1[2], c1[3], uv4[1], uv4[2], shade }
    verts[#verts + 1] = { c2[1], c2[2], c2[3], uv4[3], uv4[4], shade }
    verts[#verts + 1] = { c3[1], c3[2], c3[3], uv4[5], uv4[6], shade }
    verts[#verts + 1] = { c4[1], c4[2], c4[3], uv4[7], uv4[8], shade }
    Voxel3D.pushQuad(idx, n)
  end

  for ly = m.minY, m.maxY do
    for lx = widthBounds.minX, widthBounds.maxX do
      for sx = sideBounds.minX, sideBounds.maxX do
        if solid(lx, ly, sx) then
          local x0, x1 = lx - m.minX, lx - m.minX + 1
          local y0, y1 = lowY - ly, lowY - ly + 1
          local z0 = -(sx - sideBounds.minX)
          local z1 = z0 - 1

          if not solid(lx, ly, sx - 1) then
            quad(p(x0, y0, z0), p(x1, y0, z0), p(x1, y1, z0),
                 p(x0, y1, z0), sameUv(opaqueFrame(pose.front, widthFrame, lx, ly), lx, ly),
                 OBJ_SHADE.front)
          end
          if not solid(lx, ly, sx + 1) then
            quad(p(x1, y0, z1), p(x0, y0, z1), p(x0, y1, z1),
                 p(x1, y1, z1), sameUv(opaqueFrame(pose.back, widthFrame, lx, ly), lx, ly),
                 OBJ_SHADE.back)
          end
          if not solid(lx - 1, ly, sx) then
            quad(p(x0, y0, z1), p(x0, y0, z0), p(x0, y1, z0),
                 p(x0, y1, z1), sideUv(sx, ly), OBJ_SHADE.side)
          end
          if not solid(lx + 1, ly, sx) then
            quad(p(x1, y0, z0), p(x1, y0, z1), p(x1, y1, z1),
                 p(x1, y1, z0), sideUv(sx, ly), OBJ_SHADE.side)
          end
          if not solid(lx, ly - 1, sx) then
            quad(p(x0, y1, z1), p(x1, y1, z1), p(x1, y1, z0),
                 p(x0, y1, z0), topUv(lx, ly, 1), OBJ_SHADE.top)
          end
          if not solid(lx, ly + 1, sx) then
            quad(p(x0, y0, z0), p(x1, y0, z0), p(x1, y0, z1),
                 p(x0, y0, z1), topUv(lx, ly, -1), OBJ_SHADE.bottom)
          end
        end
      end
    end
  end

  return Voxel3D.newMesh(verts, idx)
end

local function buildSelectedMesh(def, frame, depth, correction, m, sideColor, shape)
  if shape == "carved" or shape == "carved_plus" then
    local ok, mesh = pcall(buildCarvedMesh, def, frame, depth, correction, m,
      sideColor, shape)
    if ok and mesh then return mesh end
  end
  return buildSlabMesh(def, frame, depth, correction, m, sideColor)
end

local function cacheKey(def, frame, depth, correction, layout, sideColor, shape)
  local depthPart = (shape == "carved" or shape == "carved_plus") and "art"
    or tostring(depth)
  return table.concat({
    tostring(def and def.image or ""),
    tostring(def and def.frames or ""),
    tostring(frame or 0),
    depthPart,
    tostring(sideColor or ""),
    tostring(shape or ""),
    tostring(layout and layout.cellW or ""),
    tostring(layout and layout.cellH or ""),
    tostring(layout and layout.columns or ""),
    pitchKey(correction),
  }, "#")
end

local function voxelMesh(def, frame)
  local depth = depthValue or readDepth()
  if depth == "off" then return originalMesh(def, frame) end
  local sideColor = sideColorValue or readSideColor()
  local shape = shapeValue or readShape()
  local correction = quantizeCorrection(leanCorrection())
  local okMask, m = pcall(maskFor, def)
  if not (okMask and m) then return originalMesh(def, frame) end
  local key = cacheKey(def, frame, depth, correction, m, sideColor, shape)
  if meshes[key] ~= nil then
    touchMeshKey(key)
  else
    local ok, mesh = pcall(buildSelectedMesh, def, frame, depth, correction,
      m, sideColor, shape)
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
