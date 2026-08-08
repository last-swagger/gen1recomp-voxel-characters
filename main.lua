-- Voxel Characters: personagens como slabs de pixels, sem invadir o Voxel Mod.
--
-- O Dramatic Shape desenha os personagens como cards planos. Isso e
-- uma escolha deliberada dele; este mod so troca a funcao publica que ja e
-- capturada por campo (`SpriteBillboards.mesh`) quando o jogador escolhe uma
-- espessura. A sombra e o fantasma continuam no alias original.
--
-- NAO PATCHEIE `shadowQuad`. Isso nao e economia, e requisito. A silhueta de
-- oclusao do jogador (`VoxelScene.drawGhost`) desenha essa malha com o teste
-- de profundidade INVERTIDO por `Voxel3D.beginGhost`, e o autor do Dramatic
-- Shape documenta o porque em VoxelScene.lua:390-396: "a mesh carrying both
-- front and back faces would read its own back faces as 'behind something'
-- and repaint the figure on open ground, occluded or not". Nosso slab tem
-- exatamente front e back. Trocar o shadowQuad por ele pinta o jogador como
-- fantasma em campo aberto e ainda borra em manchas por duplo blend.
--
-- O preco de manter o card plano no passe de sol e a franja de auto-sombra
-- nas faces laterais e de fundo (README, secao "Sombra do slab"). E o lado
-- certo do trade: franja sutil contra jogador repintado na tela inteira.

local mod = ...

local Semver = require("src.mods.Semver")
local Assets = require("src.render.Assets")

-- This id list is hand-maintained because the mod API only offers
-- mod.find(id); there is no way to enumerate every loaded mod, so a host's
-- id has to be known and asked for by name before its capability can be
-- probed at all. That is the one thing here that still needs manual upkeep
-- when a new lineage of the host appears. Once a host answers to one of
-- these ids, acceptance is decided entirely by capability (see probeHost
-- below), never by which id it used or what version it reports. List order
-- only breaks ties when more than one of these hosts is installed at once;
-- it is not a ranking of the hosts.
local HOSTS = {
  {
    id = "BATTLE_ART_VOXEL_FORK",
    name = "Battle Art Voxel Fork",
    supported = ">=1.7.0 <2.0.0",
  },
  {
    id = "DRAMALESS_SHAPE",
    name = "Dramaless Shape Voxel Mod",
    supported = ">=1.5.0 <2.0.0",
  },
  {
    id = "DRAMATIC_SHAPE",
    name = "Dramatic Shape",
    supported = ">=1.5.0 <2.0.0",
  },
}
local KEY = "depth"
local SIDE_COLOR_KEY = "side_color"
local SHAPE_KEY = "shape"
local GROUND_SHADE_KEY = "ground_shade"
local BLINK_KEY = "blink"
local TOP_EDGE_KEY = "top_edge"
local VALUES = { "off", 1, 2, 3, 5, 10 }
local LABELS = { "OFF", "1", "2", "3", "5", "10" }
local SIDE_COLOR_VALUES = { "body", "outline" }
local SIDE_COLOR_LABELS = { "BODY", "OUTLINE" }
local SHAPE_VALUES = { "slab", "carved", "carved_plus" }
local SHAPE_LABELS = { "SLAB", "CARVED", "CARVED+" }
local GROUND_SHADE_VALUES = { "off", "on" }
local GROUND_SHADE_LABELS = { "OFF", "ON" }
local BLINK_VALUES = { "off", "on" }
local BLINK_LABELS = { "OFF", "ON" }
local TOP_EDGE_VALUES = { "off", "on" }
local TOP_EDGE_LABELS = { "OFF", "ON" }
local DEFAULT_DEPTH = 3
local DEFAULT_INDEX = 4  -- posicao de 3 em VALUES
local DEFAULT_SIDE_COLOR = "body"
local DEFAULT_SIDE_COLOR_INDEX = 1
local DEFAULT_SHAPE = "slab"
local DEFAULT_SHAPE_INDEX = 1
local DEFAULT_GROUND_SHADE = "off"
local DEFAULT_GROUND_SHADE_INDEX = 1
local DEFAULT_BLINK = "off"
local DEFAULT_BLINK_INDEX = 1
-- DECISAO v1.4.2: OFF nao e neutro. Com SIDE COLOR: BODY, a face de topo da
-- linha mais alta pode buscar a cor do corpo abaixo e pintar uma tampa clara
-- acima do contorno escuro, como no bone do Red. TOP EDGE ligado por padrao
-- nao adiciona efeito: remove esse defeito de leitura e preserva uma quina
-- escura ajustavel para quem quiser voltar ao host shade puro.
local DEFAULT_TOP_EDGE = "on"
local DEFAULT_TOP_EDGE_INDEX = 2
-- DECISAO: a luz do Dramatic Shape vem do sudeste. Frente e topo ficam
-- claros, tras e baixo escurecem por virarem contra a luz, e as laterais
-- usam um meio-termo para o slab ler como volume sem depender de sombra real.
-- A frente segue Voxel3D.FACE_SHADE.front = 0.90, nao 1.00. As laterais ficam
-- simetricas em 0.78 de proposito: o host resolve o frame antes de chamar
-- SpriteBillboards.mesh(def, frame) e aplica o mirror depois na matriz
-- (VoxelScene.lua:234-241, 287-295). Como o shade ja vem assado no vertice,
-- valores diferentes para leste/oeste trocariam de lado em folhas espelhadas.
local OBJ_SHADE = { front = 0.90, back = 0.68, side = 0.78, top = 1.0, bottom = 0.55 }
local TOP_EDGE_SHADE = 0.82
-- Faces SLAB expostas ficam no limite real do pixel. O inset antigo escondia
-- z-fighting entre faces internas que agora nao sao mais emitidas.
local SIDE_INSET = 0
local RUN_UV_INSET = 0.05
local PITCH_BUCKET = math.pi / 180
local MAX_MESHES = 64
-- DECISAO v1.4.2, pente fino (item 1): STATUS decide por PROPORCAO numa
-- janela deslizante dos ultimos DRAW_WINDOW_SIZE resultados de desenho, nao
-- por sequencia ininterrupta. Uma contagem de falhas SEGUIDAS e derrotavel
-- por intercalacao: se o sprite do jogador desenha bem a cada quadro
-- enquanto NPCs de fonte quebrada falham intercalados na mesma tela, todo
-- `ok` do jogador zera a sequencia antes dela chegar ao limite, e o STATUS
-- fica preso em ACTIVE pra sempre mesmo com a maioria dos personagens
-- caindo pra card plano todo quadro. Escala quando METADE OU MAIS da
-- janela e falha; uma folha ruim isolada entre varias boas nunca chega
-- perto disso (na pior distribuicao dentro da janela, 1 folha ruim a cada
-- 4 boas ocupa no maximo 2 dos 8 slots), mas alternancia estrita bom/ruim
-- (metade da tela falhando) escala.
local DRAW_WINDOW_SIZE = 8
local AO_STRENGTH = 2.4
local AO_GROUND = 0.12 * AO_STRENGTH
local AO_RISE = 6
-- DECISAO: quatro pixels cobre os contornos grossos de sprites Gen 1 sem
-- deixar uma busca em arte customizada atravessar para outra parte do corpo.
local BODY_SEARCH_LIMIT = 4
local LUMA_EPSILON = 0.00001
local CARVED_PLUS_RECESS_STEPS = 2
-- DECISAO v1.4.2: a janela de varredura do poseOffset. O passo medido no
-- red.png e de uma linha; dy vai a 3 para folhas de arte customizada com um
-- passo mais largo, dx a 2 porque nao ha relato de deslocamento horizontal e
-- uma janela maior so custaria O(cell^2) por candidato extra sem motivo.
local POSE_OFFSET_DX_RANGE = 2
local POSE_OFFSET_DY_RANGE = 3
local BLINK_CLOSED_SECONDS = 0.12

local EYE_MARKS = {
  agatha = { { 5, 7 }, { 6, 7 }, { 9, 7 }, { 10, 7 } },
  balding_guy = { { 6, 7 }, { 9, 7 } },
  beauty = { { 6, 7 }, { 9, 7 }, { 6, 8 }, { 9, 8 } },
  biker = { { 5, 6 }, { 6, 7 }, { 9, 7 }, { 10, 6 } },
  bird = { { 6, 7 }, { 9, 7 } },
  blue = { { 6, 7 }, { 9, 7 } },
  brunette_girl = { { 6, 7 }, { 9, 7 }, { 6, 8 }, { 9, 8 } },
  bruno = { { 5, 7 }, { 6, 7 }, { 9, 7 }, { 10, 7 } },
  captain = { { 6, 7 }, { 9, 7 } },
  channeler = { { 5, 7 }, { 6, 7 }, { 9, 7 }, { 10, 7 } },
  clerk = { { 5, 5 }, { 6, 5 }, { 9, 5 }, { 10, 5 } },
  cook = { { 6, 7 }, { 9, 7 } },
  cooltrainer_f = { { 6, 7 }, { 9, 7 }, { 6, 8 }, { 9, 8 } },
  cooltrainer_m = { { 6, 7 }, { 9, 7 } },
  daisy = { { 6, 7 }, { 9, 7 }, { 6, 8 }, { 9, 8 } },
  fairy = { { 5, 7 }, { 10, 7 } },
  fisher = { { 5, 5 }, { 6, 5 }, { 9, 5 }, { 10, 5 } },
  fishing_guru = { { 6, 7 }, { 9, 7 } },
  gambler = { { 6, 6 }, { 9, 6 } },
  gameboy_kid = { { 6, 7 }, { 9, 7 } },
  gentleman = { { 6, 7 }, { 9, 7 } },
  giovanni = { { 5, 6 }, { 6, 6 }, { 9, 6 }, { 10, 6 }, { 6, 7 }, { 9, 7 } },
  girl = { { 6, 6 }, { 9, 6 }, { 6, 7 }, { 9, 7 } },
  gramps = { { 5, 5 }, { 6, 5 }, { 9, 5 }, { 10, 5 } },
  granny = { { 5, 5 }, { 6, 5 }, { 9, 5 }, { 10, 5 } },
  guard = { { 6, 7 }, { 9, 7 } },
  gym_guide = { { 5, 6 }, { 6, 6 }, { 9, 6 }, { 10, 6 } },
  hiker = { { 6, 5 }, { 9, 5 } },
  koga = { { 5, 6 }, { 6, 6 }, { 9, 6 }, { 10, 6 }, { 6, 7 }, { 9, 7 } },
  lance = { { 6, 7 }, { 9, 7 } },
  link_receptionist = { { 6, 7 }, { 9, 7 }, { 6, 8 }, { 9, 8 } },
  little_boy = { { 6, 8 }, { 9, 8 }, { 6, 9 }, { 9, 9 } },
  little_girl = { { 6, 8 }, { 9, 8 }, { 6, 9 }, { 9, 9 } },
  lorelei = { { 5, 7 }, { 6, 7 }, { 9, 7 }, { 10, 7 } },
  middle_aged_man = { { 6, 6 }, { 9, 6 } },
  middle_aged_woman = { { 6, 6 }, { 9, 6 }, { 6, 7 }, { 9, 7 } },
  mom = { { 6, 7 }, { 9, 7 }, { 6, 8 }, { 9, 8 } },
  mr_fuji = { { 6, 7 }, { 9, 7 } },
  nurse = { { 6, 6 }, { 9, 6 }, { 6, 7 }, { 9, 7 } },
  oak = { { 6, 6 }, { 9, 6 }, { 6, 7 }, { 9, 7 } },
  red = { { 6, 7 }, { 9, 7 } },
  red_bike = { { 6, 6 }, { 9, 6 } },
  rocker = { { 6, 6 }, { 9, 6 } },
  rocket = { { 6, 7 }, { 9, 7 } },
  safari_zone_worker = { { 6, 7 }, { 9, 7 } },
  sailor = { { 5, 6 }, { 6, 7 }, { 9, 7 }, { 10, 6 } },
  scientist = { { 5, 5 }, { 6, 5 }, { 9, 5 }, { 10, 5 } },
  seel = { { 6, 6 }, { 9, 6 }, { 6, 7 }, { 9, 7 } },
  silph_president = { { 5, 3 }, { 6, 3 }, { 9, 3 }, { 10, 3 } },
  silph_worker_f = { { 6, 6 }, { 9, 6 }, { 6, 7 }, { 9, 7 } },
  silph_worker_m = { { 5, 7 }, { 6, 7 }, { 9, 7 }, { 10, 7 } },
  super_nerd = { { 6, 7 }, { 9, 7 } },
  swimmer = { { 5, 9 }, { 10, 9 } },
  waiter = { { 6, 7 }, { 9, 7 } },
  warden = { { 5, 3 }, { 6, 3 }, { 9, 3 }, { 10, 3 } },
  youngster = { { 6, 7 }, { 9, 7 } },
}

