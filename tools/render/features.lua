-- Feature extractor (`features=<file>`), split out of the render harness's
-- main.lua (roadmap item 19).
--
-- LOVE loads tools/render/ as a single game, so this module reads the
-- harness's shared mod-loading and draw-state helpers through `ctx`, a table
-- main.lua builds and hands over via Features.init() before calling
-- love.features(). That keeps one copy of buildGeometry/classifyMesh/drawCell
-- instead of forking them.

local Features = {}
local ctx

function Features.init(c) ctx = c end

--------------------------------------------------------------------------
-- FEATURES  (features=<file>)
--------------------------------------------------------------------------
-- The quantities the judge sees. They come from the MESH and not from a
-- rendered frame, which is a choice and not an economy: measuring on the mesh
-- is deterministic, does not depend on camera or clock, and runs in
-- milliseconds per variant, so thirty choices become sixty variants in seconds
-- and the model can be refit whenever the feature list changes.
--
-- The list starts with the quantities this project has already measured and
-- that have already explained something:
--
--   top fraction    the law that killed four attempts at variable depth: top
--                    carries no art and this camera looks at it. If Kim's
--                    preference ignores this, the law is worth less than we
--                    think, and that is a result
--   art fraction     front and back are the only faces the artist drew
--                    (IS_ART); the rest is invented surface
--   quads            cost and complexity of the shape
--   depth            how much the body comes off the sprite's plane
--   tones            FRONT SHAPE and TOP DOME touch no vertex, only
--                    shade, so without shade statistics they would be
--                    invisible to the model
--
-- There is no PIXEL art% here, which is the metric this project has always
-- judged by. It needs the provenance render, which needs a grid and screen
-- reading. That is left for the second pass, and until then the judge's
-- baseline is "the best single feature", which is a more honest opponent than
-- it looks: if the fitted model does not beat ONE column, it learned nothing.
local FEATURE_NOMES = {
  "quads", "frente", "verso", "lado", "topo", "baixo",
  "arte", "profundidade", "shade_media", "shade_desvio", "shade_niveis",
  -- These two come from RENDER, not from the mesh, and are the reason this
  -- mode stopped being just vertex arithmetic. `art_px` is the metric this
  -- project has always judged by: the fraction of what the player SEES that
  -- is the artist's work, not the fraction of quads. While it was not here,
  -- the judge's opponent was "the best single column" among columns where
  -- none was the house's ruler.
  "art_px", "cobertura", "luz_media", "tons",
  -- Added after the judge said mean luminance was carrying the fit almost
  -- alone: it cannot tell a few strong darks from an evenly dim character.
  "luz_desvio", "contraste", "escuro_frac", "gradiente",
}

