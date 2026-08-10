-- MENU gate: presses a real key, in the real menu, the way the
-- player presses it.
--
-- WHY IT EXISTS, and the answer is a bug that slipped through everything. On the day of
-- v1.6.0, an independent engine review found that pressing A on top of the
-- STATUS or LIFE row CLOSED the options screen. The engine resolves A,
-- left and right in the same branch, in this order (src/ui/OptionsMenu.lua:549-566):
--
--     row.activate  ->  calls
--     row.step      ->  cycles
--     otherwise, if it was A, treat as CANCEL and POP THE MENU
--
-- Our two read-only rows have `value` and nothing else, so they fall into the third
-- case. And A is the first key someone presses on a line they don't recognize,
-- which is exactly the audience for the STATUS row.
--
-- None of the 486 offline checks nor the eight pixel checks caught it, and it wasn't
-- bad luck: NONE OF THEM PRESS A KEY IN THE MENU. The offline ones call the hook directly and
-- read the rows table; the pixel ones write the option to the save and emit the
-- event. Both skip the screen that 100% of players go through.
--
-- What this gate asks:
--
--   M1 the menu opens         START, find OPTION by LABEL, A
--   M2 the rows exist         all of ours appear, in the right order
--   M3 reachable              you can reach each one using only down/up
--   M4 A doesn't close        A on a read-only row keeps the menu open
--   M5 right cycles           the label becomes the next level, and persists
--   M6 left goes back         and the cycle closes in both directions
--   M7 coexists               another mod's rows stay intact
--   M8 reaches the screen     exit the menu, and the world really changed

