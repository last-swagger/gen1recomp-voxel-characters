-- Grava os quadros de um clipe lado a lado: o mesmo lugar, a mesma camera, o
-- mesmo numero de quadros, uma vez com a opcao desligada e uma vez com ela
-- ligada. Quem monta o video e o clip.sh, com ffmpeg.
--
-- POR QUE ISTO EXISTE: BREATH, SWAY e MOTION LAG so significam alguma coisa no
-- TEMPO. Foto parada nao julga nenhuma das tres, e ate agora a unica forma de
-- mostrar o efeito para alguem era pedir para a pessoa abrir o jogo. Um clipe
-- de tres segundos resolve isso, e e tambem o que a comunidade consegue ver
-- numa mensagem de Discord.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  io.stdout:setvbuf("line")
  -- Sem isto o laco anda a menos de um quadro por segundo com a janela
  -- ocluida, e gravar 200 quadros levaria minutos. Ver tools/ingame/driver.lua.
  if love.window and love.window.setVSync then pcall(love.window.setVSync, 0) end

  local function log(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    print("[clip] " .. (ok and s or tostring(fmt)))
  end

  -- DOIS LADOS ARBITRARIOS, nao so desligado contra ligado.
  --
  -- VC_CLIP_OPT="breath=0.020"            esquerda OFF, direita 0.020
  -- VC_CLIP_OPT="breath=0.010:0.035"      esquerda 0.010, direita 0.035
  --
  -- A segunda forma existe para o loop de escolha: julgar entre dois
  -- candidatos e mais facil e mais confiavel do que julgar um sozinho, e e o
  -- unico jeito de a preferencia de quem assiste virar sinal aproveitavel.
  -- Comparar contra OFF responde "faz alguma coisa?"; comparar dois niveis
  -- responde "qual deles?", que e a pergunta que sobra depois que a feature ja
  -- existe.
  local OPT = os.getenv("VC_CLIP_OPT") or "breath=0.020"
  local CHAVE, RESTO = OPT:match("^([%w_]+)=(.+)$")
  if not CHAVE then log("opcao ilegivel: %s", OPT); return end
  local ESQ, DIR = RESTO:match("^([^:]+):(.+)$")
  if not ESQ then ESQ, DIR = "off", RESTO end
  local VALOR = DIR
  local VAL_ESQ = tonumber(ESQ) or ESQ
  local NUM = tonumber(DIR) or DIR
  local QUADROS = tonumber(os.getenv("VC_CLIP_FRAMES")) or 96
  local PASSO = tonumber(os.getenv("VC_CLIP_STEP")) or 2  -- captura 1 em cada N
  local ZOOM = tonumber(os.getenv("VC_CLIP_ZOOM")) or 0

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
    if not ok then log("AVISO: a troca de %s NAO foi emitida", chave) end
    return ok
  end

  -- POUSO. Ver tools/ingame/pouso.lua: U.teleport nao valida nada, e por isso
  -- o jogador aterrissava em cima de placa e de mesa nas fotos do gate.
  local pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")
  local mapa, x, y = pouso.escolher(game,
    os.getenv("VC_MAP") or "OAKS_LAB",
    tonumber(os.getenv("VC_X")) or 5,
    tonumber(os.getenv("VC_Y")) or 10)
  U.teleport(game, mapa, x, y, os.getenv("VC_FACING") or "down")
  U.wait(60)
  if not (game.overworld and game.stack:top() == game.overworld) then
    log("nao cheguei ao mundo"); return
  end
  log("mapa %s em (%d,%d)", mapa, x, y)

  -- DEGRAU DE CAMERA, e primeira pessoa entre eles.
  --
  -- Ate agora todo clipe saiu no degrau que o save tinha, o que ja rescalou
  -- contagem de pixel entre corridas neste projeto e, pior, deixou a primeira
  -- pessoa sem NENHUM clipe: os jogadores pediram a feature e nao havia como
  -- mostra-la lado a lado.
  --
  -- Pela mesma porta que o host usa, e nao por VoxelState.setLevel: quem e
  -- dono do degrau e o Pipelines do motor, e Voxel.update reescreve
  -- Voxel.level a partir dele todo quadro (VoxelState.lua:180). Chamar o
  -- errado nao da erro, so nao faz nada, e o sintoma parece a camera nao
  -- existir.
  local DEGRAUS = { off = 0, baixo = 2, medio = 3, alto = 4, empe = 5,
                    primeira = 6, terceira = 7 }
  local pedido = os.getenv("VC_CLIP_DEGRAU")
  if pedido and pedido ~= "" then
    local nivel = DEGRAUS[pedido] or tonumber(pedido)
    if not nivel then
      log("VC_CLIP_DEGRAU=%s nao existe; use %s ou um numero", pedido,
          "off/baixo/medio/alto/empe/primeira/terceira")
      return
    end
    local ok = pcall(function()
      require("src.render.Pipelines").setLevel("voxel", nivel)
    end)
    if not ok then log("nao consegui trocar o degrau de camera"); return end
    -- O degrau faz tween e a primeira pessoa ainda tem o blend por cima dele.
    -- Gravar antes de assentar poe o movimento da CAMERA dentro do clipe, e o
    -- olho le isso como o efeito que a gente esta tentando mostrar.
    U.wait(120)
    log("degrau de camera: %s (nivel %d)", pedido, nivel)
  end

  -- POR QUE FECHADO E NAO NA RUA. Na rua o ceu tem ciclo de dia, e como os dois
  -- lados sao gravados um depois do outro, o degrade do fundo muda entre eles:
  -- quem olha o lado a lado ve o ceu diferente antes de ver o personagem
  -- respirar, e a diferenca que importa fica em segundo plano. Dentro do
  -- laboratorio nao ha ceu, e ainda tem gente parada o bastante para mostrar
  -- que cada um respira na sua fase.
  --
  -- ZOOM ZERO POR PADRAO. Forcar zoom no jogo puxa a camera para um angulo
  -- baixo e o quadro vira parede e chao. Quem aproxima e o RECORTE no clip.sh,
  -- depois, sobre o que o jogo desenhou: o personagem fica sempre perto do
  -- centro porque a camera o segue, entao recortar o centro basta e nao mexe em
  -- nada da cena.
  U.tap(game, "3")
  U.wait(30)
  for _ = 1, ZOOM do
    if game.zoomStep then game:zoomStep(1) end
  end
  U.wait(30)

  -- BLINK desligado durante o clipe: ele anima olho no tempo e apareceria nos
  -- dois lados, confundindo quem tenta ver o que a opcao muda.
  opcao("blink", "off")
  opcao("breath", "off"); opcao("sway", "off"); opcao("lag", "off")
  opcao("footfall", "off")
  U.wait(30)
  -- O lado esquerdo pode ser um NIVEL, nao so o desligado.
  if VAL_ESQ ~= "off" then opcao(CHAVE, VAL_ESQ); U.wait(30) end

  -- MOTION LAG so existe com o personagem SE MOVENDO: parado, a mola esta em
  -- repouso e os dois lados sairiam identicos, o que faria o clipe provar que a
  -- feature nao faz nada. Entao para essa opcao os dois lados andam, e andam
  -- IGUAL: mesma direcao, mesmo numero de quadros, invertendo no meio para o
  -- personagem nao sair do enquadramento.
  -- MOTION LAG e FOOTFALL so existem com o personagem SE MOVENDO. Parado, a
  -- mola esta em repouso e a velocidade e zero, entao os dois lados sairiam
  -- identicos e o clipe provaria que a feature nao faz nada.
  local ANDA = (CHAVE == "lag" or CHAVE == "footfall")
    or os.getenv("VC_CLIP_ANDAR") == "1"
  -- Quantos quadros ANDANDO antes de inverter o sentido. Trocar de direcao
  -- custa uma parada, e parada mata justamente o efeito que se quer filmar,
  -- entao o padrao anda o suficiente para tres passos inteiros de 16 quadros
  -- em cada sentido antes de virar.
  local TRECHO = tonumber(os.getenv("VC_CLIP_TRECHO")) or 48

  -- ------------------------------------------------------- LEGENDA NO QUADRO
  -- O rotulo e desenhado DENTRO DO JOGO, nao colado depois pelo ffmpeg, e a
  -- razao e concreta: o ffmpeg desta maquina foi compilado sem libfreetype,
  -- entao nao tem o filtro drawtext. Um pipeline de trailer que depende de um
  -- build de terceiro quebra no primeiro colaborador que nao tem o mesmo.
  --
  -- Desenhando aqui, o texto entra no quadro de origem e sobrevive a tudo que
  -- vem depois: recorte, escala, mp4 e gif. E cada lado carrega o proprio
  -- rotulo, entao quando os dois sao empilhados o BEFORE cai na esquerda e o
  -- AFTER na direita sem ninguem coordenar nada.
  --
  -- O QUE OLHAR e o pedido do Kim e e a parte que mais vale: um clipe sem isso
  -- exige que quem assiste ja saiba o que a feature faz. Com isso, o clipe se
  -- explica sozinho, que e o que um trailer precisa fazer.
  local O_QUE_OLHAR = {
    breath = "os ombros subindo e descendo com o personagem parado",
    sway = "o corpo trocando o peso de um lado para o outro",
    lag = "o corpo ficando para tras ao arrancar e passando do ponto ao parar",
    footfall = "o corpo comprimindo a cada pisada e esticando entre elas",
    front_shape = "o degrade em degraus na face da frente",
    top_dome = "o topo da cabeca deixando de ser uma tampa chata",
    step_weight = "o solido inclinando junto com o passo da arte",
    shape = "como o volume e construido",
  }

  -- O ROTULO DO NIVEL VEM DO PROPRIO MOD, nao de uma tabela aqui.
  --
  -- A legenda precisa dizer "NORMAL", nao "0.7". Manter um mapa de valor para
  -- rotulo neste arquivo criaria uma segunda fonte da verdade que envelhece na
  -- primeira vez que alguem mexer num nivel, e o clipe passaria a mentir sem
  -- nenhum teste reclamar. Em vez disso a gente monta as rows do menu pelo
  -- mesmo hook que o jogo usa e le o valor da row, que e literalmente o texto
  -- que aparece na tela de opcoes.
  local function rotuloDoNivel(chave)
    local ok, Runtime = pcall(require, "src.mods.Runtime")
    if not ok then return nil end
    local okRows, rows = pcall(Runtime.call, "ui.options.rows",
      function(_, r) return r end, game, {})
    if not (okRows and type(rows) == "table") then return nil end
    for _, row in ipairs(rows) do
      if tostring(row.id) == "voxel_characters:" .. chave and row.value then
        local okVal, v = pcall(row.value, game)
        if okVal then return v end
      end
    end
  end

  local fonteGrande = love.graphics.newFont(22)
  local fonteMedia = love.graphics.newFont(15)
  local legendaTag = nil

  -- A area que o clip.sh recorta, em coordenadas de janela. A legenda precisa
  -- cair DENTRO dela, senao ela existe no quadro cheio e some no recorte.
  local RX, RY, RW, RH = 232, 200, 560, 420
  do
    local r = os.getenv("VC_CLIP_RECORTE")
    if r then
      local w, h, xx, yy = r:match("^(%d+):(%d+):(%d+):(%d+)$")
      if w then RX, RY, RW, RH = tonumber(xx), tonumber(yy), tonumber(w), tonumber(h) end
    end
  end

  local desenhoOriginal = love.draw
  love.draw = function()
    if desenhoOriginal then desenhoOriginal() end
    if not legendaTag then return end
    local antes = legendaTag == "off"
    local rotuloLado = antes and tostring(VAL_ESQ):upper() or nil
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setBlendMode("alpha")

    -- faixa de cima: BEFORE / AFTER e a opcao com o nivel
    love.graphics.setColor(0, 0, 0, 0.62)
    love.graphics.rectangle("fill", RX, RY, RW, 52)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(fonteGrande)
    -- BEFORE e AFTER so fazem sentido quando um dos lados e o estado atual.
    -- Num A/B entre dois niveis os dois sao candidatos, entao a legenda passa a
    -- ser A e B: chamar um deles de "before" mentiria sobre o que se compara.
    local ehContraOff = tostring(VAL_ESQ) == "off"
    love.graphics.print(
      ehContraOff and (antes and "BEFORE" or "AFTER") or (antes and "A" or "B"),
      RX + 12, RY + 5)
    love.graphics.setFont(fonteMedia)
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.print(
      string.upper(CHAVE) .. "   " .. (rotuloDoNivel(CHAVE)
        or tostring(antes and VAL_ESQ or VALOR)):upper(),
      RX + 12, RY + 31)

    -- faixa de baixo: o que olhar
    local dica = O_QUE_OLHAR[CHAVE]
    if dica then
      love.graphics.setColor(0, 0, 0, 0.62)
      love.graphics.rectangle("fill", RX, RY + RH - 30, RW, 30)
      love.graphics.setColor(1, 1, 1, 0.92)
      love.graphics.setFont(fonteMedia)
      love.graphics.printf("olhe " .. dica, RX + 12, RY + RH - 22, RW - 24)
    end
    love.graphics.pop()
  end

  local function grava(tag)
    legendaTag = tag
    for i = 1, QUADROS do
      if ANDA then
        local dir = (math.floor((i - 1) / TRECHO) % 2 == 0) and "left" or "right"
        table.insert(game.input.pressQueue, dir)
        game.input.state[dir] = true
        game.input.state[dir == "left" and "right" or "left"] = false
      end
      love.graphics.captureScreenshot(string.format("vc_clip_%s_%04d.png", tag, i))
      for _ = 1, PASSO do coroutine.yield() end
    end
    if ANDA then
      game.input.state["left"] = false
      game.input.state["right"] = false
      U.wait(45)  -- deixa a mola voltar ao repouso antes do proximo lado
    end
    log("lado %s gravado%s", tag, ANDA and " (andando)" or "")
  end

  -- MESMO PONTO DE PARTIDA NOS DOIS LADOS, e isto foi aprendido olhando o
  -- resultado. Quando o clipe anda, o segundo lado comecava de onde o primeiro
  -- tinha parado, entao o lado a lado mostrava o personagem em LUGARES
  -- diferentes e ninguem conseguia ver o efeito: o olho compara a posicao
  -- antes de comparar a deformacao. Voltar para a mesma celula antes de cada
  -- lado deixa a unica diferenca visivel ser a opcao.
  local function reposiciona()
    if not ANDA then return end
    U.teleport(game, mapa, x, y, os.getenv("VC_FACING") or "down")
    U.wait(45)
  end

  -- Lado esquerdo: desligado.
  reposiciona()
  grava("off")

  -- O PISO: o MESMO lado, gravado DE NOVO, pelo mesmo caminho. E o unico jeito
  -- de saber quanto dois clipes diferem entre si por motivo que nao e a opcao.
  --
  -- A primeira tentativa de piso comparava o quadro 10 com o quadro 40 da MESMA
  -- gravacao, e isso mede outra coisa: quadros vizinhos de uma corrida continua
  -- sao correlacionados, enquanto duas corridas comecam com fases diferentes.
  -- Medido: com o mesmo valor nos dois lados, "entre" dava 22 dB e "dentro"
  -- 28 dB, ou seja o par entre lados parecia MAIS diferente, e a guarda
  -- aprovava um A/B que nao comparava nada.
  --
  -- Estes quadros nao entram no video; existem so para dar escala.
  reposiciona()
  grava("piso")

  -- Lado direito: a opcao pedida. MOTION LAG so aparece com o personagem se
  -- movendo, entao para ela os dois lados andam; para as outras, os dois lados
  -- ficam parados. O que os dois lados nunca fazem e coisas diferentes.
  opcao(CHAVE, NUM)
  U.wait(30)
  reposiciona()
  grava("on")

  legendaTag = nil
  love.draw = desenhoOriginal
  log("quadros por lado: %d", QUADROS)
  U.wait(10)
end