-- Fraction of PIXEL that came from an art face (front and back), measured the
-- same way the contact sheet measures: draws with PROVENANCE colour on a
-- canvas and reads it back. Canvas and not screenshot on purpose: a
-- screenshot is only ready at the end of the frame, and this mode runs
-- entirely inside love.load.
local function artePorPixel(row, cell, yawDeg)
  local colour = love.graphics.newCanvas(cell, cell)
  local depth = love.graphics.newCanvas(cell, cell,
    { format = "depth24", readable = false })
  love.graphics.setCanvas({ colour, depthstencil = depth })
  love.graphics.clear(0, 0, 0, 0, true, true)
  love.graphics.setDepthMode("less", true)
  love.graphics.setShader(ctx.state.shader)
  ctx.state.shader:send("provenance", 1)
  ctx.drawCell(row, math.rad(yawDeg or 0), 0, 0, cell, true)
  ctx.state.shader:send("provenance", 0)
  love.graphics.setShader()
  love.graphics.setDepthMode("always", false)
  love.graphics.setCanvas()

  local img = colour:newImageData()
  local arte, total = 0, 0
  for y = 0, cell - 1 do
    for x = 0, cell - 1 do
      local r, g, b, a = img:getPixel(x, y)
      if a >= 0.5 then
        total = total + 1
        -- Same classification as kindAt in computeMetrics: front and back are
        -- the only faces the artist drew.
        if (g > 0.75 and r < 0.25) or (g > 0.25 and r < 0.25 and b < 0.25) then
          arte = arte + 1
        end
      end
    end
  end

  -- SECOND PASS, WITH REAL COLOUR, and it exists because of a hole
  -- the judge itself pointed out: `SIDE COLOR` kept appearing in the list of
  -- "blind features" even after art_px was added. Makes sense: it swaps WHICH
  -- texel the side face samples (body or outline), which changes the colour
  -- on screen and does not change the provenance, which stays "side". No
  -- geometry column and no provenance column sees colour.
  love.graphics.setCanvas({ colour, depthstencil = depth })
  love.graphics.clear(0, 0, 0, 0, true, true)
  love.graphics.setDepthMode("less", true)
  love.graphics.setShader(ctx.state.shader)
  ctx.drawCell(row, math.rad(yawDeg or 0), 0, 0, cell)
  love.graphics.setShader()
  love.graphics.setDepthMode("always", false)
  love.graphics.setCanvas()

  -- TONAL STATISTICS, and there are more of them than there used to be
  -- because the judge said so.
  --
  -- Fitted on Kim's 106 real choices with the composition features corrected
  -- to area, cross validated over five folds: the model scored 73.6% and the
  -- best SINGLE column scored 70.6%, and that column was `luz_media` in four
  -- of the five folds. Fourteen other features were adding three points
  -- against six points of spread.
  --
  -- So what decides these choices is TONAL, and mean luminance is a blunt
  -- instrument for it: it cannot tell a character with a few strong darks from
  -- one that is evenly dim. Everything below comes out of the SAME sweep that
  -- already ran, so the cost is arithmetic rather than another render.
  local cor = colour:newImageData()
  local soma, n, tons = 0, 0, {}
  local vals = {}
  local somaGrad, nGrad = 0, 0
  local escuros = 0
  for y = 0, cell - 1 do
    for x = 0, cell - 1 do
      local r, g, b, a = cor:getPixel(x, y)
      if a >= 0.5 then
        local l = 0.299 * r + 0.587 * g + 0.114 * b
        soma, n = soma + l, n + 1
        tons[math.floor(l * 32 + 0.5)] = true
        vals[#vals + 1] = l
        if l < 0.2 then escuros = escuros + 1 end
        -- LOCAL gradient: how much the tone moves between neighbours. This is
        -- what separates "stepped into bands" from "flat", which is exactly
        -- what FRONT SHAPE and TOP DOME do and what no existing column saw.
        if x + 1 < cell then
          local r2, g2, b2, a2 = cor:getPixel(x + 1, y)
          if a2 >= 0.5 then
            local l2 = 0.299 * r2 + 0.587 * g2 + 0.114 * b2
            somaGrad, nGrad = somaGrad + math.abs(l2 - l), nGrad + 1
          end
        end
      end
    end
  end
  local distintos = 0
  for _ in pairs(tons) do distintos = distintos + 1 end

  local media = n > 0 and soma / n or 0
  local varia = 0
  for _, l in ipairs(vals) do varia = varia + (l - media) ^ 2 end
  local desvio = n > 0 and math.sqrt(varia / n) or 0

  -- Percentiles rather than min and max: one stray bright pixel from the
  -- outline should not define the range, and in this art there is always one.
  table.sort(vals)
  local function pct(p)
    if #vals == 0 then return 0 end
    local i = math.max(1, math.min(#vals, math.floor(#vals * p + 0.5)))
    return vals[i]
  end
  local p10, p90 = pct(0.10), pct(0.90)

  colour:release(); depth:release()
  return (total > 0 and arte / total or 0), total / (cell * cell),
         media, distintos,
         desvio, p90 - p10, (n > 0 and escuros / n or 0),
         (nGrad > 0 and somaGrad / nGrad or 0)
end

local function featuresDaMalha(mesh, kinds)
  local f = {}
  for _, n in ipairs(FEATURE_NOMES) do f[n] = 0 end
  if not (mesh and mesh.verts and #mesh.verts > 0) then return f end
  local quads = math.floor(#mesh.verts / 4)
  f.quads = quads
  -- COMPOSITION IS WEIGHED BY AREA, NOT COUNTED BY QUAD.
  --
  -- These were fractions of quad COUNT, and that made them measure polygon
  -- budget instead of what a character looks like. Any option that splits a
  -- run inflates them without moving a single vertex.
  --
  -- FRONT SHAPE is exactly that option, by design: it steps a run into tone
  -- bands and is built so that no vertex position changes, which is why the
  -- ruler can assert IoU 1.000 for it at any strength. Measured on `warden`,
  -- turning it from off to HIGH:
  --
  --     quads      110  ->  281
  --     frente   0.209  ->  0.690     the old count fraction
  --     art_px  0.7311  -> 0.7311     the pixel fraction, unchanged
  --
  -- The judge fitted on Kim's 106 real choices then ranked FRONT SHAPE HIGH
  -- first in the entire candidate space and FRONT SHAPE off last, crediting a
  -- 230% rise in "front faces" that was three times the same face. It may well
  -- have been right that he prefers it, for a reason that does not exist, and
  -- the danger is the next candidate that adds quads without improving
  -- anything: the model would reward that just as hard.
  --
  -- Area in MESH space, not projected area, on purpose. Projected area would
  -- depend on the camera rung and stop being comparable between variants,
  -- and the specific defect being fixed is polygon count, which mesh area is
  -- already immune to: a run split into three bands has the area of the run.
  local function areaQuad(i)
    local a, b, c, d = mesh.verts[i], mesh.verts[i+1], mesh.verts[i+2], mesh.verts[i+3]
    if not (a and b and c and d) then return 0 end
    local function tri(p, q, r)
      local ux, uy, uz = q[1]-p[1], q[2]-p[2], q[3]-p[3]
      local vx, vy, vz = r[1]-p[1], r[2]-p[2], r[3]-p[3]
      local cx, cy, cz = uy*vz - uz*vy, uz*vx - ux*vz, ux*vy - uy*vx
      return 0.5 * math.sqrt(cx*cx + cy*cy + cz*cz)
    end
    return tri(a, b, c) + tri(a, c, d)
  end
  local area, areaTotal = {}, 0
  for qi = 1, quads do
    local k = (kinds or {})[qi]
    local s = areaQuad((qi - 1) * 4 + 1)
    areaTotal = areaTotal + s
    if k then area[k] = (area[k] or 0) + s end
  end
  local function frac(k)
    return areaTotal > 0 and (area[k] or 0) / areaTotal or 0
  end
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

-- A single cell, at the game's default pitch. The pitch matters because the
-- art fraction depends on the camera: it is the law this project measured,
-- top carries no art and this camera looks at it.
local FEATURE_CELL, FEATURE_RUNG = 140, 35

function love.features()
  -- Line-buffered output, not block-buffered. Without this, a run interrupted
  -- halfway through delivers a file truncated IN THE MIDDLE OF A LINE, and a
  -- careful reader can still read the whole lines that survived as if they
  -- were the result. It happened: trailer.sh does `pkill -x love` and killed
  -- an extraction that was running in parallel, and what was left in the file
  -- looked like a short measurement instead of an interrupted one.
  io.stdout:setvbuf("line")
  love.window.setMode(FEATURE_CELL, FEATURE_CELL, { depth = 24, vsync = 0 })
  ctx.state.width, ctx.state.height = FEATURE_CELL, FEATURE_CELL
  ctx.state.shader = love.graphics.newShader(ctx.SHADER)
  local pal = ctx.PALETTES[ctx.opts.palette] or ctx.PALETTES.obj
  for i = 1, 4 do ctx.state.shader:send("pal" .. (i - 1), pal[i]) end
  local entrada = assert(io.open(ctx.opts.features, "r"),
    "nao consegui abrir " .. ctx.opts.features)
  local cab = { "folha", "frame", "clock", "estado" }
  for _, n in ipairs(FEATURE_NOMES) do cab[#cab + 1] = n end
  print("#" .. table.concat(cab, "\t"))
  local linhas, falhas = 0, 0
  for linha in entrada:lines() do
    -- Four columns: sheet, frame, clock, state. The middle two exist
    -- because measuring the feature under a condition different from the one
    -- the person judged produces zero difference precisely in the options that
    -- only appear at certain instants or certain poses.
    local folha, qf, qt, estado = linha:match("^(%S+)\t(%S+)\t(%S+)\t(.*)$")
    if not folha then
      folha, estado = linha:match("^(%S+)\t(.*)$")
      qf, qt = "0", "0"
    end
    if folha then
      local path = ctx.SPRITE_DIR .. folha .. ".png"
      local ok, data = pcall(ctx.loadImageData, path)
      if not ok then
        io.stderr:write("no sheet: " .. path .. "\n")
      else
        local sw, sh = data:getDimensions()
        local def = { image = path, frames = math.max(1, math.floor(sh / 16)) }
        local valores = {}
        for par in estado:gmatch("[^,]+") do
          local k, v = par:match("^%s*([%w_]+)%s*:%s*(.-)%s*$")
          if k then valores[k] = tonumber(v) or v end
        end
        ctx.opts.opt = estado
        local shape = valores.shape or "slab"
        local depth = tonumber(valores.depth) or 3
        -- Frozen clock: the blink moves UVs and would change the shade
        -- signature depending on the moment this command ran. A feature has
        -- to be a function of state, not of the moment.
        local relogio = love.timer.getTime
        local instante = tonumber(qt) or 0
        love.timer.getTime = function() return instante end
        local quadro = math.floor(tonumber(qf) or 0)
        if quadro >= def.frames then quadro = quadro % def.frames end
        local mesh = ctx.buildGeometry(data, def, quadro, shape, depth,
                                   valores.side_color or "body")
        love.timer.getTime = relogio
        local kinds
        if mesh then
          local role = (shape == "carved" or shape == "carved_plus") and 0 or 0
          kinds = ctx.classifyMesh(mesh, role)
        end
        -- A MESH THAT FAILED TO BUILD DOES NOT BECOME A LINE OF ZEROS.
        --
        -- featuresDaMalha returns everything zero when the mesh is nil, and
        -- the line came out the same as the others. On the judge's side that
        -- is indistinguishable from a variant measured at zero, and it enters
        -- the fit as if it were data. And juiz.sh's only completeness check
        -- is a line count, which a line of zeros satisfies.
        if not mesh then
          io.stderr:write("NO MESH: " .. folha .. "\t" .. estado .. "\n")
          falhas = falhas + 1
        else
        local f = featuresDaMalha(mesh, kinds)
        local texture = love.graphics.newImage(data)
        texture:setFilter("nearest", "nearest")
        local okArte, px, cob, luz, tons, lde, ctr, esc, grd = pcall(artePorPixel, {
          sprite = folha, frame = quadro, shape = shape, mesh = mesh,
          texture = texture, cellW = sw, cellH = sh / def.frames,
          kinds = kinds, role = 0, pitch = math.rad(90 - FEATURE_RUNG),
        }, FEATURE_CELL, 0)
        f.art_px = okArte and px or 0
        f.cobertura = okArte and cob or 0
        f.luz_media = okArte and luz or 0
        f.tons = okArte and tons or 0
        f.luz_desvio = okArte and lde or 0
        f.contraste = okArte and ctr or 0
        f.escuro_frac = okArte and esc or 0
        f.gradiente = okArte and grd or 0
        if not okArte then
          io.stderr:write("SEM RENDER: " .. folha .. "  " .. tostring(px) .. "\n")
        end
        texture:release()
        -- THE REQUESTED FRAME, not the frame used. The sheet can have fewer
        -- frames than requested and then it gets reduced by modulo; printing
        -- the reduced value changes the key and the line stops matching the
        -- choice that generated it. The symptom is "no features", which looks
        -- like a missing measurement and is actually a measurement made and
        -- filed under a different name.
        local saida = { folha, qf, qt, estado }
        for _, n in ipairs(FEATURE_NOMES) do
          saida[#saida + 1] = string.format("%.6f", f[n])
        end
        print(table.concat(saida, "\t"))
        linhas = linhas + 1
        end
      end
    end
  end
  entrada:close()
  io.stderr:write(string.format("features for %d variants, %d with no mesh\n", linhas, falhas))
  -- ACTUALLY EXIT, and this is the reason for three lines instead of one.
  --
  -- love.event.quit() alone is not enough: it only schedules the exit, and the
  -- next frame still calls love.draw, which here blows up on state.bg (nil,
  -- because features mode never assembles the scene). An error in love.draw
  -- opens LOVE's error screen, which waits for a key FOREVER.
  --
  -- And the worst part: this went unnoticed because the first test of this
  -- mode ended in `| head`, and head closing the pipe killed the process with
  -- SIGPIPE. The tool looked like it exited on its own. Whoever called it
  -- without a pipe was left hanging. This is already the second time in this
  -- project that a process that does not terminate disguises itself as a
  -- process that did.
  love.draw = function() end
  love.update = function() love.event.quit() end
  love.event.quit()
end

return Features
