-- Gate do MENU: aperta tecla de verdade, no menu de verdade, do jeito que o
-- jogador aperta.
--
-- POR QUE ELE EXISTE, e a resposta e um bug que escapou de tudo. No dia da
-- v1.6.0, uma revisao independente do motor descobriu que apertar A em cima da
-- row de STATUS ou de LIFE FECHAVA a tela de opcoes. O motor resolve A,
-- esquerda e direita no mesmo ramo, nesta ordem (src/ui/OptionsMenu.lua:549-566):
--
--     row.activate  ->  chama
--     row.step      ->  cicla
--     senao, se foi A, trata como CANCEL e da POP NO MENU
--
-- Nossas duas rows de leitura tem `value` e mais nada, entao caiam no terceiro
-- caso. E A e a primeira tecla que alguem aperta numa linha que nao reconhece,
-- que e exatamente o publico da row de STATUS.
--
-- Nenhum dos 486 checks offline nem dos oito checks de pixel pegou, e nao foi
-- azar: NENHUM DELES APERTA TECLA NO MENU. Os offline chamam o hook direto e
-- leem a tabela de rows; os de pixel escrevem a opcao no save e emitem o
-- evento. Os dois pulam a tela por onde 100% dos jogadores passam.
--
-- O que este gate pergunta:
--
--   M1 o menu abre            START, achar OPTION pelo ROTULO, A
--   M2 as rows existem        todas as nossas aparecem, na ordem certa
--   M3 alcancaveis            da para chegar em cada uma so com baixo/cima
--   M4 A nao fecha            A em row de leitura mantem o menu aberto
--   M5 direita cicla          o rotulo vira o proximo nivel, e persiste
--   M6 esquerda volta         e o ciclo fecha nos dois sentidos
--   M7 convive                as rows de outro mod continuam intactas
--   M8 chega na tela          sair do menu, e o mundo mudou de verdade

