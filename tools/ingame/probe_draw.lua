-- PASSO 1 do roadmap: provar, com o jogo rodando, que a matriz que o host
-- passa para Voxel3D.draw carrega uma posicao por INSTANCIA que serve como
-- identidade estavel.
--
-- Este driver NAO muda nada. Ele so observa. Se ele reprovar, o roadmap
-- encolhe para animacao compartilhada e nada do resto se constroi.
--
-- O que ele responde, cada um com um veredito por escrito:
--
--   P1 intercepta      o wrap de Voxel3D.draw ve desenho de PERSONAGEM
--   P2 e a posicao     m[12]-8 bate com o py do mundo, m[4] com o px
--   P3 distingue       duas instancias na mesma tela dao valores diferentes
--   P4 estavel         NPC parado nao muda de valor entre quadros
--   P5 espelho         virar para o lado nao mexe em m[12]; mede o efeito em m[4]
--   P6 camera          trocar o degrau de camera nao mexe em m[12]
--   P7 andando         valor anda continuo, sem salto e sem NaN
--   P8 mundo           com a CAMERA andando, o NPC parado nao muda de valor
--
-- P8 e o que decide o passo 6 do roadmap. Se o valor for relativo a camera,
-- ele muda para todo mundo quando o jogador anda, e defasar por posicao faria
-- a cidade inteira respirar em onda junto com o passo do jogador.

