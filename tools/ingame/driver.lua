-- Gate in-game do Voxel Characters.
--
-- O harness offline (tools/render/) mede geometria e cor em dois segundos, mas
-- carrega o mod com o host MOCKADO. Por construcao ele nunca mostra o sol de
-- verdade (o host faz p.rgb * vShade * sunlight * dayTint e o harness so tem o
-- vShade), nem o personagem contra o mundo, nem a escala real (o harness usa
-- celulas de 240 a 320 px e o jogo desenha numa fracao disso), nem movimento.
--
-- Nao substitui o harness: o harness pega regressao rapido, este responde
-- "presta".
--
-- ISTO USA tests/drivers/util.lua, o utilitario que os 240 drivers do proprio
-- projeto usam. Eu escrevi este arquivo duas vezes do zero antes de procurar,
-- e as duas versoes falharam por coisas que o util.lua ja resolve.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local n = 0

  -- Sem TTY o stdout do LOVE fica em buffer de BLOCO e um processo que nao sai
  -- nunca esvazia. Log vazio nao distingue "nao aconteceu nada" de "nao
  -- terminou", e eu ja tirei a conclusao errada disso mais de uma vez.
  io.stdout:setvbuf("line")

  -- VSYNC DESLIGADO, E ESTA E A LINHA QUE FAZ O GATE FUNCIONAR SOZINHO.
  --
  -- Com vsync ligado e a janela ocluida (o caso normal quando isto roda de um
  -- shell, atras do editor), love.graphics.present() espera um flip que o
  -- compositor do macOS nao agenda enquanto ninguem esta olhando. O laco de
  -- love.run inteiro para: medido em 5 quadros em 90 segundos. O sintoma e
  -- indistinguivel de "travou no launcher" (zero fotos, log vazio) e foi por
  -- isso que este gate passou dias parecendo quebrado. Os drivers do PROPRIO
  -- projeto (tests/drivers/zoom_test.lua) travam igual sem isto: nao era
  -- codigo nosso.
  if love.window and love.window.setVSync then pcall(love.window.setVSync, 0) end

  -- FOTO: love.graphics.captureScreenshot, NAO U.shot.
  --
  -- Os dois existem e sao caminhos de codigo diferentes. O U.shot usa
  -- game.capturePath e grava com io.open em caminho RELATIVO ao diretorio de
  -- trabalho; o captureScreenshot grava no diretorio de save do LOVE. Eu ja
  -- tinha um driver funcionando com o segundo e quebrei tudo ao "melhorar"
  -- para o padrao do projeto sem verificar que o mecanismo novo funcionava
  -- neste ambiente. Adotar a estrutura da casa foi certo; adotar junto um
  -- mecanismo que eu nao tinha provado, nao.
  local function foto(nome)
    n = n + 1
    local caminho = string.format("vc_%02d_%s.png", n, nome)
    love.graphics.captureScreenshot(caminho)
    U.wait(8)  -- a captura so chega no disco no fim do quadro
    U.log("foto " .. caminho)
  end

  U.log("VC driver: comecando")

  -- CHEGAR AO MUNDO: U.teleport, nao marteladas de "a".
  --
  -- A versao anterior deste arquivo esperava ate 900 quadros e depois batia
  -- "a" trezentas vezes torcendo para atravessar titulo e menu, e falhava com
  -- ZERO fotos e log vazio. Duas coisas estavam erradas e as duas foram
  -- medidas:
  --
  -- 1. POKEPORT_GAME e POKEPORT_SLOT sao LETRA MORTA aqui. Eles so sao lidos
  --    em LaunchOptions.resolve (main.lua:359), que fica DEPOIS do
  --    `if scripted then ... return end` (main.lua:313-330). Com
  --    POKEPORT_DRIVER setado o controle nunca chega la. A versao que boota
  --    vem de POKEPORT_VERSION (main.lua:304), default "red". Nesta maquina
  --    red NAO esta pronto (faltam assets/generated/audio/programs.bin e
  --    assets/generated/trade/game_boy.png), entao o boot caia no importador
  --    e ficava esperando um ROM que ninguem ia arrastar: o driver nem chegava
  --    a ser criado. Quem resolve isso e o run.sh, exportando POKEPORT_VERSION.
  --
  -- 2. U.teleport e o padrao da casa: 212 dos 240 drivers do projeto usam, e
  --    so 8 usam o caminho de apertar tecla. Ele esvazia a pilha e empurra o
  --    OverworldController direto, entao nao existe titulo para atravessar.
  -- E O DESTINO E VALIDADO. U.teleport nao valida nada: se a celula pedida for
  -- placa, mesa, parede ou NPC, o jogador pousa em cima e a foto sai com ele
  -- num lugar onde ninguem consegue ficar. Foi o Kim que viu isso nas fotos
  -- antes de mim. Ver tools/ingame/pouso.lua.
  local Pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")
  local MAPA, X, Y, RAIO = Pouso.escolher(game,
    os.getenv("VC_MAP") or "VIRIDIAN_CITY",
    tonumber(os.getenv("VC_X")) or 17,
    tonumber(os.getenv("VC_Y")) or 17)
  U.teleport(game, MAPA, X, Y, "down")
  U.wait(30)
  if RAIO == nil then
    U.log("VC driver: AVISO, nenhuma celula boa perto do ponto pedido")
  elseif RAIO > 0 then
    U.log(string.format("VC driver: pouso deslocado %d celula(s) para (%d,%d)",
      RAIO, X, Y))
  end

  if not (game.overworld and game.stack:top() == game.overworld) then
    U.log("VC driver: teleport para " .. MAPA .. " NAO chegou ao mundo")
    foto("preso_fora_do_mundo")
    return
  end
  U.log("VC driver: no mundo, mapa " .. MAPA)

  -- Ligar uma opcao do mod por codigo, para comparar com e sem sem ninguem
  -- navegar menu. VC_OPT="front_shape=0.12". O mod persiste a opcao no save e
  -- reage ao evento mod.options_changed, entao escrever e emitir e o mesmo
  -- caminho que o menu usa.
  local opt = os.getenv("VC_OPT")
  if opt and opt ~= "" then
    local chave, valor = opt:match("^([%w_]+)=(.+)$")
    if chave then
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
      -- O barramento e game.mods.events, nao game.mods (src/mods/Loader.lua:595
      -- e :1059). Escrever a opcao no save SEM emitir nao muda nada na tela,
      -- porque a malha ja esta cacheada: foi assim que eu produzi um A/B com
      -- imagens byte a byte identicas e quase apresentei como comparacao.
      local emitiu = false
      if game.mods and game.mods.events
        and type(game.mods.events.emit) == "function" then
        emitiu = pcall(game.mods.events.emit, game.mods.events,
          "mod.options_changed",
          { mod = "voxel_characters", key = chave, value = valor })
      end
      U.log("VC driver: opcao " .. chave .. "=" .. valor ..
        (emitiu and " (evento emitido)" or " (FALHOU o evento: A/B nao vale)"))
      if not emitiu then
        U.log("VC driver: ABORTANDO, um A/B sem efeito e pior que nenhum")
        foto("opcao_sem_efeito")
        return
      end
      U.wait(30)
    end
  end

  foto("no_mundo")

  -- Os oito degraus de camera do host. A tecla "3" cicla o pipeline voxel:
  -- ele e registrado com hotkey = "3" em DramaticShapeVoxelMod/main.lua:155,
  -- sobre VoxelState.ANGLES_DEG = { 0, 35, 15, 35, 50, 75, 75, 75 }.
  for i = 1, 7 do
    U.tap(game, "3")
    U.wait(20)
    foto(string.format("camera%d", i))
  end
  U.log("VC driver: angulos cobertos")

  -- PRIMEIRA PESSOA, os dois modos, e por que ela precisa de tratamento
  -- proprio mesmo estando na volta da tecla "3".
  --
  -- O degrau 6 do HOTKEY_ORDER ja e 1ST, entao camera5 acima ja e primeira
  -- pessoa. Mas com o padrao (FIRST PERSON = CARD) essa foto mostra o card
  -- plano, que e o comportamento antigo, e o gate contava a foto sem nunca
  -- olhar o modo novo. Duas fotos do MESMO degrau, uma em cada modo, e o que
  -- torna a diferenca visivel para quem abre a pasta.
  --
  -- Pelo Pipelines e nao por tecla: a volta da tecla depende de onde o save
  -- parou, e o gate nao pode depender disso para chegar num degrau especifico.
  do
    local ok = pcall(function()
      require("src.render.Pipelines").setLevel("voxel", 6)
    end)
    if ok then
      U.wait(120)  -- o degrau faz tween e a primeira pessoa tem blend por cima
      for _, modo in ipairs({ "card", "solid" }) do
        local o = game.save and game.save.options
        if o then
          o.modOptions = o.modOptions or {}
          o.modOptions.voxel_characters = o.modOptions.voxel_characters or {}
          o.modOptions.voxel_characters.first_person = modo
        end
        if game.mods and game.mods.modOptions then
          game.mods.modOptions.voxel_characters =
            game.mods.modOptions.voxel_characters or {}
          game.mods.modOptions.voxel_characters.first_person = modo
        end
        pcall(function()
          game.mods.events:emit("mod.options_changed",
            { mod = "voxel_characters", key = "first_person", value = modo })
        end)
        U.wait(25)
        foto("primeira_" .. modo)
      end
      pcall(function()
        require("src.render.Pipelines").setLevel("voxel", 4)
      end)
      U.wait(60)
      U.log("VC driver: primeira pessoa coberta nos dois modos")
    else
      U.log("VC driver: sem Pipelines, primeira pessoa nao coberta")
    end
  end

  -- Andando. E a unica coisa que imagem parada de harness nao julga.
  for i = 1, 6 do
    U.hold(game, "down", 8)
    if i % 2 == 0 then foto(string.format("andando%d", i)) end
  end

  -- CONTROLE NEGATIVO: existe personagem NOSSO em alguma dessas fotos?
  --
  -- Ate agora este gate dizia GATE OK contando ARQUIVOS. Desligar o mod inteiro
  -- deixaria ele verde: o driver roda ate o fim, escreve as fotos, e ninguem
  -- olha um pixel. Um gate assim mede que o jogo abriu, nao que o mod fez algo.
  --
  -- O controle e ligar e desligar o mod na MESMA posicao e na MESMA camera e
  -- comparar. Fotografa os dois estados em disco para quem abrir a pasta poder
  -- olhar, e imprime o numero para o run.sh poder reprovar.
  do
    local function opta(valor)
      local o = game.save and game.save.options
      if o then
        o.modOptions = o.modOptions or {}
        o.modOptions.voxel_characters = o.modOptions.voxel_characters or {}
        o.modOptions.voxel_characters.depth = valor
      end
      if game.mods and game.mods.modOptions then
        game.mods.modOptions.voxel_characters =
          game.mods.modOptions.voxel_characters or {}
        game.mods.modOptions.voxel_characters.depth = valor
      end
      pcall(function()
        game.mods.events:emit("mod.options_changed",
          { mod = "voxel_characters", key = "depth", value = valor })
      end)
      U.wait(20)
    end

    local function pega()
      local pronto
      love.graphics.captureScreenshot(function(img) pronto = img end)
      for _ = 1, 120 do
        coroutine.yield()
        if pronto then return pronto end
      end
      return nil
    end

    local function difere(a, b)
      if not (a and b) or a:getWidth() ~= b:getWidth() then return -1, 0 end
      local d, n = 0, 0
      for y = 0, a:getHeight() - 1, 3 do
        for x = 0, a:getWidth() - 1, 3 do
          n = n + 1
          local ar, ag, ab = a:getPixel(x, y)
          local br, bg, bb = b:getPixel(x, y)
          if math.abs(ar - br) + math.abs(ag - bg) + math.abs(ab - bb) > 0.02 then
            d = d + 1
          end
        end
      end
      return d, n
    end

    -- O PISO SAI DA MESMA CORRIDA. Duas fotos com o mod LIGADO, sem trocar
    -- nada entre elas, medem o quanto a cena anda sozinha: ciclo de dia, NPC
    -- perambulando, tudo que nao e o mod.
    --
    -- Sem isso o limiar era uma fracao que eu escolhi (um quinhentos avos), e
    -- ao neutralizar o mod de proposito a medida deu 175 de 87552 contra um
    -- limiar de exatamente 175: passou raspando, por acaso. Limiar escolhido
    -- no chute nao separa sinal de ruido, so parece que separa.
    opta(3)
    local com1 = pega()
    U.wait(20)
    local com2 = pega(); foto("controle_com_mod")
    opta("off")
    local sem = pega(); foto("controle_sem_mod")
    opta(3)

    local piso = difere(com1, com2)
    local dif, amostras = difere(com1, sem)
    U.log(string.format("VC driver: controle piso %d, mod ligado contra "
      .. "desligado %d, de %d amostras", piso, dif, amostras))
  end

  U.log("VC driver: fim, " .. n .. " fotos")
  U.wait(20)
end
