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
-- e as duas versoes falharam por coisas que o util.lua ja resolve: esperar a
-- carga, pular o intro, e conferir que a screenshot chegou no disco. Sempre
-- procure o padrao da casa antes de inventar o seu.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local n = 0

  -- FOTO: love.graphics.captureScreenshot, NAO U.shot.
  --
  -- Os dois existem e sao caminhos de codigo diferentes. O U.shot usa
  -- game.capturePath e grava com io.open em caminho RELATIVO ao diretorio de
  -- trabalho; o captureScreenshot grava no diretorio de save do LOVE. Eu ja
  -- tinha um driver funcionando com o segundo (vc_driver.png, 07/08 21:31) e
  -- quebrei tudo ao "melhorar" para o padrao do projeto sem verificar que o
  -- mecanismo novo funcionava neste ambiente. Adotar a estrutura da casa foi
  -- certo; adotar junto um mecanismo que eu nao tinha provado, nao.
  local function foto(nome)
    n = n + 1
    local caminho = string.format("vc_%02d_%s.png", n, nome)
    love.graphics.captureScreenshot(caminho)
    U.wait(8)  -- a captura so chega no disco no fim do quadro
    U.log("foto " .. caminho)
  end

  U.log("VC driver: comecando")

  -- NAO chama U.newGame. Os 240 drivers do projeto pressupoem boot direto
  -- (--game / POKEPORT_GAME), e o boot direto so acontece quando
  -- RomImporter.isReady(versao) e verdadeiro; uma versao que nao esta pronta
  -- cai no launcher e o driver fica parado para sempre esperando um mundo que
  -- nunca chega. Em vez de exigir isso, aqui a gente ESPERA: quem rodar pode
  -- clicar Play na mao, e o driver assume depois. Funciona nos dois casos.
  --
  -- A espera e generosa de proposito. Perder trinta segundos e barato; travar
  -- e caro, e ja custou sete tentativas.
  local ESPERA = tonumber(os.getenv("VC_WAIT")) or 900
  U.wait(60)
  -- Foto de diagnostico antes de qualquer outra coisa: quem dispara este
  -- driver nao ve a janela, entao se algo travar depois daqui, esta foto diz
  -- em que tela o jogo estava. Foi ela que mostrou que o driver estava
  -- fotografando a TELA DE TITULO enquanto eu achava que ele estava no mundo.
  foto("onde_estou_no_comeco")
  U.wait(math.max(0, ESPERA - 60))

  -- Chegar ao mundo. O teste de "estou no mundo" e o mesmo que o util.lua do
  -- projeto usa em U.newGame: game.stack:top() == game.overworld. Martelar "a"
  -- cobre os dois caminhos, continuar um save (titulo, menu, CONTINUE) e comecar
  -- um jogo novo, sem o driver precisar saber qual dos dois e.
  local noMundo = false
  for _ = 1, 300 do
    if game.overworld and game.stack:top() == game.overworld then
      noMundo = true
      break
    end
    U.tap(game, "a")
    U.wait(3)
  end
  if not noMundo then
    U.log("VC driver: NAO cheguei ao mundo; veja a foto de diagnostico")
    foto("preso_fora_do_mundo")
    return
  end
  U.wait(30)
  U.log("VC driver: no mundo")

  -- Ligar uma opcao do mod por codigo, para comparar com e sem sem ninguem
  -- navegar menu. VC_OPT="front_shape=low". O mod persiste a opcao no save e
  -- reage ao evento mod.options_changed (main.lua, writeOption e o handler),
  -- entao escrever e emitir e o mesmo caminho que o menu usa.
  local opt = os.getenv("VC_OPT")
  if opt then
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

  -- Andando. E a unica coisa que imagem parada de harness nao julga.
  for i = 1, 6 do
    U.hold(game, "down", 8)
    if i % 2 == 0 then foto(string.format("andando%d", i)) end
  end

  U.log("VC driver: fim, " .. n .. " fotos")
  U.wait(20)
end