local EYE_SIDE_MARKS = {
  agatha = { { 5, 7 } },
  balding_guy = { { 5, 7 } },
  beauty = { { 5, 7 }, { 5, 8 } },
  biker = { { 6, 7 } },
  blue = { { 5, 7 } },
  brunette_girl = { { 5, 7 }, { 5, 8 } },
  bruno = { { 5, 6 } },
  captain = { { 5, 7 } },
  channeler = { { 5, 7 } },
  clerk = { { 6, 6 } },
  cook = { { 5, 7 } },
  cooltrainer_f = { { 4, 7 } },
  cooltrainer_m = { { 5, 7 } },
  daisy = { { 5, 6 }, { 5, 7 } },
  fishing_guru = { { 5, 7 } },
  gambler = { { 5, 6 } },
  gameboy_kid = { { 5, 7 } },
  gentleman = { { 5, 7 } },
  giovanni = { { 5, 8 } },
  girl = { { 5, 6 }, { 5, 7 } },
  gramps = { { 5, 7 } },
  guard = { { 5, 7 } },
  hiker = { { 5, 5 } },
  koga = { { 5, 7 } },
  lance = { { 5, 7 } },
  link_receptionist = { { 5, 6 }, { 5, 7 } },
  little_boy = { { 5, 8 }, { 5, 9 } },
  little_girl = { { 5, 8 }, { 5, 9 } },
  lorelei = { { 5, 6 } },
  middle_aged_man = { { 5, 6 } },
  middle_aged_woman = { { 5, 6 }, { 5, 7 } },
  mom = { { 5, 7 } },
  mr_fuji = { { 4, 7 } },
  nurse = { { 5, 6 }, { 5, 7 } },
  oak = { { 5, 7 } },
  red = { { 5, 7 } },
  red_bike = { { 6, 6 } },
  rocker = { { 5, 7 } },
  rocket = { { 5, 7 } },
  safari_zone_worker = { { 5, 7 } },
  sailor = { { 5, 6 } },
  scientist = { { 5, 7 } },
  silph_president = { { 6, 4 } },
  silph_worker_f = { { 5, 7 } },
  silph_worker_m = { { 5, 7 } },
  super_nerd = { { 5, 7 } },
  swimmer = { { 5, 10 } },
  waiter = { { 5, 7 } },
  warden = { { 5, 3 } },
  youngster = { { 5, 7 } },
}

mod.options:define({
  {
    key = KEY,
    type = "choice",
    label = "VOXEL CHARS",
    choices = {
      { "OFF", "off" }, { "1", 1 }, { "2", 2 },
      { "3", 3 }, { "5", 5 }, { "10", 10 },
    },
    default = 3,
    help = "Extrudes overworld character sprites. Depth 1-5 stays inside the voxel pull budget; 10 may clip into walls.",
  },
  {
    key = SIDE_COLOR_KEY,
    type = "choice",
    label = "SIDE COLOR",
    choices = {
      { "BODY", "body" }, { "OUTLINE", "outline" },
    },
    default = DEFAULT_SIDE_COLOR,
    help = "Colors new side, top, and bottom faces from body pixels or keeps the original outline pixels.",
  },
  {
    key = SHAPE_KEY,
    type = "choice",
    label = "SHAPE",
    choices = {
      { "SLAB", "slab" }, { "CARVED", "carved" },
      { "CARVED+", "carved_plus" },
    },
    default = DEFAULT_SHAPE,
    help = "SLAB keeps the v1.1.0 extrusion. CARVED builds visual-hull volume from three views. CARVED+ adds tone relief.",
  },
  {
    key = GROUND_SHADE_KEY,
    type = "choice",
    label = "GROUND SHADE",
    choices = {
      { "OFF", "off" }, { "ON", "on" },
    },
    default = DEFAULT_GROUND_SHADE,
    help = "Adds the host-style contact shade to the lowest six pixels of the solid character mesh.",
  },
  {
    key = BLINK_KEY,
    type = "choice",
    label = "BLINK",
    choices = {
      { "OFF", "off" }, { "ON", "on" },
    },
    default = DEFAULT_BLINK,
    help = "Animates front-facing overworld eyes by swapping their UVs to nearby skin texels.",
  },
  {
    key = TOP_EDGE_KEY,
    type = "choice",
    label = "TOP EDGE",
    choices = {
      { "OFF", "off" }, { "ON", "on" },
    },
    default = DEFAULT_TOP_EDGE,
    help = "Darkens only exposed SLAB top faces for a false top-down edge.",
  },
})

local SpriteBillboards, Voxel3D, ImageCache
local VoxelState, FirstPerson, VoxelScene
local originalMesh
local meshes, masks = {}, {}
local meshOrder = {}
local depthValue
local sideColorValue
local shapeValue
local groundShadeValue
local blinkValue
local topEdgeValue
local optionsRegistered = false
local meshBlink = setmetatable({}, { __mode = "k" })
local blinkVertexWarned = false
-- v1.4.2, pente fino: `patch()` monta tudo em locais e so faz commit destas
-- upvalues (SpriteBillboards e as outras, installedMesh, `patched`) depois
-- que TODAS as escritas arriscadas em cima da tabela do host tiverem
-- sucesso. Um host cuja tabela recusa escrita (__newindex congelado) faz
-- pcall(patch, host) segurar o erro sem nenhuma upvalue de modulo ter sido
-- tocada; sem isso, `SpriteBillboards` ficava setada sozinha e o STATUS
-- lia REPLACED (nenhuma outra funcao "roubou" o mesh; simplesmente a nossa
-- nunca chegou a ser instalada) em vez de refletir que o patch nao
-- completou. `statusValue` e `registerOptionsRows` checam `patched`, nunca
-- `SpriteBillboards ~= nil`.
local patched = false
-- v1.4.2, TwoTracks: a funcao que ESTE mod instalou em SpriteBillboards.mesh,
-- guardada para a row de STATUS detectar se outro mod substituiu depois
-- (REPLACED). warnChainedMesh so pega quem patcheia ANTES da gente.
local installedMesh
-- v1.4.2, TwoTracks: existem cinco caminhos que devolvem o card original em
-- silencio (DEPTH: OFF, primeira pessoa, mascara que falha, malha que falha,
-- excecao no wrapper mais externo) e sao indistinguiveis entre si e de "o
-- mod nunca patcheou nada". Estas variaveis guardam o resultado do ULTIMO
-- desenho para a row de STATUS reportar; sao so atribuicao, custo zero por
-- quadro.
local lastDrawResult = "ok"
-- Janela deslizante: drawWindow[i] guarda o TIPO de falha (mask_failed,
-- build_failed ou exception) do i-esimo resultado mais recente (modulo
-- DRAW_WINDOW_SIZE), ou nil quando foi sucesso. drawWindowFailures e
-- drawWindowKindCounts sao mantidos incrementalmente (sem varrer o array a
-- cada leitura de STATUS). v1.4.2, pente fino (item 2): o rotulo de erro
-- do STATUS usa a causa DOMINANTE da janela (drawWindowKindCounts), nao a
-- mais recente: sete falhas de mascara e uma excecao isolada, mais
-- recente, numa folha diferente, tem que mostrar MASK ERROR, nao DRAW
-- ERROR. O rotulo e o produto desta row.
local drawWindow = {}
local drawWindowPos = 0
local drawWindowFailures = 0
local drawWindowKindCounts = {}
local warnedDrawCauses = {}
local warnedReplacedMesh = false
-- Motivo de cada falha de malha cacheada, para uma folha ruim que ja falhou
-- uma vez continuar entrando na janela (e continuar logavel, ainda que so
-- uma vez) em toda chamada seguinte, nao so na primeira: meshes[key] ==
-- false so guarda "falhou", nao guarda por que.
local meshFailureReasons = {}

local function indexOf(value)
  for i, v in ipairs(VALUES) do
    if v == value then return i end
  end
  return DEFAULT_INDEX
end

local function sideColorIndexOf(value)
  for i, v in ipairs(SIDE_COLOR_VALUES) do
    if v == value then return i end
  end
  return DEFAULT_SIDE_COLOR_INDEX
end

local function shapeIndexOf(value)
  for i, v in ipairs(SHAPE_VALUES) do
    if v == value then return i end
  end
  return DEFAULT_SHAPE_INDEX
end

local function groundShadeIndexOf(value)
  for i, v in ipairs(GROUND_SHADE_VALUES) do
    if v == value then return i end
  end
  return DEFAULT_GROUND_SHADE_INDEX
end

local function blinkIndexOf(value)
  for i, v in ipairs(BLINK_VALUES) do
    if v == value then return i end
  end
  return DEFAULT_BLINK_INDEX
end

local function topEdgeIndexOf(value)
  for i, v in ipairs(TOP_EDGE_VALUES) do
    if v == value then return i end
  end
  return DEFAULT_TOP_EDGE_INDEX
end

local function readDepth()
  local ok, value = pcall(mod.options.get, mod.options, KEY)
  if ok then return VALUES[indexOf(value)] end
  return DEFAULT_DEPTH
end

local function readSideColor()
  local ok, value = pcall(mod.options.get, mod.options, SIDE_COLOR_KEY)
  if ok then return SIDE_COLOR_VALUES[sideColorIndexOf(value)] end
  return DEFAULT_SIDE_COLOR
end

local function readShape()
  local ok, value = pcall(mod.options.get, mod.options, SHAPE_KEY)
  if ok then return SHAPE_VALUES[shapeIndexOf(value)] end
  return DEFAULT_SHAPE
end

local function readGroundShade()
  local ok, value = pcall(mod.options.get, mod.options, GROUND_SHADE_KEY)
  if ok then return GROUND_SHADE_VALUES[groundShadeIndexOf(value)] end
  return DEFAULT_GROUND_SHADE
end

local function readBlink()
  local ok, value = pcall(mod.options.get, mod.options, BLINK_KEY)
  if ok then return BLINK_VALUES[blinkIndexOf(value)] end
  return DEFAULT_BLINK
end

local function readTopEdge()
  local ok, value = pcall(mod.options.get, mod.options, TOP_EDGE_KEY)
  if ok then return TOP_EDGE_VALUES[topEdgeIndexOf(value)] end
  return DEFAULT_TOP_EDGE
end

local function releaseMesh(mesh)
  if mesh and mesh ~= false and mesh.release then pcall(mesh.release, mesh) end
end

local function clearMeshCache()
  for _, mesh in pairs(meshes) do releaseMesh(mesh) end
  meshes, meshOrder = {}, {}
  meshFailureReasons = {}
end

local function clearCache()
  clearMeshCache()
  masks = {}
end

local function setDepth(value)
  local nextValue = VALUES[indexOf(value)]
  if depthValue ~= nextValue then clearCache() end
  depthValue = nextValue
  return depthValue
end

local function setSideColor(value)
  local nextValue = SIDE_COLOR_VALUES[sideColorIndexOf(value)]
  if sideColorValue ~= nextValue then clearMeshCache() end
  sideColorValue = nextValue
  return sideColorValue
end

local function setShape(value)
  local nextValue = SHAPE_VALUES[shapeIndexOf(value)]
  if shapeValue ~= nextValue then clearMeshCache() end
  shapeValue = nextValue
  return shapeValue
end

local function setGroundShade(value)
  local nextValue = GROUND_SHADE_VALUES[groundShadeIndexOf(value)]
  if groundShadeValue ~= nextValue then clearMeshCache() end
  groundShadeValue = nextValue
  return groundShadeValue
end

local function setBlink(value)
  blinkValue = BLINK_VALUES[blinkIndexOf(value)]
  return blinkValue
end

local function setTopEdge(value)
  local nextValue = TOP_EDGE_VALUES[topEdgeIndexOf(value)]
  if topEdgeValue ~= nextValue then clearMeshCache() end
  topEdgeValue = nextValue
  return topEdgeValue
end

setDepth(readDepth())
setSideColor(readSideColor())
setShape(readShape())
setGroundShade(readGroundShade())
setBlink(readBlink())
setTopEdge(readTopEdge())
Assets.register(clearCache)

local function writeOption(game, key, value)
  local id = mod.id
  local opts = game and game.save and game.save.options
  if opts then
    opts.modOptions = opts.modOptions or {}
    opts.modOptions[id] = opts.modOptions[id] or {}
    opts.modOptions[id][key] = value
  end
  local loader = game and game.mods
  if loader then
    loader.modOptions = loader.modOptions or {}
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id][key] = value
  end
  if loader and loader.events then
    loader.events:emit("mod.options_changed",
      { mod = id, key = key, value = value })
  end
end

