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
-- FEATURES  (features=<arquivo>)
--------------------------------------------------------------------------
-- As grandezas que o juiz enxerga. Elas saem da MALHA e nao de um quadro
-- renderizado, o que e uma escolha e nao uma economia: medir na malha e
-- deterministico, nao depende de camera nem de relogio, e roda em milissegundos
-- por variante, entao trinta escolhas viram sessenta variantes em segundos e
-- da para reajustar o modelo sempre que a lista de features mudar.
--
-- A lista comeca pelas grandezas que este projeto ja mediu e que ja
-- explicaram alguma coisa:
--
--   fracao de topo   a lei que matou quatro tentativas de profundidade
--                    variavel: topo nao carrega arte e esta camera olha para
--                    ele. Se a preferencia do Kim ignorar isto, a lei vale
--                    menos do que a gente pensa, e isso e resultado
--   fracao de arte   frente e verso sao as unicas faces que o artista
--                    desenhou (IS_ART); o resto e superficie inventada
--   quads            custo e complexidade da forma
--   profundidade     o quanto o corpo sai do plano do sprite
--   tons             FRONT SHAPE e TOP DOME nao mexem em vertice, so em
--                    shade, entao sem estatistica de shade eles seriam
--                    invisiveis para o modelo
--
-- Nao ha art% de PIXEL aqui, que e a metrica com que este projeto sempre
-- julgou. Ela precisa do render de proveniencia, que precisa de grade e de
-- leitura de tela. Fica para a segunda passada, e ate la o baseline do juiz e
-- "a melhor feature sozinha", que e um adversario mais honesto do que parece:
-- se o modelo ajustado nao ganha de UMA coluna, ele nao aprendeu nada.
local FEATURE_NOMES = {
  "quads", "frente", "verso", "lado", "topo", "baixo",
  "arte", "profundidade", "shade_media", "shade_desvio", "shade_niveis",
  -- Estas duas vem de RENDER, nao da malha, e sao o motivo de este modo ter
  -- deixado de ser so aritmetica de vertice. `art_px` e a metrica com que este
  -- projeto sempre julgou: a fracao do que o jogador VE que e trabalho do
  -- artista, e nao a fracao de quads. Enquanto ela nao estava aqui, o
  -- adversario do juiz era "a melhor coluna sozinha" entre colunas em que
  -- nenhuma era a regua da casa.
  "art_px", "cobertura", "luz_media", "tons",
}

-- Fracao de PIXEL que veio de face de arte (frente e verso), medida do mesmo
-- jeito que o contact sheet mede: desenha com cor de PROVENIENCIA num canvas e
-- le de volta. Canvas e nao screenshot de proposito: screenshot so fica pronto
-- no fim do quadro, e este modo roda inteiro dentro do love.load.
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
        -- Mesma classificacao de kindAt no computeMetrics: frente e verso sao
        -- as unicas faces que o artista desenhou.
        if (g > 0.75 and r < 0.25) or (g > 0.25 and r < 0.25 and b < 0.25) then
          arte = arte + 1
        end
      end
    end
  end

  -- SEGUNDA PASSADA, COM COR DE VERDADE, e ela existe por causa de um buraco
  -- que o proprio juiz apontou: `SIDE COLOR` aparecia na lista de "features
  -- cegas" mesmo depois de art_px entrar. Faz sentido: ela troca QUAL texel a
  -- face lateral amostra (corpo ou contorno), o que muda a cor na tela e nao
  -- muda a proveniencia, que continua sendo "lado". Nenhuma coluna de
  -- geometria e nenhuma de proveniencia enxerga cor.
  love.graphics.setCanvas({ colour, depthstencil = depth })
  love.graphics.clear(0, 0, 0, 0, true, true)
  love.graphics.setDepthMode("less", true)
  love.graphics.setShader(ctx.state.shader)
  ctx.drawCell(row, math.rad(yawDeg or 0), 0, 0, cell)
  love.graphics.setShader()
  love.graphics.setDepthMode("always", false)
  love.graphics.setCanvas()

  local cor = colour:newImageData()
  local soma, n, tons = 0, 0, {}
  for y = 0, cell - 1 do
    for x = 0, cell - 1 do
      local r, g, b, a = cor:getPixel(x, y)
      if a >= 0.5 then
        local l = 0.299 * r + 0.587 * g + 0.114 * b
        soma, n = soma + l, n + 1
        tons[math.floor(l * 32 + 0.5)] = true
      end
    end
  end
  local distintos = 0
  for _ in pairs(tons) do distintos = distintos + 1 end

  colour:release(); depth:release()
  return (total > 0 and arte / total or 0), total / (cell * cell),
         (n > 0 and soma / n or 0), distintos
end

