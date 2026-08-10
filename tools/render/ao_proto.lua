-- Ambient-occlusion prototype, split out of the render harness's main.lua
-- (roadmap item 19).
--
-- Self-contained on purpose: it only needs `math` and the ImageData/mesh
-- shapes passed in by the caller. It has no dependency on the harness's
-- mod-loading, camera, or draw state, so it can be required and used from
-- any of the other render tools without pulling the rest of the harness in.

local M = {}

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
function M.setAoStrength(v)
  AO_STRENGTH = v
  AO_STEP = 0.09 * v
  AO_GROUND = 0.12 * v
end
local AO_RISE = 6
local AO_FLOOR = 0.25

-- Occupancy of a SLAB, rebuilt from the sheet rather than from the mesh: the
-- mesh only carries exposed faces, and AO needs to know about the voxels that
-- are NOT exposed, which are exactly the ones doing the occluding.
function M.slabOccupancy(data, frames, frame, cellW, cellH, depth)
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
function M.quadAO(verts, i, solid)
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

-- Setters for the three knobs above: main.lua reads them from `opts` at
-- startup, but the values themselves are private to this module.
function M.setRecessOverride(v) RECESS_OVERRIDE = v end
function M.setOutlineFront(v) OUTLINE_FRONT = v end
function M.setDepthMap(v) DEPTH_MAP = v end

function M.sculptMesh(data, frames, frame, mode)
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

return M