return function(game)
  local U = dofile("tests/drivers/util.lua")

  -- O DEFEITO QUE ME CUSTOU MAIS TEMPO NESTA FERRAMENTA: sem TTY, o stdout do
  -- LOVE fica em buffer de BLOCO, e um processo que nao sai nunca esvazia. Log
  -- vazio nao distingue "nao aconteceu nada" de "nao terminou", e eu ja tirei a
  -- conclusao errada disso mais de uma vez. Uma linha resolve para sempre.
  io.stdout:setvbuf("line")

  local linhas = {}
  local function nota(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    local linha = ok and s or tostring(fmt)
    linhas[#linhas + 1] = linha
    print("[probe] " .. linha)
    -- love.filesystem.write NAO levanta erro quando falha; ele devolve false.
    -- Escrever sem conferir foi como eu passei minutos achando que o driver
    -- tinha travado quando ele so tinha parado de conseguir escrever.
    local okw, err = love.filesystem.write("vc_probe.txt",
      table.concat(linhas, "\n") .. "\n")
    if not okw then print("[probe] AVISO: nao consegui escrever: " .. tostring(err)) end
  end

  local vereditos = {}
  local function veredito(nome, ok, detalhe)
    vereditos[#vereditos + 1] = { nome = nome, ok = ok, detalhe = detalhe }
    nota("%-4s %s  %s", nome, ok and "PASSOU" or "FALHOU", detalhe or "")
  end

  nota("=== passo 1: a posicao por instancia chega limpa? ===")

  -- ---------------------------------------------------------------- host
  local HOSTS = { "BATTLE_ART_VOXEL_FORK", "DRAMALESS_SHAPE", "DRAMATIC_SHAPE" }
  local V
  for _, id in ipairs(HOSTS) do
    local exports = game.mods and game.mods.exports and game.mods.exports[id]
    if exports and exports.lib then
      V = exports.lib
      nota("host: %s", id)
      break
    end
  end
  if not V then
    veredito("P1", false, "nenhum host do voxel mod exporta lib")
    return
  end

  local okV, Voxel3D = pcall(V.require, "Voxel3D")
  local okS, SpriteBillboards = pcall(V.require, "SpriteBillboards")
  if not (okV and okS and Voxel3D and SpriteBillboards) then
    veredito("P1", false, "V.require falhou em Voxel3D ou SpriteBillboards")
    return
  end
  nota("Voxel3D.draw e funcao: %s | SpriteBillboards.mesh e funcao: %s",
    tostring(type(Voxel3D.draw) == "function"),
    tostring(type(SpriteBillboards.mesh) == "function"))

  -- ------------------------------------------------- quem e malha de gente
  -- Terreno, grama, sombra e pokedex tambem passam por Voxel3D.draw. O unico
  -- discriminador exato e a procedencia: uma malha que saiu de
  -- SpriteBillboards.mesh e de personagem, e nenhuma outra e. Marcar na saida
  -- da fabrica e mais barato e mais honesto que adivinhar pelos argumentos.
  local malhaDeGente = setmetatable({}, { __mode = "k" })
  local nomeDaMalha = setmetatable({}, { __mode = "k" })
  local meshOriginal = SpriteBillboards.mesh
  SpriteBillboards.mesh = function(def, frame)
    local m = meshOriginal(def, frame)
    if m then
      malhaDeGente[m] = true
      nomeDaMalha[m] = tostring(def and def.image or "?") .. "#" .. tostring(frame)
    end
    return m
  end

  -- ------------------------------------------------------- wrap do draw
  local capturando = false
  local quadro = {}     -- desenhos de personagem do quadro corrente
  local drawOriginal = Voxel3D.draw
  Voxel3D.draw = function(mesh, texture, model, pull, sunModel)
    if capturando and mesh and malhaDeGente[mesh] and type(model) == "table" then
      -- De ONDE veio esta chamada. Sem isto eu nao teria como saber que a cena
      -- desenha cada personagem mais de uma vez por quadro, e teria lido a
      -- duplicata como "duas instancias no mesmo lugar".
      local info = debug.getinfo(2, "Sl")
      quadro[#quadro + 1] = {
        nome = nomeDaMalha[mesh],
        m1 = model[1], m4 = model[4], m8 = model[8], m12 = model[12],
        temSol = sunModel ~= nil,
        pull = pull,
        de = info and (tostring(info.short_src):match("[^/]+$") .. ":" ..
          tostring(info.currentline)) or "?",
      }
    end
    return drawOriginal(mesh, texture, model, pull, sunModel)
  end

  local function limpaQuadro() quadro = {} end
  local function copiaQuadro()
    local c = {}
    for i, d in ipairs(quadro) do c[i] = d end
    return c
  end

  -- Um quadro observado: zera, espera o desenho acontecer, devolve o que veio.
  local function observa()
    limpaQuadro()
    capturando = true
    coroutine.yield()          -- o desenho deste quadro roda agora
    capturando = false
    return copiaQuadro()
  end

  -- --------------------------------------------------------------- mundo
  -- VSYNC DESLIGADO. Com vsync ligado e a janela ocluida (que e o caso normal
  -- quando isto roda de um shell, atras do editor), love.graphics.present()
  -- espera um flip que o compositor do macOS nao agenda, e o laco inteiro anda
  -- a menos de um quadro por segundo. Sintoma: o driver parece travado logo
  -- depois de entrar no mundo, inclusive os drivers do proprio projeto. Nao e
  -- travamento, e o relogio.
  if love.window and love.window.setVSync then pcall(love.window.setVSync, 0) end

  local function ambiente()
    return string.format("fps=%d visivel=%s foco=%s",
      love.timer.getFPS(),
      tostring(love.window and love.window.isVisible and love.window.isVisible()),
      tostring(love.window and love.window.hasFocus and love.window.hasFocus()))
  end

  nota("antes do teleport (quadro %d) %s", U.frame(), ambiente())
  U.teleport(game, "VIRIDIAN_CITY", 17, 17, "down")
  nota("depois do teleport (quadro %d) %s", U.frame(), ambiente())
  U.wait(60)
  nota("depois de esperar 60 quadros (quadro %d) %s", U.frame(), ambiente())
  local ow = game.overworld
  if not (ow and game.stack:top() == ow and ow.entities) then
    veredito("P1", false, "nao cheguei ao mundo")
    return
  end
  nota("mapa: %s  entidades: %d", tostring(ow.map and ow.map.id), #ow.entities)

  -- O pipeline voxel precisa estar ligado; sem ele Voxel3D.draw sai cedo
  -- (`if not (active and mesh) then return end`) e todo o resto mede zero, que
  -- e exatamente a classe de teste que passa por motivo trivial.
  local desenhos = observa()
  local tentativas = 0
  while #desenhos == 0 and tentativas < 10 do
    U.tap(game, "3")
    U.wait(20)
    desenhos = observa()
    tentativas = tentativas + 1
  end
  nota("degraus de camera percorridos ate ver desenho: %d", tentativas)
  veredito("P1", #desenhos > 0,
    string.format("%d desenhos de personagem num quadro", #desenhos))
  if #desenhos == 0 then
    nota("sem desenho de personagem nao da para medir mais nada")
    love.graphics.captureScreenshot("vc_probe_sem_desenho.png")
    return
  end
  -- Quantas PASSADAS existem por quadro, e de onde cada uma sai. A cena
  -- desenha o mesmo personagem mais de uma vez (passada principal, silhueta de
  -- oclusao, etc). Sem separar por ponto de chamada, a duplicata se disfarca de
  -- "duas instancias no mesmo lugar" e reprova um teste que deveria passar.
  local porOrigem, ordemOrigem = {}, {}
  for _, d in ipairs(desenhos) do
    if not porOrigem[d.de] then
      porOrigem[d.de] = {}
      ordemOrigem[#ordemOrigem + 1] = d.de
    end
    local g = porOrigem[d.de]
    g[#g + 1] = d
  end
  nota("passadas por quadro: %d", #ordemOrigem)
  for _, origem in ipairs(ordemOrigem) do
    nota("  %s  %d desenhos  pull=%s",
      origem, #porOrigem[origem], tostring(porOrigem[origem][1].pull))
  end
  local principal = porOrigem[ordemOrigem[1]]
  for _, origem in ipairs(ordemOrigem) do
    if #porOrigem[origem] > #principal then principal = porOrigem[origem] end
  end
  nota("passada principal: %d desenhos (amostra dos 8 primeiros)", #principal)
  for i = 1, math.min(8, #principal) do
    local d = principal[i]
    nota("  %-28s m1=%.1f m4=%.2f m8=%.2f m12=%.2f sol=%s",
      d.nome, d.m1, d.m4, d.m8, d.m12, tostring(d.temSol))
  end

  -- ---------------------------------------------------------------- P2
  -- O teste certo e de INCLUSAO, nao de igualdade. A cena desenha mais gente do
  -- que ow.entities lista: os NPCs dos mapas VIZINHOS entram como ghosts
  -- (OverworldController.ghosts), e a primeira versao deste teste reprovou por
  -- isso, nao por defeito do host. A pergunta honesta e: TODA entidade deste
  -- mapa aparece desenhada na posicao de mundo dela?
  local desenhado, desenhadoX = {}, {}
  for _, d in ipairs(principal) do
    desenhado[string.format("%.2f", d.m12 - 8)] = true
    -- m[4] carrega px direto, ou px+16 quando espelhado (e ai m[1] = -1).
    desenhadoX[string.format("%.2f", d.m1 < 0 and (d.m4 - 16) or d.m4)] = true
  end
  local faltandoY, faltandoX = {}, {}
  for _, e in ipairs(ow.entities) do
    if not desenhado[string.format("%.2f", e.py)] then
      faltandoY[#faltandoY + 1] = string.format("%.0f", e.py)
    end
    if not desenhadoX[string.format("%.2f", e.px)] then
      faltandoX[#faltandoX + 1] = string.format("%.0f", e.px)
    end
  end
  nota("entidades deste mapa: %d | desenhos na passada principal: %d " ..
    "(o excedente sao NPCs de mapa vizinho)", #ow.entities, #principal)
  veredito("P2", #faltandoY == 0 and #faltandoX == 0, string.format(
    "py sem desenho correspondente: [%s] | px sem desenho: [%s]",
    table.concat(faltandoY, " "), table.concat(faltandoX, " ")))

  -- ---------------------------------------------------------------- P3
  -- Duas instancias DIFERENTES tem que dar pares (px,py) diferentes; se
  -- colidirem, sao indistinguiveis e animariam em unissono.
  --
  -- Antes de comparar, tirar as REPETICOES EXATAS. O mesmo personagem e
  -- desenhado mais de uma vez no mesmo quadro pelo mesmo ponto de chamada: o
  -- host desenha a copia refletida na agua por esta mesma funcao
  -- (VoxelScene.lua:604-610, "the water's reflection copy, drawn by this same
  -- function"). Repeticao exata (mesma folha, mesmo frame, mesma posicao) e uma
  -- copia, nao uma segunda pessoa; a primeira versao deste teste contou cada
  -- personagem colidindo consigo mesmo e reprovou 25 vezes.
  local exatos, unicos, copias = {}, {}, 0
  for _, d in ipairs(principal) do
    local px = d.m1 < 0 and (d.m4 - 16) or d.m4
    local py = d.m12 - 8
    local exato = string.format("%s@%.2f/%.2f", d.nome, px, py)
    if exatos[exato] then
      copias = copias + 1
    else
      exatos[exato] = true
      unicos[#unicos + 1] = { nome = d.nome, px = px, py = py }
    end
  end
  local vistos, colisoes = {}, {}
  for _, d in ipairs(unicos) do
    local k = string.format("%.2f/%.2f", d.px, d.py)
    if vistos[k] then
      colisoes[#colisoes + 1] = string.format("%s com %s em (%s)",
        d.nome, vistos[k], k)
    end
    vistos[k] = d.nome
  end
  for _, c in ipairs(colisoes) do nota("  colisao real: %s", c) end
  nota("%d desenhos = %d personagens + %d copias exatas (reflexo na agua)",
    #principal, #unicos, copias)
  veredito("P3", #unicos >= 2 and #colisoes == 0, string.format(
    "%d personagens distintos, %d colisoes de posicao", #unicos, #colisoes))

  -- ---------------------------------------------------------------- P4
  -- Um NPC ao longo de 60 quadros. O esperado e RECALCULADO do py vivo dele a
  -- cada quadro, e nao fixado uma vez: os NPCs deste jogo perambulam sozinhos,
  -- e um esperado congelado transformaria "o NPC andou" em "a medicao falhou".
  -- Com o esperado vivo, a pergunta fica a certa: o valor desenhado e SEMPRE o
  -- py de mundo daquela instancia, ande ela ou nao.
  local alvo
  for _, e in ipairs(ow.npcs or {}) do
    if not e.moving then alvo = e break end
  end
  local function bate(q, e)
    local esperado = e.py + 8
    for _, d in ipairs(q) do
      if math.abs(d.m12 - esperado) < 0.01 then return true, esperado end
    end
    return false, esperado
  end
  if not alvo then
    veredito("P4", false, "nenhum NPC parado neste mapa para acompanhar")
  else
    nota("NPC alvo: %s em px=%d py=%d", tostring(alvo.id), alvo.px, alvo.py)
    local desvios, amostras, andou = 0, 0, 0
    for _ = 1, 60 do
      local q = observa()
      local ok = bate(q, alvo)
      amostras = amostras + 1
      if not ok then desvios = desvios + 1 end
      if alvo.moving then andou = andou + 1 end
    end
    veredito("P4", desvios == 0, string.format(
      "%d/%d quadros em que o valor desenhado nao era o py do NPC " ..
      "(ele andou sozinho em %d deles)", desvios, amostras, andou))
  end

  -- ---------------------------------------------------------------- P5
  -- Espelho. O jogador virado para a esquerda e para a direita: um dos dois e
  -- espelhado (m[1] negativo). m[12] nao pode mudar; m[4] pode, e a gente
  -- mede QUANTO em vez de supor.
  local jogador = ow.player
  local function achaJogador(q)
    for _, d in ipairs(q) do
      if math.abs(d.m12 - (jogador.py + 8)) < 0.01 then return d end
    end
  end
  U.tap(game, "left");  U.wait(24)
  local esq = achaJogador(observa())
  U.tap(game, "right"); U.wait(24)
  local dir = achaJogador(observa())
  if esq and dir then
    local dz = math.abs(esq.m12 - dir.m12)
    local dx = dir.m4 - esq.m4
    nota("esquerda m1=%.1f m4=%.2f m12=%.2f | direita m1=%.1f m4=%.2f m12=%.2f",
      esq.m1, esq.m4, esq.m12, dir.m1, dir.m4, dir.m12)
    veredito("P5", dz < 0.01, string.format(
      "m[12] mudou %.3f ao espelhar (tem que ser 0); m[4] mudou %.1f", dz, dx))
  else
    veredito("P5", false, "nao localizei o jogador nos dois lados")
  end

  -- ---------------------------------------------------------------- P6
  -- Degrau de camera. O lean e rotateX; ele mexe na parte de rotacao da
  -- matriz, e nao pode mexer na translacao.
  if alvo then
    local ruins = 0
    for i = 1, 7 do
      U.tap(game, "3")
      U.wait(20)
      local ok, esperado = bate(observa(), alvo)
      if not ok then
        ruins = ruins + 1
        nota("  degrau %d: nenhum desenho com m[12]=%.1f", i, esperado)
      end
    end
    veredito("P6", ruins == 0, string.format(
      "%d de 7 degraus de camera mudaram o valor do NPC", ruins))
  end

  -- ---------------------------------------------------------------- P7 e P8
  -- Andar. Duas perguntas ao mesmo tempo: o valor do JOGADOR anda continuo
  -- (P7) e o valor do NPC PARADO nao anda junto com a camera (P8).
  local antes, saltoMax, nan = nil, 0, 0
  local npcMudou, camAntes, camAndou = 0, nil, 0
  for passo = 1, 24 do
    table.insert(game.input.pressQueue, "down")
    game.input.state["down"] = true
    local q = observa()
    local dj = achaJogador(q)
    if dj then
      if dj.m12 ~= dj.m12 then nan = nan + 1 end
      if antes then
        local salto = math.abs(dj.m12 - antes)
        if salto > saltoMax then saltoMax = salto end
      end
      antes = dj.m12
    end
    if alvo and not bate(q, alvo) then npcMudou = npcMudou + 1 end
    local cam = ow.camera
    if cam then
      if camAntes and (cam.x ~= camAntes.x or cam.y ~= camAntes.y) then
        camAndou = camAndou + 1
      end
      camAntes = { x = cam.x, y = cam.y }
    end
    if passo % 8 == 0 and antes then
      nota("  passo %d: jogador m12=%.1f  camera=(%.0f,%.0f)",
        passo, antes, ow.camera and ow.camera.x or -1,
        ow.camera and ow.camera.y or -1)
    end
  end
  game.input.state["down"] = false
  U.wait(20)
  nota("a camera se moveu em %d dos 24 quadros de caminhada", camAndou)

  veredito("P7", nan == 0 and saltoMax <= 4.01, string.format(
    "maior salto entre quadros: %.2f px; NaN em %d quadros", saltoMax, nan))
  -- P8 so vale se a camera realmente andou. Sem isso o teste passaria pelo
  -- motivo trivial de nada ter se mexido, que e a armadilha desta casa.
  veredito("P8", npcMudou == 0 and camAndou > 0, string.format(
    "o valor do NPC divergiu do py dele em %d de 24 quadros; " ..
    "a camera andou em %d quadros (se for 0, o teste nao valeu)",
    npcMudou, camAndou))

  -- ------------------------------------------------------------- resumo
  nota("")
  nota("=== resumo ===")
  local todos = true
  for _, v in ipairs(vereditos) do
    if not v.ok then todos = false end
    nota("%-4s %s", v.nome, v.ok and "PASSOU" or "FALHOU")
  end
  nota("VEREDITO: %s", todos and "A POSICAO CHEGA LIMPA"
    or "ALGO CHEGOU SUJO, ler acima")

  love.graphics.captureScreenshot("vc_probe_fim.png")
  U.wait(20)

  -- Desfaz os dois wraps. Um driver que deixa o host remendado envenena
  -- qualquer medicao seguinte no mesmo processo.
  Voxel3D.draw = drawOriginal
  SpriteBillboards.mesh = meshOriginal
end
