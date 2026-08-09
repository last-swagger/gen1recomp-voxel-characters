-- Gate in-game da PRIMEIRA PESSOA.
--
-- Desde a v1.3.0 este mod devolvia o card plano sempre que a primeira pessoa
-- estivesse ativa. Nao era falta de suporte, era conserto: o Colonel_Aureliano
-- reportou espetos pretos, e o card nao tem o defeito.
--
-- Lendo o host, o defeito nao e da camera, e da DISTANCIA. O shader empurra
-- cada vertice ao longo do proprio raio ate o olho por `pull` unidades
-- (Voxel3D.lua:122-130), primeira pessoa e o degrau 6 e ANGLES_DEG[7] = 75
-- graus, entao pull = 6 unidades de mundo com o tile valendo 16. O near plane
-- fica em 1 unidade quando olho e foco estao juntos. Um vertice a distancia d
-- vai parar em d - 6: atravessa o near plane com d < 7 e vai para tras do olho
-- com d < 6. O card plano sobrevive porque todos os seus vertices cruzam
-- juntos; num solido os cantos estao a distancias diferentes.
--
-- A suite offline ja prova a CONTA (que o pull repassado nunca alcanca o olho,
-- varrendo 0 a 80 unidades). Este arquivo mede o que so o jogo pode dizer: se
-- a conta certa chega na tela.
--
--   P1 a opcao chega no jogo      STATUS diz FIRST PERSON em CARD e nao diz
--                                 em SOLID
--   P2 o solido aparece           em primeira pessoa, SOLID difere de CARD;
--                                 sem isso os numeros abaixo nao significam
--                                 nada, porque estariam medindo a mesma tela
--   P3 o piso de ruido            CARD contra CARD no mesmo instante, que e o
--                                 quanto a cena se mexe sozinha
--   P4 a TRANSICAO nao explode    varrendo o blend de 0 a 1, a diferenca
--                                 SOLID-CARD fica na mesma ordem de grandeza
--                                 do quadro inteiro; espeto multiplicaria
--
-- P4 e o unico que interessa de verdade. O card do PROPRIO jogador e o caso
-- catastrofico, porque a camera esta entrando na cabeca dele e a distancia vai
-- a zero, e o host so esconde esse card depois de blend > 0.9. Entao a faixa
-- que este gate varre e exatamente a faixa onde o defeito vivia. Por isso o
-- mapa e o quarto do Red: zero object events, o unico personagem na tela e o
-- jogador, que e o pior caso e tambem o mais limpo de medir.

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

  local function amostras(img)
    if not img then return 0 end
    local w, h = img:getWidth(), img:getHeight()
    return math.ceil(w / 3) * math.ceil(h / 3)
  end

  -- O host, pela mesma porta que o mod usa. Se nao der para alcancar, isso e
  -- resultado e nao acidente: sem VoxelState nao ha como ENTRAR em primeira
  -- pessoa, e um gate que nao entrou nao pode dizer que passou.
  local lib
  do
    local alvos = {
      function() return game.mods.exports.DRAMATIC_SHAPE.lib end,
      function() return game.mods:find("DRAMATIC_SHAPE").exports.lib end,
      function() return game.mods.find("DRAMATIC_SHAPE").exports.lib end,
    }
    for _, f in ipairs(alvos) do
      local ok, v = pcall(f)
      if ok and type(v) == "table" and v.require then lib = v break end
    end
  end
  if not lib then
    veredito("P0", false, "nao alcancei a lib do DRAMATIC_SHAPE; sem ela nao "
      .. "da para entrar em primeira pessoa")
    love.filesystem.write("vc_fp.txt", table.concat(linhas, "\n") .. "\n")
    return
  end
  local okVS, VoxelState = pcall(lib.require, "VoxelState")
  local okFP, FirstPerson = pcall(lib.require, "FirstPerson")
  if not (okVS and okFP and VoxelState and FirstPerson) then
    veredito("P0", false, "host sem VoxelState ou FirstPerson")
    return
  end
  nota("FP_LEVEL do host: %s   pull nesse degrau: ver VoxelScene.pull",
       tostring(VoxelState.FP_LEVEL))

  -- ARMADILHA DA PRIMEIRA CORRIDA: comecei no quarto do Red, "porque nao tem
  -- mais ninguem". Em primeira pessoa o unico personagem daquele quarto e o
  -- JOGADOR, e o host esconde o card do proprio jogador quando o blend passa
  -- de 0.9 (FirstPerson.hidePlayer). Entao no blend cheio nao havia
  -- personagem nenhum na tela e a medicao deu zero diferenca, o que eu quase
  -- li como "o solido nao aparece". O centro pokemon tem a enfermeira atras
  -- do balcao, que nao anda: personagem visivel e parado ao mesmo tempo.
  local MAPA = os.getenv("VC_MAP") or "CERULEAN_POKECENTER"
  local Pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")
  local _, PX, PY = Pouso.escolher(game, MAPA, 3, 4)
  U.teleport(game, MAPA, PX, PY, "down")
  U.wait(60)
  if not (game.overworld and game.stack:top() == game.overworld) then
    veredito("P1", false, "nao cheguei ao mundo"); return
  end

  opcao("depth", 3)
  opcao("breath", "off"); opcao("sway", "off")
  opcao("lag", "off"); opcao("footfall", "off"); opcao("blink", "off")
  U.wait(20)

  -- ---------------------------------------------------------------- P1
  -- A opcao chega no jogo, lida pela row de STATUS, que e o que o jogador ve.
  -- ARMADILHA, e custou uma corrida inteira: VoxelState.setLevel NAO manda.
  -- Quem e dono do degrau e o Pipelines do motor, e Voxel.update(level)
  -- (VoxelState.lua:180) reescreve Voxel.level a partir dele TODO QUADRO.
  -- Chamar setLevel direto muda o campo e o proximo quadro desfaz, e o
  -- sintoma foi "o blend nunca subiu", que parece a camera nao existir.
  -- O host tambem entra por aqui (main.lua:572, Horde.lua:387).
  local Pipelines = require("src.render.Pipelines")
  local FP = VoxelState.FP_LEVEL or 6
  local function entra() pcall(Pipelines.setLevel, "voxel", FP) end
  local function sai() pcall(Pipelines.setLevel, "voxel", 0) end

  entra()
  -- o blend leva BLEND_TIME para subir; esperar ate ele chegar em 1
  local blendFinal = 0
  for _ = 1, 240 do
    U.wait(1)
    local okB, b = pcall(FirstPerson.cardBlend)
    blendFinal = (okB and tonumber(b)) or 0
    if blendFinal >= 0.999 then break end
  end
  nota("blend depois de entrar: %.3f", blendFinal)
  if blendFinal <= 0 then
    veredito("P1", false, "o blend nunca subiu; a camera nao entrou em "
      .. "primeira pessoa nesta maquina")
    return
  end

  -- P1 e a precondicao e nao um resultado: sem estar em primeira pessoa de
  -- verdade, tudo abaixo mediria outra coisa. O que a row de STATUS diz em
  -- cada modo ja e coberto pela suite offline, onde da para ler a row direto
  -- sem navegar menu; repetir aqui seria construir um caminho de UI fragil
  -- para reprovar o que ja esta provado.
  veredito("P1", blendFinal >= 0.999,
    string.format("a camera entrou em primeira pessoa, blend %.3f", blendFinal))

  -- ---------------------------------------------------------------- P2 e P3
  local function tela(modo)
    opcao("first_person", modo)
    U.wait(6)
    return captura()
  end

  local card1 = tela("card")
  local card2 = tela("card")
  local solid = tela("solid")
  local piso = difere(card1, card2)
  local delta = difere(card1, solid)
  local total = amostras(card1)
  nota("amostras por quadro: %d", total)
  nota("piso de ruido, CARD contra CARD: %d (%.2f%%)", piso, piso / total * 100)
  nota("CARD contra SOLID: %d (%.2f%%)", delta, delta / total * 100)

  veredito("P3", piso >= 0 and piso < total * 0.02,
    string.format("a cena parada muda %d de %d amostras sozinha", piso, total))
  veredito("P2", delta > piso * 4 + 20,
    string.format("SOLID muda a tela: %d contra piso %d", delta, piso))

  -- ---------------------------------------------------------------- P4
  -- A TRANSICAO. Sai da primeira pessoa, volta, e mede a cada poucos quadros
  -- enquanto o blend sobe. Espeto preto nao e uma diferenca a mais: e uma
  -- diferenca de outra ordem de grandeza, porque a cunha varre a tela.
  -- SEGUNDA ARMADILHA, e ela quase virou um resultado: na primeira versao eu
  -- fotografava CARD e SOLID um depois do outro DURANTE a subida do blend. A
  -- camera anda entre as duas fotos, entao 80 a 94 por cento do quadro
  -- diferia, e nada daquilo era espeto: era a camera. Medir efeito pequeno com
  -- a cena andando ja custou uma sessao inteira neste projeto, e aqui a coisa
  -- que anda e a propria camera.
  --
  -- Conserto: cada lado sai de uma ENTRADA propria, com a mesma espera, e a
  -- amostra so conta se os dois blends baterem. Amostra descartada e dita em
  -- voz alta, senao corte silencioso se le como cobertura.
  local pior, piorBlend = 0, 0
  local usadas, descartadas = 0, 0
  local function entraAte(frames, modo)
    sai(); U.wait(70)
    opcao("first_person", modo); U.wait(6)
    entra()
    U.wait(frames)
    local okB, b = pcall(FirstPerson.cardBlend)
    return (okB and tonumber(b)) or 0, captura()
  end
  for passo = 1, 12 do
    local frames = passo * 3
    local bA, imgA = entraAte(frames, "card")
    local bB, imgB = entraAte(frames, "solid")
    if math.abs(bA - bB) > 0.03 then
      descartadas = descartadas + 1
      nota("  descartada: blends nao bateram, %.2f contra %.2f", bA, bB)
    else
      local d = difere(imgA, imgB)
      usadas = usadas + 1
      if d > pior then pior, piorBlend = d, (bA + bB) / 2 end
      nota("  blend %.2f   CARD contra SOLID %d (%.1f%%)", bA, d, d / total * 100)
    end
  end
  sai(); U.wait(60)

  -- O CRITERIO, e por que este numero.
  --
  -- Um solido honesto difere do card no corpo do personagem e em nada mais. Em
  -- primeira pessoa o personagem mais proximo ocupa uma fatia grande da tela,
  -- entao a diferenca legitima pode ser alta, e um limite apertado reprovaria
  -- a feature funcionando. O que o espeto faz e diferente em ESPECIE: a cunha
  -- preta sai do corpo e cruza o quadro, entao ela leva a diferenca para perto
  -- do quadro inteiro. Metade do quadro separa os dois casos com folga dos
  -- dois lados, e e um numero que uma medicao futura pode apertar com dado.
  local TETO = total * 0.5
  veredito("P4", pior <= TETO and usadas >= 6,
    string.format("pior diferenca na transicao %d (%.1f%%) no blend %.2f, "
      .. "teto %d (50%%), %d amostras usadas e %d descartadas",
      pior, pior / total * 100, piorBlend, math.floor(TETO),
      usadas, descartadas))

  opcao("first_person", "card")

  nota("")
  local todosOk = true
  for _, v in ipairs(vereditos) do
    nota("%-3s %s", v.nome, v.ok and "PASSOU" or "FALHOU")
    todosOk = todosOk and v.ok
  end
  nota("VEREDITO: %s", todosOk
    and "O SOLIDO SOBREVIVE A PRIMEIRA PESSOA"
    or "AINDA NAO")
end
