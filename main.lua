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
-- REFATORACAO (locais do chunk principal): main.lua chegou a 199 locais
-- contra o teto de 200 do LuaJIT (LUAI_MAXVARS) porque cada opcao de menu
-- trazia consigo um punhado de locais proprios no topo do arquivo (chave,
-- valores, rotulos, default, indice do default, a variavel de estado, e
-- quatro funcoes: indexOf/read/set/row). Sete opcoes depois o orcamento
-- tinha acabado e a proxima nao coube: erro de COMPILACAO, nao de
-- comportamento, porque o mod inteiro deixa de carregar.
--
-- A partir de agora existe UMA tabela de descricao de opcao (OPTIONS,
-- logo abaixo) e funcoes genericas que operam sobre qualquer entrada dela
-- (optionIndexOf/readOption/setOption/makeOptionRow, mais adiante), mais UM
-- local de estado (optionState, uma tabela indexada pela chave da opcao) no
-- lugar da variavel de estado dedicada de cada opcao. Acrescentar uma opcao
-- nova e acrescentar uma entrada nesta tabela: nenhum local novo no chunk
-- principal.
--
-- Cada entrada usa o mesmo formato de pares { ROTULO, valor } que STEP
-- WEIGHT ja usava sozinho antes desta rodada (o campo `levels` abaixo):
-- serve tanto para valores numericos com rotulo separado (FRONT SHAPE:
-- { "LOW", 0.12 }) quanto para strings (SIDE COLOR: { "BODY", "body" }),
-- sem caso especial. `defaultIndex` aponta a posicao default dentro de
-- `levels` (TOP EDGE e a unica que nao comeca na posicao 1: default ON,
-- ver comentario na propria entrada). `clears` diz o que `setOption` limpa
-- quando o valor muda: "full" (so DEPTH, que tambem invalida `masks`),
-- "mesh" (a maioria, que so precisa reconstruir a malha), ou omitido
-- (BLINK, que nunca limpa cache: e aplicado por malha a cada desenho em
-- applyBlinkUv, nao assado na geometria).
local OPTIONS = {
  {
    key = "depth",
    label = "VOXEL CHARS",
    levels = {
      { "OFF", "off" }, { "1", 1 }, { "2", 2 },
      { "3", 3 }, { "5", 5 }, { "10", 10 },
    },
    defaultIndex = 4, -- posicao de 3
    help = "Extrudes overworld character sprites. Depth 1-5 stays inside the voxel pull budget; 10 may clip into walls.",
    clears = "full",
  },
  {
    key = "side_color",
    label = "SIDE COLOR",
    levels = { { "BODY", "body" }, { "OUTLINE", "outline" } },
    defaultIndex = 1,
    help = "Colors new side, top, and bottom faces from body pixels or keeps the original outline pixels.",
    clears = "mesh",
  },
  {
    key = "shape",
    label = "SHAPE",
    levels = {
      { "SLAB", "slab" }, { "CARVED", "carved" }, { "CARVED+", "carved_plus" },
    },
    defaultIndex = 1,
    -- OS TRES NAO SAO UMA ESCADA DE QUALIDADE, e o menu vinha sugerindo que sao.
    --
    -- Medido no red frame 0: SLAB tem 104 quads, dos quais 16 sao de topo.
    -- CARVED tem 1068, dos quais 216 sao de topo. Treze vezes mais superficie
    -- virada para cima, e superficie de topo e por definicao superficie que o
    -- artista nunca desenhou. Nesta camera, que olha de cima, e justamente ela
    -- que o jogador ve.
    --
    -- Isso nao e ajuste, e a lei que explica as tres tentativas de profundidade
    -- variavel que ja morreram aqui (relevo por tom, mapa por IA, profundidade
    -- por linha): toda variacao de profundidade cria degrau, todo degrau expoe
    -- topo, e topo nao carrega arte.
    --
    -- O que o CARVED compra em troca e silhueta correta de QUALQUER angulo. Num
    -- jogo que gira a camera isso e tudo; neste, que nunca gira em yaw, e um
    -- beneficio que a camera nunca cobra. Entao ele nao e o modo melhor nem o
    -- pior: e o modo independente de camera, e e o unico dos dois que produz um
    -- volume de verdade, que e o que serviria de base para qualquer coisa fora
    -- deste jogo.
    help = "SLAB keeps the artist's front face flat and whole, which is what this game's camera looks at. CARVED builds real volume from three views: correct from any angle, but it trades the art for stair steps here. CARVED+ adds tone relief to CARVED.",
    clears = "mesh",
  },
  {
    key = "ground_shade",
    label = "GROUND SHADE",
    levels = { { "OFF", "off" }, { "ON", "on" } },
    defaultIndex = 1,
    help = "Adds the host-style contact shade to the lowest six pixels of the solid character mesh.",
    clears = "mesh",
  },
  {
    key = "blink",
    label = "BLINK",
    levels = { { "OFF", "off" }, { "ON", "on" } },
    -- DECISAO DO KIM, 2026-08-09: ligado por padrao. A regra da casa e que toda
    -- mudanca visual nova nasce desligada, e ela continua valendo para o que e
    -- NOVO. Piscar nao e novo: saiu na v1.4.0, a comunidade usou e gostou, e
    -- ninguem reportou que incomoda. O default conservador existe para nao
    -- surpreender quem instala; depois que a feature foi vista e aprovada, o
    -- conservador passa a ser entregar o que as pessoas ja escolheriam.
    defaultIndex = 2,
    help = "Animates front-facing overworld eyes by swapping their UVs to nearby skin texels.",
  },
  {
    key = "top_edge",
    label = "TOP EDGE",
    levels = { { "OFF", "off" }, { "ON", "on" } },
    -- DECISAO v1.4.2: OFF nao e neutro. Com SIDE COLOR: BODY, a face de
    -- topo da linha mais alta pode buscar a cor do corpo abaixo e pintar
    -- uma tampa clara acima do contorno escuro, como no bone do Red. TOP
    -- EDGE ligado por padrao nao adiciona efeito: remove esse defeito de
    -- leitura e preserva uma quina escura ajustavel para quem quiser
    -- voltar ao host shade puro.
    defaultIndex = 2, -- "on"
    help = "Darkens only exposed SLAB top faces for a false top-down edge.",
    clears = "mesh",
  },
  {
    key = "front_shape",
    label = "FRONT SHAPE",
    -- DECISAO v1.6.0: os tres niveis sao forca de sombreamento em degraus
    -- na face frontal, nao contagem de poligonos. A geometria (posicao de
    -- vertice, logo IoU e contagem de quads) e identica para qualquer
    -- forca > 0: emitFrontRun so usa a forca para escalar o multiplicador
    -- de shade de cada degrau, nunca a posicao de um vertice. 0.12 e o
    -- valor medido e validado por Kim (IoU 1.000 contra o card plano em
    -- red, blue, snorlax, poke_ball e nurse, frames 0-5; 259 quads no
    -- red.png frame 0, dentro do orcamento de 300) e e o primeiro nivel
    -- ligado. 0.22 tambem foi medido e ja "pesa demais" na leitura do Kim,
    -- mas fica disponivel como teto para quem preferir mais contraste.
    -- 0.17 (MED) e o ponto medio entre os dois extremos medidos: como a
    -- geometria independe da magnitude da forca, os dois numeros medidos
    -- ja cobrem esse terceiro nivel por construcao, sem exigir uma rodada
    -- extra de render.
    levels = {
      { "OFF", "off" }, { "LOW", 0.12 }, { "MED", 0.17 }, { "HIGH", 0.22 },
    },
    defaultIndex = 1,
    help = "Steps the SLAB front face into three pixel aligned shade tones toward each run's edges, for false roundness without a gradient.",
    clears = "mesh",
  },
  {
    key = "top_dome",
    label = "TOP DOME",
    -- DECISAO v1.6.0: TOP DOME segue o mesmo mecanismo de FRONT SHAPE
    -- (degraus de shade por posicao no run, a forca so escala o
    -- multiplicador de cada degrau, nunca a posicao de um vertice), mas
    -- com dois niveis, nao tres: so 0.15 e 0.30 foram medidos (IoU 1.000
    -- contra o card plano em red, blue, snorlax, poke_ball e nurse, frames
    -- 0-5; contagem de quads identica a com a opcao desligada em qualquer
    -- forca) e a cintilacao entre poses, o risco pre-registrado, nao
    -- apareceu no gate. Ao contrario de FRONT SHAPE, nao ha um MED
    -- interpolado aqui: a spec desta rodada so deu os dois pontos
    -- medidos, e um terceiro nivel sem medicao seria chute.
    levels = { { "OFF", "off" }, { "LOW", 0.15 }, { "HIGH", 0.30 } },
    -- Regra da casa: toda opcao de menu nova comeca com um default
    -- conservador. TOP DOME muda uma leitura visual estabelecida (a tampa
    -- chapada) e nao foi lancada ainda, entao OFF, como FRONT SHAPE.
    defaultIndex = 1,
    help = "Steps the SLAB top face into pixel aligned shade tones toward each run's edges, for a domed cap instead of a flat one.",
    clears = "mesh",
  },
  {
    key = "step_weight",
    label = "STEP WEIGHT",
    -- DECISAO: STEP WEIGHT desloca VERTICE (cisalhamento em Z), nao shade,
    -- entao ao contrario de FRONT SHAPE/TOP DOME a magnitude muda
    -- geometria de verdade, na formula z = z + forca * (y / cellH). Essa
    -- formula e linear na forca por construcao: nenhum degrau, nenhum
    -- quantizador, so uma multiplicacao. Kim mediu o deslocamento de tela
    -- numa celula de 300px em tres pontos (lean 0: +8px, so a arte; +0.5:
    -- +13px; -0.5: +3px) e a silhueta a pitch 0 (IoU 1.000) em CINCO
    -- pontos, -1.0 a +1.0, cobrindo folgadamente a faixa usada aqui. 0.5 e
    -- o teto medido e tambem o teto que Kim julgou como o limite antes do
    -- personagem parecer agachar em vez de andar (palpite dele, nao
    -- contrariado por nenhuma medicao nova: a formula linear nao da
    -- motivo para uma virada nao linear entre 0.25 e 0.5). 0.25 e
    -- exatamente a metade dessa forca; a mesma linearidade que garante
    -- metade do deslocamento medido garante metade do caminho ate
    -- qualquer efeito colateral, sem exigir uma malha nova pra confirmar.
    -- So o sinal positivo vira nivel: negativo achata o passo, um efeito
    -- diferente e fora do escopo desta rodada.
    levels = { { "OFF", "off" }, { "LOW", 0.25 }, { "HIGH", 0.5 } },
    -- Regra da casa outra vez: STEP WEIGHT desloca vertice pela primeira
    -- vez nesta branch (FRONT SHAPE e TOP DOME so mexem em shade), entao o
    -- conservadorismo do default OFF vale ainda mais aqui.
    defaultIndex = 1,
    help = "Shears the SLAB mesh toward the camera on walking frames only, proportional to height, so the solid's weight trails the art's own step.",
    clears = "mesh",
  },
  -- ------------------------------------------------------------------ VIDA
  -- As tres opcoes abaixo NAO tocam em malha. Elas pos-multiplicam a MATRIZ
  -- que o host monta por personagem por quadro, dentro do nosso wrap de
  -- Voxel3D.draw. Por isso nao tem `clears`: a geometria cacheada continua
  -- valendo, e trocar de nivel tem efeito no quadro seguinte.
  --
  -- Por que matriz e nao vertice: a malha e criada com dica "static"
  -- (Voxel3D.newMesh) e COMPARTILHADA por todas as instancias da mesma folha.
  -- Reescrever vertice todo quadro seria o mau uso que a dica existe para
  -- evitar, e faria dois NPCs iguais respirarem em unissono. A matriz chega
  -- recem alocada por instancia (medido: tools/ingame/probe_draw.lua, oito
  -- propriedades, todas passaram), entao ela e o canal certo.
  {
    key = "breath",
    label = "BREATH",
    -- Escala em Y em torno dos PES. O pivo ja esta nos pes por construcao da
    -- matriz do host, e S(1,s,1) comuta com o espelho e com o T(-8,0,0)
    -- local, entao pos-multiplicar a matriz final da exatamente "o corpo
    -- estica para cima a partir do chao" (conferido na algebra e confirmado
    -- por revisao externa independente).
    --
    -- Os numeros sao fracao da altura: a folha tem 16 px de altura, entao
    -- 0.010 desloca o topo da cabeca em 0.16 px de mundo. Default OFF pela
    -- regra da casa: toda mudanca visual nova entra como opcao desligada.
    levels = {
      { "OFF", "off" }, { "SUBTLE", 0.010 }, { "NORMAL", 0.020 },
      { "STRONG", 0.035 },
    },
    -- DECISAO DO KIM, 2026-08-09: ligado por padrao, no nivel MAIS BAIXO.
    --
    -- E a primeira vez que este mod entrega movimento sem ninguem pedir, entao
    -- vale registrar o que sustenta a escolha. SUBTLE desloca a cabeca em 0.16
    -- px de mundo, menos de um pixel de tela na camera do jogo; o custo do
    -- canal inteiro ficou abaixo do piso de ruido da regua; e o efeito some
    -- sozinho num host sem o canal, sem quebrar nada. O que ele compra e a
    -- ausencia da sensacao de estatua, que e o motivo de o mod existir.
    --
    -- SUBTLE e nao NORMAL de proposito: o default certo para uma coisa que a
    -- pessoa nao escolheu e o menor que ainda faz diferenca.
    defaultIndex = 2,
    help = "Breathes the solid by scaling it vertically from the feet, out of phase per character, so a room of NPCs stops reading as frozen.",
  },
  {
    key = "sway",
    label = "SWAY",
    -- Cisalhamento em X proporcional a altura: x' = x + k*(y/cellH). Os pes
    -- ficam cravados (y=0) e a cabeca desloca k px. O sinal e invertido
    -- quando a folha esta espelhada, senao o balanco viraria de lado junto
    -- com o personagem.
    levels = { { "OFF", "off" }, { "SUBTLE", 0.20 }, { "NORMAL", 0.45 } },
    defaultIndex = 1,
    help = "Sways the solid side to side from the feet, at half the breath rate and its own phase, for idle weight shift.",
  },
  {
    key = "lag",
    label = "MOTION LAG",
    -- Inercia. Uma mola de segunda ordem por instancia persegue a velocidade do
    -- personagem e cisalha o corpo NA DIRECAO CONTRARIA, proporcional a altura,
    -- com passagem do ponto quando ele para.
    --
    -- O QUE ISTO NAO E, e a honestidade importa aqui porque o nome engana
    -- facil: nao e movimento secundario por parte. Uma matriz transforma a
    -- malha inteira de um jeito so; ela nao consegue segurar a mochila
    -- enquanto o tronco acompanha o passo. Revisao externa foi direta nesse
    -- ponto e esta certa. O que sai daqui e o CORPO TODO inclinando a partir
    -- dos pes, que le como peso e inercia, nao como cabelo esvoacando.
    --
    -- Movimento secundario de verdade exige submalha por regiao (corpo,
    -- cabeca, mochila) desenhada com matriz propria. Isso NAO esta feito, e
    -- esta escrito assim no roadmap para ninguem achar que esta.
    -- Os numeros sao deslocamento da CABECA em pixels de mundo na velocidade de
    -- caminhada, a mesma unidade de SWAY. A mola passa do ponto em cerca de 8%,
    -- entao o pico real fica um pouco acima do nivel escolhido.
    levels = { { "OFF", "off" }, { "SUBTLE", 0.6 }, { "NORMAL", 1.2 } },
    defaultIndex = 1,
    help = "Leans the whole solid back from its feet with a spring while it moves, and overshoots when it stops, so the body carries weight instead of sliding.",
  },
  {
    key = "footfall",
    label = "FOOTFALL",
    -- ACHATA NO IMPACTO DO PASSO e estica no meio dele, mantendo o volume:
    -- o corpo baixa e alarga quando o pe bate, sobe e afina quando o passo
    -- passa pelo alto. E a transferencia de peso que a arte do ciclo de
    -- caminhada ja implica, levada para o solido sem separar perna nenhuma.
    --
    -- A FASE vem da DISTANCIA percorrida, nao do frame do sprite. O jogo anda
    -- 16 px por passo, entao cada 16 px e uma pisada, e isso vale igual para o
    -- jogador, para NPC perambulando e para quem estiver de bicicleta (que so
    -- muda quantos quadros o passo leva, nunca quantos pixels ele tem).
    --
    -- A AMPLITUDE vem da velocidade suavizada, entao o efeito nasce e morre
    -- sozinho quando o personagem comeca e para de andar. Sem isso seria
    -- preciso um booleano "esta andando", que ligaria e desligaria de estalo no
    -- meio de uma escala e apareceria como um tranco.
    --
    -- Os numeros sao o achatamento maximo em pixels de mundo, a mesma unidade
    -- de SWAY e MOTION LAG.
    levels = { { "OFF", "off" }, { "SUBTLE", 0.35 }, { "NORMAL", 0.7 } },
    defaultIndex = 1,
    help = "Squashes the solid on each footfall and stretches it at the top of the step, so the walk cycle's weight transfer reaches the body.",
  },
  {
    key = "first_person",
    label = "FIRST PERSON",
    levels = { { "CARD", "card" }, { "SOLID", "solid" } },
    defaultIndex = 1,
    -- POR QUE ISTO EXISTE, E POR QUE SO AGORA.
    --
    -- Desde a v1.3.0 este mod devolve o card plano sempre que
    -- FirstPerson.cardBlend() > 0. Nao foi preguica, foi conserto: o
    -- Colonel_Aureliano reportou espetos pretos com Dramatic Shape 1.7.0 mais
    -- Kanto First Person, e o card plano nao tem o defeito.
    --
    -- Lendo o host, o mecanismo e este e nao e "primeira pessoa":
    --
    --   o shader move CADA VERTICE ao longo do proprio raio ate o olho, por
    --   `pull` unidades (Voxel3D.lua:122-130);
    --   primeira pessoa e o degrau 6, e ANGLES_DEG[7] = 75 graus, entao
    --   VoxelScene.pull(rad 75) = 6 unidades de mundo, com o tile valendo 16;
    --   o near plane fica em max(1, |olho-foco| * 0.05), ou seja 1 unidade
    --   quando olho e foco estao juntos, que e o caso aqui.
    --
    -- Um vertice a distancia d do olho vai parar em d - 6: atravessa o near
    -- plane com d < 7 e passa para TRAS do olho com d < 6. O card plano
    -- sobrevive porque seus vertices estao todos a mesma distancia e cruzam
    -- juntos; num solido os cantos estao a distancias diferentes, os da frente
    -- cruzam primeiro, e o que sobra na tela e o espeto.
    --
    -- ENTAO O DEFEITO E DE PROXIMIDADE, NAO DE CAMERA. O caso catastrofico e o
    -- card do proprio jogador durante a transicao, porque a camera esta
    -- entrando na cabeca dele e d vai a zero; o host so esconde esse card
    -- depois de blend > 0.9, entao toda entrada e toda saida passa pela faixa
    -- quebrada. Um NPC a um tile esta a 16 unidades e nunca chega perto.
    --
    -- Por isso desligar o solido na camera inteira sempre foi grosso demais, e
    -- por isso a correcao mora no wrap de desenho e nao aqui: limitar o `pull`
    -- que a gente repassa tira a travessia do near plane por construcao, sem
    -- abrir mao do volume. Ver fpPullSeguro.
    --
    -- Nasce em CARD pela regra da casa. Que os jogadores tenham pedido conta
    -- como pedido, nao como aprovacao: ninguem viu ainda.
    help = "Keeps characters solid in first person instead of falling back to the flat card. Needs the host's draw channel.",
  },
}