local function featuresDaMalha(mesh, kinds)
  local f = {}
  for _, n in ipairs(FEATURE_NOMES) do f[n] = 0 end
  if not (mesh and mesh.verts and #mesh.verts > 0) then return f end
  local quads = math.floor(#mesh.verts / 4)
  f.quads = quads
  local conta = {}
  for _, k in ipairs(kinds or {}) do conta[k] = (conta[k] or 0) + 1 end
  local function frac(k) return quads > 0 and (conta[k] or 0) / quads or 0 end
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

-- Uma celula so, no degrau padrao do jogo. O degrau importa porque a fracao de
-- arte depende da camera: e a lei que este projeto mediu, topo nao carrega arte
-- e esta camera olha para ele.
local FEATURE_CELL, FEATURE_RUNG = 140, 35

function love.features()
  -- Saida em linha e nao em bloco. Sem isto, um run interrompido no meio
  -- entrega um arquivo truncado NO MEIO DE UMA LINHA, e um leitor cuidadoso
  -- ainda pode ler as linhas inteiras que sobraram como se fossem o resultado.
  -- Aconteceu: o trailer.sh faz `pkill -x love` e matou uma extracao que
  -- rodava em paralelo, e o que ficou no arquivo parecia uma medicao curta em
  -- vez de uma medicao interrompida.
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
    -- Quatro colunas: folha, quadro, relogio, estado. As duas do meio existem
    -- porque medir a feature numa condicao diferente daquela em que a pessoa
    -- julgou produz diferenca zero justamente nas opcoes que so aparecem em
    -- certos instantes ou certas poses.
    local folha, qf, qt, estado = linha:match("^(%S+)\t(%S+)\t(%S+)\t(.*)$")
    if not folha then
      folha, estado = linha:match("^(%S+)\t(.*)$")
      qf, qt = "0", "0"
    end
    if folha then
      local path = ctx.SPRITE_DIR .. folha .. ".png"
      local ok, data = pcall(ctx.loadImageData, path)
      if not ok then
        io.stderr:write("sem folha: " .. path .. "\n")
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
        -- Relogio congelado: a piscada mexe UV e mudaria a assinatura de shade
        -- conforme a hora em que este comando rodou. Feature tem que ser
        -- funcao do estado, nao do momento.
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
        -- MALHA QUE NAO CONSTRUIU NAO VIRA LINHA DE ZEROS.
        --
        -- featuresDaMalha devolve tudo zero quando a malha e nil, e a linha
        -- saia igual as outras. Do lado do juiz isso e indistinguivel de uma
        -- variante medida em zero, e entra no ajuste como se fosse dado. E a
        -- unica conferencia de completude do juiz.sh e contagem de linhas, que
        -- uma linha de zeros satisfaz.
        if not mesh then
          io.stderr:write("SEM MALHA: " .. folha .. "\t" .. estado .. "\n")
          falhas = falhas + 1
        else
        local f = featuresDaMalha(mesh, kinds)
        local texture = love.graphics.newImage(data)
        texture:setFilter("nearest", "nearest")
        local okArte, px, cob, luz, tons = pcall(artePorPixel, {
          sprite = folha, frame = quadro, shape = shape, mesh = mesh,
          texture = texture, cellW = sw, cellH = sh / def.frames,
          kinds = kinds, role = 0, pitch = math.rad(90 - FEATURE_RUNG),
        }, FEATURE_CELL, 0)
        f.art_px = okArte and px or 0
        f.cobertura = okArte and cob or 0
        f.luz_media = okArte and luz or 0
        f.tons = okArte and tons or 0
        if not okArte then
          io.stderr:write("SEM RENDER: " .. folha .. "  " .. tostring(px) .. "\n")
        end
        texture:release()
        -- O QUADRO PEDIDO, nao o quadro usado. A folha pode ter menos frames
        -- do que o pedido e ai ele e reduzido por modulo; imprimir o reduzido
        -- muda a chave e a linha deixa de casar com a escolha que a gerou. O
        -- sintoma e "sem features", que parece medicao faltando e na verdade e
        -- medicao feita e arquivada com outro nome.
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
  io.stderr:write(string.format("features de %d variantes, %d sem malha\n", linhas, falhas))
  -- SAIR DE VERDADE, e este e o motivo de tres linhas em vez de uma.
  --
  -- love.event.quit() sozinho nao basta: ele so agenda a saida, e o quadro
  -- seguinte ainda chama love.draw, que aqui explode em state.bg (nil, porque
  -- o modo features nunca monta a cena). Erro em love.draw abre a tela de erro
  -- do LOVE, que espera uma tecla PARA SEMPRE.
  --
  -- E o pior: isso passou despercebido porque o primeiro teste deste modo
  -- terminava em `| head`, e o head fechando o cano matava o processo com
  -- SIGPIPE. A ferramenta parecia sair sozinha. Quem chamou sem cano ficou
  -- pendurado. Ja e a segunda vez neste projeto que um processo que nao
  -- termina se disfarca de processo que terminou.
  love.draw = function() end
  love.update = function() love.event.quit() end
  love.event.quit()
end

return Features