return function(game)
  local U = dofile("tests/drivers/util.lua")
  dofile("mods/voxel_characters/tools/ingame/erro.lua")()
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

  -- --------------------------------------------------------------- world
  local Pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")
  -- EMPTY ROOM, and the lesson came from the other gate. M8 measures a half
  -- pixel effect by comparing two frames; on an open map the day cycle, the water and the
  -- NPC wandering around make the baseline thousands of pixels and the effect
  -- sinks into the noise. REDS_HOUSE_2F has ZERO object events: the only character
  -- on screen is the player, and the baseline sits at zero.
  local mapa, x, y = Pouso.escolher(game,
    os.getenv("VC_MAP") or "REDS_HOUSE_2F",
    tonumber(os.getenv("VC_X")) or 3,
    tonumber(os.getenv("VC_Y")) or 4)
  U.teleport(game, mapa, x, y, "down")
  U.wait(60)
  if topo() ~= game.overworld then
    veredito("M1", false, "nao cheguei ao mundo"); return
  end

  -- ---------------------------------------------------------------- M1
  -- START is latched while the player is mid-step
  -- (OverworldController.lua:1186), so wait for it to settle.
  for _ = 1, 120 do
    if not (game.overworld.player and game.overworld.player.moving) then break end
    U.wait(1)
  end
  -- Open the options screen the way the player does, reusable: M8 needs to
  -- close and reopen it, and the second opening can NOT assume the same index as
  -- the first, because the START menu remembers where the cursor was
  -- (StartMenu.lua:153, game.save.startMenuIndex).
  local function abrirOpcoes()
    for _ = 1, 120 do
      if topo() == game.overworld
        and not (game.overworld.player and game.overworld.player.moving) then break end
      U.wait(1)
    end
    U.tap(game, "start"); U.wait(12)
    local inicio = topo()
    if not (inicio and inicio.items) then return nil, "o menu START nao abriu" end
    local rotulo = Strings("OPTION")
    local destino
    for i, item in ipairs(inicio.items) do
      if item.label == rotulo then destino = i break end
    end
    if not destino then return nil, "nao achei a linha OPTION" end
    for _ = 1, #inicio.items + 2 do
      if inicio.index == destino then break end
      U.tap(game, "down"); U.wait(3)
    end
    if inicio.index ~= destino then return nil, "o cursor nao chegou em OPTION" end
    U.tap(game, "a"); U.wait(15)
    if getmetatable(topo()) ~= OptionsMenu then
      return nil, "OPTION nao abriu a tela de opcoes"
    end
    return topo()
  end

  local menuAberto, porqueNao = abrirOpcoes()
  veredito("M1", menuAberto ~= nil, menuAberto
    and "START, OPTION, A: a tela de opcoes abriu" or tostring(porqueNao))
  if not menuAberto then return end

  -- Dramatic Shape SWAPS menu.rows in place on certain changes
  -- (DramaticShapeVoxelMod/main.lua:958), so never cache the array: always
  -- reread it from the state object.
  local function rows() return topo().rows or {} end
  local function rowPorId(sufixo)
    for i, r in ipairs(rows()) do
      if tostring(r.id):match(":" .. sufixo .. "$") then return i, r end
    end
  end
  -- Defensive on purpose: rowPorId returns nil when the menu is closed, and
  -- the first version of this blew up in M8 exactly like that, after leaving the
  -- menu to take a screenshot. A gate that dies partway through doesn't fail anything, it just
  -- vanishes along with the rest of the checks.
  local function valorDe(r) return (r and r.value) and r.value(game) or "" end
  local function valorDaRow(sufixo)
    local _, r = rowPorId(sufixo)
    return valorDe(r)
  end

  -- ---------------------------------------------------------------- M2
  local ESPERADAS = {
    { "status", "STATUS" }, { "life", "LIFE" },
    { "camera_preset", "CAMERA FIT" }, { "depth", "VOXEL CHARS" },
    { "side_color", "SIDE COLOR" }, { "shape", "SHAPE" },
    { "ground_shade", "GROUND SHADE" }, { "blink", "BLINK" },
    { "top_edge", "TOP EDGE" }, { "front_shape", "FRONT SHAPE" },
    { "top_dome", "TOP DOME" }, { "step_weight", "STEP WEIGHT" },
    { "breath", "BREATH" }, { "sway", "SWAY" }, { "lag", "MOTION LAG" },
    { "footfall", "FOOTFALL" }, { "part_lag", "PART LAG" },
    { "first_person", "FIRST PERSON" },
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
  -- EXTRAS ALSO COUNT. The first version only asked whether each expected row
  -- existed, so forgetting FOOTFALL in the list didn't show up here: it passed and
  -- what caught it was M7, which counts. An inventory test has to complain
  -- about both sides, otherwise it only covers what someone remembered to write.
  local nomeados = {}
  for _, e in ipairs(ESPERADAS) do nomeados[e[1]] = true end
  local extras = {}
  for _, r in ipairs(rows()) do
    local chave = tostring(r.id):match("^voxel_characters:(.+)$")
    if chave and not nomeados[chave] then extras[#extras + 1] = chave end
  end
  nota("%d rows na tela de opcoes, %d nossas", #rows(), #ESPERADAS - #faltando)
  veredito("M2", #faltando == 0 and #foraDeOrdem == 0 and #extras == 0,
    string.format("faltando: [%s] | fora de ordem: [%s] | nao esperadas: [%s]",
      table.concat(faltando, ", "), table.concat(foraDeOrdem, ", "),
      table.concat(extras, ", ")))

  -- ---------------------------------------------------------------- M3
  -- Reachable using only the keyboard. The window shows four rows at a time
  -- (OptionRows.VISIBLE), so reaching ours costs dozens of presses: that's
  -- exactly what the player does, and nobody had tested it.
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
  -- THE v1.6.0 BUG. A on a read-only row must not close the menu.
  local ruins = {}
  for _, id in ipairs({ "status", "life" }) do
    local i = rowPorId(id)
    if i and vaiPara(i) then
      U.tap(game, "a"); U.wait(8)
      if getmetatable(topo()) ~= OptionsMenu then
        ruins[#ruins + 1] = id .. " fechou o menu"
        abrirOpcoes()  -- reopens so the following checks stay valid
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
  -- Right cycles forward, left goes back, and the value persists in the save.
  local ciclos, quebrados = 0, {}
  for _, chave in ipairs({ "breath", "sway", "lag", "front_shape", "shape" }) do
    local i = rowPorId(chave)
    if i and vaiPara(i) then
      local antes = valorDaRow(chave)
      U.tap(game, "right"); U.wait(4)
      local depois = valorDaRow(chave)
      U.tap(game, "left"); U.wait(4)
      local voltou = valorDaRow(chave)
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
  -- Coexistence. Other mods append rows through the same hook; ours must not
  -- have eaten or reordered theirs.
  local outras, nossas = 0, 0
  for _, r in ipairs(rows()) do
    if tostring(r.id):match("^voxel_characters:") then nossas = nossas + 1
    else outras = outras + 1 end
  end
  nota("rows: %d nossas, %d de outros (motor e outros mods)", nossas, outras)
  veredito("M7", nossas == #ESPERADAS and outras > 0, string.format(
    "esperado %d nossas e pelo menos uma de fora", #ESPERADAS))

  -- ---------------------------------------------------------------- M8
  -- Exit the menu the way the player does and check that the change reached the
  -- screen. Without this, everything above could be a pretty table that doesn't draw.
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

  -- Sets BREATH to a given value, using only keys, and returns the label it ended on.
  local function porBreath(rotulo)
    local i = rowPorId("breath")
    if not (i and vaiPara(i)) then return nil end
    for _ = 1, 8 do
      if valorDaRow("breath") == rotulo then return rotulo end
      U.tap(game, "right"); U.wait(4)
    end
    return valorDaRow("breath")
  end

  -- EXIT ALL THE WAY TO THE WORLD, not just one B. The options screen was pushed ON TOP OF the
  -- START menu, so one B returns to START and not to the world. The first version
  -- of this measured a frame with the menu in front, thought it wasn't in the world
  -- and gave up, and the verdict came out as "couldn't put together the comparison" without saying
  -- that the problem was the number of key presses.
  local function sairParaOMundo()
    for _ = 1, 6 do
      if topo() == game.overworld then return true end
      U.tap(game, "b"); U.wait(20)
    end
    return topo() == game.overworld
  end

  -- Measures how much the screen changes with the menu CLOSED, at the current
  -- setting.
  --
  -- ENVELOPE, NOT A PAIR, and this is the second time this project has had to
  -- learn it. The first version took two photographs 46 frames apart and
  -- reported the difference. That number depends on WHERE IN THE BREATHING
  -- CYCLE the two photographs happen to land, not on how big the breathing is,
  -- so the same build measured 45, 48, 48, 56 and 59 across five runs against
  -- a threshold of 53. The gate failed three times out of five with nothing
  -- wrong: a gate that fails half the time for reasons unrelated to the code
  -- teaches people to rerun it until it is green, which is worse than no gate.
  --
  -- Sweeping a whole period and keeping the largest difference measures the
  -- AMPLITUDE, which is what the option controls, and the phase drops out.
  -- The threshold was deliberately NOT lowered to make this pass: the number
  -- was never the problem, the instrument was.
  local ENVELOPE_QUADROS = 120   -- about two seconds at 60fps, over a full cycle
  local ENVELOPE_PASSO = 12
  local function medeNoMundo()
    if not sairParaOMundo() then return -1 end
    local a = foto()
    local maior = 0
    for _ = 1, math.floor(ENVELOPE_QUADROS / ENVELOPE_PASSO) do
      U.wait(ENVELOPE_PASSO)
      local d = difere(a, foto())
      if d > maior then maior = d end
    end
    return maior
  end

  local m8ok, detalheM8 = false, "nao consegui montar a comparacao"
  if porBreath("OFF") == "OFF" then
    local base = medeNoMundo()
    if abrirOpcoes() and porBreath("STRONG") == "STRONG" then
      local ligado = medeNoMundo()
      nota("maior mudanca num periodo inteiro: %d com BREATH OFF, %d com STRONG",
        base, ligado)
      m8ok = base >= 0 and ligado > base + 40
      detalheM8 = string.format("OFF %d, STRONG %d", base, ligado)
    end
  end
  -- M8 proves the PATH, not the magnitude. It runs on the open map, where the NPC
  -- wanders and water moves, so the baseline is already high and the difference is
  -- a few percent. What measures how much the effect is worth is probe_life.lua, in a
  -- room with nobody else. The two together cover: here, that changing the menu
  -- reaches the screen; there, that what reaches it has the requested size.
  veredito("M8", m8ok, detalheM8 ..
    " (mudar a opcao SO PELO MENU tem que mudar a tela)")

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
