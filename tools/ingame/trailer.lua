-- TRAILER, gravado dentro do proprio jogo.
--
-- Uma lista de PLANOS: cada um escolhe mapa, posicao, degrau de camera, opcoes
-- do mod, se o personagem anda, quanto dura e o que a legenda diz. O driver
-- executa a lista e grava a sequencia inteira numerada; o trailer.sh monta.
--
-- POR QUE DENTRO DO JOGO, e nao capturando tela por fora: o degrau de camera,
-- a hora do dia, a posicao e as opcoes viram DADO em vez de gesto. Um trailer
-- gravado a mao nao se refaz quando uma feature muda; este se refaz rodando de
-- novo, e e por isso que ele vale como ferramenta e nao so como video.
--
-- O ROTEIRO conta a historia do mod na ordem em que ela aconteceu: o mundo
-- deita, os personagens ganham corpo, o corpo ganha vida, e no fim a camera
-- entra na cabeca do jogador. Cada plano existe para mostrar UMA coisa, porque
-- plano que mostra duas nao mostra nenhuma.
--
-- Uso:
--   POKEPORT_VERSION=blue POKEPORT_DRIVER=.../trailer.lua love .
--   VC_TRAILER_SEGUNDOS=12  corta tudo proporcionalmente, para testar rapido

