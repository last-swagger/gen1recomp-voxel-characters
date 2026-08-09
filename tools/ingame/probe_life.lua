-- Gate in-game do canal de vida.
--
-- PRIMEIRO ERRO DESTE ARQUIVO, guardado porque e instrutivo: a primeira versao
-- envolvia Voxel3D.draw por CIMA do wrap do mod e lia a matriz achando que via
-- a saida. Ve a ENTRADA. Quem envolve depois roda antes. O resultado foi
-- "escala 1.000000 em 440 amostras", que eu quase li como "a feature nao
-- funciona" quando o defeito era do instrumento. De fora do processo do mod
-- nao da para ver a matriz que ele produz: ela vai direto para uma referencia
-- que o mod capturou no patch.
--
-- Entao a divisao de trabalho ficou assim, e cada lado mede o que so ele pode:
--
--   tests/voxel_chars_test.lua   a MATEMATICA. O host mockado e quem recebe a
--                                matriz transformada, entao la ela e visivel
--                                inteira: colunas, espelho, sombra, fase.
--   este arquivo                 os PIXELS. Se a conta certa chega na tela.
--
-- O que este gate pergunta:
--
--   V1 a linha de base e parada   com tudo OFF, um ciclo inteiro de quadros
--                                 e identico. Sem isso nada abaixo vale.
--   V2 respirar mexe a tela       com BREATH ligado, o mesmo ciclo passa a
--                                 diferir
--   V3 o menu manda               o nivel mais fraco se separa dos outros
--                                 (a metrica satura acima disso, e diz isso)
--   V4 a mudanca e NOSSA          com VOXEL CHARS OFF, BREATH nao muda nada
--   V5 balancar tambem mexe       e tambem responde ao nivel do menu
--   V6 a mola fica quieta         MOTION LAG com todo mundo parado nao muda
--                                 nada: mola em repouso, alvo zero
--   V7 e acorda com o passo       a mesma caminhada com e sem LAG difere
--   V8 quanto custa               ms por quadro numa cidade cheia, com e sem
--
-- V4 e o que nao passa por acaso: e o controle negativo. V6
-- e V7 sao um par: um sozinho passaria por motivo errado (uma feature morta
-- passa em V6; uma feature que oscila sozinha passa em V7).

