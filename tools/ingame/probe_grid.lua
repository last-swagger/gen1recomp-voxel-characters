-- Sonda do GRID do host: nossos personagens ganham o wireframe?
--
-- O Kim perguntou se o mod devia "se comportar de acordo" com o grid do voxel
-- mod. Antes de projetar qualquer coisa, a pergunta e se ja nao esta resolvido.
--
-- Lendo o host: o grid nao e um overlay desenhado por cima, e o PROPRIO shader
-- da cena medindo a distancia do fragmento ate o plano inteiro mais proximo, em
-- espaco de MODELO (VoxelGrid.lua:1-18). Toda malha desenhada por Voxel3D.draw
-- passa por esse shader, e a nossa passa. Entao a previsao e que o solido ja
-- receba o wireframe de graca, e que o "suporte" seja zero codigo.
--
-- Previsao nao e medicao. Isto mede.
--
--   G1 da para ler o estado    VoxelGrid.enabled() responde e set() muda
--   G2 o grid muda a tela      controle: ligar o grid tem que mudar alguma
--                              coisa, senao nada abaixo vale
--   G3 e NAO toca no personagem o delta do grid tem que ser o MESMO com o mod
--                              ligado e desligado
--
-- G3 AFIRMA O CONTRARIO DO QUE ESTE ARQUIVO PREVIA, e a inversao e o resultado.
--
-- A previsao era que o solido ganhasse o wireframe de graca, porque o grid e o
-- proprio shader da cena medindo distancia ate plano inteiro em espaco de
-- modelo, e a nossa malha passa por esse shader. Medido: 54700 amostras mudam
-- com o mod ligado e 54701 com ele desligado. O grid nao encosta na gente.
--
-- O motivo esta escrito no host, e e uma decisao e nao um esquecimento
-- (VoxelScene.lua:584-589, drawCast chama Voxel3D.seams(false)):
--
--   "Characters carry no wireframe out here, whatever the V-GRID row says. The
--    seams are what makes the WORLD read as built out of voxels, and the people
--    walking around in it are the one thing that should read as drawn instead
--    -- a grid over a 16x16 sprite lands a line every couple of display pixels
--    and turns a face into a mesh."
--
-- Ou seja: nosso mod ja se comporta certo, por heranca, e "ligar o grid nos
-- personagens" nao seria preencher uma lacuna, seria CONTRARIAR o autor do
-- host num ponto que ele pensou. Continua sendo uma opcao possivel de produto,
-- com custo declarado: as faces laterais e de topo do solido nao tem arte
-- nenhuma, e costura em cima delas realca justamente a superficie inventada.
--
-- Entao este gate deixou de perguntar "ja funciona?" e passou a proteger o
-- contrato: se um dia o wireframe comecar a aparecer nos personagens, alguem
-- mudou algo e a gente quer saber no mesmo dia..

return function(game)
  local U = dofile("tests/drivers/util.lua")
  dofile("mods/voxel_characters/tools/ingame/erro.lua")()
  io.stdout:setvbuf("line")
  if love.window and love.window.setVSync then pcall(love.window.setVSync, 0) end

  local linhas = {}
  local function nota(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    linhas[#linhas + 1] = ok and s or tostring(fmt)
    print("[grid] " .. linhas[#linhas])
    love.filesystem.write("vc_grid.txt", table.concat(linhas, "\n") .. "\n")
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
      and "O GRID PINTA O MUNDO E NAO PINTA GENTE, COMO O HOST QUER"
      or "AINDA NAO")
  end

  nota("=== sonda do grid ===")

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
    U.wait(12)
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
    local n = 0
    for y = 0, a:getHeight() - 1, 3 do
      for x = 0, a:getWidth() - 1, 3 do
        local ar, ag, ab = a:getPixel(x, y)
        local br, bg, bb = b:getPixel(x, y)
        if math.abs(ar - br) + math.abs(ag - bg) + math.abs(ab - bb) > 0.02 then
          n = n + 1
        end
      end
    end
    return n
  end

  local HOSTS = { "BATTLE_ART_VOXEL_FORK", "DRAMALESS_SHAPE", "DRAMATIC_SHAPE" }
  local lib
  for _, id in ipairs(HOSTS) do
    for _, f in ipairs({
      function() return game.mods.exports[id].lib end,
      function() return game.mods:find(id).exports.lib end,
      function() return game.mods.find(id).exports.lib end,
    }) do
      local ok, v = pcall(f)
      if ok and type(v) == "table" and v.require then lib = v break end
    end
    if lib then break end
  end
  if not lib then veredito("G1", false, "sem lib do host"); return fim() end
  local okG, VoxelGrid = pcall(lib.require, "VoxelGrid")
  if not (okG and VoxelGrid and VoxelGrid.enabled) then
    veredito("G1", false, "host sem VoxelGrid")
    return fim()
  end

  local Pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")
  local MAPA = os.getenv("VC_MAP") or "REDS_HOUSE_2F"
  local _, PX, PY = Pouso.escolher(game, MAPA, 3, 4)
  U.teleport(game, MAPA, PX, PY, "down")
  U.wait(60)
  pcall(require("src.render.Pipelines").setLevel, "voxel", 4)
  U.wait(60)

  local function grid(v)
    pcall(VoxelGrid.set, v, game)
    U.wait(18)
    local ok, e = pcall(VoxelGrid.enabled)
    return ok and e
  end

  local ligou = grid(true)
  local desligou = grid(false)
  veredito("G1", ligou == true and desligou == false,
    string.format("o estado do grid responde: ligado=%s desligado=%s",
      tostring(ligou), tostring(desligou)))

  -- Com o MOD LIGADO: quanto o grid muda a tela.
  opcao("depth", 3)
  grid(false); local semGrid = captura()
  grid(true);  local comGrid = captura()
  local dMod = difere(semGrid, comGrid)

  -- Com o MOD DESLIGADO: quanto o grid muda a tela sem o nosso solido. A
  -- diferenca entre os dois numeros e a area que o grid pinta EM CIMA DO QUE
  -- NOS DESENHAMOS. Sem este segundo termo, G3 estaria medindo o cenario.
  opcao("depth", "off")
  grid(false); local semGridSemMod = captura()
  grid(true);  local comGridSemMod = captura()
  local dSemMod = difere(semGridSemMod, comGridSemMod)
  opcao("depth", 3)

  nota("grid muda %d amostras com o mod, %d sem o mod", dMod, dSemMod)
  veredito("G2", dMod > 200,
    string.format("o grid muda a tela: %d amostras", dMod))
  -- O host suprime a costura nos personagens de proposito (drawCast chama
  -- Voxel3D.seams(false)). Entao o certo e os dois numeros baterem: o grid
  -- pinta o mundo e nao pinta gente, com ou sem o nosso solido em cena.
  local folga = math.max(200, dSemMod * 0.02)
  veredito("G3", math.abs(dMod - dSemMod) <= folga,
    string.format("o grid nao encosta no nosso solido: %d com o mod contra %d "
      .. "sem, folga %d", dMod, dSemMod, math.floor(folga)))

  grid(false)
  fim()
end
