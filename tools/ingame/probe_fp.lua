-- Gate in-game da PRIMEIRA PESSOA.
--
-- Desde a v1.3.0 este mod devolvia o card plano sempre que a primeira pessoa
-- estivesse ativa. Nao era falta de suporte, era conserto: o Colonel_Aureliano
-- reportou espetos pretos, e o card nao tem o defeito.
--
-- Lendo o host, o defeito nao e da camera, e da DISTANCIA. O shader empurra
-- cada vertice ao longo do proprio raio ate o olho por `pull` unidades
-- (Voxel3D.lua:122-130); primeira pessoa e o degrau 6 e ANGLES_DEG[7] = 75
-- graus, entao pull = 6 unidades de mundo com o tile valendo 16; o near plane
-- fica em 1 unidade quando olho e foco estao juntos. Um vertice a distancia d
-- vai parar em d - 6: atravessa o near plane com d < 7 e vai para tras do olho
-- com d < 6. O card plano sobrevive porque todos os seus vertices cruzam
-- juntos; num solido os cantos estao a distancias diferentes.
--
-- A suite offline ja prova a CONTA: varrendo 0 a 80 unidades, o pull repassado
-- nunca alcanca o olho, e quebrar o clamp mata quatro checks. Este arquivo
-- mede a unica coisa que a suite nao pode: se a conta certa chega na TELA.
--
--   P1 entrou mesmo              o blend chega a 1; sem isso tudo abaixo
--                                mediria outra camera
--   P2 tem personagem na tela    controle ligando e desligando o mod inteiro.
--                                E o primeiro que eu preciso porque zero
--                                diferenca tem duas causas opostas: a opcao
--                                nao chegou, ou nao havia o que mudar
--   P3 o solido aparece          com personagem confirmado na tela, SOLID
--                                difere de CARD
--   P4 a TRANSICAO nao explode   varrendo o blend, a diferenca SOLID-CARD
--                                fica na ordem do volume e nao do quadro,
--                                comparada contra um piso medido do MESMO
--                                jeito
--
-- P4 e o que interessa. O card do PROPRIO jogador e o caso catastrofico,
-- porque a camera esta entrando na cabeca dele e a distancia vai a zero, e o
-- host so esconde esse card depois de blend > 0.9. A faixa varrida aqui e
-- exatamente onde o defeito vivia.
--
-- DUAS ARMADILHAS QUE ESTE ARQUIVO JA PAGOU, escritas para nao se repetirem:
--
--   VoxelState.setLevel NAO MANDA. Quem e dono do degrau e o Pipelines do
--   motor, e Voxel.update(level) (VoxelState.lua:180) reescreve Voxel.level a
--   partir dele todo quadro. O sintoma de chamar o errado foi "o blend nunca
--   subiu", que parece a camera nao existir nesta maquina.
--
--   FOTOGRAFAR OS DOIS LADOS ENQUANTO A CAMERA ANDA mede a camera. Na primeira
--   versao isso deu 80 a 94 por cento do quadro diferindo, e nada era espeto.
--   Cada lado agora sai de uma entrada propria com a mesma espera, e a amostra
--   so conta se os dois blends baterem.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  io.stdout:setvbuf("line")
  if love.window and love.window.setVSync then pcall(love.window.setVSync, 0) end

  local linhas = {}
  local function nota(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    linhas[#linhas + 1] = ok and s or tostring(fmt)
    print("[fp] " .. linhas[#linhas])
    love.filesystem.write("vc_fp.txt", table.concat(linhas, "\n") .. "\n")
  end

  local vereditos = {}
  local function veredito(nome, ok, detalhe)
    vereditos[#vereditos + 1] = { nome = nome, ok = ok }
    nota("%-3s %s  %s", nome, ok and "PASSOU" or "FALHOU", detalhe or "")
  end

  local function fim()
    nota("")
    local todos = true
    for _, v in ipairs(vereditos) do
      nota("%-3s %s", v.nome, v.ok and "PASSOU" or "FALHOU")
      todos = todos and v.ok
    end
    nota("VEREDITO: %s", todos
      and "O SOLIDO SOBREVIVE A PRIMEIRA PESSOA" or "AINDA NAO")
  end

  nota("=== gate de primeira pessoa ===")

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

  local function captura()
    local pronto
    love.graphics.captureScreenshot(function(img) pronto = img end)
    for _ = 1, 120 do
      coroutine.yield()
      if pronto then return pronto end
    end
    return nil
  end

  local function difere(a, b)
    if not (a and b) then return -1 end
    local w, h = a:getWidth(), a:getHeight()
    if b:getWidth() ~= w or b:getHeight() ~= h then return -1 end
    local n = 0
    for y = 0, h - 1, 3 do
      for x = 0, w - 1, 3 do
        local ar, ag, ab = a:getPixel(x, y)
        local br, bg, bb = b:getPixel(x, y)
        if math.abs(ar - br) + math.abs(ag - bg) + math.abs(ab - bb) > 0.02 then
          n = n + 1
        end
      end
    end
    return n
  end

  -- O host, pela mesma porta que o mod usa.
  local lib
  for _, f in ipairs({
    function() return game.mods.exports.DRAMATIC_SHAPE.lib end,
    function() return game.mods:find("DRAMATIC_SHAPE").exports.lib end,
    function() return game.mods.find("DRAMATIC_SHAPE").exports.lib end,
  }) do
    local ok, v = pcall(f)
    if ok and type(v) == "table" and v.require then lib = v break end
  end
  if not lib then
    veredito("P0", false, "nao alcancei a lib do DRAMATIC_SHAPE")
    return fim()
  end
  local okVS, VoxelState = pcall(lib.require, "VoxelState")
  local okFP, FirstPerson = pcall(lib.require, "FirstPerson")
  if not (okVS and okFP and VoxelState and FirstPerson) then
    veredito("P0", false, "host sem VoxelState ou FirstPerson")
    return fim()
  end

  local Pipelines = require("src.render.Pipelines")
  local FPLEVEL = VoxelState.FP_LEVEL or 6
  local function entra() pcall(Pipelines.setLevel, "voxel", FPLEVEL) end
  local function sai() pcall(Pipelines.setLevel, "voxel", 0) end
  local function blendAgora()
    local ok, b = pcall(FirstPerson.cardBlend)
    return (ok and tonumber(b)) or 0
  end
  nota("FP_LEVEL do host: %d", FPLEVEL)

  -- O quarto do Red foi a primeira escolha e foi errada: em primeira pessoa o
  -- unico personagem la e o JOGADOR, e o host esconde o card do proprio
  -- jogador acima de blend 0.9 (FirstPerson.hidePlayer). No blend cheio a tela
  -- ficava sem personagem nenhum e a medicao dava zero, que eu quase li como
  -- "o solido nao aparece". Centro pokemon tem gente parada atras do balcao.
  local MAPA = os.getenv("VC_MAP") or "CERULEAN_POKECENTER"
  local Pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")
  local _, PX, PY = Pouso.escolher(game, MAPA, 3, 4)

  opcao("depth", 3)
  opcao("breath", "off"); opcao("sway", "off"); opcao("lag", "off")
  opcao("footfall", "off"); opcao("blink", "off")
  opcao("first_person", "card")

  local TOTAL
  local function total(img)
    if not TOTAL and img then
      TOTAL = math.ceil(img:getWidth() / 3) * math.ceil(img:getHeight() / 3)
    end
    return TOTAL or 1
  end

  -- ---------------------------------------------------------------- P1 e P2
  --
  -- A CAMERA DE PRIMEIRA PESSOA OLHA PARA ONDE O JOGADOR OLHA, entao a direcao
  -- do teleporte decide se existe personagem no quadro. Em vez de eu escolher
  -- uma direcao e torcer, o gate MEDE as quatro: liga e desliga o mod inteiro
  -- e fica com a que mais muda. Essa e a mesma pergunta do controle negativo,
  -- respondida uma vez e reaproveitada.
  local melhor = { dir = nil, delta = -1 }
  for _, dir in ipairs({ "up", "left", "right", "down" }) do
    sai(); U.wait(30)
    U.teleport(game, MAPA, PX, PY, dir)
    U.wait(40)
    entra()
    for _ = 1, 240 do
      U.wait(1)
      if blendAgora() >= 0.999 then break end
    end
    opcao("depth", 3); U.wait(8)
    local com = captura()
    opcao("depth", "off"); U.wait(8)
    local sem = captura()
    opcao("depth", 3); U.wait(8)
    local d = difere(com, sem)
    nota("  olhando para %-5s: mod ligado contra desligado %d (%.1f%%)",
         dir, d, d / total(com) * 100)
    if d > melhor.delta then melhor = { dir = dir, delta = d } end
  end

  veredito("P1", blendAgora() >= 0.999,
    string.format("a camera entrou em primeira pessoa, blend %.3f", blendAgora()))
  veredito("P2", melhor.delta > total() * 0.005,
    string.format("olhando para %s ha personagem nosso na tela: %d de %d "
      .. "amostras (%.1f%%)", tostring(melhor.dir), melhor.delta, total(),
      melhor.delta / total() * 100))
  if melhor.delta <= total() * 0.005 then
    nota("sem personagem no quadro em nenhuma das quatro direcoes, nada abaixo")
    nota("mediria a opcao. Tente outro mapa com VC_MAP.")
    return fim()
  end

  -- Dali em diante, sempre a mesma direcao.
  local DIR = melhor.dir
  local function posiciona()
    sai(); U.wait(30)
    U.teleport(game, MAPA, PX, PY, DIR)
    U.wait(40)
  end

  -- ---------------------------------------------------------------- P3
  posiciona()
  entra()
  for _ = 1, 240 do U.wait(1); if blendAgora() >= 0.999 then break end end
  local function tela(modo)
    opcao("first_person", modo); U.wait(8)
    return captura()
  end
  local c1, c2 = tela("card"), tela("card")
  local s1 = tela("solid")
  local piso = difere(c1, c2)
  local sinal = difere(c1, s1)
  nota("blend cheio: piso CARD-CARD %d, sinal CARD-SOLID %d de %d amostras",
       piso, sinal, total())
  veredito("P3", sinal > piso * 4 + 20,
    string.format("no blend cheio o SOLID muda a tela: %d contra piso %d",
      sinal, piso))

  -- ---------------------------------------------------------------- P4
  --
  -- O PISO VEM DO MESMO PROCEDIMENTO. Comparar a diferenca contra um numero
  -- absoluto escolhido por mim mediria o meu chute; comparar contra CARD-CARD
  -- feito com a mesma saida, mesma entrada e mesma espera mede so o que a
  -- opcao mudou. Tudo que a cena faz sozinha nesse intervalo aparece nos dois.
  local function amostraEm(frames, modo)
    posiciona()
    opcao("first_person", modo); U.wait(6)
    entra()
    U.wait(frames)
    return blendAgora(), captura()
  end

  local piorSinal, piorBlend, piorPiso = 0, 0, 0
  local usadas, descartadas = 0, 0
  for passo = 1, 8 do
    local frames = passo * 4
    local bA, imgA = amostraEm(frames, "card")
    local bF, imgF = amostraEm(frames, "card")
    local bS, imgS = amostraEm(frames, "solid")
    if math.abs(bA - bF) > 0.03 or math.abs(bA - bS) > 0.03 then
      descartadas = descartadas + 1
      nota("  descartada: blends %.2f / %.2f / %.2f nao bateram", bA, bF, bS)
    else
      local p = difere(imgA, imgF)
      local d = difere(imgA, imgS)
      usadas = usadas + 1
      if d > piorSinal then piorSinal, piorBlend, piorPiso = d, bA, p end
      nota("  blend %.2f   piso %d (%.1f%%)   CARD-SOLID %d (%.1f%%)",
           bA, p, p / total() * 100, d, d / total() * 100)
    end
  end
  sai(); U.wait(60)

  -- O CRITERIO. Um solido honesto difere do card no CORPO e em nada mais, e o
  -- corpo em primeira pessoa e grande, entao um teto apertado reprovaria a
  -- feature funcionando. O espeto e diferente em especie: a cunha preta sai do
  -- corpo e varre o quadro. Metade do quadro separa os dois com folga dos dois
  -- lados, e o piso medido no mesmo procedimento diz quanto disso e a cena.
  local TETO = total() * 0.5
  veredito("P4", usadas >= 5 and piorSinal <= TETO,
    string.format("pior CARD-SOLID na transicao %d (%.1f%%) no blend %.2f, "
      .. "com piso %d ali; teto %d (50%%); %d amostras usadas, %d descartadas",
      piorSinal, piorSinal / total() * 100, piorBlend, piorPiso,
      math.floor(TETO), usadas, descartadas))

  opcao("first_person", "card")
  fim()
end