return function(game)
  local U = dofile("tests/drivers/util.lua")
  io.stdout:setvbuf("line")
  if love.window and love.window.setVSync then pcall(love.window.setVSync, 0) end

  local linhas = {}
  local function nota(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    local linha = ok and s or tostring(fmt)
    linhas[#linhas + 1] = linha
    print("[vida] " .. linha)
    love.filesystem.write("vc_life.txt", table.concat(linhas, "\n") .. "\n")
  end

  local vereditos = {}
  local function veredito(nome, ok, detalhe)
    vereditos[#vereditos + 1] = { nome = nome, ok = ok }
    nota("%-3s %s  %s", nome, ok and "PASSOU" or "FALHOU", detalhe or "")
  end

  nota("=== gate de pixel do canal de vida ===")

  -- Captura um quadro como ImageData, sem passar por disco. A callback do
  -- captureScreenshot roda no fim do quadro, entao a gente cede ate ela vir.
  local function captura()
    local pronto
    love.graphics.captureScreenshot(function(imageData) pronto = imageData end)
    for _ = 1, 120 do
      coroutine.yield()
      if pronto then return pronto end
    end
    return nil
  end

  -- Conta pixels diferentes com passo 3 nos dois eixos: um nono do trabalho, e
  -- nenhum efeito deste tamanho se esconde numa grade de 3 px quando o jogo
  -- desenha a 5 px de tela por pixel de Game Boy.
  local function difere(a, b)
    if not (a and b) then return -1 end
    local w, h = a:getWidth(), a:getHeight()
    if b:getWidth() ~= w or b:getHeight() ~= h then return -1 end
    local n = 0
    for y = 0, h - 1, 3 do
      for x = 0, w - 1, 3 do
        local r1, g1, b1 = a:getPixel(x, y)
        local r2, g2, b2 = b:getPixel(x, y)
        if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 then n = n + 1 end
      end
    end
    return n
  end

  local function opcao(chave, valor)
    local o = game.save and game.save.options
    if o then
      o.modOptions = o.modOptions or {}
      o.modOptions.voxel_characters = o.modOptions.voxel_characters or {}
      o.modOptions.voxel_characters[chave] = valor
    end
    if game.mods and game.mods.modOptions then
      game.mods.modOptions.voxel_characters =
        game.mods.modOptions.voxel_characters or {}
      game.mods.modOptions.voxel_characters[chave] = valor
    end
    local ok = game.mods and game.mods.events
      and pcall(game.mods.events.emit, game.mods.events, "mod.options_changed",
        { mod = "voxel_characters", key = chave, value = valor })
    if not ok then nota("AVISO: a troca de %s NAO foi emitida", chave) end
    return ok
  end

  -- UM LUGAR SEM MAIS NINGUEM, e isso foi aprendido caro.
  --
  -- Primeira escolha foi o laboratorio do Oak, "porque tem gente parada". Tem
  -- ONZE object events, e em tres segundos sempre algum vira de lado ou anda um
  -- passo. O gate ficou reprovando por movimento de NPC e eu quase li isso como
  -- defeito da mola. O quarto do Red no andar de cima tem ZERO object events:
  -- o unico personagem na tela e o jogador, que fica exatamente onde a gente
  -- deixou. Um personagem so basta, porque o que este gate mede e se o efeito
  -- CHEGA na tela e responde ao menu; que duas instancias fiquem fora de fase e
  -- provado na suite offline, onde da para ler a matriz inteira.
  local MAPA = os.getenv("VC_MAP") or "REDS_HOUSE_2F"
  local Pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")
  local _, PX, PY = Pouso.escolher(game, MAPA, 3, 4)
  U.teleport(game, MAPA, PX, PY, "down")
  U.wait(60)
  if not (game.overworld and game.stack:top() == game.overworld) then
    veredito("V1", false, "nao cheguei ao mundo"); return
  end
  nota("mapa: %s, %d entidades", MAPA, #(game.overworld.entities or {}))

  -- O pipeline voxel precisa estar num degrau que desenhe solido.
  opcao("depth", 3)
  U.wait(20)
  for _ = 1, 8 do
    -- rung 0 e o 2D puro; qualquer outro serve. Anda ate a tela mudar de
    -- tamanho de arquivo, que e o sinal barato de "agora e 3D".
    U.tap(game, "3"); U.wait(20)
    break
  end
  U.wait(30)

  -- BLINK e um confundidor: ele anima os olhos no tempo, entao a linha de base
  -- nunca ficaria parada e V1 acusaria o inocente.
  opcao("blink", "off")
  opcao("sway", "off"); opcao("lag", "off")
  U.wait(30)


  -- Assinatura da cena: onde cada entidade esta. Se ela mudar entre as duas
  -- fotos, alguem deu um passo, e um passo muda centenas de pixels, o que
  -- afoga um efeito de meio pixel.
  --
  -- Isto NAO e conveniencia: a primeira versao mediu 1261 pixels em SUBTLE
  -- contra 566 em STRONG, e a ordem invertida parecia defeito do mod. Era um
  -- ajudante do laboratorio dando um passo dentro da janela de medicao. Sem
  -- provar que a cena estava parada, o numero nao mede a feature, mede o NPC.
  --
  -- E POSICAO NAO BASTA. Um NPC com NPC_CHANGE_FACING "marcha" parado: ele
  -- troca de direcao e de frame de caminhada sem sair do lugar (NPC.lua:70-79
  -- deixa px e py cravados). A assinatura so de posicao nao ve isso, e a troca
  -- de frame muda centenas de pixels, que foi como MOTION LAG parado mediu 476
  -- pixels e pareceu uma mola oscilando sozinha. Entao a assinatura carrega
  -- tudo que escolhe o sprite: onde, para onde, e em que ponto do passo.
  local function assinatura()
    local t = {}
    for _, e in ipairs(game.overworld.entities or {}) do
      -- walkPhase() e o seletor de frame de verdade, e em NPC ele nao tem
      -- efeito colateral (NPC.lua:124-127). pcall porque o jogador nao tem.
      local ok, fase = pcall(function() return e:walkPhase() end)
      t[#t + 1] = string.format("%d,%d,%s,%s,%s,%s",
        e.px or 0, e.py or 0, tostring(e.facing), tostring(e.progress),
        tostring(e.stepFlip), ok and tostring(fase) or "-")
    end
    return table.concat(t, ";")
  end

  -- ENVELOPE, e nao um par de quadros.
  --
  -- Um par separado por um intervalo FIXO mede |s(t2) - s(t1)|, que depende da
  -- fase em que cada personagem estava. Com dez pessoas em fases diferentes o
  -- numero balanca: eu medi NORMAL 525 contra STRONG 510 e SUBTLE 1261 contra
  -- STRONG 566 em corridas diferentes, e as duas inversoes eram do instrumento,
  -- nao do mod. A resposta certa e varrer o CICLO: uma foto de referencia e
  -- cinco comparacoes espalhadas por um periodo, ficando com a MAIOR. Isso mede
  -- a excursao, que e o que a amplitude controla, e nao depende de onde a
  -- senoide estava quando o gate comecou.
  local PERIODO = 186  -- 3.1 s a 60 fps
  local function envelope()
    for tentativa = 1, 6 do
      local antes = assinatura()
      local ref = captura()
      local pior, estavel = 0, true
      for k = 1, 5 do
        U.wait(math.floor(PERIODO / 6))
        local q = captura()
        if assinatura() ~= antes then estavel = false; break end
        local d = difere(ref, q)
        if d > pior then pior = d end
      end
      if estavel then return pior, tentativa end
      U.wait(30)
    end
    return -1, 6
  end
  local parDeQuadros = envelope

  -- ---------------------------------------------------------------- V1
  opcao("breath", "off")
  U.wait(30)
  local base, tb = parDeQuadros()
  nota("linha de base (tudo OFF): envelope de %d pixels (%d tentativas)", base, tb)
  veredito("V1", base >= 0 and base < 40,
    "com tudo OFF a cena tem que estar parada")

  -- ---------------------------------------------------------------- V2, V3
  local medidas = {}
  for _, nivel in ipairs({ { "SUBTLE", 0.010 }, { "NORMAL", 0.020 }, { "STRONG", 0.035 } }) do
    opcao("breath", nivel[2])
    U.wait(30)
    local n, tt = parDeQuadros()
    medidas[#medidas + 1] = { nome = nivel[1], valor = nivel[2], px = n }
    nota("BREATH %-6s (%.3f): envelope de %d pixels (%d tentativas)",
      nivel[1], nivel[2], n, tt)
  end

  veredito("V2", medidas[3] and medidas[3].px > base + 40, string.format(
    "STRONG mudou %d pixels contra %d da linha de base",
    medidas[3] and medidas[3].px or -1, base))

  -- ESTA METRICA SATURA, e o gate diz isso em vez de fingir que nao.
  --
  -- Contar pixel que mudou cresce enquanto o deslocamento e menor que um pixel
  -- de tela: em SUBTLE (0.8 px na cabeca) so parte das bordas vira. A partir de
  -- NORMAL (1.6 px) praticamente toda borda da silhueta ja virou, e STRONG
  -- (2.8 px) nao tem mais o que virar. Medido em corridas seguidas: SUBTLE 34 a
  -- 39, NORMAL 246 a 257, STRONG 250 a 275. Os dois de cima empatam dentro do
  -- ruido, e exigir ordem estrita entre eles reprova por saturacao da regua, do
  -- mesmo jeito que `art%` empatou entre forcas de FRONT SHAPE.
  --
  -- Entao aqui se afirma so o que esta regua sustenta: o nivel mais baixo se
  -- separa dos outros com folga, e todos ficam acima da linha de base. Que
  -- NORMAL e STRONG diferem exatamente na proporcao pedida e provado onde da
  -- para ler o numero exato, que e a suite offline.
  local separa = medidas[1] and medidas[2] and medidas[3]
    and medidas[1].px > base
    and medidas[2].px > medidas[1].px * 2
    and medidas[3].px > medidas[1].px * 2
  veredito("V3", separa, string.format(
    "SUBTLE %d, NORMAL %d, STRONG %d (base %d); a regua satura acima de SUBTLE",
    medidas[1] and medidas[1].px or -1,
    medidas[2] and medidas[2].px or -1,
    medidas[3] and medidas[3].px or -1, base))

  -- ---------------------------------------------------------------- V4
  -- Sem solido nao ha o que respirar: o mod devolve o card original do host e
  -- o wrap de draw nao reconhece a malha como nossa. Se ainda assim mudasse
  -- pixel, a mudanca viria de outro lugar e as tres medidas acima nao valem.
  opcao("depth", "off")
  U.wait(40)
  local semSolido, ts = parDeQuadros()
  nota("VOXEL CHARS OFF com BREATH STRONG: %d pixels diferentes (%d tentativas)",
    semSolido, ts)
  veredito("V4", semSolido >= 0 and semSolido < 40,
    "sem solido, BREATH nao pode mexer em nada")

  -- ---------------------------------------------------------------- V5
  -- SWAY e uma oscilacao de ocioso, como a respiracao: cena parada, tela muda,
  -- e mais forca muda mais.
  opcao("depth", 3); opcao("breath", "off")
  U.wait(40)
  local balanco = {}
  for _, nivel in ipairs({ { "SUBTLE", 0.20 }, { "NORMAL", 0.45 } }) do
    opcao("sway", nivel[2])
    U.wait(30)
    local n, ts2 = parDeQuadros()
    balanco[#balanco + 1] = n
    nota("SWAY %-6s (%.2f): envelope de %d pixels (%d tentativas)",
      nivel[1], nivel[2], n, ts2)
  end
  veredito("V5", balanco[1] and balanco[2]
    and balanco[1] > base + 20 and balanco[2] > balanco[1], string.format(
    "SUBTLE %d < NORMAL %d, os dois acima da base %d",
    balanco[1] or -1, balanco[2] or -1, base))

  -- ---------------------------------------------------------------- V6
  -- MOTION LAG nao pode aparecer com o personagem PARADO ha muito tempo: a
  -- mola esta em repouso e o alvo e zero. Se aparecesse, o efeito estaria
  -- vindo de outro lugar (ou a mola estaria oscilando sozinha, que e o modo de
  -- falha classico de uma mola mal amortecida).
  opcao("sway", "off"); opcao("lag", 1.2)
  U.wait(90)  -- tempo de sobra para a mola assentar
  local lagParado, tl = parDeQuadros()
  nota("MOTION LAG NORMAL com todo mundo parado: %d pixels (%d tentativas)",
    lagParado, tl)
  veredito("V6", lagParado >= 0 and lagParado < 40,
    "com ninguem se movendo, a mola tem que estar em repouso")

  -- ---------------------------------------------------------------- V7
  -- E tem que aparecer DEPOIS de um passo. A mesma sequencia exata rodada com
  -- LAG desligado e ligado: mesmo mapa, mesma celula de partida, mesmo numero
  -- de quadros. O jogador termina na mesma celula com o mesmo frame de sprite
  -- nas duas, entao a unica diferenca possivel entre as duas fotos e o atraso.
  -- O QUARTO E PEQUENO E TEM MOVEL. A primeira versao mandava "down" de um
  -- ponto onde a cama bloqueia: o jogador nao saia do lugar, velocidade zero,
  -- atraso zero, e as duas fotos sairam IDENTICAS. Zero pixel de diferenca
  -- parecia "a feature nao faz nada" e era "o teste nao andou". Entao: descobre
  -- primeiro uma direcao que realmente move, e so depois mede.
  local PARTIDA_X, PARTIDA_Y = 3, 4
  local function tentaPasso(dir)
    U.teleport(game, MAPA, PARTIDA_X, PARTIDA_Y, dir)
    U.wait(50)
    local antes = game.overworld.player.cellY * 1000 + game.overworld.player.cellX
    U.hold(game, dir, 16)
    U.wait(6)
    local depois = game.overworld.player.cellY * 1000 + game.overworld.player.cellX
    return depois ~= antes, captura()
  end

  opcao("lag", "off"); U.wait(20)
  local direcao, semLag
  for _, dir in ipairs({ "down", "left", "right", "up" }) do
    local andou, foto = tentaPasso(dir)
    if andou then direcao, semLag = dir, foto; break end
  end
  if not direcao then
    veredito("V7", false,
      "o jogador nao conseguiu andar em nenhuma direcao; o teste nao vale")
  else
    nota("direcao que move a partir de (%d,%d): %s", PARTIDA_X, PARTIDA_Y, direcao)
    opcao("lag", 1.2); U.wait(20)
    local andou, comLag = tentaPasso(direcao)
    local dLag = andou and difere(semLag, comLag) or -1
    nota("um passo para %s, com e sem MOTION LAG: %d pixels diferentes",
      direcao, dLag)
    veredito("V7", dLag > 40,
      "o atraso tem que aparecer logo depois do passo")
  end

  -- ---------------------------------------------------------------- V8
  -- CUSTO. O wrap roda uma vez por personagem por desenho, e numa cidade cheia
  -- isso e cinquenta vezes por quadro. O numero que importa nao e "e rapido",
  -- e "quanto do orcamento de 16.7 ms some".
  --
  -- DUAS ARMADILHAS, as duas ja pagas neste projeto:
  --
  -- 1. vsync. Com ele ligado todo quadro custa 16.67 ms faca o que fizer, e o
  --    benchmark mede o monitor. Desligado la em cima.
  -- 2. AQUECIMENTO. A primeira versao mediu 11.45 ms desligado e 4.35 ms
  --    ligado: ligar a feature deixava o jogo 2.6 vezes MAIS RAPIDO, que e
  --    impossivel. O que estava sendo medido era o mod construindo as 25 malhas
  --    da cidade na primeira passada, tudo caindo na condicao que rodou
  --    primeiro. Numero absurdo e o instrumento falando, nao o codigo.
  --
  -- Consertado com aquecimento antes e A/B/A/B depois: se a diferenca fosse
  -- deriva de aquecimento, ela sumiria no segundo par.
  do
    U.teleport(game, "VIRIDIAN_CITY", 17, 17, "down")
    U.wait(60)
    local function mede(quadros)
      local soma, n = 0, 0
      for _ = 1, quadros do
        coroutine.yield()
        local dt = love.timer.getDelta()
        if dt > 0 and dt < 0.2 then soma = soma + dt; n = n + 1 end
      end
      return n > 0 and (soma / n * 1000) or -1
    end
    local function desliga()
      opcao("breath", "off"); opcao("sway", "off"); opcao("lag", "off")
      U.wait(30)
    end
    local function liga()
      opcao("breath", 0.020); opcao("sway", 0.45); opcao("lag", 1.2)
      U.wait(30)
    end
    -- Aquecimento: constroi malha, carrega textura, deixa o LRU assentar.
    liga(); mede(300); desliga(); mede(300)

    local off1 = mede(240); liga()
    local on1 = mede(240); desliga()
    local off2 = mede(240); liga()
    local on2 = mede(240); desliga()
    local off = (off1 + off2) / 2
    local on = (on1 + on2) / 2
    nota("custo por quadro na cidade, A/B/A/B depois de aquecer:")
    nota("  desligado  %.3f e %.3f ms   media %.3f", off1, off2, off)
    nota("  ligado     %.3f e %.3f ms   media %.3f", on1, on2, on)
    nota("  diferenca  %.3f ms de 16.7 ms de orcamento (%.1f%%)",
      on - off, (on - off) / 16.7 * 100)
    -- COMO LER ISTO. O piso de ruido da medida e a variacao entre duas leituras
    -- da MESMA condicao. Se a diferenca entre ligado e desligado for menor que
    -- esse piso, o custo nao e "pequeno": e NAO MENSURAVEL com esta regua, e o
    -- sinal da diferenca vira moeda jogada. Exigir que os dois pares concordem
    -- no sinal seria exigir que o ruido se comporte, e reprovaria justamente o
    -- melhor resultado possivel.
    local ruido = math.max(math.abs(off1 - off2), math.abs(on1 - on2))
    local diferenca = math.abs(on - off)
    nota("  piso de ruido da regua: %.3f ms", ruido)
    veredito("V8", off > 0 and on > 0 and diferenca < 0.5, string.format(
      "diferenca %.3f ms contra piso de ruido %.3f ms: %s",
      diferenca, ruido, diferenca < ruido
        and "abaixo do ruido, o custo nao e mensuravel aqui"
        or "acima do ruido, e um custo real"))
  end

  -- Fotos para o Kim julgar de olho, ja que numero nao diz se presta.
  opcao("depth", 3); opcao("breath", 0.020); U.wait(40)
  love.graphics.captureScreenshot("vc_life_a.png"); U.wait(8)
  U.wait(46)
  love.graphics.captureScreenshot("vc_life_b.png"); U.wait(8)

  nota("")
  local todos = true
  for _, v in ipairs(vereditos) do
    if not v.ok then todos = false end
    nota("%-3s %s", v.nome, v.ok and "PASSOU" or "FALHOU")
  end
  nota("VEREDITO: %s", todos and "A RESPIRACAO CHEGA NA TELA" or "LER ACIMA")

  opcao("breath", "off"); opcao("blink", "on")
  U.wait(10)
end