local OPTION_BY_KEY = {}
for _, opt in ipairs(OPTIONS) do
  OPTION_BY_KEY[opt.key] = opt
end

-- As opcoes que dependem do SEGUNDO ponto de patch (Voxel3D.draw). Sem esse
-- canal elas nao aparecem no menu: ver registerOptionsRows.
-- FIRST PERSON entra aqui apesar de nao ser animacao: o que ela promete e o
-- pull limitado, que so existe se a gente conseguir envolver Voxel3D.draw.
-- Oferecer SOLID num host sem esse canal seria oferecer os espetos de volta.
local LIFE_OPTION_KEYS = { breath = true, sway = true, lag = true,
  footfall = true, first_person = true }

-- Sentinela de SIDE COLOR usado por bodyTexelInFrame/blinkBodyTexel (mais
-- abaixo) para decidir se a busca de corpo entra em jogo. Fica como
-- constante propria, fora do sistema de opcoes generico, porque essas duas
-- funcoes ficam no meio da construcao de malha, nao no menu.
local DEFAULT_SIDE_COLOR = "body"
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
-- DECISAO v1.6.0: tres degraus de shade e o mesmo numero de tons que o
-- artista ja usa para volume nos sprites Gen 1 fonte. Um gradiente
-- continuo foi prototipado antes e leu como uma listra brilhante solta por
-- cima da arte, porque arte de pixel duro e degrade suave brigam entre si;
-- shade constante por pixel, quantizado nestes degraus, e o que combina
-- com o resto do desenho.
local FRONT_SHAPE_STEPS = 3
-- Mesmo raciocinio de FRONT_SHAPE_STEPS: tres tons e o que o artista ja usa
-- para volume nos sprites Gen 1 fonte, e degrau alinhado ao pixel, nao
-- gradiente continuo (main.lua, DECISAO acima de FRONT_SHAPE_STEPS).
local TOP_DOME_STEPS = 3
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