return function(game)
  local U = dofile("tests/drivers/util.lua")
  io.stdout:setvbuf("line")
  if love.window and love.window.setVSync then pcall(love.window.setVSync, 0) end

  local Strings = require("src.core.Strings")
  local OptionsMenu = require("src.ui.OptionsMenu")
  local OptionRows = require("src.ui.OptionRows")

  local linhas = {}
  local function nota(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    local linha = ok and s or tostring(fmt)
    linhas[#linhas + 1] = linha
    print("[menu] " .. linha)
    love.filesystem.write("vc_menu.txt", table.concat(linhas, "\n") .. "\n")
  end

  local vereditos = {}
  local function veredito(nome, ok, detalhe)
    vereditos[#vereditos + 1] = { nome = nome, ok = ok }
    nota("%-3s %s  %s", nome, ok and "PASSOU" or "FALHOU", detalhe or "")
  end

  local function topo() return game.stack:top() end

  nota("=== gate do menu de opcoes ===")

  -- --------------------------------------------------------------- mundo
  local Pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")
  local mapa, x, y = Pouso.escolher(game,
    os.getenv("VC_MAP") or "PALLET_TOWN",
    tonumber(os.getenv("VC_X")) or 10,
    tonumber(os.getenv("VC_Y")) or 8)
  U.teleport(game, mapa, x, y, "down")
  U.wait(60)
  if topo() ~= game.overworld then
    veredito("M1", false, "nao cheguei ao mundo"); return
  end

  -- ---------------------------------------------------------------- M1
  -- START e latcheado enquanto o jogador esta no meio de um passo
  -- (OverworldController.lua:1186), entao espera ele assentar.
  for _ = 1, 120 do
    if not (game.overworld.player and game.overworld.player.moving) then break end
    U.wait(1)
  end
  U.tap(game, "start"); U.wait(12)
  local inicio = topo()
  if not (inicio and inicio.items) then
    veredito("M1", false, "o menu START nao abriu"); return
  end

  -- Achar OPTION pelo ROTULO, nunca contando posicoes: as linhas do START vao e
  -- vem com o estado do save (POKEDEX so aparece depois de ganhar, LINK depende
  -- de ter time) e com o hook ui.start_menu.items de outros mods.
  local alvoRotulo = Strings("OPTION")
  local alvo
  for i, item in ipairs(inicio.items) do
    if item.label == alvoRotulo then alvo = i break end
  end
  if not alvo then
    veredito("M1", false, "nao achei a linha OPTION no menu START"); return
  end
  for _ = 1, #inicio.items + 2 do
    if inicio.index == alvo then break end
    U.tap(game, "down"); U.wait(3)
  end
  U.tap(game, "a"); U.wait(15)
  local menu = topo()
  local abriu = getmetatable(menu) == OptionsMenu
  veredito("M1", abriu, abriu and "START, OPTION, A: a tela de opcoes abriu"
    or "OPTION nao abriu a tela de opcoes")
  if not abriu then return end

  -- O Dramatic Shape TROCA menu.rows no lugar em certas mudancas
  -- (DramaticShapeVoxelMod/main.lua:958), entao nunca cachear o array: sempre
  -- reler do objeto de estado.
  local function rows() return topo().rows or {} end
  local function rowPorId(sufixo)
    for i, r in ipairs(rows()) do
      if tostring(r.id):match(":" .. sufixo .. "$") then return i, r end
    end
  end
  local function valorDe(r) return r.value and r.value(game) or "" end

  -- ---------------------------------------------------------------- M2
  local ESPERADAS = {
    { "status", "STATUS" }, { "life", "LIFE" }, { "depth", "VOXEL CHARS" },
    { "side_color", "SIDE COLOR" }, { "shape", "SHAPE" },
    { "ground_shade", "GROUND SHADE" }, { "blink", "BLINK" },
    { "top_edge", "TOP EDGE" }, { "front_shape", "FRONT SHAPE" },
    { "top_dome", "TOP DOME" }, { "step_weight", "STEP WEIGHT" },
    { "breath", "BREATH" }, { "sway", "SWAY" }, { "lag", "MOTION LAG" },
  }
  local faltando, foraDeOrdem, anterior = {}, {}, 0
  for _, esperada in ipairs(ESPERADAS) do
    local i, r = rowPorId(esperada[1])
    if not i then
      faltando[#faltando + 1] = esperada[2]
    else
      if r.label ~= esperada[2] then
        faltando[#faltando + 1] = esperada[2] .. " (rotulo " .. tostring(r.label) .. ")"
      end
      if i < anterior then foraDeOrdem[#foraDeOrdem + 1] = esperada[2] end
      anterior = i
    end
  end
  nota("%d rows na tela de opcoes, %d nossas", #rows(), #ESPERADAS - #faltando)
  veredito("M2", #faltando == 0 and #foraDeOrdem == 0, string.format(
    "faltando: [%s] | fora de ordem: [%s]",
    table.concat(faltando, ", "), table.concat(foraDeOrdem, ", ")))

  -- ---------------------------------------------------------------- M3
  -- Alcancavel so com o teclado. A janela mostra quatro rows por vez
  -- (OptionRows.VISIBLE), entao chegar nas nossas custa dezenas de toques: e
  -- exatamente o que o jogador faz, e ninguem tinha testado.
  local function vaiPara(indiceAlvo)
    local m = topo()
    local limite = #rows() + 3
    for _ = 1, limite do
      if m.index == indiceAlvo then return true end
      U.tap(game, m.index < indiceAlvo and "down" or "up")
      U.wait(2)
    end
    return topo().index == indiceAlvo
  end
  local iBreath = rowPorId("breath")
  local chegou = iBreath and vaiPara(iBreath)
  local m = topo()
  local visivel = chegou and m.index > (m.scroll or 0)
    and m.index <= (m.scroll or 0) + OptionRows.VISIBLE
  veredito("M3", chegou and visivel, string.format(
    "cursor em BREATH (indice %s), scroll %s, janela de %d rows: %s",
    tostring(iBreath), tostring(m.scroll), OptionRows.VISIBLE,
    visivel and "dentro" or "FORA da janela visivel"))

  -- ---------------------------------------------------------------- M4
  -- O BUG DA v1.6.0. A numa row de leitura nao pode fechar o menu.
  local ruins = {}
  for _, id in ipairs({ "status", "life" }) do
    local i = rowPorId(id)
    if i and vaiPara(i) then
      U.tap(game, "a"); U.wait(8)
      if getmetatable(topo()) ~= OptionsMenu then
        ruins[#ruins + 1] = id .. " fechou o menu"
        -- reabre para os testes seguintes continuarem valendo
        U.tap(game, "start"); U.wait(12)
        for _ = 1, #(topo().items or {}) + 2 do
          if topo().index == alvo then break end
          U.tap(game, "down"); U.wait(3)
        end
        U.tap(game, "a"); U.wait(15)
      end
    else
      ruins[#ruins + 1] = id .. " nao alcancavel"
    end
  end
  veredito("M4", #ruins == 0, #ruins == 0
    and "A em STATUS e em LIFE deixa o menu aberto"
    or table.concat(ruins, "; "))
  if getmetatable(topo()) ~= OptionsMenu then
    nota("menu fechado e nao consegui reabrir; parando aqui"); return
  end

  -- ---------------------------------------------------------------- M5, M6
  -- Direita cicla para frente, esquerda volta, e o valor persiste no save.
  local ciclos, quebrados = 0, {}
  for _, chave in ipairs({ "breath", "sway", "lag", "front_shape", "shape" }) do
    local i = rowPorId(chave)
    if i and vaiPara(i) then
      local antes = valorDe(select(2, rowPorId(chave)))
      U.tap(game, "right"); U.wait(4)
      local depois = valorDe(select(2, rowPorId(chave)))
      U.tap(game, "left"); U.wait(4)
      local voltou = valorDe(select(2, rowPorId(chave)))
      local persistiu = game.save and game.save.options
        and game.save.options.modOptions
        and game.save.options.modOptions.voxel_characters
        and game.save.options.modOptions.voxel_characters[chave] ~= nil
      nota("  %-12s %s -> %s -> %s   persistiu=%s",
        chave, antes, depois, voltou, tostring(persistiu))
      if depois == antes then
        quebrados[#quebrados + 1] = chave .. ": direita nao mudou"
      elseif voltou ~= antes then
        quebrados[#quebrados + 1] = chave .. ": esquerda nao voltou"
      elseif not persistiu then
        quebrados[#quebrados + 1] = chave .. ": nao persistiu no save"
      else
        ciclos = ciclos + 1
      end
    else
      quebrados[#quebrados + 1] = chave .. ": nao alcancavel"
    end
  end
  veredito("M5", ciclos > 0 and #quebrados == 0, string.format(
    "%d rows ciclaram nos dois sentidos e persistiram; problemas: [%s]",
    ciclos, table.concat(quebrados, ", ")))
  veredito("M6", #quebrados == 0, "o ciclo fecha nos dois sentidos")

  -- ---------------------------------------------------------------- M7
  -- Convivencia. Outros mods anexam rows pelo mesmo hook; as nossas nao podem
  -- ter comido nem reordenado as deles.
  local outras, nossas = 0, 0
  for _, r in ipairs(rows()) do
    if tostring(r.id):match("^voxel_characters:") then nossas = nossas + 1
    else outras = outras + 1 end
  end
  nota("rows: %d nossas, %d de outros (motor e outros mods)", nossas, outras)
  veredito("M7", nossas == #ESPERADAS and outras > 0, string.format(
    "esperado %d nossas e pelo menos uma de fora", #ESPERADAS))

  -- ---------------------------------------------------------------- M8
  -- Sair do menu pelo caminho do jogador e conferir que a mudanca chegou na
  -- tela. Sem isto, tudo acima poderia ser uma tabela bonita que nao desenha.
  local iBreath2 = rowPorId("breath")
  if iBreath2 and vaiPara(iBreath2) then
    -- garante BREATH desligado, fotografa, liga no maximo, fotografa de novo
    for _ = 1, 6 do
      if valorDe(select(2, rowPorId("breath"))) == "OFF" then break end
      U.tap(game, "right"); U.wait(4)
    end
  end
  U.tap(game, "b"); U.wait(20)
  local noMundo = topo() == game.overworld
  local function foto()
    local pronto
    love.graphics.captureScreenshot(function(d) pronto = d end)
    for _ = 1, 120 do coroutine.yield(); if pronto then return pronto end end
  end
  local function difere(a, b)
    if not (a and b) then return -1 end
    local n = 0
    for yy = 0, a:getHeight() - 1, 3 do
      for xx = 0, a:getWidth() - 1, 3 do
        local r1, g1, b1 = a:getPixel(xx, yy)
        local r2, g2, b2 = b:getPixel(xx, yy)
        if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 then n = n + 1 end
      end
    end
    return n
  end
  local desligado = noMundo and foto()
  U.wait(46)
  local desligado2 = noMundo and foto()
  local base = difere(desligado, desligado2)

  -- volta ao menu e liga BREATH no maximo, tudo por tecla
  U.tap(game, "start"); U.wait(12)
  for _ = 1, #(topo().items or {}) + 2 do
    if topo().index == alvo then break end
    U.tap(game, "down"); U.wait(3)
  end
  U.tap(game, "a"); U.wait(15)
  local iB = rowPorId("breath")
  if iB then vaiPara(iB) end
  for _ = 1, 6 do
    if valorDe(select(2, rowPorId("breath"))) == "STRONG" then break end
    U.tap(game, "right"); U.wait(4)
  end
  local ligadoRotulo = valorDe(select(2, rowPorId("breath")))
  U.tap(game, "b"); U.wait(20)
  local ligado = (topo() == game.overworld) and foto()
  U.wait(46)
  local ligado2 = (topo() == game.overworld) and foto()
  local comEfeito = difere(ligado, ligado2)
  nota("pixels que mudam em 46 quadros: %d desligado, %d com BREATH %s",
    base, comEfeito, ligadoRotulo)
  veredito("M8", base >= 0 and comEfeito > base + 40,
    "mudar a opcao SO PELO MENU muda a tela")

  nota("")
  local todos = true
  for _, v in ipairs(vereditos) do
    if not v.ok then todos = false end
    nota("%-3s %s", v.nome, v.ok and "PASSOU" or "FALHOU")
  end
  nota("VEREDITO: %s", todos and "O MENU FAZ O QUE O JOGADOR ESPERA"
    or "LER ACIMA")
  U.wait(10)
end