return function(game)
  local U = dofile("tests/drivers/util.lua")
  io.stdout:setvbuf("line")
  if love.window and love.window.setVSync then pcall(love.window.setVSync, 0) end

  local function log(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    print("[trailer] " .. (ok and s or tostring(fmt)))
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
    pcall(function()
      game.mods.events:emit("mod.options_changed",
        { mod = "voxel_characters", key = chave, value = valor })
    end)
  end

  local lib
  for _, f in ipairs({
    function() return game.mods.exports.DRAMATIC_SHAPE.lib end,
    function() return game.mods:find("DRAMATIC_SHAPE").exports.lib end,
    function() return game.mods.find("DRAMATIC_SHAPE").exports.lib end,
  }) do
    local ok, v = pcall(f)
    if ok and type(v) == "table" and v.require then lib = v break end
  end
  if not lib then log("sem a lib do host, nao da para dirigir a camera"); return end
  local okVS, VoxelState = pcall(lib.require, "VoxelState")
  if not okVS then log("host sem VoxelState"); return end
  local Pipelines = require("src.render.Pipelines")
  local FPLEVEL = VoxelState.FP_LEVEL or 6

  -- Os degraus por NOME, para o roteiro nao carregar numero magico. A escada
  -- do host e ANGLES_DEG = {0, 35, 15, 35, 50, 75, 75, 75}, indexada por
  -- nivel + 1, entao o nivel 0 e o jogo plano e o 5 e o mais em pe.
  local DEGRAU = { plano = 0, baixo = 2, medio = 3, alto = 4, empe = 5,
                   primeira = FPLEVEL }

  local BASE = {
    depth = 3, shape = "slab", side_color = "body", ground_shade = "off",
    blink = "on", top_edge = "on", front_shape = "off", top_dome = "off",
    step_weight = "off", breath = 0.010, sway = "off", lag = "off",
    footfall = "off", first_person = "card",
  }

  -- O ROTEIRO. Editar aqui e editar o trailer.
  local PLANOS = {
    { mapa = "PALLET_TOWN", x = 5, y = 6, dir = "down", degrau = "plano",
      seg = 4, legenda = "Pokemon Red, como ele sempre foi" },
    { mapa = "PALLET_TOWN", x = 5, y = 6, dir = "down", degrau = "medio",
      seg = 5, legenda = "O Dramatic Shape deita o mundo" },
    { mapa = "PALLET_TOWN", x = 5, y = 6, dir = "down", degrau = "alto",
      seg = 5, legenda = "Voxel Characters da corpo a quem anda nele" },
    { mapa = "VIRIDIAN_CITY", x = 17, y = 17, dir = "down", degrau = "alto",
      anda = true, seg = 6, legenda = "Uma cidade inteira, sem card plano" },
    { mapa = "CERULEAN_POKECENTER", x = 3, y = 4, dir = "up", degrau = "medio",
      seg = 5, opcoes = { breath = 0.035 },
      legenda = "Eles respiram, cada um no seu ritmo" },
    { mapa = "CERULEAN_POKECENTER", x = 3, y = 4, dir = "up", degrau = "empe",
      seg = 4, opcoes = { blink = "on" }, legenda = "E piscam" },
    { mapa = "ROUTE_1", x = 10, y = 20, dir = "down", degrau = "alto",
      anda = true, seg = 6, opcoes = { footfall = 0.7, lag = 0.6 },
      legenda = "O passo tem peso, e o corpo demora a acompanhar" },
    { mapa = "VIRIDIAN_CITY", x = 17, y = 17, dir = "down", degrau = "empe",
      seg = 4, opcoes = { front_shape = 0.17, top_dome = 0.15 },
      legenda = "Sombreamento que sugere volume sem inventar geometria" },
    { mapa = "CERULEAN_POKECENTER", x = 3, y = 4, dir = "right",
      degrau = "primeira", seg = 6, opcoes = { first_person = "solid" },
      legenda = "E agora tambem em primeira pessoa" },
    { mapa = "PALLET_TOWN", x = 5, y = 6, dir = "down", degrau = "alto",
      seg = 4, legenda = "Voxel Characters" },
  }

  -- Escala o roteiro inteiro quando se quer so conferir o encanamento.
  local ALVO = tonumber(os.getenv("VC_TRAILER_SEGUNDOS") or "")
  if ALVO then
    local soma = 0
    for _, p in ipairs(PLANOS) do soma = soma + p.seg end
    for _, p in ipairs(PLANOS) do
      p.seg = math.max(1, math.floor(p.seg * ALVO / soma + 0.5))
    end
  end

  -- 30 quadros por segundo de video, capturando um quadro de jogo sim outro
  -- nao. Trinta chega para leitura de movimento e corta pela metade o disco e
  -- o tempo de montagem, que a 1500 arquivos deixa de ser detalhe.
  local PASSO, FPS = 2, 30

  local legenda, legendaAlpha = nil, 0
  local fonte = love.graphics.newFont(20)
  local desenhoOriginal = love.draw
  love.draw = function()
    desenhoOriginal()
    if not legenda or legendaAlpha <= 0 then return end
    local w, h = love.graphics.getDimensions()
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setFont(fonte)
    local tw = fonte:getWidth(legenda)
    local x, y = (w - tw) / 2, h - 86
    -- Terco inferior, sem caixa: caixa preta num jogo de Game Boy le como
    -- interface do jogo e nao como legenda de video. Sombra resolve leitura
    -- sobre qualquer fundo sem competir com a arte.
    love.graphics.setColor(0, 0, 0, 0.75 * legendaAlpha)
    love.graphics.print(legenda, x + 2, y + 2)
    love.graphics.setColor(1, 1, 1, legendaAlpha)
    love.graphics.print(legenda, x, y)
    love.graphics.pop()
  end

  local Pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")
  local n = 0
  local cortes = {}

  for indice, p in ipairs(PLANOS) do
    for k, v in pairs(BASE) do opcao(k, v) end
    for k, v in pairs(p.opcoes or {}) do opcao(k, v) end

    pcall(Pipelines.setLevel, "voxel", DEGRAU[p.degrau] or 4)
    local _, px, py = Pouso.escolher(game, p.mapa, p.x, p.y)
    U.teleport(game, p.mapa, px, py, p.dir)
    -- Assentar antes de gravar: o degrau faz tween, a malha reconstroi e o
    -- teleporte tem um quadro de mundo velho. Gravar por cima disso poe um
    -- salto no comeco de cada plano, e o corte ja e o salto.
    U.wait(70)

    local quadros = p.seg * FPS
    local inicio = n + 1
    legenda = p.legenda
    for i = 1, quadros do
      -- A legenda entra e sai dentro do plano. Aparecer de uma vez junto com o
      -- corte faz o olho ler as duas coisas ao mesmo tempo e nao ler nenhuma.
      local t = i / quadros
      legendaAlpha = math.min(1, math.min(t, 1 - t) * 6)
      if p.anda then
        local dir = p.dir == "down" and "down" or p.dir
        table.insert(game.input.pressQueue, dir)
        game.input.state[dir] = true
      end
      n = n + 1
      love.graphics.captureScreenshot(string.format("vc_trailer_%05d.png", n))
      for _ = 1, PASSO do coroutine.yield() end
    end
    if p.anda then
      for _, d in ipairs({ "up", "down", "left", "right" }) do
        game.input.state[d] = false
      end
    end
    legendaAlpha = 0
    cortes[#cortes + 1] = string.format("%d:%d:%s", inicio, n, p.degrau)
    log("plano %d/%d  %-22s %-9s %ds  quadros %d a %d",
        indice, #PLANOS, p.mapa, p.degrau, p.seg, inicio, n)
  end

  legenda = nil
  love.draw = desenhoOriginal
  log("cortes: %s", table.concat(cortes, " "))
  log("fim, %d quadros a %d fps, %.1f s", n, FPS, n / FPS)
end
