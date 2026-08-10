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

-- Constroi a malha do estado atual. Passa TODA opcao pela passagem generica
-- `opt=`, entao uma opcao nova aparece aqui sem nenhuma linha nova.
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
    if row.mesh then row.kinds = ctx.classifyMesh(row.mesh, row.role) end
    lab.row = row
    lab.construcoes = lab.construcoes + 1
  end
  lab.sujo = false
end

-- Global de proposito: love.load e definido ACIMA desta secao, entao um local
-- daqui nao existiria como upvalue la. Mesmo motivo de love.labdraw/labkeys.
function love.labsetup()
  lab.folhas = labFolhas()
  if #lab.folhas == 0 then return ctx.fail("nenhuma folha em " .. ctx.SPRITE_DIR) end
  for i, n in ipairs(lab.folhas) do if n == ctx.opts.sprite then lab.i = i end end

  -- Uma construcao so para o mod se registrar e o schema existir.
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
  for _, oo in ipairs(ctx.getLabSchema()) do base[oo.key] = lab.valores[oo.key] end
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
-- OS PARES QUE O JUIZ PEDIU, quando existem.
--
-- Sortear e o certo na primeira rodada, quando nao ha modelo. Depois disso e
-- desperdicio: boa parte dos sorteios cai em par que o modelo ja acerta de
-- olhos fechados, e uma escolha dessas nao move peso nenhum. O tempo do Kim e
-- o insumo caro aqui, entao a partir do momento em que existe modelo, quem
-- escolhe o que perguntar e o proprio juiz, pelos pares em que ele esta em
-- cima do muro (tools/juiz/ajusta.lua --pares).
--
-- Formato, uma linha por par: folha TAB quadro TAB relogio TAB estadoA TAB estadoB
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

  -- Qual opcao difere: e ela que da nome aos dois lados na tela.
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
  -- A CONDICAO EM QUE A ESCOLHA FOI FEITA VAI JUNTO, e sem ela o registro
  -- mente. O par e encenado num (quadro, instante) onde os dois lados de fato
  -- diferem, senao BLINK e STEP WEIGHT seriam duas imagens iguais. Mas o
  -- extrator de features media todo mundo no quadro 0 com o relogio em 0, que
  -- e exatamente onde eles NAO diferem: o vetor de diferenca saia todo zero, o
  -- modelo pontuava z=0, previa sempre "A", e a escolha entrava no denominador
  -- como cara ou coroa sem ninguem contar. Medido: 2 de 8 escolhas de teste.
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
  -- Sob labshot a corrida e automatica e tem que ser reprodutivel. Uma tecla
  -- solta chegando na janela ja mudou o resultado uma vez: a corrida saiu com
  -- duas construcoes em vez de duzentas porque alguma coisa entregou `space`,
  -- e eu quase li isso como a reconstrucao estar lenta.
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

-- Global on purpose, same reasoning as love.labsetup/labkeys/labdraw above:
-- main.lua dispatches here so a local defined in this file would not exist
-- as an upvalue there.
function love.labupdate(dt)
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
  if ctx.opts.labshot ~= "" then
    lab.quadros = (lab.quadros or 0) + 1
    if lab.quadros == 200 then
      love.graphics.captureScreenshot(function(img)
        img:encode("png", ctx.opts.labshot)
        print("LAB FOTO " .. love.filesystem.getSaveDirectory() .. "/" ..
              ctx.opts.labshot)
      end)
    elseif lab.quadros == 202 and ctx.opts.labpick ~= "" then
      -- Prova o caminho da gravacao inteiro, do par ate a linha no arquivo.
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