-- Gerado a partir de OPTIONS (acima): uma opcao nova ganha `type = "choice"`
-- e os campos `choices`/`default` derivados de `levels`/`defaultIndex` de
-- graca, sem precisar duplicar a tabela aqui.
do
  local schema = {}
  for _, opt in ipairs(OPTIONS) do
    schema[#schema + 1] = {
      key = opt.key,
      type = "choice",
      label = opt.label,
      choices = opt.levels,
      default = opt.levels[opt.defaultIndex][2],
      help = opt.help,
    }
  end
  mod.options:define(schema)
end

local SpriteBillboards, Voxel3D, ImageCache
local VoxelState, FirstPerson, VoxelScene
local originalMesh
local meshes, masks = {}, {}
local meshOrder = {}
-- Estado resolvido de toda opcao, indexado pela chave (opt.key). Substitui
-- as nove variaveis dedicadas de antes (depthValue, sideColorValue, ...):
-- ver a REFATORACAO acima de OPTIONS.
local optionState = {}
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
-- VIDA. `originalDraw` e a Voxel3D.draw do host; `installedDraw` a nossa, para
-- a row de LIFE detectar quem foi substituido depois de nos (mesma logica de
-- installedMesh). `drawPatched` so vira true depois da escrita ter sucesso, e
-- so quando a sonda de capacidade aprovou o canal: um host sem Voxel3D.draw
-- utilizavel perde a animacao e MANTEM o resto do mod funcionando.
local originalDraw, installedDraw, drawPatched = nil, nil, false
-- Malhas que ESTE mod construiu. Chave fraca: quando o LRU solta a malha, a
-- entrada some sozinha. E o unico discriminador exato de "isto e um
-- personagem nosso" dentro do wrap de draw, onde terreno, grama, sombra e
-- pokedex passam pela mesma funcao.
local ourMeshes = setmetatable({}, { __mode = "k" })

-- Genericas: operam sobre qualquer entrada de OPTIONS (opt.levels e um
-- array de pares { ROTULO, valor }, opt.defaultIndex a posicao default
-- nesse array). Substituem os pares indexOf/readX dedicados de cada opcao.
local function optionIndexOf(opt, value)
  for i, level in ipairs(opt.levels) do
    if level[2] == value then return i end
  end
  return opt.defaultIndex
end

local function readOption(opt)
  local ok, value = pcall(mod.options.get, mod.options, opt.key)
  if ok then return opt.levels[optionIndexOf(opt, value)][2] end
  return opt.levels[opt.defaultIndex][2]
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

-- Generica: substitui os nove setX dedicados. `opt.clears` decide o que
-- limpar quando o valor muda (ver comentario de campo em OPTIONS, acima):
-- "full" so para DEPTH (clearCache, que tambem derruba `masks`), "mesh"
-- para a maioria (clearMeshCache, libera as malhas velhas na hora em vez de
-- esperar o LRU reciclar -- o defeito que o Colonel_Aureliano reportou na
-- v1.4.0 quando a opcao mudava no menu sem mudar nada em tela), e nenhum
-- dos dois para BLINK.
local function setOption(opt, value)
  local nextValue = opt.levels[optionIndexOf(opt, value)][2]
  if optionState[opt.key] ~= nextValue then
    if opt.clears == "full" then
      clearCache()
    elseif opt.clears == "mesh" then
      clearMeshCache()
    end
  end
  optionState[opt.key] = nextValue
  return nextValue
end

for _, opt in ipairs(OPTIONS) do
  setOption(opt, readOption(opt))
end
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

-- Generica: substitui os nove rowX dedicados. Mesma forma que cada um
-- tinha (id/label fixos, value() le o rotulo do nivel atual, step() avanca
-- um nivel ciclicamente e passa pelo setOption/writeOption de sempre).
local function makeOptionRow(opt)
  return {
    id = mod.id .. ":" .. opt.key,
    label = opt.label,
    value = function()
      local current = optionState[opt.key] or readOption(opt)
      return opt.levels[optionIndexOf(opt, current)][1]
    end,
    step = function(game, dir)
      local current = optionState[opt.key] or readOption(opt)
      local i = optionIndexOf(opt, current)
      i = ((i + (dir or 1) - 1) % #opt.levels) + 1
      local value = setOption(opt, opt.levels[i][2])
      writeOption(game, opt.key, value)
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
  local closed = (optionState.blink or readOption(OPTION_BY_KEY.blink)) == "on"
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
                             groundShade, baseName, topEdge, frontShape,
                             topDome, stepWeight)
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

  -- FEATURE TOP DOME (v1.6.0): a face de topo ja sai como um quad por pixel
  -- (o ramo `if not at(sx, ly - 1)` mais abaixo), entao variar o shade pela
  -- posicao dentro do run custa ZERO quad extra: e so trocar o valor de
  -- shade que ja ia em cada quad, nunca adicionar um quad novo. Mesmo
  -- mecanismo de FRONT SHAPE: TOP_DOME_STEPS tons constantes, alinhados ao
  -- pixel, escolhidos pela distancia ate a borda do run, nao um gradiente
  -- continuo (esse ja foi prototipado na face frontal e leu como uma
  -- listra brilhante solta por cima da arte). `a` e `b` sao os limites do
  -- run horizontal DESTA linha (lx, lx2 no laco principal), a mesma
  -- referencia que emitFrontRun usa para o proprio degrau: relativos
  -- apenas ao run, nunca a uma coordenada absoluta de tela, o que garante
  -- a simetria em X exigida (o run espelha junto com o personagem, e o
  -- shade espelha junto com ele). `base` vem de topShade(), entao TOP EDGE
  -- e TOP DOME convivem por construcao: o degrau do domo e sempre um
  -- multiplicador APLICADO SOBRE a base do TOP EDGE, nunca no lugar dela;
  -- ligar um nao anula o outro.
  local domoStep = tonumber(topDome) or 0
  local function topShadeDomo(sx, a, b)
    local base = topShade()
    -- Runs com menos de 3 pixels nao tem um pixel "do meio" distinto das
    -- duas bordas: nao ha degrau possivel, entao ficam no shade constante
    -- de sempre, igual a opcao desligada.
    if domoStep <= 0 or b - a < 2 then return base end
    local center = (a + b) / 2
    local half = (b - a) / 2
    local t = math.abs(sx - center) / half
    local level = math.floor(t * (TOP_DOME_STEPS - 0.001))
    return base * (1 - domoStep * level / (TOP_DOME_STEPS - 1))
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

  -- FEATURE STEP WEIGHT (v1.6.0): cisalhamento em Z proporcional a altura,
  -- so nos frames de caminhada. Em Z de proposito: a pitch 0, a camera do
  -- gate de conformidade, o eixo Z aponta para a camera, entao mexer nele
  -- nao muda silhueta (Kim mediu IoU 1.000 em -1.0, -0.5, 0, +0.5 e +1.0).
  -- Na camera do jogo, que olha de cima, o mesmo deslocamento em Z aparece
  -- na vertical depois da rotacao de `correction` que `p()` ja aplicava.
  -- Nada em X: o espelho do host nunca ve esta opcao.
  --
  -- "Frame de caminhada" e derivado do mesmo bucket que carvedFrames ja usa
  -- para CARVED (main.lua, funcao carvedFrames abaixo), nao os literais 3,
  -- 4 e 5 chutados: um frame acima de 5 dobra em bucket de 3 (frame % 3),
  -- igual roleForFrame, e so entra no bucket "andando" (posicao 3) quando a
  -- folha de fato tem seis frames. Isso cobre por construcao a restricao
  -- "folhas com menos frames nao tem pose de caminhada": com m.frames < 6,
  -- bucketFrame nunca chega a 3 dentro do intervalo valido de frame (ja
  -- normalizado para [0, m.frames) no topo desta funcao), entao `andando`
  -- fica falso e nenhuma folha de 1 ou 3 frames estoura.
  local stepWeightForce = tonumber(stepWeight) or 0
  local bucketFrame = frame
  if bucketFrame > 5 then bucketFrame = bucketFrame % 3 end
  local andando = bucketFrame >= 3 and m.frames >= 6
  local stepWeightZ = andando and stepWeightForce or 0

  local function p(x, y, z)
    -- Zero exato quando a opcao esta desligada ou o frame nao e de
    -- caminhada: soma de 0.0 preserva o valor de z bit a bit, entao a
    -- malha continua identica a de hoje nesses dois casos.
    if stepWeightZ ~= 0 then z = z + stepWeightZ * (y / m.cellH) end
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
  -- FRONT SHAPE (v1.6.0): forca constante para a malha inteira, lida uma
  -- unica vez fora do laco. "off" vira 0 (tonumber("off") == nil), o mesmo
  -- branch do quad unico de sempre dentro de emitFrontRun; qualquer forca >
  -- 0 liga o escalonamento em degraus.
  local frontStep = tonumber(frontShape) or 0

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
        -- FEATURE FRONT SHAPE (v1.6.0): degraus alinhados ao pixel na face
        -- frontal, no lugar do shade constante de sempre, quando a opcao
        -- esta ligada. Um gradiente continuo foi prototipado antes disto e
        -- leu como uma listra brilhante solta por cima da arte (arte de
        -- pixel duro e degrade suave brigam entre si); aqui cada pixel do
        -- run recebe um shade CONSTANTE, escolhido entre FRONT_SHAPE_STEPS
        -- niveis pela distancia ate a borda do run, do mesmo jeito que o
        -- artista ja faz volume nos sprites fonte.
        --
        -- CORRECAO (pente fino de olho novo): `runCenter` e `runHalf` vem
        -- do RUN INTEIRO (`lx`, `lx2`), nunca do segmento `a..b` que
        -- `emitFrontRun` recebe. Um olho no meio do run corta a CHAMADA em
        -- pedacos (o laco `isEye` logo abaixo), mas nao corta o run: o
        -- pixel do olho continua opaco e dentro de `lx..lx2`. Medir contra
        -- o segmento fazia cada pedaco tratar a propria ponta, colada no
        -- olho, como se fosse a borda real da silhueta, entao esse pixel
        -- saia no mesmo tom escuro da borda verdadeira: um anel escuro em
        -- volta de cada olho, em qualquer folha com marca de olho
        -- (`EYE_MARKS`/`EYE_SIDE_MARKS`) e independente da opcao BLINK,
        -- porque o corte por `isEye` nunca consulta o estado de BLINK. `lx` e
        -- `lx2` espelham juntos como o resto do run, entao a simetria em X
        -- exigida continua garantida por construcao: nunca uma coordenada
        -- absoluta de tela, sempre os limites do proprio run.
        local runCenter = (lx + lx2) / 2
        local runHalf = (lx2 - lx) / 2
        local function emitFrontRun(a, b)
          if a > b then return end
          -- Sem degrau possivel quando a opcao esta desligada OU o RUN
          -- INTEIRO, nao o segmento, tem menos de 3 pixels: nao ha um
          -- pixel "do meio" distinto das duas bordas reais. Um segmento
          -- curto colado num olho, dentro de um run largo, ainda precisa
          -- do degrau: por isso a guarda olha `lx2 - lx`, nao `b - a`.
          if frontStep <= 0 or lx2 - lx < 2 then
            local rx, rw = a, b - a + 1
            quad(p(rx, y, z1), p(rx + rw, y, z1),
                 p(rx + rw, y + 1, z1), p(rx, y + 1, z1),
                 rectUv(a, ly, b), OBJ_SHADE.front)
            return
          end
          for sx = a, b do
            local t = math.abs(sx - runCenter) / runHalf
            local level = math.floor(t * (FRONT_SHAPE_STEPS - 0.001))
            local sh = OBJ_SHADE.front
              * (1 - frontStep * level / (FRONT_SHAPE_STEPS - 1))
            quad(p(sx, y, z1), p(sx + 1, y, z1),
                 p(sx + 1, y + 1, z1), p(sx, y + 1, z1),
                 rectUv(sx, ly, sx), sh)
          end
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
                 verticalUv(sx, ly, 1), topShadeDomo(sx, lx, lx2))
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
                                 groundShade, baseName, topEdge, frontShape,
                                 topDome, stepWeight)
  if shape == "carved" or shape == "carved_plus" then
    local ok, mesh = pcall(buildCarvedMesh, def, frame, depth, correction, m,
      sideColor, shape, groundShade)
    if ok and mesh then return mesh end
  end
  return buildSlabMesh(def, frame, depth, correction, m, sideColor, groundShade,
    baseName, topEdge, frontShape, topDome, stepWeight)
