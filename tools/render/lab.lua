-- Laboratory and A/B choice mode (`lab=1`, `labab=1`), split out of the
-- render harness's main.lua (roadmap item 19).
--
-- LOVE loads tools/render/ as a single game, so this module reads the
-- harness's shared mod-loading and draw-state helpers through `ctx`, a table
-- main.lua builds and hands over via Lab.init() before calling
-- love.labsetup(). That keeps one copy of buildGeometry/classifyMesh/drawCell
-- instead of forking them.

local Lab = {}
local ctx

function Lab.init(c) ctx = c end

--------------------------------------------------------------------------
-- LABORATORY  (lab=1)
--------------------------------------------------------------------------
-- A character editor: one large sheet in the middle, all the mod's options
-- on the side, and navigation through the game's 67 sheets. It serves three
-- things at the same time:
--
--   1. seeing an option change instantly, instead of waiting for a contact sheet;
--   2. seeing the option on SOMEONE WHO IS NOT RED, which is where regressions
--      live (nurse has three frames, boulder has one, snorlax is wider);
--   3. recording a CHOICE, which is the one thing no number here produces.
--
-- The third is the real reason. This project has already measured that an
-- AI redraw satisfies every numeric constraint and delivers worse art, so
-- the generator cannot be trained against the rulers we have. What is
-- missing is a judge, and a judge starts with someone choosing between two.

local FACINGS = {
  { nome = "FRENTE", pose = 0, anda = 3 },
  { nome = "COSTAS", pose = 1, anda = 4 },
  { nome = "LADO",   pose = 2, anda = 5 },
}

local lab = {
  folhas = {}, i = 1, facing = 1, andando = false, tocando = true,
  rung = 35, yaw = 0, sel = 1, valores = {}, opcoes = {},
  row = nil, erro = nil, sujo = true, t = 0, construcoes = 0,
  -- choice mode
  ab = false, par = nil, rowA = nil, rowB = nil, escolhas = 0, pulos = 0,
  -- region boundary overlay (roadmap item 11, key `b`)
  overlay = false,
}

-- Where choices are stored. One line per choice, key=value, so the judge's
-- fit can be redone from scratch and audited later.
--
-- Deliberately does NOT record any feature here: features are recalculated
-- from the recorded state, by the ruler itself, when it is time. Recording a
-- measured number alongside would freeze the feature list at the first
-- version, and the feature list is exactly what will change when the judge
-- stalls. Declared here because love.labsetup, further below, needs to call
-- this and choice mode is defined after it.
local labMontaPar

local function labGrava(linha)
  local caminho = love.filesystem.getSaveDirectory() .. "/" .. ctx.opts.labfile
  local f = io.open(caminho, "a")
  if not f then print("NAO CONSEGUI GRAVAR A ESCOLHA em " .. caminho); return false end
  f:write(linha .. "\n")
  f:close()
  return true
end

