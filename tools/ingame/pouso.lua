-- Escolhe onde o driver pode largar o jogador sem ele aparecer em cima de
-- coisa nenhuma.
--
-- O DEFEITO QUE ISTO CONSERTA. `U.teleport(game, mapa, x, y, dir)` esvazia a
-- pilha e empurra o OverworldController naquelas coordenadas SEM VALIDAR NADA
-- (tests/drivers/util.lua:85-90). Se a celula for uma placa, uma mesa, uma
-- parede ou um NPC, o jogador pousa ali e fica. O Kim viu isso nas fotos do
-- gate antes de mim: "o ash ta em cima de um lugar q nao era pra ele estar".
-- As fotos estavam certas; o driver e que estava errado.
--
-- O jogo ja sabe responder a pergunta. Nenhuma destas checagens foi inventada
-- aqui, todas sao o que o proprio motor consulta:
--
--   map:inBounds(cx, cy)              Map.lua:216   dentro do mapa
--   map:isWalkableCell(cx, cy)        Map.lua:220   o mesmo teste que Collision usa
--   map:signAtCell(cx, cy)            Map.lua:287   placa. era esta a da foto
--   map:warpAtCell(cx, cy)            Map.lua:283   porta registrada
--   map:isWarpTileCell(cx, cy)        Map.lua:261   tile que dispara a porta
--   map:warpPadOrHoleAt(cx, cy)       Map.lua:268   plataforma de teleporte, buraco
--   overworld:npcAtCell(cx, cy)       OverworldController.lua:1721   quem esta la
--
-- Warp e buraco ficam de fora porque parar em cima deles troca de mapa no
-- primeiro quadro e o driver perde o mapa que pediu. `npcAtCell` e melhor que
-- varrer `npcs` na mao: ele tambem pega o NPC que esta ENTRANDO na celula
-- (targetX/targetY), que e meio passo de distancia de virar uma sobreposicao.
--
-- Vinte e poucos drivers do proprio projeto fazem alguma versao disto, cada um
-- a sua maneira, e nenhum deles cobre os sete testes. Este cobre.

local Pouso = {}

-- Aneis crescentes em torno da celula pedida (distancia de Chebyshev). A busca
-- devolve a primeira celula boa, entao ela e sempre a mais proxima do que o
-- chamador queria: se a celula pedida ja presta, e ela que sai, e nada muda
-- onde ja estava certo.
local function anel(raio)
  if raio == 0 then return { { 0, 0 } } end
  local pontos = {}
  for d = -raio, raio do
    pontos[#pontos + 1] = { d, -raio }
    pontos[#pontos + 1] = { d, raio }
  end
  for d = -raio + 1, raio - 1 do
    pontos[#pontos + 1] = { -raio, d }
    pontos[#pontos + 1] = { raio, d }
  end
  return pontos
end

-- Cada metodo em pcall: um mapa de uma versao do jogo que nao tenha um deles
-- nao pode derrubar o driver inteiro. Ausencia conta como "nao bloqueia", que
-- e o lado seguro: no pior caso a gente volta ao comportamento antigo em vez
-- de nao pousar em lugar nenhum.
local function chama(obj, metodo, ...)
  if type(obj) ~= "table" or type(obj[metodo]) ~= "function" then return nil end
  local ok, r = pcall(obj[metodo], obj, ...)
  return ok and r or nil
end

-- Por que esta celula NAO serve, ou nil quando serve.
function Pouso.recusa(map, ow, cx, cy)
  if not map then return "sem mapa" end
  if chama(map, "inBounds", cx, cy) == false then return "fora do mapa" end
  if chama(map, "isWalkableCell", cx, cy) ~= true then return "nao da para andar" end
  if chama(map, "signAtCell", cx, cy) then return "placa" end
  if chama(map, "warpAtCell", cx, cy) then return "porta" end
  if chama(map, "isWarpTileCell", cx, cy) then return "tile de porta" end
  if chama(map, "warpPadOrHoleAt", cx, cy) then return "plataforma ou buraco" end
  if ow and chama(ow, "npcAtCell", cx, cy) then return "tem alguem" end
  return nil
end

-- Devolve mapa, x, y, raio. `raio` e quantas celulas a busca teve que andar
-- (0 = a celula pedida servia) ou nil quando nao achou nada perto.
--
-- Carrega o mapa DIRETO com MapLoader, sem teleportar antes: e a mesma chamada
-- que OverworldController:setMap faz (OverworldController.lua:320) e o
-- resultado fica em cache, entao o teleporte seguinte reaproveita. A primeira
-- versao disto teleportava para o lugar ruim so para poder ler o mapa e depois
-- teleportava de novo, o que aparecia na tela como um piscar.
function Pouso.escolher(game, mapa, x, y, raioMax)
  local ok, MapLoader = pcall(require, "src.world.MapLoader")
  if not (ok and MapLoader and MapLoader.load) then return mapa, x, y, 0 end
  local okMap, map = pcall(MapLoader.load, game.data, mapa)
  if not (okMap and map) then return mapa, x, y, 0 end

  -- O overworld so serve para consultar NPC, e so quando ja estamos NESTE
  -- mapa; num mapa diferente a lista de NPCs e de outro lugar e responderia
  -- sobre gente que nao esta la.
  local ow = game.overworld
  if not (ow and ow.map and ow.map.id == mapa) then ow = nil end

  for raio = 0, (raioMax or 8) do
    for _, p in ipairs(anel(raio)) do
      local cx, cy = x + p[1], y + p[2]
      if not Pouso.recusa(map, ow, cx, cy) then return mapa, cx, cy, raio end
    end
  end
  -- Nenhuma celula boa perto. Devolve o pedido original e avisa por nil:
  -- entregar o problema visivel e melhor que escondê-lo num lugar aleatorio.
  return mapa, x, y, nil
end

return Pouso