local function depthRow()
  return {
    id = mod.id .. ":" .. KEY,
    label = "VOXEL CHARS",
    value = function() return LABELS[indexOf(depthValue or readDepth())] end,
    step = function(game, dir)
      local i = indexOf(depthValue or readDepth())
      i = ((i + (dir or 1) - 1) % #VALUES) + 1
      local value = setDepth(VALUES[i])
      writeOption(game, KEY, value)
      return true
    end,
  }
end

local function sideColorRow()
  return {
    id = mod.id .. ":" .. SIDE_COLOR_KEY,
    label = "SIDE COLOR",
    value = function()
      return SIDE_COLOR_LABELS[sideColorIndexOf(sideColorValue or readSideColor())]
    end,
    step = function(game, dir)
      local i = sideColorIndexOf(sideColorValue or readSideColor())
      i = ((i + (dir or 1) - 1) % #SIDE_COLOR_VALUES) + 1
      local value = setSideColor(SIDE_COLOR_VALUES[i])
      writeOption(game, SIDE_COLOR_KEY, value)
      return true
    end,
  }
end

local function shapeRow()
  return {
    id = mod.id .. ":" .. SHAPE_KEY,
    label = "SHAPE",
    value = function()
      return SHAPE_LABELS[shapeIndexOf(shapeValue or readShape())]
    end,
    step = function(game, dir)
      local i = shapeIndexOf(shapeValue or readShape())
      i = ((i + (dir or 1) - 1) % #SHAPE_VALUES) + 1
      local value = setShape(SHAPE_VALUES[i])
      writeOption(game, SHAPE_KEY, value)
      return true
    end,
  }
end

local function groundShadeRow()
  return {
    id = mod.id .. ":" .. GROUND_SHADE_KEY,
    label = "GROUND SHADE",
    value = function()
      return GROUND_SHADE_LABELS[groundShadeIndexOf(groundShadeValue or readGroundShade())]
    end,
    step = function(game, dir)
      local i = groundShadeIndexOf(groundShadeValue or readGroundShade())
      i = ((i + (dir or 1) - 1) % #GROUND_SHADE_VALUES) + 1
      local value = setGroundShade(GROUND_SHADE_VALUES[i])
      writeOption(game, GROUND_SHADE_KEY, value)
      return true
    end,
  }
end

local function blinkRow()
  return {
    id = mod.id .. ":" .. BLINK_KEY,
    label = "BLINK",
    value = function()
      return BLINK_LABELS[blinkIndexOf(blinkValue or readBlink())]
    end,
    step = function(game, dir)
      local i = blinkIndexOf(blinkValue or readBlink())
      i = ((i + (dir or 1) - 1) % #BLINK_VALUES) + 1
      local value = setBlink(BLINK_VALUES[i])
      writeOption(game, BLINK_KEY, value)
      return true
    end,
  }
end

local function topEdgeRow()
  return {
    id = mod.id .. ":" .. TOP_EDGE_KEY,
    label = "TOP EDGE",
    value = function()
      return TOP_EDGE_LABELS[topEdgeIndexOf(topEdgeValue or readTopEdge())]
    end,
    step = function(game, dir)
      local i = topEdgeIndexOf(topEdgeValue or readTopEdge())
      i = ((i + (dir or 1) - 1) % #TOP_EDGE_VALUES) + 1
      local value = setTopEdge(TOP_EDGE_VALUES[i])
      writeOption(game, TOP_EDGE_KEY, value)
      return true
    end,
  }
end

-- v1.4.2: recebe a tabela por parametro, nao pela upvalue de modulo, porque
-- patch() so pode fazer commit dessa upvalue DEPOIS que todas as escritas
-- arriscadas (main.lua, patch()) tiverem sucesso; ate la a upvalue
-- SpriteBillboards ainda nao existe.
local function warnChainedMesh(spriteBillboards)
  if spriteBillboards.__voxelCharactersOriginal then return end
  if spriteBillboards.shadowQuad
      and spriteBillboards.mesh ~= spriteBillboards.shadowQuad then
    mod.log:warn("SpriteBillboards.mesh was already patched; chaining over %s",
      tostring(spriteBillboards.mesh))
  end
end

local function intField(def, ...)
  for i = 1, select("#", ...) do
    local v = tonumber(def and def[select(i, ...)])
    if v and v > 0 then return math.floor(v) end
  end
end

local function spriteLayout(def, sheetW, sheetH)
  local frames = intField(def, "frames")
  if not (frames and sheetW and sheetH and sheetW > 0 and sheetH > 0) then
    return nil
  end

  local frameW = intField(def, "frameW", "frameWidth", "cellW", "cellWidth",
                          "spriteW", "spriteWidth")
  local frameH = intField(def, "frameH", "frameHeight", "cellH", "cellHeight",
                          "spriteH", "spriteHeight")
  local columns = intField(def, "columns", "cols", "framesPerRow")

  if frameW or columns then
    frameW = frameW or (columns and math.floor(sheetW / columns))
    if not (frameW and frameW > 0 and frameW <= sheetW) then return nil end
    columns = columns or math.max(1, math.floor(sheetW / frameW))
    if columns < 1 then return nil end
    local rows = math.ceil(frames / columns)
    frameH = frameH or math.floor(sheetH / rows)
    if not (frameH and frameH > 0 and frameH <= sheetH) then return nil end
    if (columns - 1) * frameW + frameW > sheetW then return nil end
    if (rows - 1) * frameH + frameH > sheetH then return nil end
    return { frames = frames, w = frameW, h = frameH, columns = columns }
  end

  -- Sem metadados de celula, so ha duas folhas derivaveis sem adivinhar:
  -- uma coluna vertical como o motor vanilla, ou uma linha horizontal. Folhas
  -- com padding ou grade ambigua degradam para o card original.
  local vertical = (sheetH % frames == 0)
    and { frames = frames, w = sheetW, h = sheetH / frames, columns = 1 }
  local horizontal = (sheetW % frames == 0)
    and { frames = frames, w = sheetW / frames, h = sheetH, columns = frames }
  if frames == 1 and vertical then return vertical end
  if vertical and not horizontal then return vertical end
  if horizontal and not vertical then return horizontal end
  if vertical and horizontal then
    local vScore = math.abs(vertical.w - vertical.h)
    local hScore = math.abs(horizontal.w - horizontal.h)
    if vScore < hScore then return vertical end
    if hScore < vScore then return horizontal end
  end
  return nil
end

local function frameOrigin(layout, frame)
  local col = frame % layout.columns
  local row = math.floor(frame / layout.columns)
  local w, h = layout.w or layout.cellW, layout.h or layout.cellH
  return col * w, row * h
end

local function pixelAt(data, x, y)
  local ok, r, g, b, a = pcall(data.getPixel, data, x, y)
  if not ok then return nil end
  return r or 0, g or 0, b or 0, a or 0
end

local function luminance(r, g, b)
  return (r or 0) * 0.2126 + (g or 0) * 0.7152 + (b or 0) * 0.0722
end

local function maskFor(def)
  if not (def and def.image) then return nil end
  local data = ImageCache.get(def.image)
  if not data then return nil end
  local sheetW, sheetH = data:getDimensions()
  local layout = spriteLayout(def, sheetW, sheetH)
  if not layout then return nil end
  local frames = layout.frames
  local key = table.concat({
    def.image, sheetW, sheetH, frames, layout.w, layout.h, layout.columns,
  }, "#")
  if masks[key] ~= nil then return masks[key] or nil end

  local mask = {}
  local outlineLuma
  local minX, maxX, minY, maxY = layout.w, -1, layout.h, -1
  for f = 0, frames - 1 do
    local fx, fy = frameOrigin(layout, f)
    if fx + layout.w <= sheetW and fy + layout.h <= sheetH then
      for ly = 0, layout.h - 1 do
        for lx = 0, layout.w - 1 do
          local r, g, b, a = pixelAt(data, fx + lx, fy + ly)
          if r and (a or 0) >= 0.5 then
            mask[ly * layout.w + lx] = true
            local luma = luminance(r, g, b)
            if not outlineLuma or luma < outlineLuma then outlineLuma = luma end
            if lx < minX then minX = lx end
            if lx > maxX then maxX = lx end
            if ly < minY then minY = ly end
            if ly > maxY then maxY = ly end
          end
        end
      end
    end
  end

  if maxX < minX or maxY < minY then
    masks[key] = false
    return nil
  end

  local out = {
    mask = mask, minX = minX, maxX = maxX, minY = minY, maxY = maxY,
    sheetW = sheetW, sheetH = sheetH, frames = frames,
    cellW = layout.w, cellH = layout.h, columns = layout.columns,
    data = data, outlineLuma = outlineLuma,
  }
  masks[key] = out
  return out
end

-- O lean real e `leanAngle()` da VoxelScene, que da precedencia a
-- `VoxelScene.spriteLean` sobre `VoxelState.angle` (VoxelScene.lua:283-285).
-- Hoje so o VR seta esse campo, para 75 graus (VR.lua:281); ler apenas o
-- `angle` deixaria o corpo tombado pela diferenca dentro do headset.
local function leanCorrection()
  local a = 0
  local pinned
  if VoxelScene then
    local ok, value = pcall(function() return VoxelScene.spriteLean end)
    if ok then pinned = tonumber(value) end
  end
  if pinned then
    a = pinned
  elseif VoxelState then
    local ok, value = pcall(function() return VoxelState.angle end)
    if ok then a = tonumber(value) or 0 end
  end
  local b = 0
  if FirstPerson and FirstPerson.cardBlend then
    local ok, value = pcall(FirstPerson.cardBlend)
    if ok then b = math.max(0, math.min(1, tonumber(value) or 0)) end
  end
  return (math.pi / 2 - a) * (1 - b)
end

-- DECISAO: o tween de rung dura 0,25 s; a 60 fps ele gerava cerca de
-- 15 pitches distintos, cada um com chave propria. O bucket de 1 grau
-- reduz a transicao a 2 ou 3 buckets visiveis sem deslocamento perceptivel.
-- O cache continua deliberadamente pequeno: 8 tipos x 6 frames ja ocupam 48
-- entradas em um unico pitch, e um tween que cruza 2 ou 3 buckets pode pedir
-- 96 a 144 malhas. O LRU evita crescimento sem limite, mas pode reciclar
-- malhas durante tweens com muitos NPCs diferentes na tela.
local function quantizeCorrection(angle)
  return math.floor(((angle or 0) / PITCH_BUCKET) + 0.5) * PITCH_BUCKET
end

local function pitchKey(angle)
  return tostring(math.floor(((angle or 0) / PITCH_BUCKET) + 0.5))
end

local function touchMeshKey(key)
  for i = #meshOrder, 1, -1 do
    if meshOrder[i] == key then
      table.remove(meshOrder, i)
      break
    end
  end
  meshOrder[#meshOrder + 1] = key
end

local function rememberMesh(key, mesh)
  meshes[key] = mesh
  touchMeshKey(key)
  while #meshOrder > MAX_MESHES do
    local oldKey = table.remove(meshOrder, 1)
    local old = meshes[oldKey]
    meshes[oldKey] = nil
    releaseMesh(old)
  end
end

local function frameTexel(m, frame, lx, ly)
  if lx < 0 or lx >= m.cellW or ly < 0 or ly >= m.cellH then return false end
  frame = tonumber(frame) or 0
  if frame < 0 or frame >= m.frames then return false end
  local fx, fy = frameOrigin(m, frame)
  if fx + m.cellW > m.sheetW or fy + m.cellH > m.sheetH then return false end
  local r, g, b, a = pixelAt(m.data, fx + lx, fy + ly)
  if not r or (a or 0) < 0.5 then return false end
  local outline = m.outlineLuma
    and math.abs(luminance(r, g, b) - m.outlineLuma) <= LUMA_EPSILON
  return true, outline
end

local function roleForFrame(frame, frames)
  frame = tonumber(frame) or 0
  if frame < 0 or frame >= frames then frame = 0 end
  if frame > 5 then frame = frame % 3 end
  return frame % 3
end

local function referenceFramesForRole(frame, frames, role)
  role = role or roleForFrame(frame, frames)
  if frames >= 6 then return role, role + 3 end
  if frames >= 3 then return role, nil end
  return tonumber(frame) or 0, nil
end

local function bodyTexelInFrame(m, frameIndex, lx, ly, dx, dy, sideColor)
  if sideColor ~= DEFAULT_SIDE_COLOR then return lx, ly, true end
  local opaque, outline = frameTexel(m, frameIndex, lx, ly)
  if not (opaque and outline) then return lx, ly, opaque and not outline end
  for step = 1, BODY_SEARCH_LIMIT do
    local bx, by = lx + dx * step, ly + dy * step
    local bodyOpaque, bodyOutline = frameTexel(m, frameIndex, bx, by)
    if bodyOpaque and not bodyOutline then return bx, by, true end
  end
  return lx, ly, false
end

-- CORRECAO defeito do topo piscando ao andar (SLAB, v1.4.2): a pose andando e
-- a pose parada descida uma linha, um passo deliberado na arte (AngelusRole:
-- "when a character's head is set to use the body color, the top of the head
-- flickers while walking"). verticalUv e sideUv liam a referencia na MESMA
-- coordenada (lx, ly) do frame corrente, entao o topo da cabeca do frame 3
-- resolvia para o texel do frame 0 uma linha mais baixa, outra faixa do
-- boné. poseOffset mede, por sobreposicao de mascara opaca, o quanto a arte
-- se desloca entre dois frames, para a leitura da referencia buscar o texel
-- fisicamente correspondente, nao so o mesmo indice.
--
-- DECISAO: desempate deterministico obrigatorio. |dx| + |dy| menor primeiro,
-- depois dy menor, depois dx menor. Sem uma ordem total explicita, folhas
-- simetricas empatam de verdade (teste "poseOffset desempata de forma
-- deterministica"), e o resultado passaria a depender da ordem de varredura
-- em vez do conteudo da folha; a malha cacheada mudaria de corrida para
-- corrida, o pior bug possivel aqui. `better` so troca o melhor candidato
-- quando ele e estritamente melhor por essas regras, entao o resultado
-- independe de como os loops de dx/dy sao percorridos.
--
-- DECISAO v1.4.2, pente fino (item 3): pre-computa a opacidade de
-- `fromFrame` num array local (flat, indexado por ly*cellW+lx) antes do
-- laco de candidatos. frameTexel(m, fromFrame, lx, ly) nao depende de dx
-- nem dy, mas a varredura recomputava ela para cada um dos ate 35
-- candidatos (7 valores de dy vezes 5 de dx); isso corta essa metade do
-- custo da primeira varredura de cada par, sem mudar nenhum resultado
-- (mesmos candidatos, mesmo desempate). E o risco "trocar flicker por
-- stutter" que a spec original nomeou, evitavel de graca.
local function poseOffsetScan(m, fromFrame, toFrame)
  local cellW, cellH = m.cellW, m.cellH
  local fromOpaque = {}
  for ly = 0, cellH - 1 do
    local row = ly * cellW
    for lx = 0, cellW - 1 do
      fromOpaque[row + lx] = frameTexel(m, fromFrame, lx, ly)
    end
  end

  local bestDx, bestDy, bestScore = 0, 0, -1
  for dy = -POSE_OFFSET_DY_RANGE, POSE_OFFSET_DY_RANGE do
    for dx = -POSE_OFFSET_DX_RANGE, POSE_OFFSET_DX_RANGE do
      local score = 0
      for ly = 0, cellH - 1 do
        local row = ly * cellW
        for lx = 0, cellW - 1 do
          if fromOpaque[row + lx]
              and frameTexel(m, toFrame, lx + dx, ly + dy) then
            score = score + 1
          end
        end
      end
      local better = score > bestScore
      if not better and score == bestScore then
        local curTie = math.abs(dx) + math.abs(dy)
        local bestTie = math.abs(bestDx) + math.abs(bestDy)
        if curTie < bestTie then
          better = true
        elseif curTie == bestTie then
          if dy < bestDy then
            better = true
          elseif dy == bestDy and dx < bestDx then
            better = true
          end
        end
      end
      if better then
        bestDx, bestDy, bestScore = dx, dy, score
      end
    end
  end
  return bestDx, bestDy
end

local function poseOffset(m, fromFrame, toFrame)
  fromFrame = tonumber(fromFrame) or 0
  toFrame = tonumber(toFrame) or 0
  if fromFrame == toFrame then return 0, 0 end
  -- DECISAO CARVED (v1.4.2): so compensa entre frames do MESMO role (a
  -- mesma vista: frente, cima ou perfil). CARVED reusa a textura de frente
  -- (role 0) para colorir o topo em qualquer orientacao renderizada e a
  -- textura de perfil (role 2) para colorir a lateral, entao um chamador
  -- errado poderia pedir a sobreposicao entre a mascara de frente e a de
  -- perfil. Isso nao mede deslocamento de passo, mede diferenca de
  -- silhueta (o personagem de perfil e mais estreito que de frente por
  -- natureza da arte), e devolveria um numero com cara de deslocamento que
  -- na verdade e ruido. Todo chamador correto ja compara pose.front com
  -- pose.front ou pose.side com pose.side, entao este branch nao deveria
  -- disparar em uso correto; ele fica de cinto e suspensorio contra o
  -- proximo lugar que chamar poseOffset com frames de roles diferentes.
  if roleForFrame(fromFrame, m.frames) ~= roleForFrame(toFrame, m.frames) then
    return 0, 0
  end

  -- DECISAO v1.4.2, pente fino (item 2): canonicaliza o par antes de
  -- escanear, sempre do menor indice de frame pro maior, e nega quando o
  -- pedido for na direcao oposta. Um empate genuino de score entre +dy e
  -- -dy faz a regra "menor dy" escolher -1 nas DUAS direcoes se cada
  -- chamada escaneasse pro seu proprio lado (poseOffset(A,B) e
  -- poseOffset(B,A) sao duas varreduras independentes, cada uma aplicando
  -- a MESMA regra "prefira dy negativo" sem saber da outra), quebrando
  -- poseOffset(A,B) == -poseOffset(B,A). Isso importa de verdade: a
  -- compensacao do olho pede poseOffset(refFrame, frame) e a geometria
  -- pede poseOffset(frame, frameIndex), direcoes opostas do mesmo par.
  -- Canonicalizando, so existe UMA varredura por par (memoizada por
  -- lo:hi), nunca duas independentes, entao a simetria vale por
  -- construcao, nao por sorte do desempate.
  local lo, hi, negate = fromFrame, toFrame, false
  if lo > hi then
    lo, hi, negate = hi, lo, true
  end

  m.poseOffsets = m.poseOffsets or {}
  local key = lo .. ":" .. hi
  local cached = m.poseOffsets[key]
  if not cached then
    if lo < 0 or lo >= m.frames or hi < 0 or hi >= m.frames then
      cached = { 0, 0 }
    else
      -- DECISAO: a varredura e O(cellW*cellH*janela) e roda dentro da
      -- construcao de malha; memoizar em `m` (o mesmo objeto que ja
      -- cacheia a mascara) garante no maximo uma varredura por par
      -- canonico por folha, nao uma por face.
      local dx, dy = poseOffsetScan(m, lo, hi)
      cached = { dx, dy }
    end
    m.poseOffsets[key] = cached
  end
  if negate then
    return -cached[1], -cached[2]
  end
  return cached[1], cached[2]
end

local function spriteBaseName(path)
  if type(path) ~= "string" then return nil end
  local name = path:match("([^/\\]+)$") or path
  return (name:gsub("%.[^%.]*$", ""))
end

local function hashName(name)
  local h = 5381
  name = tostring(name or "")
  for i = 1, #name do
    h = (h * 33 + name:byte(i)) % 4294967296
  end
  return h
end

local function blinkTiming(baseName)
  local h = hashName(baseName)
  local period = 3 + (h % 3000) / 1000
  local phase = (math.floor(h / 3000) % 3000) / 1000
  return period, phase
end

local function blinkClosedForBase(baseName)
  if not (love and love.timer and love.timer.getTime) then return false end
  local ok, now = pcall(love.timer.getTime)
  if not ok then return false end
  local period, phase = blinkTiming(baseName)
  return ((tonumber(now) or 0) + phase) % period < BLINK_CLOSED_SECONDS
end

local function blinkBodyTexel(m, frameIndex, lx, ly)
  local dirs = {
    { 0, 1 }, { -1, 0 }, { 1, 0 }, { 0, -1 },
  }
  for _, dir in ipairs(dirs) do
    local bx, by, found = bodyTexelInFrame(m, frameIndex, lx, ly, dir[1],
      dir[2], DEFAULT_SIDE_COLOR)
    if found and (bx ~= lx or by ~= ly) then return bx, by end
  end
end

local function eyeTexelLuma(m, frameIndex, lx, ly)
  if lx < 0 or lx >= m.cellW or ly < 0 or ly >= m.cellH then return nil end
  local fx, fy = frameOrigin(m, frameIndex)
  local r, g, b, a = pixelAt(m.data, fx + lx, fy + ly)
  if not r or (a or 0) < 0.5 then return nil end
  return luminance(r, g, b)
end

-- CORRECAO defeito "so pisca parado" (v1.4.2): a marca de olho e sempre a do
-- frame de referencia (parado); para a pose andando, a coordenada e a marca
-- mais poseOffset, mas so conta se o tom realmente transferir. Sem isso a
-- v1.4.1 fechava o "olho" em cima de pele quando o frame 3 descia uma linha
-- (CHANGELOG v1.4.1: "the face shifts vertically on many sheets"), que e
-- exatamente o deslocamento que poseOffset mede.
local function eyeMarkTransfers(m, refFrame, rx, ry, walkFrame, wx, wy)
  local refLuma = eyeTexelLuma(m, refFrame, rx, ry)
  local walkLuma = eyeTexelLuma(m, walkFrame, wx, wy)
  if not (refLuma and walkLuma) then return false end
  return math.abs(refLuma - walkLuma) <= LUMA_EPSILON
end

local function rowsForUv(rows, first, uv4)
  local out = {}
  for i = 0, 3 do
    local src = rows[first + i]
    out[i + 1] = { src[1], src[2], src[3], uv4[i * 2 + 1],
      uv4[i * 2 + 2], src[6] }
  end
  return out
end

local function setMeshVertex(mesh, index, row)
  if not (mesh and mesh.setVertex) then return false end
  local ok = pcall(mesh.setVertex, mesh, index, row)
  if ok then return true end
  return pcall(mesh.setVertex, mesh, index, row[1], row[2], row[3], row[4],
    row[5], row[6])
end

local function warnBlinkVertexFailure()
  if blinkVertexWarned then return end
  blinkVertexWarned = true
  mod.log:warn("could not update SLAB blink UVs; mesh.setVertex failed")
end

local function applyBlinkUv(mesh)
  local meta = meshBlink[mesh]
  if not meta then return end
  local closed = (blinkValue or readBlink()) == "on"
    and blinkClosedForBase(meta.baseName)
  if meta.closed == closed then return end
  meta.closed = closed
  for _, quad in ipairs(meta.quads) do
    local rows = closed and quad.closedRows or quad.openRows
    for i = 1, 4 do
      if not setMeshVertex(mesh, quad.first + i - 1, rows[i]) then
        warnBlinkVertexFailure()
      end
    end
  end
end

local function shadeAtHeight(shade, y, groundShade)
  if groundShade ~= "on" or y >= AO_RISE then return shade end
  local t = math.max(0, y) / AO_RISE
  return shade * (1 - AO_GROUND * (1 - t))
end

local function buildSlabMesh(def, frame, depth, correction, m, sideColor,
                             groundShade, baseName, topEdge)
  m = m or maskFor(def)
  if not m then return nil end
  frame = tonumber(frame) or 0
  if frame < 0 or frame >= m.frames then frame = 0 end
  local fx, fy = frameOrigin(m, frame)
  if fx + m.cellW > m.sheetW or fy + m.cellH > m.sheetH then return nil end
  local refFrameA, refFrameB = referenceFramesForRole(frame, m.frames)

  local z0, z1 = -depth, 0
  -- CORRECAO defeito 2b (SLAB, v1.3.0): o eixo Y tinha o mesmo defeito que o
  -- X, e a spec desta rodada afirmou que nao tinha. O host translada o card
  -- para a altura do chao e pivota o lean ali (VoxelScene.lua:287-295), entao
  -- y = 0 no espaco local e a linha de BAIXO da celula, nao a linha opaca
  -- mais baixa da arte. Ancorar em m.maxY afunda no chao toda folha que tem
  -- rodape vazio: 8 das 67, e entre elas poke_ball.png por 2 pixels, que e o
  -- sprite de object event mais comum do jogo, alem de snorlax, pokedex,
  -- fossil e old_amber. Para as 59 folhas cuja arte encosta em ly = cellH-1
  -- a formula e identica a anterior, entao isto nao mexe em ninguem que ja
  -- estava certo.
  local cellBottom = m.cellH - 1
  local verts, idx = {}, {}
  local c, s = math.cos(correction or 0), math.sin(correction or 0)

  -- CORRECAO defeito 1 (SLAB, v1.3.0): `at` respondia com `m.mask`, a uniao
  -- de opacidade de TODOS os frames da folha (maskFor acumula sobre os
  -- frames em main.lua:365-383). Isso funciona para frente/tras, que
  -- amostram o frame corrente via rectUv e dependem do alpha discard do
  -- shader para recortar a pose; nao funciona para topo/base/lateral, cujo
  -- UV resolve de proposito para um texel opaco fixo (verticalUv, sideUv) e
  -- nunca e descartado. O SLAB desenhava a silhueta da caminhada inteira em
  -- cada pose (Pikon: "It kinda looks like all Red's sprites are appearing
  -- at once when walking left to right"). Agora `at` consulta a opacidade
  -- do FRAME CORRENTE, nao a uniao.
  local function at(lx, ly)
    if lx < m.minX or lx > m.maxX or ly < m.minY or ly > m.maxY then return false end
    return (frameTexel(m, frame, lx, ly))
  end

  local function uv(lx, ly)
    return (fx + lx + 0.5) / m.sheetW, (fy + ly + 0.5) / m.sheetH
  end

  local function bodyTexel(lx, ly, dx, dy)
    return bodyTexelInFrame(m, frame, lx, ly, dx, dy, sideColor)
  end

  local function topShade()
    if topEdge == "on" then return OBJ_SHADE.top * TOP_EDGE_SHADE end
    return OBJ_SHADE.top
  end

  local function sameUv(lx, ly)
    local u, v = uv(lx, ly)
    return { u, v, u, v, u, v, u, v }
  end

  local function sameFrameUv(frameIndex, lx, ly)
    local ffx, ffy = frameOrigin(m, frameIndex)
    local u = (ffx + lx + 0.5) / m.sheetW
    local v = (ffy + ly + 0.5) / m.sheetH
    return { u, v, u, v, u, v, u, v }
  end

  -- CORRECAO defeito do topo piscando ao andar (SLAB, v1.4.2): `lx, ly` e a
  -- coordenada da face no frame CORRENTE; `frameIndex` e o frame de
  -- referencia. Antes de ler o corpo em `frameIndex`, compensamos pelo
  -- deslocamento medido entre as duas poses (poseOffset), senao a leitura
  -- cai na mesma linha do frame errado. Se a coordenada compensada sair da
  -- celula ou nao achar corpo opaco no frame de referencia, degrada para a
  -- coordenada sem compensar (o comportamento anterior a v1.4.2) antes de
  -- desistir deste frame de referencia; nenhuma face fica sem UV resolvida.
  local function sideUv(lx, ly, dx)
    local function tryFrame(frameIndex)
      if not frameIndex then return nil end
      local pdx, pdy = poseOffset(m, frame, frameIndex)
      local bx, by = bodyTexelInFrame(m, frameIndex, lx + pdx, ly + pdy, dx, 0,
        sideColor)
      if frameTexel(m, frameIndex, bx, by) then
        return sameFrameUv(frameIndex, bx, by)
      end
      bx, by = bodyTexelInFrame(m, frameIndex, lx, ly, dx, 0, sideColor)
      if frameTexel(m, frameIndex, bx, by) then
        return sameFrameUv(frameIndex, bx, by)
      end
    end
    return tryFrame(refFrameA) or tryFrame(refFrameB)
      or sameUv(bodyTexel(lx, ly, dx, 0))
  end

  local function verticalUv(lx, ly, dy)
    local function tryFrame(frameIndex)
      if not frameIndex then return nil end
      local pdx, pdy = poseOffset(m, frame, frameIndex)
      local bx, by = bodyTexelInFrame(m, frameIndex, lx + pdx, ly + pdy, 0, dy,
        sideColor)
      if frameTexel(m, frameIndex, bx, by) then
        return sameFrameUv(frameIndex, bx, by)
      end
      bx, by = bodyTexelInFrame(m, frameIndex, lx, ly, 0, dy, sideColor)
      if frameTexel(m, frameIndex, bx, by) then
        return sameFrameUv(frameIndex, bx, by)
      end
    end
    return tryFrame(refFrameA) or tryFrame(refFrameB)
      or sameUv(bodyTexel(lx, ly, 0, dy))
  end

  local function rectFrameUv(frameIndex, lx, ly, lx2, order)
    local ffx, ffy = frameOrigin(m, frameIndex)
    local u0 = (ffx + lx + RUN_UV_INSET) / m.sheetW
    local u1 = (ffx + lx2 + 1 - RUN_UV_INSET) / m.sheetW
    local v0 = (ffy + ly + RUN_UV_INSET) / m.sheetH
    local v1 = (ffy + ly + 1 - RUN_UV_INSET) / m.sheetH
    if order == "back" then
      return { u1, v1, u0, v1, u0, v0, u1, v0 }
    elseif order == "top" then
      return { u0, v0, u1, v0, u1, v1, u0, v1 }
    end
    return { u0, v1, u1, v1, u1, v0, u0, v0 }
  end

  local function rectUv(lx, ly, lx2, order)
    return rectFrameUv(frame, lx, ly, lx2, order)
  end

  -- CORRECAO defeito "so pisca parado" (v1.4.2): as poses andando (3 e 5)
  -- passam a piscar tambem. `refFrameA` (calculado acima) ja e a role do
  -- frame corrente (0 frente, 1 costas, 2 perfil); costas nunca teve marca
  -- de olho e continua sem piscar. Na pose parada (frame == refFrameA) a
  -- marca vale na propria coordenada, como sempre. Na pose andando, cada
  -- marca so entra em eyeLookup se o tom em (x+dx, y+dy) no frame andando
  -- bater com o tom em (x, y) no frame de referencia; se QUALQUER marca da
  -- folha nao transferir, a folha inteira fica de olho aberto NESTA pose,
  -- nunca meio olho. Decidido aqui, medido folha a folha e pose a pose,
  -- nunca por tabela escrita a mao.
  local blinkQuads = {}
  local canBlinkFrame = false
  local eyeLookup
  if refFrameA == 0 or refFrameA == 2 then
    local marks = refFrameA == 2 and EYE_SIDE_MARKS[baseName or ""]
      or EYE_MARKS[baseName or ""]
    if marks then
      if frame == refFrameA then
        eyeLookup = {}
        for _, eye in ipairs(marks) do
          eyeLookup[eye[2] .. ":" .. eye[1]] = true
        end
        canBlinkFrame = true
      else
        local pdx, pdy = poseOffset(m, refFrameA, frame)
        local candidate, allTransfer = {}, true
        for _, eye in ipairs(marks) do
          local wx, wy = eye[1] + pdx, eye[2] + pdy
          if eyeMarkTransfers(m, refFrameA, eye[1], eye[2], frame, wx, wy) then
            candidate[wy .. ":" .. wx] = true
          else
            allTransfer = false
            break
          end
        end
        if allTransfer then
          eyeLookup = candidate
          canBlinkFrame = true
        end
      end
    end
  end

  -- DECISAO: SLAB tambem precisa fixar a classificacao de cor das faces novas
  -- por role, nao pelo frame corrente. O bug medido no red.png vinha de usar
  -- a caminhada diretamente: 49/180 posicoes de face de topo alternavam entre
  -- parado e andando, 14 delas na regiao do bone. A causa direta e a linha 0
  -- do frame 3 ficar vazia porque o sprite desce uma linha inteira. Topo,
  -- base e laterais usam texel fixo por pixel para poder buscar corpo no
  -- eixo certo sem misturar colunas de um run.

  local function p(x, y, z)
    -- A matriz do Dramatic Shape inclina o card no X, pivotando nos pes.
    -- A malha solida chega contra-rotacionada no mesmo pivo; depois do lean
    -- externo, o corpo volta a ficar de pe.
    return { x, y * c - z * s, y * s + z * c, y }
  end

  local function quad(c1, c2, c3, c4, uv4, shade)
    local n = #verts / 4
    local first = #verts + 1
    local function add(corner, u, v)
      verts[#verts + 1] = {
        corner[1], corner[2], corner[3], u, v,
        shadeAtHeight(shade, corner[4], groundShade),
      }
    end
    add(c1, uv4[1], uv4[2])
    add(c2, uv4[3], uv4[4])
    add(c3, uv4[5], uv4[6])
    add(c4, uv4[7], uv4[8])
    Voxel3D.pushQuad(idx, n)
    return first
  end

  local function isEye(lx, ly)
    return eyeLookup and eyeLookup[ly .. ":" .. lx]
  end

  local function eyeClosedUv(lx, ly)
    local bx, by = blinkBodyTexel(m, frame, lx, ly)
    if bx then return sameUv(bx, by) end
  end

  local function addEyeQuad(first, openUv, closedUv)
    if not (canBlinkFrame and closedUv) then return end
    blinkQuads[#blinkQuads + 1] = {
      first = first,
      openRows = rowsForUv(verts, first, openUv),
      closedRows = rowsForUv(verts, first, closedUv),
    }
  end

  -- CORRECAO defeito B (SLAB, v1.3.0): desde que `at()` passou a consultar o
  -- frame corrente, as faces laterais podem ser runs verticais quando isso
  -- preserva exatamente o mesmo UV e o mesmo shade dos quads por pixel.
  local function sameUvTable(a, b)
    if not (a and b) then return false end
    for i = 1, 8 do
      if a[i] ~= b[i] then return false end
    end
    return true
  end

  local sideRuns, finishedSideRuns = {}, {}

  local function sideRunKey(px, side)
    return side .. ":" .. px
  end

  local function finishSideRun(key)
    local run = sideRuns[key]
    if run then
      finishedSideRuns[#finishedSideRuns + 1] = run
      sideRuns[key] = nil
    end
  end

  local function addSideRun(px, ly, side, uv4)
    local key = sideRunKey(px, side)
    local sy = cellBottom - ly
    local run = sideRuns[key]
    if run and run.lastLy + 1 == ly and sameUvTable(run.uv4, uv4)
        and run.shade == OBJ_SHADE.side then
      run.lastLy = ly
      run.minY = math.min(run.minY, sy)
      run.maxY = math.max(run.maxY, sy + 1)
      return
    end
    finishSideRun(key)
    sideRuns[key] = {
      px = px, side = side, lastLy = ly, minY = sy, maxY = sy + 1,
      uv4 = uv4, shade = OBJ_SHADE.side,
    }
  end

  local function emitSideRun(run)
    if run.side == "left" then
      local x = run.px + SIDE_INSET
      quad(p(x, run.minY, z0), p(x, run.minY, z1),
           p(x, run.maxY, z1), p(x, run.maxY, z0),
           run.uv4, run.shade)
    else
      local x = run.px + 1 - SIDE_INSET
      quad(p(x, run.minY, z1), p(x, run.minY, z0),
           p(x, run.maxY, z0), p(x, run.maxY, z1),
           run.uv4, run.shade)
    end
  end

  -- DECISAO: historicamente as laterais esquerda/direita do SLAB eram por
  -- pixel porque a ocupacao vinha de `m.mask` (uniao de todos os frames) e so
  -- o alpha discard do shader recortava a pose por cima. Se fossem runs, a
  -- lateral deixaria rastro quando a silhueta andasse. Desde a v1.3.0, `at()`
  -- consulta o frame corrente e a lateral ja nasce na silhueta certa, entao
  -- faces adjacentes podem ser mescladas verticalmente quando isso e
  -- lossless: mesmo X, mesmo lado, mesmo shade e mesmo UV resolvido. Onde o
  -- UV muda, preservamos os quads separados. Frente e tras continuam em runs
  -- horizontais com UV retangular e inset de 0,05 texel.
  -- A comunidade mediu que 34/34 pixels de silhueta lateral de red.png vinham
  -- no tom mais escuro, mas um passo para dentro so 16/34 ainda eram contorno.
  -- Por isso BODY pinta faces novas com texel interno, enquanto frente e tras
  -- continuam sendo a arte original. Topo/base sao por pixel como as laterais:
  -- quando um pixel de contorno encosta numa linha vertical de corpo, o texel
  -- novo vem desse corpo em vez de exigir que o run horizontal inteiro combine.
  -- A partir da v1.2.2, essa decisao roda em frames de referencia fixos para
  -- o SLAB nao piscar.
  for ly = m.minY, m.maxY do
    local lx = m.minX
    while lx <= m.maxX do
      if at(lx, ly) then
        local lx2 = lx
        while lx2 + 1 <= m.maxX and at(lx2 + 1, ly) do lx2 = lx2 + 1 end

        -- CORRECAO defeito 2 (SLAB, v1.3.0): X saia relativo a bbox opaca
        -- (`lx - m.minX`), nao a celula do sprite. O host ancora o card com
        -- Mat4.translate(px+8, y, py+8) seguido de Mat4.translate(-8,0,0)
        -- (VoxelScene.lua:287-295): o espaco local vai de x=0 a x=16 e o
        -- pivo de yaw/espelho fica em x=8, o centro da CELULA, nao da bbox
        -- da arte. 40 das 67 folhas tem minX=1, entao a arte inteira saia
        -- 1 pixel a esquerda do card que ela substitui. X agora usa lx puro.
        local x, y = lx, cellBottom - ly
        local w = lx2 - lx + 1
        local function emitFrontRun(a, b)
          if a > b then return end
          local rx, rw = a, b - a + 1
          quad(p(rx, y, z1), p(rx + rw, y, z1),
               p(rx + rw, y + 1, z1), p(rx, y + 1, z1),
               rectUv(a, ly, b), OBJ_SHADE.front)
        end
        local cursor = lx
        for sx = lx, lx2 do
          if isEye(sx, ly) then
            emitFrontRun(cursor, sx - 1)
            local openUv = sameUv(sx, ly)
            local first = quad(p(sx, y, z1), p(sx + 1, y, z1),
              p(sx + 1, y + 1, z1), p(sx, y + 1, z1),
              openUv, OBJ_SHADE.front)
            addEyeQuad(first, openUv, eyeClosedUv(sx, ly))
            cursor = sx + 1
          end
        end
        emitFrontRun(cursor, lx2)
        quad(p(x + w, y, z0), p(x, y, z0), p(x, y + 1, z0),
             p(x + w, y + 1, z0), rectUv(lx, ly, lx2, "back"),
             OBJ_SHADE.back)
        for sx = lx, lx2 do
          if not at(sx, ly - 1) then
            quad(p(sx, y + 1 - SIDE_INSET, z0),
                 p(sx + 1, y + 1 - SIDE_INSET, z0),
                 p(sx + 1, y + 1 - SIDE_INSET, z1),
                 p(sx, y + 1 - SIDE_INSET, z1),
                 verticalUv(sx, ly, 1), topShade())
          end
          if not at(sx, ly + 1) then
            quad(p(sx, y + SIDE_INSET, z1),
                 p(sx + 1, y + SIDE_INSET, z1),
                 p(sx + 1, y + SIDE_INSET, z0),
                 p(sx, y + SIDE_INSET, z0),
                 verticalUv(sx, ly, -1), OBJ_SHADE.bottom)
          end
          -- CORRECAO v1.4.1: laterais tambem precisam ser faces expostas.
          -- Dentro de um run horizontal, a lateral esquerda de uma coluna e
          -- coplanar com a direita da coluna vizinha; com inset, isso ainda
          -- abria vao entre colunas. Emitimos so o contorno da silhueta.
          if not at(sx - 1, ly) then
            addSideRun(sx, ly, "left", sideUv(sx, ly, 1))
          end
          if not at(sx + 1, ly) then
            addSideRun(sx, ly, "right", sideUv(sx, ly, -1))
          end
        end
        lx = lx2 + 1
      else
        lx = lx + 1
      end
    end
  end

  local finalSideKeys = {}
  for key in pairs(sideRuns) do finalSideKeys[#finalSideKeys + 1] = key end
  table.sort(finalSideKeys)
  for _, key in ipairs(finalSideKeys) do finishSideRun(key) end
  for _, run in ipairs(finishedSideRuns) do emitSideRun(run) end

  local mesh = Voxel3D.newMesh(verts, idx)
  if mesh and #blinkQuads > 0 then
    meshBlink[mesh] = { baseName = baseName, quads = blinkQuads }
  end
  return mesh
end

local function frameBounds(m, frame)
  if frame < 0 or frame >= m.frames then return nil end
  local minX, maxX, minY, maxY = m.cellW, -1, m.cellH, -1
  for ly = 0, m.cellH - 1 do
    for lx = 0, m.cellW - 1 do
      if frameTexel(m, frame, lx, ly) then
        if lx < minX then minX = lx end
        if lx > maxX then maxX = lx end
        if ly < minY then minY = ly end
        if ly > maxY then maxY = ly end
      end
    end
  end
  if maxX < minX or maxY < minY then return nil end
  return { minX = minX, maxX = maxX, minY = minY, maxY = maxY }
end

local function carvedFrames(frame, frames)
  frame = tonumber(frame) or 0
  if frame < 0 or frame >= frames then frame = 0 end
  -- DECISAO: sprites Gen 1 usam buckets de tres vistas:
  -- parado down/up/left e, quando existe, andando down/up/left. A auditoria
  -- contou 20/73 sprites com so tres frames; eles tem as tres vistas completas
  -- e devem usar CARVED. Frames acima de 5 caem explicitamente no bucket de
  -- tres para nao transformar frame futuro em role silenciosamente invalido.
  local bucketFrame = frame
  if bucketFrame > 5 then bucketFrame = bucketFrame % 3 end
  local pose = (bucketFrame >= 3 and frames >= 6) and 3 or 0
  local role = bucketFrame - pose
  return {
    front = pose,
    back = pose + 1,
    side = pose + 2,
    role = role,
  }
end

local function buildCarvedMesh(def, frame, depth, correction, m, sideColor, shape,
                               groundShade)
  m = m or maskFor(def)
  if not (m and m.frames >= 3) then return nil end
  local pose = carvedFrames(frame, m.frames)
  if pose.back >= m.frames or pose.side >= m.frames then return nil end
  local carvedPlus = shape == "carved_plus"

  local frontBounds = frameBounds(m, pose.front)
  local backBounds = frameBounds(m, pose.back)
  local sideBounds = frameBounds(m, pose.side)
  if not (frontBounds and backBounds and sideBounds) then return nil end
  local widthFrame = pose.front
  local widthBounds = frontBounds
  local widthFrameA, widthFrameB = referenceFramesForRole(frame, m.frames,
    0)
  -- CORRECAO defeito do topo piscando ao andar, agora no CARVED (v1.4.2):
  -- topUv tem a mesma estrutura de busca por frame de referencia que o
  -- SLAB tinha, e o mesmo defeito (le lx, ly na coordenada do frame
  -- corrente, sem compensar o passo). A compensacao entra aqui, uma vez por
  -- malha, comparando pose.front (SEMPRE role 0, a vista de frente desta
  -- folha) contra a referencia (tambem sempre role 0), nunca o `frame` bruto
  -- recebido pela funcao: `frame` pode ser role 1 ou role 2, e comparar a
  -- mascara de frente com uma de outro role mediria diferenca de silhueta,
  -- nao deslocamento de passo (poseOffset ja se recusa e devolve 0,0 se as
  -- roles nao baterem, mas o chamador tem que pedir a comparacao certa para
  -- comecar). Calculado aqui, no espaco de textura, antes de qualquer
  -- rotacao por role em p(): a compensacao nunca entra no espaco de
  -- geometria.
  local widthOffsetAX, widthOffsetAY = poseOffset(m, pose.front, widthFrameA)
  local widthOffsetBX, widthOffsetBY = 0, 0
  if widthFrameB then
    widthOffsetBX, widthOffsetBY = poseOffset(m, pose.front, widthFrameB)
  end

  local verts, idx = {}, {}
  local pitchC, pitchS = math.cos(correction or 0), math.sin(correction or 0)
  local cellBottom = m.cellH - 1
  local depthPixels = sideBounds.maxX - sideBounds.minX + 1
  local frontFrameA = 0
  local frontFrameB = m.frames >= 6 and 3 or nil
  local sideLineRecess = {}

  local function mirrorX(lx)
    -- CORRECAO defeito A (CARVED, v1.3.0): o espelho de intersecao e a
    -- rotacao por role derivam do mesmo eixo de celula.
    return (m.cellW - 1) - lx
  end

  local function frontXFor(lx)
    return lx
  end

  local function backXFor(lx)
    return mirrorX(lx)
  end

  local function frameLuma(frameIndex, lx, ly)
    if not frameIndex then return nil end
    if lx < 0 or lx >= m.cellW or ly < 0 or ly >= m.cellH then return nil end
    if frameIndex < 0 or frameIndex >= m.frames then return nil end
    local fx, fy = frameOrigin(m, frameIndex)
    local r, g, b, a = pixelAt(m.data, fx + lx, fy + ly)
    if not r or (a or 0) < 0.5 then return nil end
    return luminance(r, g, b)
  end

  local function maxRecessForLine(ly)
    if sideLineRecess[ly] ~= nil then return sideLineRecess[ly] end
    local farthest = -1
    for sx = sideBounds.minX, sideBounds.maxX do
      if frameTexel(m, pose.side, sx, ly) then
        farthest = math.max(farthest, sx - sideBounds.minX)
      end
    end
    local limit = math.max(0, math.min(CARVED_PLUS_RECESS_STEPS, farthest))
    sideLineRecess[ly] = limit
    return limit
  end

  local reliefMinLuma, reliefMaxLuma
  if carvedPlus then
    if m.reliefScanned then
      reliefMinLuma, reliefMaxLuma = m.reliefMinLuma, m.reliefMaxLuma
    else
      local function scanReliefFrame(frameIndex)
        if not frameIndex then return end
        for ly = 0, m.cellH - 1 do
          for lx = 0, m.cellW - 1 do
            local luma = frameLuma(frameIndex, lx, ly)
            if luma and not (m.outlineLuma
                and math.abs(luma - m.outlineLuma) <= LUMA_EPSILON) then
              reliefMinLuma = reliefMinLuma and math.min(reliefMinLuma, luma) or luma
              reliefMaxLuma = reliefMaxLuma and math.max(reliefMaxLuma, luma) or luma
            end
          end
        end
      end
      scanReliefFrame(frontFrameA)
      scanReliefFrame(frontFrameB)
      if not reliefMinLuma then
        for ly = 0, m.cellH - 1 do
          for lx = 0, m.cellW - 1 do
            local luma = frameLuma(frontFrameA, lx, ly) or frameLuma(frontFrameB, lx, ly)
            if luma then
              reliefMinLuma = reliefMinLuma and math.min(reliefMinLuma, luma) or luma
              reliefMaxLuma = reliefMaxLuma and math.max(reliefMaxLuma, luma) or luma
            end
          end
        end
      end
      m.reliefScanned = true
      m.reliefMinLuma, m.reliefMaxLuma = reliefMinLuma, reliefMaxLuma
    end
  end

  -- DECISAO: o frame lateral 2 e o personagem olhando para a esquerda.
  -- Nas folhas Gen 1 essa borda esquerda e o rosto. Por isso a coluna
  -- opaca mais a esquerda da vista lateral fica em z = 0, e as colunas
  -- seguintes caminham para z negativo, em direcao a nuca. No red.png o
  -- tronco medido e 14 colunas de frente e 11 de lado; a caixa opaca completa
  -- da lateral tem 13 colunas por incluir pixels fora do tronco. Em ambos os
  -- casos, profundidade vem da arte, nao do slider de slab.
  --
  -- DECISAO: v1.2.1 acrescentou a silhueta de costas na intersecao. Como
  -- frente e costas sao vistas opostas, a coluna X da vista traseira entra
  -- espelhada; sem esse espelho o casco perde quase tudo em sprites
  -- assimetricos. O eixo nao pode vir do bbox global da folha: Kim mediu
  -- 12/40 folhas de 6 frames em que a vista lateral alarga esse bbox
  -- (biker 0..15 contra frente 1..14; bird 0..15 contra 2..13;
  -- brunette_girl e cooltrainer_f 1..15 contra 2..13), cortando 3% a 8% dos
  -- voxels legitimos em 7/8 sprites auditados. Tambem nao pode divergir do
  -- eixo usado pela rotacao por role: desde a v1.3.0 a geometria e ancorada
  -- na celula, entao o espelho de textura frente/costas usa o mesmo eixo da
  -- celula para nao vazar fora do card em folhas assimetricas.
  -- No role 1 esse espelho nao pode inverter de novo o espaco logico do casco:
  -- p() ja transforma lx em m.cellW - x para apresentar a vista de costas.
  -- Espelhar tambem aqui valida a opacidade em uma coluna e desenha em outra.
  --
  -- DECISAO: CARVED+ recua a superficie frontal por tom em so 2 passos. red.png
  -- tem 3 tons opacos de corpo alem do contorno; mais degraus so fingiriam uma
  -- precisao que a arte nao tem. A mesma arte usa tom para contorno e volume:
  -- onde o artista escureceu so para separar bone da testa, o relevo vira sulco.
  -- Por isso e um degrau proprio, nao o default. O recuo tambem e limitado pela
  -- profundidade real de cada linha lateral: sempre sobra pelo menos uma camada,
  -- porque sprite fino de mod externo nao pode virar um buraco atravessando o
  -- personagem.
  local function solid(lx, ly, sx)
    if lx < widthBounds.minX or lx > widthBounds.maxX then return false end
    if ly < widthBounds.minY or ly > widthBounds.maxY then return false end
    if sx < sideBounds.minX or sx > sideBounds.maxX then return false end
    local frontX = frontXFor(lx)
    if not frameTexel(m, pose.front, frontX, ly) then return false end
    if not frameTexel(m, pose.back, backXFor(lx), ly) then return false end
    if not frameTexel(m, pose.side, sx, ly) then return false end
    if carvedPlus and reliefMinLuma and reliefMaxLuma
        and reliefMaxLuma > reliefMinLuma + LUMA_EPSILON then
      local luma = frameLuma(frontFrameA, frontX, ly)
        or frameLuma(frontFrameB, frontX, ly)
      if luma then
        local dark = (reliefMaxLuma - luma) / (reliefMaxLuma - reliefMinLuma)
        local recess = math.max(0, math.min(maxRecessForLine(ly),
          math.floor(dark * CARVED_PLUS_RECESS_STEPS + 0.5)))
        if (sx - sideBounds.minX) < recess then return false end
      end
    end
    return true
  end

  local function uvFor(frameIndex, lx, ly)
    local fx, fy = frameOrigin(m, frameIndex)
    return (fx + lx + 0.5) / m.sheetW, (fy + ly + 0.5) / m.sheetH
  end

  local function sameUv(frameIndex, lx, ly)
    local u, v = uvFor(frameIndex, lx, ly)
    return { u, v, u, v, u, v, u, v }
  end

  local function opaqueFrame(preferred, fallback, lx, ly)
    if frameTexel(m, preferred, lx, ly) then return preferred end
    if fallback and frameTexel(m, fallback, lx, ly) then return fallback end
    return preferred
  end

  local function bodyTexel(frameIndex, lx, ly, dx, dy)
    return bodyTexelInFrame(m, frameIndex, lx, ly, dx, dy, sideColor)
  end

  local sideFrameA, sideFrameB = referenceFramesForRole(frame, m.frames, 2)
  -- v1.4.2: mesma logica de widthOffsetA/B acima, mas para a lateral.
  -- pose.side e SEMPRE role 2 (a vista de perfil desta folha), como
  -- sideFrameA/B; a comparacao fica perfil-contra-perfil, nunca
  -- frente-contra-perfil.
  local sideOffsetAX, sideOffsetAY = poseOffset(m, pose.side, sideFrameA)
  local sideOffsetBX, sideOffsetBY = 0, 0
  if sideFrameB then
    sideOffsetBX, sideOffsetBY = poseOffset(m, pose.side, sideFrameB)
  end

  local function sideUv(sx, ly)
    local middle = (sideBounds.minX + sideBounds.maxX) / 2
    local dx = sx <= middle and 1 or -1
    -- DECISAO: a casca lateral tem que ter classificacao estavel entre
    -- frames. No red.png, 161/378 posicoes laterais alternavam corpo/contorno
    -- porque a malha vinha da silhueta combinada, mas a busca de cor olhava
    -- so o frame corrente. Procuramos uma vez entre as vistas laterais da
    -- folha e fixamos o primeiro texel opaco encontrado; assim caminhar nao
    -- troca vermelho por preto na mesma posicao da face.
    --
    -- v1.4.2: `sx, ly` compensado pelo deslocamento entre pose.side e o
    -- frame de referencia antes de ler o corpo, com a mesma degradacao de
    -- topUv: compensado, depois sem compensar, depois os fallbacks de
    -- sempre.
    local function tryFrame(sideFrame, pdx, pdy)
      if not sideFrame then return nil end
      local bx, by = bodyTexel(sideFrame, sx + pdx, ly + pdy, dx, 0)
      if frameTexel(m, sideFrame, bx, by) then
        return sameUv(sideFrame, bx, by)
      end
      bx, by = bodyTexel(sideFrame, sx, ly, dx, 0)
      if frameTexel(m, sideFrame, bx, by) then
        return sameUv(sideFrame, bx, by)
      end
    end
    local uv = tryFrame(sideFrameA, sideOffsetAX, sideOffsetAY)
      or tryFrame(sideFrameB, sideOffsetBX, sideOffsetBY)
    if uv then return uv end
    return sameUv(pose.side, sx, ly)
  end

  local function topUv(lx, ly, dy)
    -- DECISAO: topo/base precisam de classificacao fixa como as laterais.
    -- O bug medido no red.png vinha de usar o frame corrente: 49/180 posicoes
    -- de face de topo alternavam parado/andando, 14 delas nas 6 linhas de cima
    -- do bone. A causa direta e a linha 0 existir no frame 0
    -- (".....######.....") e sumir no frame 3, porque o sprite inteiro desce uma
    -- linha ao andar. Tentar a vista de referencia e so cair para a caminhada
    -- quando ha opacidade fixa a cor da face no mesmo texel logico.
    --
    -- v1.4.2: `lx, ly` compensado pelo deslocamento entre pose.front e o
    -- frame de referencia (widthOffsetA/B, calculados uma vez acima) antes
    -- de ler o corpo; se a coordenada compensada sair da celula ou nao
    -- achar corpo opaco no frame de referencia, degrada para a coordenada
    -- sem compensar antes de cair nos fallbacks que ja existiam.
    local function tryFrame(frameIndex, pdx, pdy)
      if not frameIndex then return nil end
      local bx, by = bodyTexel(frameIndex, lx + pdx, ly + pdy, 0, dy)
      if frameTexel(m, frameIndex, bx, by) then
        return sameUv(frameIndex, bx, by)
      end
      bx, by = bodyTexel(frameIndex, lx, ly, 0, dy)
      if frameTexel(m, frameIndex, bx, by) then
        return sameUv(frameIndex, bx, by)
      end
    end
    local uv = tryFrame(widthFrameA, widthOffsetAX, widthOffsetAY)
      or tryFrame(widthFrameB, widthOffsetBX, widthOffsetBY)
    if uv then return uv end
    return sameUv(widthFrame, lx, ly)
  end

  local function p(x, y, z)
    local ox, oz = x, z
    if pose.role == 1 then
      ox, oz = m.cellW - x, -depthPixels - z
    elseif pose.role == 2 then
      -- DECISAO: o role lateral tambem precisa compensar o pivo. Sem isso,
      -- red.png medido no main.lua real ia de Y [0, 13] na frente para
      -- Y [-14, 0] de lado: o z positivo entrava na contra-rotacao do lean
      -- como deslocamento vertical e metade das direcoes afundava no chao.
      -- A compensacao mantem o volume em z nao positivo, como frente e costas.
      -- Desde a v1.3.0 o X tambem preserva o padding da celula; por isso o
      -- eixo que vem da vista lateral soma sideBounds.minX de volta, enquanto
      -- o eixo de profundidade gira em torno da largura da celula.
      ox, oz = sideBounds.minX - z, x - m.cellW
    end
    return { ox, y * pitchC - oz * pitchS, y * pitchS + oz * pitchC, y }
  end

  local function quad(c1, c2, c3, c4, uv4, shade)
    local n = #verts / 4
    local function add(corner, u, v)
      verts[#verts + 1] = {
        corner[1], corner[2], corner[3], u, v,
        shadeAtHeight(shade, corner[4], groundShade),
      }
    end
    add(c1, uv4[1], uv4[2])
    add(c2, uv4[3], uv4[4])
    add(c3, uv4[5], uv4[6])
    add(c4, uv4[7], uv4[8])
    Voxel3D.pushQuad(idx, n)
  end

  for ly = m.minY, m.maxY do
    for lx = widthBounds.minX, widthBounds.maxX do
      for sx = sideBounds.minX, sideBounds.maxX do
        if solid(lx, ly, sx) then
          local x0, x1 = lx, lx + 1
          local y0, y1 = cellBottom - ly, cellBottom - ly + 1
          local z0 = -(sx - sideBounds.minX)
          local z1 = z0 - 1

          if not solid(lx, ly, sx - 1) then
            quad(p(x0, y0, z0), p(x1, y0, z0), p(x1, y1, z0),
                 p(x0, y1, z0), sameUv(opaqueFrame(pose.front, widthFrame, lx, ly), lx, ly),
                 OBJ_SHADE.front)
          end
          if not solid(lx, ly, sx + 1) then
            quad(p(x1, y0, z1), p(x0, y0, z1), p(x0, y1, z1),
                 p(x1, y1, z1), sameUv(opaqueFrame(pose.back, widthFrame, lx, ly), lx, ly),
                 OBJ_SHADE.back)
          end
          if not solid(lx - 1, ly, sx) then
            quad(p(x0, y0, z1), p(x0, y0, z0), p(x0, y1, z0),
                 p(x0, y1, z1), sideUv(sx, ly), OBJ_SHADE.side)
          end
          if not solid(lx + 1, ly, sx) then
            quad(p(x1, y0, z0), p(x1, y0, z1), p(x1, y1, z1),
                 p(x1, y1, z0), sideUv(sx, ly), OBJ_SHADE.side)
          end
          if not solid(lx, ly - 1, sx) then
            quad(p(x0, y1, z1), p(x1, y1, z1), p(x1, y1, z0),
                 p(x0, y1, z0), topUv(lx, ly, 1), OBJ_SHADE.top)
          end
          if not solid(lx, ly + 1, sx) then
            quad(p(x0, y0, z0), p(x1, y0, z0), p(x1, y0, z1),
                 p(x0, y0, z1), topUv(lx, ly, -1), OBJ_SHADE.bottom)
          end
        end
      end
    end
  end

  return Voxel3D.newMesh(verts, idx)
end

local function buildSelectedMesh(def, frame, depth, correction, m, sideColor, shape,
                                 groundShade, baseName, topEdge)
  if shape == "carved" or shape == "carved_plus" then
    local ok, mesh = pcall(buildCarvedMesh, def, frame, depth, correction, m,
      sideColor, shape, groundShade)
    if ok and mesh then return mesh end
  end
  return buildSlabMesh(def, frame, depth, correction, m, sideColor, groundShade,
    baseName, topEdge)
end

local function cacheKey(def, frame, depth, correction, layout, sideColor, shape,
                        groundShade, topEdge)
  local depthPart = (shape == "carved" or shape == "carved_plus") and "art"
    or tostring(depth)
  local topEdgePart = shape == "slab" and tostring(topEdge or "") or ""
  return table.concat({
    tostring(def and def.image or ""),
    tostring(def and def.frames or ""),
    tostring(frame or 0),
    depthPart,
    tostring(sideColor or ""),
    tostring(shape or ""),
    tostring(groundShade or ""),
    topEdgePart,
    tostring(layout and layout.cellW or ""),
    tostring(layout and layout.cellH or ""),
    tostring(layout and layout.columns or ""),
    pitchKey(correction),
  }, "#")
end

-- CORRECAO defeito 3 (SLAB e CARVED, v1.3.0; roda antes de qualquer um dos
-- dois ser escolhido): o shader do host move cada vertice em direcao ao olho
-- quando FirstPerson.cardBlend() > 0 (Voxel3D.lua:122-130, enviado em
-- :1296-1307). Num card plano isso e projetivamente estavel; num volume
-- solido, cada canto anda numa direcao diferente, e somado a camera de
-- primeira pessoa, que fica na cabeca do sprite com near plane curto
-- (FirstPerson.lua:63-75, Voxel3D.lua:518-519), atravessa o near plane e
-- produz espetos pretos (Colonel_Aureliano, Dramatic Shape 1.7.0 + Kanto
-- First Person, campo de conflito do manifest limpo a mao). O contrato deste
-- mod e explicito: todo caminho de falha cai de volta para o card plano
-- original, nunca um corpo com espetos. Em pcall como leanCorrection ja faz
-- (main.lua:418-421), porque FirstPerson pode nao existir em toda versao
-- suportada do host; ausencia = blend zero = comportamento atual. Nao
-- tentamos compensar o rotateY: o host tambem troca o frame pedido por uma
-- direcao aparente continua em primeira pessoa (VoxelScene.lua:234-241) e
-- documenta o card de primeira pessoa como billboard cilindrico; um solido
-- nao deveria herdar esse contrato. Isto nao vira opcao de menu: nao e
-- escolha estetica, e o contrato de falha limpa.
local function firstPersonCardActive()
  if not (FirstPerson and FirstPerson.cardBlend) then return false end
  local ok, blend = pcall(FirstPerson.cardBlend)
  return ok and tonumber(blend) ~= nil and tonumber(blend) > 0
end

local originalMeshWarned = false

local function warnOriginalMeshFailure(reason)
  if originalMeshWarned then return end
  originalMeshWarned = true
  mod.log:warn(
    "dropped a character billboard because the original mesh call failed: %s",
    tostring(reason))
end

-- CORRECAO defeito "um mod de terceiro derruba o modo voxel do jogo inteiro"
-- (v1.4.2): o host (DramaticShapeVoxelMod/lib/SpriteBillboards.lua:65) faz
-- `def.image .. "#" .. frame` sem guarda de tipo; um `frame` nulo vindo de
-- QUALQUER mod de entidade lanca ali. Quem chama o host e
-- VoxelScene.lua:368, dentro do loop de desenho, sem pcall; a excecao sobe
-- ate Pipelines.lua, que marca o mod inteiro como broken pela sessao inteira
-- (AngelusRole: precisou desligar o Wilds of Kanto pro nosso mod voltar a
-- funcionar). Uma unica entidade com pose ruim, um unico frame, desliga o
-- modo voxel do jogo inteiro ate reiniciar. Nenhum caminho nosso que chama o
-- original pode deixar essa excecao escapar; por isso TODO chamador de
-- `originalMesh` passa por aqui, nunca chama `originalMesh` direto.
local function safeOriginal(def, frame)
  local ok, mesh = pcall(originalMesh, def, frame)
  if ok then return mesh end
  warnOriginalMeshFailure(mesh)
  return nil
end

-- v1.4.2, pente fino (itens 1 e 2): empurra um resultado para a janela
-- deslizante. `kind` e nil para sucesso, ou o tipo de falha (mask_failed,
-- build_failed, exception) para falha. Mantem drawWindowFailures e
-- drawWindowKindCounts corretos sem varrer o array: se o slot que esta
-- sendo sobrescrito era falha, tira ele das duas contagens antes de
-- escrever o novo valor por cima.
local function pushDrawWindow(kind)
  local slot = (drawWindowPos % DRAW_WINDOW_SIZE) + 1
  local old = drawWindow[slot]
  if old then
    drawWindowFailures = drawWindowFailures - 1
    drawWindowKindCounts[old] = drawWindowKindCounts[old] - 1
  end
  drawWindow[slot] = kind
  if kind then
    drawWindowFailures = drawWindowFailures + 1
    drawWindowKindCounts[kind] = (drawWindowKindCounts[kind] or 0) + 1
  end
  drawWindowPos = drawWindowPos + 1
end

-- v1.4.2, TwoTracks: registra um desenho bem sucedido (ou um caminho
-- intencional, DEPTH: OFF ou primeira pessoa) na janela.
local function recordDrawResult(kind)
  lastDrawResult = kind
  pushDrawWindow(nil)
end

-- v1.4.2, TwoTracks: registra uma falha de desenho na janela e loga a
-- causa, uma vez por causa DISTINTA (chave = tipo + mensagem), nunca por
-- quadro. Causas diferentes (duas folhas quebradas de jeitos diferentes)
-- logam cada uma a sua vez; a MESMA causa repetindo (a mesma folha ruim
-- toda vez) loga so uma.
local function recordDrawFailure(kind, message)
  lastDrawResult = kind
  pushDrawWindow(kind)
  local causeKey = kind .. ": " .. tostring(message)
  if not warnedDrawCauses[causeKey] then
    warnedDrawCauses[causeKey] = true
    mod.log:warn("voxel mesh %s: %s", kind, tostring(message))
  end
end

local DRAW_FAILURE_KIND_PRIORITY = { "mask_failed", "build_failed", "exception" }

-- v1.4.2, pente fino (item 2): a causa DOMINANTE da janela, nao a mais
-- recente. So troca o melhor candidato quando a contagem e estritamente
-- maior, entao um empate desempata pela ordem fixa acima (deterministico),
-- nunca pela ordem em que as falhas chegaram.
local function dominantFailureKind()
  local bestKind, bestCount = nil, 0
  for _, kind in ipairs(DRAW_FAILURE_KIND_PRIORITY) do
    local count = drawWindowKindCounts[kind] or 0
    if count > bestCount then
      bestKind, bestCount = kind, count
    end
  end
  return bestKind
end

local function warnReplacedMesh()
  if warnedReplacedMesh then return end
  warnedReplacedMesh = true
  mod.log:warn("SpriteBillboards.mesh is no longer the function this mod " ..
    "installed; another mod replaced it after patching")
end

local STATUS_FAILURE_LABELS = {
  mask_failed = "MASK ERROR",
  build_failed = "BUILD ERROR",
  exception = "DRAW ERROR",
}

-- v1.4.2, AngelusRole/Tyler Durden/TwoTracks: a row de STATUS existe porque
-- nenhum dos tres reports tinha como saber, olhando o jogo, por que os
-- personagens nao estavam desenhando voxel. Ordem de precedencia (Kim): NO
-- HOST e REPLACED primeiro, sao estados do patch e valem para todo desenho;
-- DEPTH: OFF e primeira pessoa por leitura de estado ao vivo, porque sao
-- escolhas uniformes que valem para o quadro inteiro, nao por sprite; so
-- depois a proporcao de falha na janela deslizante dos ultimos
-- DRAW_WINDOW_SIZE desenhos, que so escala para um erro quando METADE OU
-- MAIS da janela e falha (item C: uma folha ruim isolada, ou intercalada
-- com folhas boas, nao pode deixar o STATUS preso em erro).
local function statusValue()
  -- v1.4.2, pente fino: `patched`, nunca `SpriteBillboards ~= nil`. Um
  -- patch que comecou mas nao terminou (tabela do host recusou uma
  -- escrita) nunca chega a marcar `patched`, entao isto ainda le NO HOST
  -- em vez de REPLACED, mesmo que `SpriteBillboards` tivesse sido setada
  -- cedo demais numa versao anterior deste codigo.
  if not patched then return "NO HOST" end
  if SpriteBillboards.mesh ~= installedMesh then
    warnReplacedMesh()
    return "REPLACED"
  end
  if (depthValue or readDepth()) == "off" then return "OFF" end
  -- Intencional, nao defeito: um solido nao herda o contrato de billboard
  -- cilindrico da primeira pessoa, entao devolvemos o card original de
  -- proposito enquanto isto for verdade (main.lua, firstPersonCardActive).
  if firstPersonCardActive() then return "FIRST PERSON" end
  if drawWindowFailures * 2 >= DRAW_WINDOW_SIZE then
    return STATUS_FAILURE_LABELS[dominantFailureKind()] or "ACTIVE"
  end
  return "ACTIVE"
end

local function statusRow()
  return {
    id = mod.id .. ":status",
    label = "STATUS",
    value = statusValue,
  }
end

-- v1.4.2: registrado SEMPRE, com ou sem host (Colonel_Aureliano perdeu vinte
-- minutos numa reinstalacao limpa, e o Angelus achou que era o Wilds of
-- Kanto, porque sem host a row nem aparecia). Sem host, so a row de STATUS
-- (dizendo NO HOST); com host, STATUS no topo e as rows de sempre depois,
-- na mesma ordem.
local function registerOptionsRows()
  if optionsRegistered then return end
  optionsRegistered = true
  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    out[#out + 1] = statusRow()
    if patched then
      out[#out + 1] = depthRow()
      out[#out + 1] = sideColorRow()
      out[#out + 1] = shapeRow()
      out[#out + 1] = groundShadeRow()
      out[#out + 1] = blinkRow()
      out[#out + 1] = topEdgeRow()
    end
    return out
  end)

  mod.events:on("mod.options_changed", function(payload)
    if payload and payload.mod == mod.id and payload.key == KEY then
      setDepth(payload.value)
    elseif payload and payload.mod == mod.id and payload.key == SIDE_COLOR_KEY then
      setSideColor(payload.value)
    elseif payload and payload.mod == mod.id and payload.key == SHAPE_KEY then
      setShape(payload.value)
    elseif payload and payload.mod == mod.id and payload.key == GROUND_SHADE_KEY then
      setGroundShade(payload.value)
    elseif payload and payload.mod == mod.id and payload.key == BLINK_KEY then
      setBlink(payload.value)
    elseif payload and payload.mod == mod.id and payload.key == TOP_EDGE_KEY then
      setTopEdge(payload.value)
    end
  end)
end

local function voxelMesh(def, frame)
  local depth = depthValue or readDepth()
  if depth == "off" then
    recordDrawResult("off")
    return safeOriginal(def, frame)
  end
  if firstPersonCardActive() then
    recordDrawResult("first_person")
    return safeOriginal(def, frame)
  end
  local sideColor = sideColorValue or readSideColor()
  local shape = shapeValue or readShape()
  local groundShade = groundShadeValue or readGroundShade()
  local topEdge = topEdgeValue or readTopEdge()
  local correction = quantizeCorrection(leanCorrection())
  local okMask, m = pcall(maskFor, def)
  if not (okMask and m) then
    recordDrawFailure("mask_failed",
      okMask and "maskFor found no usable mask for this sprite" or m)
    return safeOriginal(def, frame)
  end
  local baseName = spriteBaseName(def and def.image)
  local key = cacheKey(def, frame, depth, correction, m, sideColor, shape,
    groundShade, topEdge)
  if meshes[key] ~= nil then
    touchMeshKey(key)
  else
    local ok, mesh = pcall(buildSelectedMesh, def, frame, depth, correction,
      m, sideColor, shape, groundShade, baseName, topEdge)
    if ok and mesh then
      meshFailureReasons[key] = nil
    else
      meshFailureReasons[key] = (not ok) and mesh
        or "buildSelectedMesh returned no mesh for this sprite"
    end
    rememberMesh(key, (ok and mesh) or false)
  end
  local mesh = meshes[key]
  if mesh then
    recordDrawResult("ok")
    applyBlinkUv(mesh)
    return mesh
  end
  -- Registra de novo em toda chamada, mesmo quando `mesh` veio do cache
  -- (meshes[key] == false de uma falha anterior): sem isso, so a PRIMEIRA
  -- tentativa entraria na janela deslizante, e uma folha que falha sempre
  -- pareceria ter falhado uma vez so.
  recordDrawFailure("build_failed", meshFailureReasons[key])
  return safeOriginal(def, frame)
end

-- v1.4.2, pente fino (bloqueante): patch atomico. Tudo montado em locais
-- primeiro; as DUAS escritas na tabela do host (as unicas que podem lancar,
-- se essa tabela recusar escrita) rodam antes de qualquer commit de
-- upvalue de modulo. Se qualquer uma lancar, a excecao sobe para o
-- pcall(patch, host) do chamador e NENHUMA upvalue de modulo foi tocada
-- (nem SpriteBillboards, nem installedMesh, nem `patched`), entao o
-- proximo statusValue() ainda le NO HOST. Sem isso, SpriteBillboards podia
-- ficar setada sozinha por uma escrita anterior bem sucedida e o STATUS
-- lia REPLACED por uma substituicao que nunca aconteceu.
--
-- v1.4.2, pente fino (item 1): as duas escritas nao sao uma transacao so;
-- um host cujo __newindex protege so a chave `mesh` (ja existente) e
-- permite chave nova (o jeito mais plausivel de defender uma API publica
-- sem travar extensao) deixa a PRIMEIRA escrita passar e a segunda
-- lancar. Sem desfazer a primeira, __voxelCharactersOriginal fica gravado
-- na tabela do host pra sempre, mesmo com o patch nunca tendo pegado, o
-- que contradiz o README ("does not modify the Voxel Mod"). Se a segunda
-- lancar, a primeira e desfeita: se __voxelCharactersOriginal ja existia
-- antes (repatch de verdade), o valor anterior volta; se nao existia,
-- volta pra nil, exatamente como estava.
local function patch(host)
  local handle = host.handle
  local V = handle.exports.lib
  local spriteBillboards = host.modules.SpriteBillboards
  local voxel3D = host.modules.Voxel3D
  local imageCache = host.modules.ImageCache
  local okVoxel, voxel = pcall(V.require, "VoxelState")
  local voxelState = okVoxel and voxel or nil
  local okFirst, first = pcall(V.require, "FirstPerson")
  local firstPerson = okFirst and first or nil
  local okScene, scene = pcall(V.require, "VoxelScene")
  local voxelScene = okScene and scene or nil

  warnChainedMesh(spriteBillboards)
  local previousOriginal = spriteBillboards.__voxelCharactersOriginal
  local original = previousOriginal or spriteBillboards.mesh
  local installed = function(def, frame)
    local ok, mesh = pcall(voxelMesh, def, frame)
    if ok then return mesh end
    recordDrawFailure("exception", mesh)
    return safeOriginal(def, frame)
  end
  -- Escritas arriscadas. Nenhum commit de upvalue antes das duas terem
  -- sucesso.
  spriteBillboards.__voxelCharactersOriginal = original
  local okMesh, meshErr = pcall(function()
    spriteBillboards.mesh = installed
  end)
  if not okMesh then
    -- Desfaz a primeira escrita: `spriteBillboards[k] = v` nunca invoca
    -- __newindex para uma chave que ja tem valor bruto (a que acabamos de
    -- gravar), entao esta atribuicao passa direto por rawset mesmo numa
    -- tabela cujo __newindex bloqueia chave nova, sem precisar do builtin
    -- `rawset` explicito. Em pcall porque desfazer e melhor esforco: o
    -- erro que importa pro chamador e o da segunda escrita, nao o do
    -- rollback.
    pcall(function()
      spriteBillboards.__voxelCharactersOriginal = previousOriginal
    end)
    error(meshErr, 0)
  end

  -- Commit: so chega aqui se as duas escritas acima nao lancaram.
  Voxel3D = voxel3D
  ImageCache = imageCache
  SpriteBillboards = spriteBillboards
  VoxelState = voxelState
  FirstPerson = firstPerson
  VoxelScene = voxelScene
  originalMesh = original
  installedMesh = installed
  patched = true
  registerOptionsRows()
  mod.log:info("patched %s character billboards", host.name)
end

local function hostIds()
  local ids = {}
  for i, host in ipairs(HOSTS) do ids[i] = host.id end
  return table.concat(ids, ", ")
end

-- DECISAO v1.4.2: decidir por capacidade, nao por numero de versao. Medido
-- antes desta mudanca: "banana" (versao ilegivel) era ACEITO e "1.3.1"
-- (versao legivel, mas fora da faixa, com a API inteira presente) era
-- RECUSADO, o oposto do que faz sentido. Existem tres linhagens do host
-- versionando de forma independente e caotica (1.6.2.ST com sufixo que o
-- Semver nao le; v1.68 que parseia como 1.68.0 e por isso fica "maior" que
-- 1.7.6; e o manifesto de uma release podendo dizer uma versao enquanto o
-- proprio codigo interno diz outra). Um portao de versao sobre isso erra de
-- novo a cada lancamento novo, e cada erro custa uma versao inteira em que
-- o mod nao faz nada para quem migrou. A partir de agora a versao nunca
-- recusa um host: ela e so informacao, logada sempre, e um aviso quando
-- esta fora da faixa conhecida.
local REQUIRED_MODULES = { "Voxel3D", "ImageCache", "SpriteBillboards" }

-- Sonda de capacidade: um host e utilizavel quando exports.lib existe e
-- devolve os tres modulos obrigatorios, e SpriteBillboards.mesh e uma
-- funcao. Os tres opcionais (VoxelState, FirstPerson, VoxelScene) continuam
-- opcionais, tratados em patch(). pcall em cada require porque um host que
-- passe no id mas nao tenha um dos modulos obrigatorios (ou cujo require
-- estoure) tem que ser recusado limpo, sem derrubar o carregamento do mod
-- inteiro (mesma classe de defeito da rodada 2).
local function probeHost(handle)
  if not (handle.exports and handle.exports.lib) then
    return nil, "exports.lib is missing"
  end
  local V = handle.exports.lib
  local modules = {}
  for _, name in ipairs(REQUIRED_MODULES) do
    local ok, required = pcall(V.require, name)
    if not ok or required == nil then
      return nil, name .. " is missing"
    end
    modules[name] = required
  end
  if type(modules.SpriteBillboards.mesh) ~= "function" then
    return nil, "SpriteBillboards.mesh is not a function"
  end
  return modules
end

local function findHost()
  local rejected = {}
  for _, host in ipairs(HOSTS) do
    local handle = mod.find(host.id)
    if not handle then
      rejected[#rejected + 1] = host.id .. ": not found"
    else
      local modules, why = probeHost(handle)
      if modules then
        local okVersion, versionWhy = Semver.satisfies(handle.version, host.supported)
        if not okVersion then
          mod.log:warn(
            "found %s %s (%s) with an untested version (checked against %s: %s); " ..
            "continuing because the required API is present",
            host.name, tostring(handle.version), host.id, host.supported,
            tostring(versionWhy or "does not satisfy the range"))
        end
        return {
          id = host.id,
          name = host.name,
          supported = host.supported,
          handle = handle,
          modules = modules,
        }
      end
      rejected[#rejected + 1] = ("%s: found %s but %s")
        :format(host.id, tostring(handle.version), why)
    end
  end
  return nil, table.concat(rejected, "; ")
end

local host, hostRejects = findHost()
if not host then
  mod.log:warn("could not find usable Voxel Characters host; checked %s: %s",
    hostIds(), hostRejects)
  registerOptionsRows()
  return
end

local handle = host.handle
mod.log:info("found %s %s (%s)", host.name, tostring(handle.version), host.id)

local ok, err = pcall(patch, host)
if not ok then
  mod.log:warn("could not patch %s character billboards: %s", host.name, tostring(err))
  registerOptionsRows()
end