local function labEstadoTexto(v)
  local partes = {}
  for _, o in ipairs(ctx.getLabSchema() or {}) do
    partes[#partes + 1] = o.key .. "=" .. tostring(v[o.key])
  end
  return table.concat(partes, " ")
end

local function labFolhas()
  local out = {}
  local p = io.popen("ls " .. ctx.SPRITE_DIR .. " 2>/dev/null")
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

-- Builds the mesh for the current state. Passes EVERY option through the
-- generic `opt=` pass-through, so a new option shows up here without a
-- single new line.
local function labMalha(nomeFolha, frame, valores)
  local path = ctx.SPRITE_DIR .. nomeFolha .. ".png"
  local ok, data = pcall(ctx.loadImageData, path)
  if not ok then return nil, "sem folha: " .. path end
  local sw, sh = data:getDimensions()
  local def = { image = path, frames = math.max(1, math.floor(sh / 16)) }
  if frame >= def.frames then frame = frame % def.frames end
  local pares = {}
  for _, o in ipairs(ctx.getLabSchema() or {}) do
    if valores[o.key] ~= nil then
      pares[#pares + 1] = o.key .. ":" .. tostring(valores[o.key])
    end
  end
  ctx.opts.opt = table.concat(pares, ",")
  local shape = valores.shape or "slab"
  local depth = tonumber(valores.depth) or 3
  local mesh, why = ctx.buildGeometry(data, def, frame, shape, depth,
                                  valores.side_color or "body")
  return {
    sprite = nomeFolha, frame = frame, shape = shape, mesh = mesh, why = why,
    texture = nil, data = data,
    cellW = sw, cellH = sh / def.frames, frames = def.frames,
    role = (shape == "carved" or shape == "carved_plus") and (frame % 3) or 0,
  }
end

-- Signature of a mesh, to answer "does this option change the GEOMETRY?".
local function labAssinatura(m)
  if not m or not m.verts then return "sem malha" end
  local s = #m.verts
  for i = 1, #m.verts do
    local v = m.verts[i]
    s = s + v[1] * 7 + v[2] * 13 + v[3] * 17 + v[4] * 23 + v[5] * 29 + v[6] * 31
  end
  return string.format("%d:%.4f", #m.verts, s)
end

-- Which options this laboratory can show, MEASURED and not assumed.
--
-- BREATH, SWAY, MOTION LAG and FOOTFALL touch no vertex: they post-multiply
-- the matrix the host passes to Voxel3D.draw, and here there is no real host
-- and no matrix. A control that does nothing is worse than an absent
-- control, because the person moves it, sees no effect, and concludes the
-- feature is broken. So instead of keeping a hand-written list (which rots
-- with the next new option), we BUILD each level and compare: if no level
-- changes the mesh, the option belongs to the game, not to here.
--
-- The first version of this got TWO options wrong at once, both by comparing
-- at a single point instead of on the axes where the effect lives. The axes,
-- now explicit, each one by a mechanism read from the mod:
--
--   FRAME. STEP WEIGHT only shifts z when `andando` (main.lua:1407). Measured
--   only in the standing pose, it changes nothing and looked like a game
--   option. So the sweep includes a walking pose.
--
--   CLOCK. The blink closes for 0.12 s in a period between 3 and 6 s, with a
--   phase per sheet (main.lua:408, 1085-1096). Three arbitrarily chosen
--   instants miss it almost every time. A step of 0.1 s covers any 0.12 s
--   window, so the sweep FINDS the blink instead of hoping to catch it. This
--   project already concluded the blink was not working when it was, exactly
--   this way.
--
-- Exits early on the first difference, so the real cost is high only for the
-- option that in fact does not touch the mesh, which is what one wants to
-- prove carefully.
local LAB_CLOCK_PASSO = 0.1
local LAB_CLOCK_ATE = 6.0

local function labClassifica(base)
  local relogio = love.timer.getTime
  local geometrica, construcoes = {}, 0
  for _, o in ipairs(ctx.getLabSchema() or {}) do
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
    -- Texture per SHEET, not per frame. While playing, this used to be an
    -- image upload per frame just to resend identical bytes.
    lab.texturas = lab.texturas or {}
    local tex = lab.texturas[row.sprite]
    if not tex then
      tex = love.graphics.newImage(row.data)
      tex:setFilter("nearest", "nearest")
      lab.texturas[row.sprite] = tex
    end
    row.texture = tex
    if row.mesh then row.kinds = ctx.classifyMesh(row.mesh, row.role) end
    lab.row = row
    lab.construcoes = lab.construcoes + 1
  end
  lab.sujo = false
end

--------------------------------------------------------------------------
-- REGION OVERLAY  (key `b`, roadmap item 11)
--------------------------------------------------------------------------
-- Roadmap item 9 (per-part secondary motion) needs the mesh split into
-- regions, each with its own matrix, and the one place a cut is SAFE is a
-- row that already has a cap: the SLAB builder only emits a top or bottom
-- face where the neighbouring row is empty (main.lua's `at(sx, ly - 1)` /
-- `at(sx, ly + 1)` guards), and the host draws characters with culling
-- disabled, so cutting anywhere else leaves the un-drawn inside of the back
-- wall facing the camera.
--
-- Read straight off the BUILT mesh instead of reimplementing that row scan:
-- classifyMesh already answers "is this quad top/bottom" from the quad's own
-- winding, verified against both builders (main.lua's comment above KINDS),
-- and a top/bottom quad's four vertices share one Y by construction (the cap
-- is a horizontal plane). So the cap rows ARE the distinct Y values already
-- sitting on classified top/bottom quads; nothing here re-derives the mod's
-- own row-emptiness test.
local function labRegioes(row)
  if not row or not row.mesh or not row.kinds then return nil end
  local verts, kinds = row.mesh.verts, row.kinds
  local vistoY, kindDoY = {}, {}
  local counts = {}
  for _, k in ipairs({ "front", "back", "side_e", "side_w", "top", "bottom" }) do
    counts[k] = 0
  end
  for i = 1, #verts, 4 do
    local kind = kinds[(i - 1) / 4 + 1]
    counts[kind] = (counts[kind] or 0) + 1
    if kind == "top" or kind == "bottom" then
      local yv = verts[i][2]
      local chave = string.format("%.3f", yv)
      if not vistoY[chave] then
        vistoY[chave] = yv
        kindDoY[chave] = kind
      elseif kindDoY[chave] ~= kind then
        kindDoY[chave] = "ambos"
      end
    end
  end
  local ys = {}
  for _, yv in pairs(vistoY) do ys[#ys + 1] = yv end
  table.sort(ys)

  -- Bands: what a cut at two consecutive cap rows would isolate. Counted
  -- from EVERY quad's own vertices, not just the caps, so the readout
  -- answers "how much mesh would this region carry" for whoever is planning
  -- the cut.
  local bands = {}
  for b = 1, #ys - 1 do bands[b] = { lo = ys[b], hi = ys[b + 1], quads = 0 } end
  for i = 1, #verts, 4 do
    local midY = (verts[i][2] + verts[i + 1][2] + verts[i + 2][2]
      + verts[i + 3][2]) / 4
    for _, band in ipairs(bands) do
      if midY >= band.lo and midY <= band.hi then
        band.quads = band.quads + 1
        break
      end
    end
  end
  return { ys = ys, kindDoY = kindDoY, counts = counts, bands = bands }
end

-- Global on purpose: love.load is defined ABOVE this section, so a local
-- here would not exist as an upvalue there. Same reason as love.labdraw/labkeys.
function love.labsetup()
  lab.folhas = labFolhas()
  if #lab.folhas == 0 then return ctx.fail("nenhuma folha em " .. ctx.SPRITE_DIR) end
  for i, n in ipairs(lab.folhas) do if n == ctx.opts.sprite then lab.i = i end end

  -- A single build just for the mod to register and the schema to exist.
  labMalha(lab.folhas[lab.i], 0, {})
  if not ctx.getLabSchema() then return ctx.fail("o mod nao registrou schema de opcoes") end
  for _, o in ipairs(ctx.getLabSchema()) do lab.valores[o.key] = o.default end

  local t0 = love.timer.getTime()
  local geometrica, construcoes = labClassifica(lab.valores)
  local custo = love.timer.getTime() - t0
  local aqui, la = {}, {}
  for _, o in ipairs(ctx.getLabSchema()) do
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
  ctx.state.width, ctx.state.height = 1280, 800
  ctx.state.bg = { 0.10, 0.11, 0.13 }
  ctx.state.shader = love.graphics.newShader(ctx.SHADER)
  local pal = ctx.PALETTES[ctx.opts.palette] or ctx.PALETTES.obj
  for i = 1, 4 do ctx.state.shader:send("pal" .. (i - 1), pal[i]) end
  ctx.state.rows = {}
  math.randomseed(os.time())
  labRebuild()
  -- `labregions=1` forces the overlay on for the gate, which cannot press
  -- keys under labshot (love.labkeys returns early there).
  lab.overlay = ctx.opts.labregions == "1"
  if ctx.opts.labab == "1" then
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
-- CHOICE MODE (t key)
--------------------------------------------------------------------------
-- Two variants side by side, one key chooses, and the choice becomes a line
-- in a file. It is the one thing this project cannot compute.
--
-- Three decisions that are not obvious:
--
--   A PAIR DIFFERS IN ONE OPTION ONLY. If the two sides differ in several,
--   the choice does not attribute credit to any of them, and the record is
--   useless for fitting anything. Comparison of whole states comes later,
--   once there is a judge to propose the states.
--
--   THE SHEET IS ALSO RANDOMISED. Every option in this mod was judged on
--   red, and what pleases on red may not please on nurse or on snorlax. If
--   the sheet does not vary, the judge learns Kim's taste FOR RED.
--
--   SKIPPING IS AN ANSWER. Forcing a choice between two indistinguishable
--   things injects noise disguised as signal. "I see no difference" is
--   information: it says the distance between the two levels is below the
--   threshold of whoever is looking.
-- Not every difference is always on screen, and a pair assembled at an
-- instant where the two sides are IDENTICAL does not collect preference, it
-- collects a coin flip.
--
-- Two cases, both measured and not assumed:
--   BLINK only differs during 0.12 s of every period of 3 to 6 s.
--   STEP WEIGHT only differs in the walking pose (main.lua:1407).
--
-- So before showing a pair, it looks for a condition (pose, instant) where
-- the two sides actually differ, and FREEZES there. Freezing is better than
-- animating here: the question is which of the two, and the answer cannot
-- depend on the frame in which the person pressed the key.
--
-- Finding instead of computing is deliberate. Replicating the blink's phase
-- formula would be testing the implementation against itself, and this
-- harness already solves that the same way elsewhere (blinkscan).
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
  for _, oo in ipairs(ctx.getLabSchema()) do base[oo.key] = lab.valores[oo.key] end
  local va, vb = {}, {}
  for k, v in pairs(base) do va[k] = v; vb[k] = v end
  va[o.key] = o.choices[a][2]
  vb[o.key] = o.choices[b][2]
  local cond, sempre = labCondicao(folha, o, va, vb)
  if not cond then
    -- The two levels produce the same mesh on THIS sheet across every
    -- condition swept. Asking would mean choosing between two identical
    -- images.
    return nil
  end
  return {
    opcao = o, folha = folha,
    rotuloA = o.choices[a][1], rotuloB = o.choices[b][1],
    valoresA = va, valoresB = vb,
    congela = (not sempre) and cond or nil,
  }
end

-- Rolls until it lands a pair that actually shows a difference. Tries a
-- fixed number of times and gives up out loud: an uncapped loop on a roll
-- that may never land is a tool that hangs without anyone understanding why.
-- THE PAIRS THE JUDGE REQUESTED, when they exist.
--
-- Rolling is the right call on the first round, when there is no model.
-- After that it is waste: a good share of the rolls land on a pair the model
-- already gets right with its eyes closed, and a choice like that moves no
-- weight at all. Kim's time is the expensive input here, so from the moment
-- a model exists, what to ask is chosen by the judge itself, through the
-- pairs where it is on the fence (tools/juiz/ajusta.lua --pares).
--
-- Format, one line per pair: sheet TAB frame TAB clock TAB stateA TAB stateB
local labFilaPares = nil
local function labParDoArquivo()
  if ctx.opts.labpares == "" then return nil end
  if not labFilaPares then
    labFilaPares = {}
    local f = io.open(ctx.opts.labpares, "r")
    if f then
      for linha in f:lines() do
        local folha, qf, qt, ea, eb =
          linha:match("^(%S+)\t(%S+)\t(%S+)\t(%S+)\t(%S+)$")
        if folha then
          labFilaPares[#labFilaPares + 1] =
            { folha = folha, qf = qf, qt = qt, a = ea, b = eb }
        end
      end
      f:close()
    end
    print(string.format("laboratorio: %d pares pedidos pelo juiz em %s",
      #labFilaPares, ctx.opts.labpares))
  end
  local item = table.remove(labFilaPares, 1)
  if not item then return nil end

  local function paraValores(txt)
    local v = {}
    for oo in ipairs(ctx.getLabSchema() or {}) do local _ = oo end
    for par in txt:gmatch("[^,]+") do
      local k, val = par:match("^%s*([%w_]+)%s*:%s*(.-)%s*$")
      if k then v[k] = tonumber(val) or val end
    end
    return v
  end
  local va, vb = paraValores(item.a), paraValores(item.b)

  -- Which option differs: it is the one that names the two sides on screen.
  local chave
  for _, o in ipairs(ctx.getLabSchema() or {}) do
    if tostring(va[o.key]) ~= tostring(vb[o.key]) then chave = o; break end
  end
  if not chave then return nil end

  local function rotulo(o, valor)
    for _, nivel in ipairs(o.choices or {}) do
      if tostring(nivel[2]) == tostring(valor) then return nivel[1] end
    end
    return tostring(valor)
  end

  local cond, sempre = labCondicao(item.folha, chave, va, vb)
  if not cond then return labParDoArquivo() end
  return {
    opcao = chave, folha = item.folha,
    rotuloA = rotulo(chave, va[chave.key]),
    rotuloB = rotulo(chave, vb[chave.key]),
    valoresA = va, valoresB = vb,
    congela = (not sempre) and cond or nil,
    doJuiz = true,
  }
end

local function labSorteiaParValido()
  local pedido = labParDoArquivo()
  if pedido then return pedido end
  for _ = 1, 40 do
    local p = labSorteiaPar()
    if p then return p end
  end
  print("modo escolha: 40 sorteios sem par visivel; ver a lista de opcoes")
  return nil
end

-- Rebuilds the meshes of the CURRENT pair. Separated from the roll on
-- purpose: the animation rebuilds every frame and cannot swap the pair out
-- from under whoever is deciding.
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
      if r.mesh then r.kinds = ctx.classifyMesh(r.mesh, r.role) end
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
  -- THE CONDITION UNDER WHICH THE CHOICE WAS MADE TRAVELS WITH IT, and
  -- without it the record lies. The pair is staged at a (frame, instant)
  -- where the two sides actually differ, otherwise BLINK and STEP WEIGHT
  -- would be two identical images. But the feature extractor used to measure
  -- everyone at frame 0 with the clock at 0, which is exactly where they do
  -- NOT differ: the difference vector came out all zero, the model scored
  -- z=0, always predicted "A", and the choice entered the denominator as a
  -- coin flip without anyone counting it. Measured: 2 of 8 test choices.
  local cf = p.congela and p.congela.frame
    or ((lab.andando and FACINGS[lab.facing].anda) or FACINGS[lab.facing].pose)
  local ct = p.congela and p.congela.t or 0
  labGrava(string.format(
    "t=%s folha=%s pose=%s frame=%d clock=%.2f rung=%d yaw=%d opcao=%s a=%s b=%s escolha=%s | A: %s | B: %s",
    os.date("%Y-%m-%dT%H:%M:%S"), p.folha, FACINGS[lab.facing].nome,
    cf, ct, lab.rung, lab.yaw, p.opcao.key, tostring(p.valoresA[p.opcao.key]),
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
  -- Under labshot the run is automatic and has to be reproducible. A stray
  -- keystroke arriving in the window already changed the result once: the
  -- run came out with two builds instead of two hundred because something
  -- delivered `space`, and I almost read that as the rebuild being slow.
  if ctx.opts.labshot ~= "" then return end
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
    for _, o in ipairs(ctx.getLabSchema()) do lab.valores[o.key] = o.default end
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
  elseif key == "b" then
    -- Region overlay, roadmap item 11: `r` was already taken by "reset
    -- options to default" (above), so this one gets its own letter instead
    -- of displacing a binding someone's fingers already know.
    lab.overlay = not lab.overlay
  elseif key == "g" or key == "n" then
    -- The host's own grid and day/night settings (roadmap item 11) are NOT
    -- reachable from here: love.load never receives a `game`, and
    -- makeVoxelHandle's V.require only stubs Voxel3D, ImageCache,
    -- SpriteBillboards, VoxelState, VoxelScene and FirstPerson, so asking for
    -- VoxelGrid or DayNight throws "unexpected module" instead of silently
    -- doing nothing. Rather than fake either one, the key prints why, same
    -- as the note under NAO APARECEM AQUI on screen.
    if key == "g" then
      print("grade do voxel: fora do alcance deste harness autonomo (sem " ..
        "`game`; o host tambem nunca grade personagens de proposito -- " ..
        "VoxelScene.lua chama Voxel3D.seams(false) em drawCast, medido em " ..
        "tools/ingame/probe_grid.lua)")
    else
      print("hora do dia: fora do alcance deste harness autonomo (sem " ..
        "`game`, sem ModSetting/PaletteFX e sem save; " ..
        "DayNight.setting:setIndex grava no save do jogador -- o padrao " ..
        "correto, que restaura no fim, esta em tools/ingame/trailer.lua)")
    end
  end
end

local function labTexto(x, y, s, cor)
  love.graphics.setColor(cor or { 1, 1, 1, 1 })
  love.graphics.print(s, x, y)
end

local CAP_LINE_COR = {
  top = { 0.25, 1, 1, 0.9 }, bottom = { 1, 0.6, 0.15, 0.9 },
  ambos = { 1, 1, 1, 0.9 },
}

-- Draws the cap lines and the band readout over an already-drawn character.
-- Two passes: a translucent recolour of the mesh itself (drawCell's asOverlay,
-- reusing classifyMesh's kind per quad so top/bottom read as visibly distinct
-- from front/back), then the cap-row lines and the quad-per-band count in
-- text, both read straight off `labRegioes`.
local function labDesenhaRegioes(row, x, y, size)
  if not (row and row.mesh) then return end
  love.graphics.setDepthMode("lequal", false)
  love.graphics.setShader(ctx.state.shader)
  ctx.state.shader:send("provenance", 1)
  love.graphics.setColor(1, 1, 1, 0.55)
  ctx.drawCell(row, math.rad(lab.yaw), x, y, size, false, false, true)
  ctx.state.shader:send("provenance", 0)
  love.graphics.setShader()
  love.graphics.setDepthMode("always", false)
  love.graphics.setColor(1, 1, 1, 1)

  local info = labRegioes(row)
  if not info then return end
  local cam = ctx.cellCamera(row, math.rad(lab.yaw), x, y, size)
  local cx = (row.cellW or 16) / 2
  local prevScissor = { love.graphics.getScissor() }
  love.graphics.setScissor(x, y, size, size)
  for _, yv in ipairs(info.ys) do
    local pts = ctx.projectScreen({ { cx, yv, 0 } }, cam)
    local py = pts[1][2]
    local chave = string.format("%.3f", yv)
    love.graphics.setColor(CAP_LINE_COR[info.kindDoY[chave]] or { 1, 1, 1, 0.9 })
    love.graphics.line(x, py, x + size, py)
  end
  love.graphics.setScissor(unpack(prevScissor))
  love.graphics.setColor(1, 1, 1, 1)

  local ty = y + size + (lab.erro and 26 or 8)
  labTexto(x, ty, string.format(
    "REGIOES: %d linhas de corte (%d topo, %d fundo), %d bandas",
    #info.ys, info.counts.top or 0, info.counts.bottom or 0, #info.bands),
    { 0.6, 0.85, 0.9, 1 })
  local partes = {}
  for _, band in ipairs(info.bands) do
    partes[#partes + 1] = tostring(band.quads)
  end
  labTexto(x, ty + 18, "quads por banda: " .. table.concat(partes, ","),
    { 0.55, 0.6, 0.65, 1 })
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
      love.graphics.setShader(ctx.state.shader)
      love.graphics.setColor(1, 1, 1, 1)
      ctx.drawCell(par[2], math.rad(lab.yaw), par[1], GY, S)
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
      "%s, %s, rung %d, e o resto esta igual dos dois lados%s",
      p.folha, FACINGS[lab.facing].nome, lab.rung,
      p.doJuiz and "   (par pedido pelo juiz)" or ""),
      { 0.5, 0.54, 0.60, 1 })
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
  love.graphics.clear(ctx.state.bg[1], ctx.state.bg[2], ctx.state.bg[3], 1, true, true)
  if lab.ab then return labDrawAB() end

  local VX, VY, VS = 330, 70, 620
  love.graphics.setDepthMode("always", false)
  love.graphics.setShader()
  love.graphics.setColor(0.16, 0.17, 0.20, 1)
  love.graphics.rectangle("fill", VX, VY, VS, VS)

  if lab.row and lab.row.mesh then
    love.graphics.setDepthMode("less", true)
    love.graphics.setShader(ctx.state.shader)
    love.graphics.setColor(1, 1, 1, 1)
    ctx.drawCell(lab.row, math.rad(lab.yaw), VX, VY, VS)
    love.graphics.setShader()
    love.graphics.setDepthMode("always", false)
    if lab.overlay then labDesenhaRegioes(lab.row, VX, VY, VS) end
  end

  -- options column
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
  labTexto(20, y, "malha. So no jogo: clip.sh", { 0.5, 0.52, 0.56, 1 }); y = y + 16
  labTexto(20, y, "grade (g) e hora do dia (n): sem", { 0.5, 0.52, 0.56, 1 }); y = y + 16
  labTexto(20, y, "`game` aqui, ver console", { 0.5, 0.52, 0.56, 1 })

  -- character header
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

  -- neighbourhood in the sheet list, so as not to navigate blind
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
    "espaco anda   q/e gira   1-4 camera   r reseta   b regioes   g/n info   " ..
    "s foto   esc sai",
    { 0.45, 0.48, 0.53, 1 })
  labTexto(1150, 780, string.format("%d fps", love.timer.getFPS()),
    { 0.35, 0.38, 0.43, 1 })
end

-- Global on purpose, same reasoning as love.labsetup/labkeys/labdraw above:
-- main.lua dispatches here so a local defined in this file would not exist
-- as an upvalue there.
function love.labupdate(dt)
  -- The step alternates pose and walking. The blink is a short window with a
  -- phase per sheet, and it lives in the mesh's UV, so it only shows up if
  -- the mesh is rebuilt with the clock running: that is why it rebuilds per
  -- frame while playing, and only when something changes while stopped.
  lab.t = lab.t + (dt or 0)
  if lab.tocando then lab.andando = (lab.t % 0.5) < 0.25 end
  if lab.ab then
    -- The two sides rebuild on the SAME frame, with the same clock: if one
    -- blinked and the other did not, the choice would be about the blink and
    -- not about the option the pair claims to be comparing.
    if lab.tocando or lab.sujo then labConstroiPar() end
    lab.sujo = false
  elseif lab.tocando or lab.sujo then
    labRebuild()
  end
  if ctx.opts.labshot ~= "" then
    lab.quadros = (lab.quadros or 0) + 1
    if lab.quadros == 200 then
      love.graphics.captureScreenshot(function(img)
        img:encode("png", ctx.opts.labshot)
        print("LAB FOTO " .. love.filesystem.getSaveDirectory() .. "/" ..
              ctx.opts.labshot)
      end)
    elseif lab.quadros == 202 and ctx.opts.labpick ~= "" then
      -- Proves the whole recording path, from the pair to the line in the file.
      labEscolhe(ctx.opts.labpick)
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
end

return Lab
