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
  dofile("mods/voxel_characters/tools/ingame/erro.lua")()
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
  -- OS TRES HOSTS, e nao so o original. O mod aceita DRAMATIC_SHAPE, o fork de
  -- arte de batalha do absol89 e o Dramaless do artyrambles (main.lua:37-47), e
  -- probe_life.lua ja varre os tres. Este arquivo pedia so o primeiro, entao no
  -- fork que boa parte da comunidade roda ele falhava no P0 e o gate inteiro
  -- era pulado, sem que ninguem visse diferenca entre "nao mediu" e "mediu e
  -- passou".
  local HOSTS = { "BATTLE_ART_VOXEL_FORK", "DRAMALESS_SHAPE", "DRAMATIC_SHAPE" }
  local lib, hostId
  for _, id in ipairs(HOSTS) do
    for _, f in ipairs({
      function() return game.mods.exports[id].lib end,
      function() return game.mods:find(id).exports.lib end,
      function() return game.mods.find(id).exports.lib end,
    }) do
      local ok, v = pcall(f)
      if ok and type(v) == "table" and v.require then lib, hostId = v, id break end
    end
    if lib then break end
  end
  if lib then nota("host: %s", hostId) end
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

  -- O QUARTO DO RED, e a volta a ele conta uma historia inteira.
  --
  -- Primeira escolha: quarto do Red, zero object events. Errado, porque no
  -- blend CHEIO o unico personagem ali e o jogador e o host esconde o card
  -- dele acima de 0.9. A tela ficava sem ninguem e a medicao dava zero, que le
  -- como "o solido nao aparece".
  --
  -- Segunda escolha: centro pokemon, "porque tem gente parada". Media com
  -- sorte: uma corrida achou um NPC no cone da camera e a seguinte nao achou
  -- nenhum nas quatro direcoes. E quando finalmente casei os blends, o piso
  -- CARD contra CARD deu 29 mil de 87 mil amostras, 33% do quadro, porque
  -- aquele mapa tem NPC andando e o gate estava medindo eles.
  --
  -- Terceira, e a certa: quarto do Red DE NOVO, mas medindo no MEIO do blend
  -- em vez de no fim. Ali o card do proprio jogador esta em cena por
  -- construcao, e ele e o pior caso do defeito, porque a camera esta entrando
  -- na cabeca dele. Zero object events volta a ser a vantagem que era.
  local MAPA = os.getenv("VC_MAP") or "REDS_HOUSE_2F"
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
  -- O CONTROLE MEDE CONTRA O CARD DO PROPRIO JOGADOR, e nao contra um NPC que
  -- talvez esteja no quadro.
  --
  -- A versao anterior varria as quatro direcoes procurando alguem em cena. Ela
  -- recusava o veredito quando nao achava, que e o certo, mas achava com sorte:
  -- mesmo comando, uma corrida achou 531 amostras e a seguinte achou zero nas
  -- quatro. O probe teleporta para um centro pokemon e torce para um NPC estar
  -- no cone da camera, e onde os NPCs estao nao e coisa que ele controle. Gate
  -- que falha por motivo alheio ao codigo ensina a rodar de novo ate ficar
  -- verde, e gate que se roda de novo nao e gate.
  --
  -- O jogador esta SEMPRE em cena abaixo do blend 0.9: o host so esconde o card
  -- dele acima disso (FirstPerson.hidePlayer), e a faixa abaixo e exatamente
  -- onde o defeito dos espetos vivia, porque e onde a camera entra na cabeca
  -- dele. Entao o controle mora ali: garantido, e no caso que interessa.
  -- ESPERAR PELO BLEND, e nao por um numero de quadros. Contar quadros deu
  -- 0.64 num lado e 0.94 no outro, e a diferenca entre as duas fotos passou a
  -- ser a CAMERA em vez da opcao: 62 mil amostras de "controle" que nao
  -- controlavam nada. Parar num valor de blend faz os dois lados casarem por
  -- construcao.
  local ALVO = 0.55
  local function noBlend(alvo)
    sai(); U.wait(50)
    entra()
    for _ = 1, 240 do
      U.wait(1)
      if blendAgora() >= alvo then break end
    end
    local b = blendAgora()
    return b, captura()
  end

  sai(); U.wait(40)
  U.teleport(game, MAPA, PX, PY, "down")
  U.wait(40)

  -- O CONTROLE RODA EM SOLID, e isto ja me enganou uma vez. Com FIRST PERSON
  -- em CARD o mod devolve o card original nessa camera POR CONTRATO, entao
  -- ligar e desligar o mod inteiro nao muda nada e o controle mede zero por
  -- decisao de projeto, nao por falta de personagem em cena. Um controle que
  -- pode dar zero pelo motivo certo e pelo motivo errado nao controla nada.
  opcao("first_person", "solid")
  opcao("depth", 3); U.wait(8)
  local bCom, com = noBlend(ALVO)
  opcao("depth", "off"); U.wait(8)
  local bSem, sem = noBlend(ALVO)
  opcao("depth", 3); U.wait(8)
  total(com)
  local melhor = { dir = "down", delta = difere(com, sem) }
  nota("controle no blend %.2f e %.2f: mod ligado contra desligado %d de %d",
       bCom, bSem, melhor.delta, total())
  veredito("P1", math.abs(bCom - bSem) <= 0.05 and bCom > 0.02 and bCom < 0.9,
    string.format("as duas medidas casaram no meio da entrada: blend %.2f e "
      .. "%.2f", bCom, bSem))
  if math.abs(bCom - bSem) > 0.05 then
    nota("blends diferentes: a medida seria da camera, nao da opcao")
    return fim()
  end

  veredito("P2", melhor.delta > total() * 0.002,
    string.format("ha personagem nosso na tela: %d de %d amostras (%.2f%%)",
      melhor.delta, total(), melhor.delta / total() * 100))
  if melhor.delta <= total() * 0.002 then
    nota("nem o card do proprio jogador aparece; nada abaixo mede a opcao")
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
  -- No MESMO blend do controle, porque e ali que existe personagem garantido.
  local function ladoNoBlend(modo)
    opcao("first_person", modo); U.wait(8)
    return noBlend(ALVO)
  end
  local b1, c1 = ladoNoBlend("card")
  local b2, c2 = ladoNoBlend("card")
  local b3, s1 = ladoNoBlend("solid")
  local piso = difere(c1, c2)
  local sinal = difere(c1, s1)
  nota("blend %.2f/%.2f/%.2f: piso CARD-CARD %d, sinal CARD-SOLID %d de %d",
       b1, b2, b3, piso, sinal, total())
  veredito("P3", sinal > piso * 2 + 20,
    string.format("o SOLID muda a tela: %d contra piso %d", sinal, piso))

  -- ---------------------------------------------------------------- P4
  --
  -- O PISO VEM DO MESMO PROCEDIMENTO. Comparar a diferenca contra um numero
  -- absoluto escolhido por mim mediria o meu chute; comparar contra CARD-CARD
  -- feito com a mesma saida, mesma entrada e mesma espera mede so o que a
  -- opcao mudou. Tudo que a cena faz sozinha nesse intervalo aparece nos dois.
  -- Tambem por blend, e nao por quadro. Com contagem de quadros o piso da
  -- transicao chegou a 39 mil de 87 mil amostras, quase o teto inteiro: os
  -- dois lados paravam em blends diferentes e a diferenca era a camera.
  local function amostraEm(alvo, modo)
    opcao("first_person", modo); U.wait(6)
    return noBlend(alvo)
  end

  local piorSinal, piorBlend, piorPiso = 0, 0, 0
  local usadas, descartadas = 0, 0
  for passo = 1, 8 do
    local alvo = 0.10 + (passo - 1) * 0.10
    local bA, imgA = amostraEm(alvo, "card")
    local bF, imgF = amostraEm(alvo, "card")
    local bS, imgS = amostraEm(alvo, "solid")
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
  -- TETO E PISO. So com teto, P4 nao distingue "nao explodiu" de "nao
  -- desenhou": um SOLID que caisse no card durante a transicao daria sinal
  -- zero, que e <= teto, e passaria. P3 nao cobre isso porque mede no blend
  -- alvo, nao na varredura.
  veredito("P4", usadas >= 5 and piorSinal <= TETO
      and piorSinal > piorPiso * 2 + 100,
    string.format("pior CARD-SOLID na transicao %d (%.1f%%) no blend %.2f, "
      .. "entre o piso %d e o teto %d (50%%); %d usadas, %d descartadas",
      piorSinal, piorSinal / total() * 100, piorBlend, piorPiso,
      math.floor(TETO), usadas, descartadas))

  opcao("first_person", "card")
  fim()
end