end

-- FRONT SHAPE, TOP DOME e STEP WEIGHT, como TOP EDGE, so existem para SLAB:
-- CARVED/CARVED+ constroem a partir do casco visual em voxels, sem o run
-- frontal continuo que emitFrontRun escalona, sem o run de topo que
-- topShadeDomo le, e sem o `p()` que aplica o cisalhamento de STEP WEIGHT.
-- Fora do SLAB, a chave ignora a forca de proposito, para nao duplicar
-- malhas identicas so porque o menu trocou de nivel.
local function cacheKey(def, frame, depth, correction, layout, sideColor, shape,
                        groundShade, topEdge, frontShape, topDome, stepWeight)
  local depthPart = (shape == "carved" or shape == "carved_plus") and "art"
    or tostring(depth)
  local topEdgePart = shape == "slab" and tostring(topEdge or "") or ""
  local frontShapePart = shape == "slab" and tostring(frontShape or "") or ""
  -- A chave PRECISA incluir a forca do domo, mesmo padrao de FRONT SHAPE:
  -- sem isso, mexer no menu nao muda nada na tela ate o LRU reciclar por
  -- acaso, exatamente o defeito que o Colonel_Aureliano reportou na v1.4.0.
  local topDomePart = shape == "slab" and tostring(topDome or "") or ""
  -- Mesma exigencia da spec desta rodada ("a chave de cache precisa incluir
  -- a forca"), mesmo motivo de TOP DOME logo acima.
  local stepWeightPart = shape == "slab" and tostring(stepWeight or "") or ""
  return table.concat({
    tostring(def and def.image or ""),
    tostring(def and def.frames or ""),
    tostring(frame or 0),
    depthPart,
    tostring(sideColor or ""),
    tostring(shape or ""),
    tostring(groundShade or ""),
    topEdgePart,
    frontShapePart,
    topDomePart,
    stepWeightPart,
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
  if (optionState.depth or readOption(OPTION_BY_KEY.depth)) == "off" then return "OFF" end
  -- Intencional, nao defeito: em CARD devolvemos o card original de proposito
  -- em primeira pessoa (ver a opcao first_person e fpPullSeguro). Em SOLID
  -- nada disso acontece e a linha nao deve mentir dizendo que aconteceu.
  if firstPersonCardActive() then
    local fp = optionState.first_person or readOption(OPTION_BY_KEY.first_person)
    if fp ~= "solid" or installedDraw == nil then return "FIRST PERSON" end
  end
  if drawWindowFailures * 2 >= DRAW_WINDOW_SIZE then
    return STATUS_FAILURE_LABELS[dominantFailureKind()] or "ACTIVE"
  end
  return "ACTIVE"
end

-- `activate` VAZIO NAO E ENFEITE, e o conserto de um defeito de verdade.
--
-- OptionsMenu:update (src/ui/OptionsMenu.lua:549-566) trata A, esquerda e
-- direita no mesmo ramo, e escolhe o que fazer nesta ordem: se a linha tem
-- `activate`, chama; senao, se tem `step`, cicla; SENAO, se foi A, trata como
-- CANCEL e da POP NO MENU. Uma linha so de leitura, com `value` e sem os dois
-- outros, cai nesse terceiro caso: apertar A em cima de STATUS fechava a tela
-- de opcoes inteira, como se o jogador tivesse escolhido sair.
--
-- E o A e a tecla que a pessoa aperta primeiro quando quer entender uma linha
-- que ela nao reconhece, que e exatamente a situacao para a qual a row de
-- STATUS foi criada. Um `activate` que nao faz nada mantem o cursor onde
-- estava, que e o comportamento certo para uma linha que so informa.
--
-- Achado por revisao independente lendo o motor, nao por teste nosso: nenhum
-- gate daqui aperta tecla no menu de verdade. Ver o passo de tooling da
-- proxima versao.
local function readOnlyRow(id, label, value)
  return {
    id = mod.id .. ":" .. id,
    label = label,
    value = value,
    activate = function() end,
  }
end

local function statusRow()
  return readOnlyRow("status", "STATUS", statusValue)
end

local warnedReplacedDraw = false

-- Mesma ideia da row de STATUS, para o canal novo. Os tres reports que
-- motivaram o STATUS (AngelusRole, TwoTracks, Tyler Durden) tinham em comum
-- nao ter como saber, olhando o jogo, por que nada acontecia. Um canal que
-- depende de um SEGUNDO ponto do host tem ainda mais jeitos de nao acontecer,
-- entao ele nasce dizendo em qual deles esta.
local function lifeStatusValue()
  if not patched then return "NO HOST" end
  if not drawPatched then return "NO CHANNEL" end
  if Voxel3D.draw ~= installedDraw then
    if not warnedReplacedDraw then
      warnedReplacedDraw = true
      mod.log:warn("Voxel3D.draw is no longer the function this mod " ..
        "installed; another mod replaced it after patching")
    end
    return "REPLACED"
  end
  if firstPersonCardActive() then
    local fp = optionState.first_person or readOption(OPTION_BY_KEY.first_person)
    if fp ~= "solid" then return "FIRST PERSON" end
  end
  local on = {}
  if optionState.breath ~= "off" then on[#on + 1] = "BREATH" end
  if optionState.sway ~= "off" then on[#on + 1] = "SWAY" end
  if optionState.lag ~= "off" then on[#on + 1] = "LAG" end
  if optionState.footfall ~= "off" then on[#on + 1] = "STEP" end
  if #on == 0 then return "OFF" end
  return table.concat(on, "+")
end

local function lifeStatusRow()
  return readOnlyRow("life", "LIFE", lifeStatusValue)
end

-- ====================================================== PRESET DE CAMERA
--
-- MEDIDO, nao escolhido. O harness rendeu o red frame 0 em cada degrau de
-- camera do host contra cada espessura do menu, e contou que fracao dos pixels
-- desenhados vem da arte do artista (faces de frente e de costas) contra
-- superficie que este mod inventou (topo, laterais, base):
--
--                 rung 15   rung 35   rung 50   rung 75
--     depth  1     76.3      88.4      92.8      97.6
--     depth  2     62.2      80.0      86.9      95.5
--     depth  3     52.4      73.4      81.6      93.3
--     depth  5     40.1      62.9      73.8      89.1
--     depth 10     26.0      49.6      62.1      81.0
--
-- O criterio nao foi inventado: e o que JA E O PADRAO. rung 35 com depth 3 da
-- 73.4% de arte, e essa e a configuracao que a comunidade viu, usou e aprovou.
-- Entao para cada degrau a recomendacao e a maior espessura que ainda fica
-- nesse patamar. Sai 1, 3, 5, 10, e a monotonia e consequencia da tabela, nao
-- um arredondamento nosso.
--
-- O RESULTADO INTERESSANTE: com essas espessuras a composicao fica quase
-- constante em todo degrau (arte entre 73 e 81%). Uma camera mais deitada olha
-- mais para o topo, e o preset compensa exatamente isso tirando espessura. E
-- por isso que ele NAO mexe em FRONT SHAPE nem em TOP DOME: depois de acertar a
-- espessura, a proporcao entre a face da frente e a de topo ja e a mesma em
-- todo lugar, entao nao existe motivo medido para variar o sombreamento junto.
--
-- E o de baixo para cima tambem vale: no degrau 75 da para usar a espessura
-- MAXIMA do menu e ainda ter mais arte na tela do que a configuracao padrao tem
-- hoje. Quem joga naquela camera esta deixando volume na mesa sem saber.
local CAMERA_PRESET = {
  { rung = 15, depth = 1 },
  { rung = 35, depth = 3 },
  { rung = 50, depth = 5 },
  { rung = 75, depth = 10 },
}

-- O degrau atual em graus, do jeito que o host mede (0 deita o card no chao, 90
-- levanta ele). Devolve nil quando nao da para saber, e ai a row diz isso em
-- vez de chutar.
local function cameraRung()
  if not VoxelState then return nil end
  local ok, value = pcall(function() return VoxelState.angle end)
  if not ok then return nil end
  local rad = tonumber(value)
  if not rad then return nil end
  return math.deg(rad)
end

local function presetParaAgora()
  local graus = cameraRung()
  if not graus then return nil end
  local melhor, distancia = nil, math.huge
  for _, entrada in ipairs(CAMERA_PRESET) do
    local d = math.abs(entrada.rung - graus)
    if d < distancia then melhor, distancia = entrada, d end
  end
  return melhor, graus
end

-- Row de ACAO, nao de ciclo. Apertar A aplica; esquerda e direita nao fazem
-- nada. E deliberado que ela nao seja automatica: o mod mexer sozinho na
-- escolha de alguem toda vez que a pessoa troca de camera e a mesma familia do
-- defeito em que A numa row de leitura fechava o menu, ou seja fazer o que
-- ninguem pediu. Aqui a pessoa pede, ve o valor mudar na row de VOXEL CHARS
-- logo abaixo, e o save guarda o que ela escolheu.
local function cameraPresetRow()
  return {
    id = mod.id .. ":camera_preset",
    label = "CAMERA FIT",
    value = function()
      local entrada, graus = presetParaAgora()
      if not entrada then return "NO CAMERA" end
      local atual = optionState.depth
      if atual == entrada.depth then
        return string.format("OK AT %d", math.floor(graus + 0.5))
      end
      return string.format("SET DEPTH %d", entrada.depth)
    end,
    activate = function(game)
      local entrada = presetParaAgora()
      if not entrada then return end
      local opt = OPTION_BY_KEY.depth
      local valor = setOption(opt, entrada.depth)
      writeOption(game, opt.key, valor)
    end,
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
      out[#out + 1] = lifeStatusRow()
      out[#out + 1] = cameraPresetRow()
      for _, opt in ipairs(OPTIONS) do
        -- As tres opcoes de vida so aparecem quando o canal existe. Um menu
        -- que oferece BREATH num host sem Voxel3D.draw substituivel promete o
        -- que nao pode cumprir, e essa e exatamente a experiencia que a row de
        -- STATUS foi criada para acabar.
        if not (LIFE_OPTION_KEYS[opt.key] and not drawPatched) then
          out[#out + 1] = makeOptionRow(opt)
        end
      end
    end
    return out
  end)

  mod.events:on("mod.options_changed", function(payload)
    if not (payload and payload.mod == mod.id) then return end
    local opt = OPTION_BY_KEY[payload.key]
    if opt then setOption(opt, payload.value) end
  end)
end

-- ========================================================================
-- VIDA: animacao por matriz, uma instancia de cada vez
-- ========================================================================
--
-- O QUE ESTA SECAO FAZ, EM UMA FRASE: o host monta uma matriz de mundo nova
-- para cada personagem a cada quadro; a gente pos-multiplica essa matriz por
-- uma transformacao LOCAL pequena (escala em Y, cisalhamento em X e em Z) e
-- devolve. Nenhum vertice e escrito, nenhuma malha e duplicada.
--
-- POR QUE ISSO E CORRETO, e nao um truque. A cadeia do host e
--
--     M = T(px+8, y, py+8) . Rx(lean - pi/2) . [S(-1,1,1)] . T(-8,0,0)
--
-- (row-major, translacao na 4a coluna; VoxelScene.billboardMatrix). Eu quero
-- injetar a transformacao ANTES da rotacao, no espaco local do card, para o
-- efeito ser "estica para cima a partir do chao" e nao "estica na direcao da
-- camera". Pos-multiplicar poe a transformacao no lugar mais local de todos,
-- depois do T(-8,0,0). Isso e equivalente porque:
--
--   S(1,s,1) comuta com T(-8,0,0)   (uma escala so em Y, uma translacao so
--                                    em X: eixos ortogonais)
--   S(1,s,1) comuta com S(-1,1,1)   (duas diagonais)
--
-- entao M . S = T . Rx . S(-1,1,1) . S(1,s,1) . T(-8,0,0), que e exatamente
-- onde eu queria a escala. O cisalhamento H (x' = x + kx.y, z' = z + kz.y)
-- tambem comuta com T(-8,0,0), mas NAO com o espelho: por isso kx e negado
-- quando m[1] < 0, senao o balanco viraria de lado junto com o personagem.
--
-- O PIVO SAO OS PES. A malha tem y=0 no chao (o proprio host documenta "its
-- feet at local y = 0 land on y"), entao escalar y em torno de zero mantem o
-- pe plantado e levanta a cabeca, e cisalhar proporcional a y nao arrasta o
-- pe. E o que faz isto parecer corpo e nao adesivo deslizando.

-- Amplitudes e ritmos. Segundos e fracao de altura de celula.
local BREATH_PERIOD = 3.1      -- respiracao calma de adulto parado
local SWAY_PERIOD = 6.2        -- metade do ritmo, para nao bater junto
local LAG_STIFFNESS = 90       -- mola do movimento secundario
local LAG_DAMPING = 12         -- abaixo do critico: passa do ponto e volta
local LAG_REFERENCE_SPEED = 60 -- px/s de uma caminhada normal (16 px / 16 quadros)
local LIFE_CELL = 16           -- a grade de caminhada do jogo
local LIFE_MATCH_RADIUS = 24   -- px: o quanto uma instancia pode ter andado
-- DERIVADO, nunca escrito a mao. A varredura de vizinhos precisa alcancar
-- TODA celula que possa conter um ponto dentro do raio, e essa relacao e
-- geometrica: um raio de 24 px sobre celulas de 16 px alcanca DUAS celulas,
-- nao uma (px' = 15 esta na celula 0, px = 32 na celula 2, e a distancia entre
-- eles e 17, bem dentro de 24).
--
-- A primeira versao varria so as oito celulas adjacentes com o raio em 24, e
-- revisao independente pegou: nesse vao a instancia nao era encontrada e
-- renascia com fase nova, que e exatamente o escorregamento de fase que este
-- rastreador existe para evitar. Derivar o alcance do raio faz os dois numeros
-- nao poderem mais divergir.
local LIFE_MATCH_CELLS = math.ceil(LIFE_MATCH_RADIUS / 16)
local LIFE_FORGET_SECONDS = 2  -- sem aparecer, a instancia e esquecida
local LIFE_MAX_INSTANCES = 512

-- PERSONALIDADE POR FOLHA (passo 7 do roadmap). Multiplicadores sobre o que o
-- menu escolheu: ritmo, amplitude de respiracao, amplitude de balanco. Ausente
-- da tabela = 1, 1, 1. A forma e a mesma de EYE_MARKS, que ja tem 112 entradas
-- e provou que uma tabela escrita a mao envelhece bem neste mod.
--
-- Isto NAO inventa movimento novo: so diz que um velho sentado respira devagar
-- e quase nao balanca, e que um nadador parado na agua balanca mais que um
-- guarda em posicao de sentido. Nenhum pixel novo foi desenhado para isso.
local LIFE_PERSONALITY = {
  -- quem esta dormindo ou sentado: lento e quase parado
  gambler_asleep   = { rate = 0.45, breath = 1.35, sway = 0.0 },
  sleeping_boy     = { rate = 0.45, breath = 1.35, sway = 0.0 },
  -- quem esta em posicao de sentido: ritmo normal, sem balanco
  guard            = { rate = 1.00, breath = 0.80, sway = 0.15 },
  officer_jenny    = { rate = 1.00, breath = 0.80, sway = 0.20 },
  scientist        = { rate = 1.05, breath = 0.85, sway = 0.30 },
  -- quem esta na agua ou em pe ha muito tempo: mais balanco
  swimmer          = { rate = 1.15, breath = 1.10, sway = 1.60 },
  fisher           = { rate = 0.85, breath = 1.05, sway = 1.25 },
  -- criancas e gente agitada: rapido e curto
  youngster        = { rate = 1.30, breath = 0.90, sway = 1.20 },
  girl             = { rate = 1.25, breath = 0.90, sway = 1.15 },
  little_girl      = { rate = 1.40, breath = 0.85, sway = 1.30 },
  -- quem carrega peso
  super_nerd       = { rate = 0.90, breath = 1.15, sway = 0.75 },
  gambler          = { rate = 0.95, breath = 1.10, sway = 0.85 },
  -- OBJETOS. Uma item ball nao respira. Sem esta entrada, a poke_ball do chao
  -- ficaria pulsando, que e o defeito mais obvio possivel desta feature.
  poke_ball        = { rate = 1, breath = 0, sway = 0, lag = 0 },
  boulder          = { rate = 1, breath = 0, sway = 0, lag = 0 },
  snorlax          = { rate = 0.40, breath = 1.60, sway = 0.0 },
}

-- Rastreador de instancias.
--
-- POR QUE ELE EXISTE, e nao so um hash da posicao: se a fase da animacao for
-- f(posicao), o personagem andando muda de posicao a cada quadro e a fase
-- escorrega junto (revisao externa chamou isso de "phase slipping", e esta
-- certa: ele respiraria em supervelocidade andando num sentido e congelaria
-- andando no outro). A fase tem que avancar com o TEMPO e so com o tempo.
--
-- Entao a gente casa cada desenho com uma instancia conhecida por
-- proximidade, e carrega a fase de um quadro para o outro. Sem isso nao ha
-- movimento secundario nenhum: mola precisa de estado.
local lifeInstances = {}
local lifeCount = 0

local function lifeCellKey(sheet, px, py)
  return sheet .. "\1" .. math.floor(px / LIFE_CELL) ..
    "\1" .. math.floor(py / LIFE_CELL)
end

-- Fase inicial de uma instancia nova. Determinista (mesma folha no mesmo lugar
-- volta com a mesma fase depois de trocar de mapa e voltar) e bem espalhada:
-- as constantes sao irracionais de proposito, porque px e py sao multiplos de
-- 16 e qualquer fator racional simples alinharia instancias vizinhas na mesma
-- fase, que e exatamente o coro de robos que a gente esta tentando evitar.
local function lifeSeedPhase(px, py)
  local v = px * 0.6180339887 + py * 0.4142135624
  return v - math.floor(v)
end

local function lifeForget(now)
  if lifeCount <= LIFE_MAX_INSTANCES then return end
  for key, inst in pairs(lifeInstances) do
    if now - inst.seen > LIFE_FORGET_SECONDS then
      lifeInstances[key] = nil
      lifeCount = lifeCount - 1
    end
  end
end

-- Devolve a instancia deste desenho, criando se for a primeira vez.
--
-- Tres tentativas, nesta ordem:
--   1. celula exata. Cobre o caso normal (parado) E a copia refletida na agua,
--      que o host desenha pela MESMA funcao no mesmo quadro com a mesma
--      matriz: ela cai na mesma instancia e nao vira uma segunda pessoa.
--   2. as oito celulas vizinhas, mesma folha, dentro do raio. E o personagem
--      que acabou de atravessar a fronteira de uma celula andando.
--   3. instancia nova.
local function lifeInstance(sheet, px, py, now)
  local key = lifeCellKey(sheet, px, py)
  local inst = lifeInstances[key]
  if not inst then
    local best, bestKey, bestDist = nil, nil, LIFE_MATCH_RADIUS * LIFE_MATCH_RADIUS
    for dx = -LIFE_MATCH_CELLS, LIFE_MATCH_CELLS do
      for dy = -LIFE_MATCH_CELLS, LIFE_MATCH_CELLS do
        if dx ~= 0 or dy ~= 0 then
          local k = lifeCellKey(sheet, px + dx * LIFE_CELL, py + dy * LIFE_CELL)
          local c = lifeInstances[k]
          -- `c.seen < now` impede roubar uma instancia que JA foi vista neste
          -- quadro: essa e outra pessoa, nao esta.
          if c and c.seen < now then
            local ddx, ddy = px - c.px, py - c.py
            local d = ddx * ddx + ddy * ddy
            if d < bestDist then best, bestKey, bestDist = c, k, d end
          end
        end
      end
    end
    if best then
      lifeInstances[bestKey] = nil
      inst = best
    else
      inst = {
        phase = lifeSeedPhase(px, py),
        px = px, py = py,
        lagX = 0, lagVX = 0, lagZ = 0, lagVZ = 0,
        -- distancia total ja percorrida, em pixels de mundo. E dela que sai a
        -- fase da PASSADA: o jogo anda 16 px por passo, entao cada 16 px
        -- percorridos e uma pisada, sem precisar ler frame nenhum.
        andado = 0, velocidade = 0,
        seen = now,
      }
      lifeCount = lifeCount + 1
      lifeForget(now)
    end
    lifeInstances[key] = inst
  end
  return inst
end

-- Avanca a instancia ate `now`. Idempotente dentro do mesmo quadro: a segunda
-- chamada (o reflexo na agua) tem dt = 0 e nao mexe em nada. E o que dispensa
-- este codigo de saber onde comeca e termina um quadro.
local function lifeAdvance(inst, px, py, now, rate)
  local dt = now - inst.seen
  if dt <= 0 then return end
  -- Um dt gigante quer dizer que a instancia sumiu e voltou (troca de mapa,
  -- menu aberto, jogo em pausa). Continuar a mola com ele daria um estouro.
  if dt > 0.25 then dt = 1 / 60 end

  inst.phase = (inst.phase + dt * rate) % 1

  -- Velocidade em px/s a partir do deslocamento real. E a unica fonte honesta:
  -- o mod nao ve o estado de caminhada do NPC, so onde ele estava e onde esta.
  local dx, dz = px - inst.px, py - inst.py
  local vx, vz = dx / dt, dz / dt
  inst.px, inst.py = px, py

  -- Distancia percorrida e velocidade suavizada. A distancia da a FASE da
  -- passada; a velocidade da a AMPLITUDE, e e o que faz o efeito sumir sozinho
  -- quando o personagem para, sem precisar de um "esta andando?" booleano que
  -- ligaria e desligaria de estalo.
  inst.andado = (inst.andado or 0) + math.sqrt(dx * dx + dz * dz)
  local vel = math.sqrt(vx * vx + vz * vz) / LAG_REFERENCE_SPEED
  if vel > 1 then vel = 1 end
  -- Suaviza para a amplitude nao piscar quando um quadro anda 0 px por
  -- arredondamento, que acontece em toda passada.
  inst.velocidade = (inst.velocidade or 0) + (vel - (inst.velocidade or 0)) * 0.25

  -- Mola de segunda ordem perseguindo o negativo da velocidade: o corpo fica
  -- para tras enquanto acelera, e passa do ponto quando o personagem para.
  local alvoX = -vx / LAG_REFERENCE_SPEED
  local alvoZ = -vz / LAG_REFERENCE_SPEED
  inst.lagVX = inst.lagVX +
    (LAG_STIFFNESS * (alvoX - inst.lagX) - LAG_DAMPING * inst.lagVX) * dt
  inst.lagVZ = inst.lagVZ +
    (LAG_STIFFNESS * (alvoZ - inst.lagZ) - LAG_DAMPING * inst.lagVZ) * dt
  inst.lagX = inst.lagX + inst.lagVX * dt
  inst.lagZ = inst.lagZ + inst.lagVZ * dt

  inst.seen = now
end

-- Pos-multiplica `m` (row-major, 16 numeros) pela transformacao local
--
--     L = S(1, s, 1) . H(kx, kz)     com H: x' = x + kx.y,  z' = z + kz.y
--
-- e devolve uma tabela NOVA. Nova, e nao mutacao no lugar, mesmo tendo
-- verificado que o host aloca a matriz a cada chamada: se um host futuro
-- reciclar uma matriz de rascunho, mutar acumularia o efeito a cada quadro ate
-- explodir, e esse modo de falha e caro demais para o que se economiza.
-- Pos-multiplica `m` pela transformacao LOCAL
--
--     L = [ sx  kx  0  8-8sx ]      escala em X com pivo no CENTRO da celula
--         [ 0   s   0  0     ]      escala em Y com pivo nos PES
--         [ 0   kz  1  0     ]      cisalhamento proporcional a altura
--         [ 0   0   0  1     ]
--
-- e devolve tabela NOVA.
--
-- POR QUE O X E DIFERENTE DOS OUTROS. Escala em Y e cisalhamento COMUTAM com o
-- T(-8,0,0) local do host, entao pos-multiplicar ja os coloca no lugar certo.
-- Escala em X NAO comuta: S(sx,1,1) . T(-8,0,0) escala o -8 junto, e o
-- personagem engordaria so para um lado, a partir da borda esquerda da folha em
-- vez do proprio eixo. Por isso o X entra como T(8,0,0) . S(sx,1,1) . T(-8,0,0),
-- que e o que produz o termo (8 - 8sx) na coluna 4.
--
-- Conferido no papel: o ponto local (8, 0, z), o centro do pe, vai parar em
-- col4 + 8.col1 com e sem a escala. O pe fica plantado e o corpo engorda para os
-- dois lados, que e o unico jeito de achatar sem o personagem escorregar.
--
-- Escrito aberto, sem laco sobre indices, porque este e o caminho mais quente do
-- mod: roda uma vez por personagem por desenho, duas vezes por quadro cada.
local function lifeApply(m, s, kx, kz, sx, corr)
  local out = {
    m[1], m[2], m[3], m[4],
    m[5], m[6], m[7], m[8],
    m[9], m[10], m[11], m[12],
    m[13], m[14], m[15], m[16],
  }
  -- A TRANSFORMACAO E CONJUGADA PELA CORRECAO DE INCLINACAO, e sem isso ela
  -- opera no eixo errado. Isto era um defeito em producao.
  --
  -- O builder devolve o vertice ja contra-rotacionado: `p()` aplica Rx(corr)
  -- com corr = pi/2 menos o angulo da camera, e o host desfaz com
  -- Rx(angulo - pi/2). Liquido, o personagem fica em pe. Mas pos-multiplicar
  -- aqui poe a nossa transformacao no espaco da MALHA, que esta girado pelo
  -- pitch, e nao no espaco do personagem. O mundo entao ve Rx(t)*L*Rx(-t) em
  -- vez de L.
  --
  -- Medido: com BREATH SUBTLE a cabeca subia 16*eps*cos^2(corr) em vez de
  -- 16*eps. No degrau padrao (35) isso e 33% do prometido; no degrau 15 sobra
  -- 7%. E aparecia deriva em Z de 16*eps*sin*cos, ate 0.079 px, empurrando o
  -- corpo para tras sem ninguem pedir. O MOTION LAG era o pior: o termo kz
  -- virava 82% vertical no degrau padrao, entao "inercia" era em boa parte o
  -- corpo subindo e descendo.
  --
  -- Nenhum gate pegou porque todos os testes de vida afirmavam sobre a MATRIZ
  -- e nenhum compunha a matriz com a rotacao assada no vertice. O teste que
  -- faltava existe agora e mede deslocamento NO MUNDO nos quatro degraus.
  --
  -- Conserto: pos-multiplicar L' = Rx(corr) * L * Rx(-corr), que faz o mundo
  -- ver exatamente L. Com corr = 0 isto colapsa em L e o comportamento antigo
  -- volta identico, que e o certo quando nao ha inclinacao.
  --
  -- L, em coordenadas do personagem (x cisalha por y, y escala, z cisalha por
  -- y), e a conjugacao expandida termo a termo:
  --
  --   L  = [ 1 kx 0 ; 0 s 0 ; 0 kz 1 ]
  --   L' = [ 1        kx*c                 kx*n              ]
  --        [ 0   s*c*c + n*n - kz*n*c   s*n*c - kz*n*n - n*c ]
  --        [ 0   s*n*c + kz*c*c - c*n   s*n*n + kz*n*c + c*c ]
  local c, n = 1, 0
  if corr and corr ~= 0 then c, n = math.cos(corr), math.sin(corr) end

  local a12, a13 = kx * c, kx * n
  local a22 = s * c * c + n * n - kz * n * c
  local a23 = s * n * c - kz * n * n - n * c
  local a32 = s * n * c + kz * c * c - c * n
  local a33 = s * n * n + kz * n * c + c * c

  -- out[coluna j] = m * (coluna j de L')
  local m1, m2, m3 = m[1], m[2], m[3]
  local m5, m6, m7 = m[5], m[6], m[7]
  local m9, m10, m11 = m[9], m[10], m[11]
  local m13, m14, m15 = m[13], m[14], m[15]

  out[2] = m1 * a12 + m2 * a22 + m3 * a32
  out[6] = m5 * a12 + m6 * a22 + m7 * a32
  out[10] = m9 * a12 + m10 * a22 + m11 * a32
  out[14] = m13 * a12 + m14 * a22 + m15 * a32

  out[3] = m1 * a13 + m2 * a23 + m3 * a33
  out[7] = m5 * a13 + m6 * a23 + m7 * a33
  out[11] = m9 * a13 + m10 * a23 + m11 * a33
  out[15] = m13 * a13 + m14 * a23 + m15 * a33

  if sx and sx ~= 1 then
    local recuo = 8 - 8 * sx
    out[1] = m[1] * sx
    out[5] = m[5] * sx
    out[9] = m[9] * sx
    out[13] = m[13] * sx
    out[4] = m[4] + m[1] * recuo
    out[8] = m[8] + m[5] * recuo
    out[12] = m[12] + m[9] * recuo
    out[16] = m[16] + m[13] * recuo
  end
  return out
end

-- ------------------------------------------------------------ o wrap
-- Le a identidade do desenho a partir da propria matriz. Medido em jogo
-- (tools/ingame/probe_draw.lua): m[4] carrega px, ou px+16 quando espelhado, e
-- nesse caso m[1] = -1; m[12] carrega py+8. Sao coordenadas de MUNDO, imunes a
-- camera (P8) e ao degrau de inclinacao (P6).
--
-- Quando m[1] nao e +-1, o host esta misturando o yaw de primeira pessoa
-- (billboardMatrix, ramo cardBlend > 0) e px deixa de ser recuperavel. Ali este
-- mod ja devolve card plano de proposito, entao a animacao tambem sai fora.
-- Raio conservador do personagem a partir da ancora da matriz: meia celula em
-- x e z, mais a profundidade maxima que o menu oferece. Serve para perguntar
-- pelo vertice MAIS PROXIMO em vez de pelo centro, que e o que decide se algum
-- canto atravessa o near plane.
local FP_RAIO = 14
-- Folga acima do near plane (1 unidade quando olho e foco estao juntos). Dois
-- e o menor numero que ainda deixa margem para a respiracao e a inercia
-- moverem o corpo depois desta conta, ja que elas mexem a matriz e nao o pull.
local FP_FOLGA = 2

-- O CONSERTO. `pull` e um vies de profundidade: o shader empurra cada vertice
-- na direcao do olho por essa distancia. Perto demais, isso joga o vertice
-- para tras do olho e o que aparece e um espeto preto.
--
-- Entao a gente nao desliga o volume, a gente entrega um pull que a distancia
-- aguenta. Errar para menos e seguro por construcao: pull menor so significa
-- menos vies de profundidade, e a razao de existir do vies (nao brigar em z
-- com o terreno LONGE) nao se aplica a quem esta colado na camera.
local function fpPullSeguro(model, pull)
  if type(pull) ~= "number" or pull <= 0 then return pull end
  local eye = Voxel3D and Voxel3D.eye
  if type(eye) ~= "table" then return pull end
  local ex, ey, ez = eye[1], eye[2], eye[3]
  if type(ex) ~= "number" or type(ey) ~= "number" or type(ez) ~= "number" then
    return pull
  end
  local dx = ex - (model[4] or 0)
  local dy = ey - (model[8] or 0)
  local dz = ez - (model[12] or 0)
  local d = math.sqrt(dx * dx + dy * dy + dz * dz) - FP_RAIO
  local teto = d - FP_FOLGA
  if teto < 0 then teto = 0 end
  return math.min(pull, teto)
end

-- WHAT MAY BREATHE, SWAY, LAG AND SQUASH.
--
-- Reported by Pikon: the town map lying on the table in the rival's house
-- sways. He is right that it should not, and right about the rule too, which
-- Kim confirmed: people and Pokemon move, objects do not. A swaying map reads
-- as a bug even to someone who cannot name what is wrong, because maps on
-- tables do not breathe.
--
-- THE LIST IS OF OBJECTS, NOT OF CHARACTERS, and that direction is the whole
-- design. Measuring every sheet's frame count (its height over 16, see
-- RomExtractor.lua:481) splits them almost along the line we want: 58 sheets
-- have 3 or 6 frames and are all characters, 9 have one frame. But two of
-- those nine are alive and merely still, `snorlax` and `gambler_asleep`, and a
-- sleeping Snorlax that breathes is exactly the reading we want.
--
-- So the rule is not "animate what walks", it is "hold still what is furniture",
-- and anything unknown is treated as alive. That default is the one that
-- survives other mods: overworld_wild_spawns registers hundreds of Pokemon
-- sprites we have never seen, and a Pokemon should breathe. A list of
-- characters would freeze them all; a list of objects lets them through.
--
-- The names come from the ROM and cannot grow, and the offline suite asserts
-- the classification over the real sheet names, so a wrong entry fails a test
-- instead of sitting in a table nobody rereads.
--
-- Note what this does NOT explain, because the difference matters: Pikon also
-- noticed the pokeballs on Oak's table do not sway. That is not this rule at
-- work. Those pokeballs are map art, not object events, so they never reach
-- SpriteBillboards.mesh and were never ours to animate.
local STILL_OBJECTS = {
  boulder = true, clipboard = true, fossil = true, old_amber = true,
  paper = true, poke_ball = true, pokedex = true,
}

local function lifeAlive(info)
  if not info then return false end
  return not STILL_OBJECTS[info.base]
end

local function lifeDrawWrap(mesh, texture, model, pull, sunModel)
  local info = ourMeshes[mesh]
  if not info or type(model) ~= "table" then
    return originalDraw(mesh, texture, model, pull, sunModel)
  end

  -- Antes de qualquer saida antecipada, porque isto nao e animacao: e a
  -- condicao para o solido poder existir em primeira pessoa, e vale mesmo com
  -- todas as opcoes de vida desligadas.
  local fp = optionState.first_person or readOption(OPTION_BY_KEY.first_person)
  if fp == "solid" and firstPersonCardActive() then
    pull = fpPullSeguro(model, pull)
  end

  local breath = optionState.breath
  local sway = optionState.sway
  local lag = optionState.lag
  local footfall = optionState.footfall
  if breath == "off" and sway == "off" and lag == "off"
    and footfall == "off" then
    return originalDraw(mesh, texture, model, pull, sunModel)
  end
  -- After the first-person pull clamp on purpose: that one is about not
  -- drawing garbage and applies to everything we draw, including objects.
  -- This one is about what is alive.
  if not lifeAlive(info) then
    return originalDraw(mesh, texture, model, pull, sunModel)
  end

  local m1 = model[1]
  local espelhado = m1 < 0
  if math.abs(math.abs(m1) - 1) > 1e-6 then
    return originalDraw(mesh, texture, model, pull, sunModel)
  end

  -- Mesmo cuidado do piscar (blinkClosedForBase): o relogio vem do host, e um
  -- host sem love.timer nao pode derrubar o desenho. Sem relogio nao ha
  -- animacao, e o personagem sai como sempre saiu.
  if not (love and love.timer and love.timer.getTime) then
    return originalDraw(mesh, texture, model, pull, sunModel)
  end
  local okNow, now = pcall(love.timer.getTime)
  if not okNow or type(now) ~= "number" then
    return originalDraw(mesh, texture, model, pull, sunModel)
  end

  local px = espelhado and (model[4] - LIFE_CELL) or model[4]
  local py = model[12] - 8
  local pessoa = LIFE_PERSONALITY[info.base]
  local rate = pessoa and pessoa.rate or 1
  local inst = lifeInstance(info.base, px, py, now)
  lifeAdvance(inst, px, py, now, rate / BREATH_PERIOD)

  local s, kx, kz = 1, 0, 0
  if breath ~= "off" then
    local amp = breath * (pessoa and pessoa.breath or 1)
    s = 1 + amp * math.sin(inst.phase * 2 * math.pi)
  end
  if sway ~= "off" then
    local amp = sway * (pessoa and pessoa.sway or 1)
    -- Metade do ritmo da respiracao e um quarto de volta fora de fase: os dois
    -- nunca chegam no extremo juntos, que e o que faria o personagem parecer
    -- um metronomo em vez de uma pessoa.
    local a = (inst.phase * BREATH_PERIOD / SWAY_PERIOD + 0.25) * 2 * math.pi
    kx = amp * math.sin(a) / LIFE_CELL
  end
  if lag ~= "off" then
    -- DIVIDIR POR LIFE_CELL, igual ao SWAY logo acima, e o motivo esta escrito
    -- aqui porque a falta disso passou por todos os gates numericos.
    --
    -- `amp` e deslocamento da CABECA em pixels de mundo. O cisalhamento e
    -- x' = x + k*y com y ate 16, entao k tem que ser amp/16. Sem a divisao,
    -- `amp` virava a INCLINACAO: no nivel 0.70 a cabeca andava 0.70*16 = 11 px,
    -- quase um tile inteiro, e o personagem nao lia como andando com peso, lia
    -- como caindo de lado. Os oito checks in-game passaram assim mesmo, porque
    -- todos perguntavam "mudou?" e nenhum perguntava "mudou quanto?". Quem
    -- pegou foi olhar o clipe.
    local amp = lag * (pessoa and pessoa.lag or 1) / LIFE_CELL
    kx = kx + amp * inst.lagX
    kz = kz + amp * inst.lagZ
  end
  local sx = 1
  if footfall ~= "off" then
    local amp = footfall * (pessoa and pessoa.footfall or 1) / LIFE_CELL
    -- cosseno da fase da passada: +1 no impacto, -1 no alto do passo. Um ciclo
    -- inteiro por celula andada.
    local pulso = math.cos((inst.andado / LIFE_CELL) * 2 * math.pi)
    local achata = amp * (inst.velocidade or 0) * pulso
    s = s - achata
    -- Volume preservado: o que some em altura aparece em largura. Sem isso o
    -- personagem so encolhe, que le como afundar no chao em vez de pisar.
    sx = 1 + achata
  end

  -- O cisalhamento em X vive no espaco do card, que o espelho ja inverteu.
  -- Sem negar aqui, o balanco e o atraso trocariam de lado toda vez que o
  -- personagem virasse para o outro lado, e o pulo seria visivel.
  if espelhado then kx = -kx end

  -- A MESMA correcao que o builder assou no vertice, quantizada igual: se as
  -- duas divergirem, a conjugacao nao cancela e sobra um residuo.
  local corr = quantizeCorrection(leanCorrection())
  local novo = lifeApply(model, s, kx, kz, sx, corr)
  -- A sombra recebe a MESMA escala. Sem isso o corpo respira e a sombra fica
  -- imovel, e o personagem descola da propria sombra. O cisalhamento em Z fica
  -- de fora: a matriz de sombra ja achata z (casterMatrix termina em S(1,1,0))
  -- e reintroduzir profundidade ali nao teria significado.
  local novoSol = sunModel and lifeApply(sunModel, s, kx, 0, sx, corr) or nil
  return originalDraw(mesh, texture, novo, pull, novoSol)
end

local function voxelMesh(def, frame)
  local depth = optionState.depth or readOption(OPTION_BY_KEY.depth)
  if depth == "off" then
    recordDrawResult("off")
    return safeOriginal(def, frame)
  end
  -- Em primeira pessoa o solido so sai se DUAS coisas forem verdade: a pessoa
  -- pediu, e o canal de desenho existe para limitar o pull. Sem o canal,
  -- installedDraw fica nil e SOLID prometeria exatamente os espetos que a
  -- v1.3.0 consertou; a opcao nem chega a aparecer no menu nesse host, mas um
  -- save antigo pode carregar o valor, entao a checagem e aqui e nao no menu.
  if firstPersonCardActive() then
    local fp = optionState.first_person or readOption(OPTION_BY_KEY.first_person)
    if fp ~= "solid" or installedDraw == nil then
      recordDrawResult("first_person")
      return safeOriginal(def, frame)
    end
  end
  local sideColor = optionState.side_color or readOption(OPTION_BY_KEY.side_color)
  local shape = optionState.shape or readOption(OPTION_BY_KEY.shape)
  local groundShade = optionState.ground_shade or readOption(OPTION_BY_KEY.ground_shade)
  local topEdge = optionState.top_edge or readOption(OPTION_BY_KEY.top_edge)
  local frontShape = optionState.front_shape or readOption(OPTION_BY_KEY.front_shape)
  local topDome = optionState.top_dome or readOption(OPTION_BY_KEY.top_dome)
  local stepWeight = optionState.step_weight or readOption(OPTION_BY_KEY.step_weight)
  local correction = quantizeCorrection(leanCorrection())
  local okMask, m = pcall(maskFor, def)
  if not (okMask and m) then
    recordDrawFailure("mask_failed",
      okMask and "maskFor found no usable mask for this sprite" or m)
    return safeOriginal(def, frame)
  end
  local baseName = spriteBaseName(def and def.image)
  local key = cacheKey(def, frame, depth, correction, m, sideColor, shape,
    groundShade, topEdge, frontShape, topDome, stepWeight)
  if meshes[key] ~= nil then
    touchMeshKey(key)
  else
    local ok, mesh = pcall(buildSelectedMesh, def, frame, depth, correction,
      m, sideColor, shape, groundShade, baseName, topEdge, frontShape, topDome,
      stepWeight)
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
    -- Marca a malha como NOSSA e guarda a folha. E o que o wrap de
    -- Voxel3D.draw usa para saber que aquele desenho e um personagem deste mod
    -- e nao terreno, grama, sombra ou a pokedex, que passam pela mesma funcao.
    --
    -- So na PRIMEIRA vez. A malha e cacheada por (folha, frame, opcoes), entao
    -- base e frame nunca mudam para um mesmo objeto de malha; reatribuir a cada
    -- acerto de cache alocaria uma tabela por personagem por quadro sem trocar
    -- nada dentro dela.
    if ourMeshes[mesh] == nil then
      ourMeshes[mesh] = { base = baseName, frame = frame,
                          frames = (def and def.frames) or 1 }
    end
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

  -- SEGUNDO PONTO DE PATCH, e ele e OPCIONAL de proposito.
  --
  -- O canal de animacao precisa envolver Voxel3D.draw. Isso e mais superficie
  -- do host do que este mod tinha antes, e mais superficie e mais chance de um
  -- fork futuro quebrar a gente: entre outubro e agora o repositorio original
  -- saiu do ar duas vezes e nasceram tres linhagens versionando de formas
  -- incompativeis. Por isso o patch inteiro fica DEPOIS do commit acima e num
  -- pcall proprio: se ele falhar, o mod perde a animacao e continua desenhando
  -- solidos normalmente, que e o produto principal. O contrario (perder o mod
  -- por causa de um enfeite) seria inaceitavel.
  --
  -- A sonda de capacidade ja recusou hosts sem Voxel3D.draw utilizavel
  -- (probeHost, OPTIONAL_CAPABILITIES), entao chegar aqui sem capacidade
  -- significa host antigo, e a ausencia e silenciosa por escolha: quem roda um
  -- host sem o canal ve LIFE: NO CHANNEL na tela de opcoes e sabe o porque.
  if host.caps and host.caps.drawWrap then
    local okDraw, drawErr = pcall(function()
      local previous = voxel3D.draw
      if previous ~= installedDraw then originalDraw = previous end
      installedDraw = lifeDrawWrap
      voxel3D.draw = lifeDrawWrap
    end)
    if okDraw then
      drawPatched = true
      mod.log:info("patched %s character draw for the life channel", host.name)
    else
      originalDraw, installedDraw, drawPatched = nil, nil, false
      mod.log:warn("could not patch %s character draw; the mod works, but " ..
        "BREATH, SWAY and MOTION LAG stay off: %s", host.name, tostring(drawErr))
    end
  end
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

-- PASSO 2 DO ROADMAP. Capacidades OPCIONAIS: a ausencia NAO recusa o host, so
-- desliga o recurso que depende dela.
--
-- Isto e o preco de encostar em mais de um ponto do host, e o preco tem que
-- ser pago aqui e nao no lugar do acidente. A sonda de v1.4.2 ja provou o
-- valor da ideia: ela e o motivo de a v1.5.0 ter sobrevivido ao repositorio
-- original sair do ar duas vezes e a comunidade se partir em tres linhagens.
-- Um recurso novo que dependa de mais API do host tem que entrar pela mesma
-- porta, senao a primeira mudanca de um fork leva o mod inteiro junto.
--
-- Cada capacidade e uma pergunta que so o host pode responder, respondida por
-- leitura e nunca por numero de versao.
local function probeCapabilities(modules)
  return {
    -- Canal de vida: exige que Voxel3D.draw exista como funcao substituivel
    -- por CAMPO. Nao da para verificar por leitura que os pontos de chamada
    -- resolvem o campo em tempo de chamada (nas tres linhagens vivas, os 32
    -- resolvem), mas da para exigir o minimo: que o campo exista e seja
    -- chamavel. O resto e coberto pelo pcall em volta da escrita.
    drawWrap = type(modules.Voxel3D) == "table"
      and type(modules.Voxel3D.draw) == "function",
  }
end

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
  return modules, nil, probeCapabilities(modules)
end

local function findHost()
  local rejected = {}
  for _, host in ipairs(HOSTS) do
    local handle = mod.find(host.id)
    if not handle then
      rejected[#rejected + 1] = host.id .. ": not found"
    else
      local modules, why, caps = probeHost(handle)
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
          caps = caps,
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
