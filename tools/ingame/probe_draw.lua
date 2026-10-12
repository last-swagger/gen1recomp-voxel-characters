-- STEP 1 of the roadmap: prove, with the game running, that the matrix the host
-- passes to Voxel3D.draw carries a position per INSTANCE that serves as a
-- stable identity.
--
-- This driver does NOT change anything. It only observes. If it fails, the roadmap
-- shrinks to shared animation and nothing else gets built.
--
-- What it answers, each one with a verdict written out:
--
--   P1 intercepts      the wrap of Voxel3D.draw sees a CHARACTER draw
--   P2 is the position m[12]-8 matches the world's py, m[4] the px
--   P3 distinguishes   two instances on the same screen give different values
--   P4 stable          a still NPC doesn't change value between frames
--   P5 mirror          turning sideways doesn't touch m[12]; measures the effect on m[4]
--   P6 camera          switching the camera step doesn't touch m[12]
--   P7 walking         value moves continuously, no jump and no NaN
--   P8 world           with the CAMERA moving, the still NPC doesn't change value
--
-- P8 is what decides step 6 of the roadmap. If the value were relative to camera,
-- it would change for everyone when the player walks, and staggering by position would make
-- the whole city breathe in a wave together with the player's step.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  dofile("mods/voxel_characters/tools/ingame/erro.lua")()

  -- THE BUG THAT COST ME THE MOST TIME IN THIS TOOL: without a TTY, LOVE's stdout
  -- stays in BLOCK buffer, and a process that never exits never flushes it. An empty
  -- log doesn't distinguish "nothing happened" from "didn't finish", and I've drawn
  -- the wrong conclusion from this more than once. Line buffering fixes it for good.
  io.stdout:setvbuf("line")

  local linhas = {}
  local function nota(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    local linha = ok and s or tostring(fmt)
    linhas[#linhas + 1] = linha
    print("[probe] " .. linha)
    -- love.filesystem.write does NOT raise an error when it fails; it returns false.
    -- Writing without checking is how I spent minutes thinking the driver
    -- had frozen when it had only stopped being able to write.
    local okw, err = love.filesystem.write("vc_probe.txt",
      table.concat(linhas, "\n") .. "\n")
    if not okw then print("[probe] WARNING: could not write: " .. tostring(err)) end
  end

  local vereditos = {}
  local function veredito(nome, ok, detalhe)
    vereditos[#vereditos + 1] = { nome = nome, ok = ok, detalhe = detalhe }
    nota("%-4s %s  %s", nome, ok and "PASSED" or "FAILED", detalhe or "")
  end

  nota("=== passo 1: a posicao por instancia chega limpa? ===")

  -- ---------------------------------------------------------------- host
  -- potato_voxel LAST, so a machine with any other host enabled measures
  -- exactly what it measured before. It was missing entirely until 1.8.1,
  -- which is part of how the mod came to LIST PotatoVoxel as a supported
  -- host for a whole release without ever having attached to it: the gates
  -- could not see that host either, so nothing could have contradicted the
  -- claim.
  local HOSTS = { "BATTLE_ART_VOXEL_FORK", "DRAMALESS_SHAPE", "DRAMATIC_SHAPE",
                  "TERRARIUM", "potato_voxel" }
  local V
  for _, id in ipairs(HOSTS) do
    local exports = game.mods and game.mods.exports and game.mods.exports[id]
    if exports and exports.lib then
      V = exports.lib
      nota("host: %s", id)
      break
    end
  end
  if not V then
    veredito("P1", false, "nenhum host do voxel mod exporta lib")
    return
  end

  local okV, Voxel3D = pcall(V.require, "Voxel3D")
  local okS, SpriteBillboards = pcall(V.require, "SpriteBillboards")
  if not (okV and okS and Voxel3D and SpriteBillboards) then
    veredito("P1", false, "V.require falhou em Voxel3D ou SpriteBillboards")
    return
  end
  nota("Voxel3D.draw e funcao: %s | SpriteBillboards.mesh e funcao: %s",
    tostring(type(Voxel3D.draw) == "function"),
    tostring(type(SpriteBillboards.mesh) == "function"))

  -- ------------------------------------------------- who is a people mesh
  -- Terrain, grass, shadow and pokedex also go through Voxel3D.draw. The only
  -- exact discriminator is provenance: a mesh that came out of
  -- SpriteBillboards.mesh is a character's, and nothing else is. Marking it at the
  -- factory's output is cheaper and more honest than guessing from the arguments.
  local malhaDeGente = setmetatable({}, { __mode = "k" })
  local nomeDaMalha = setmetatable({}, { __mode = "k" })
  local meshOriginal = SpriteBillboards.mesh
  SpriteBillboards.mesh = function(def, frame)
    local m = meshOriginal(def, frame)
    if m then
      malhaDeGente[m] = true
      nomeDaMalha[m] = tostring(def and def.image or "?") .. "#" .. tostring(frame)
    end
    return m
  end

  -- ------------------------------------------------------- draw wrap
  local capturando = false
  local quadro = {}     -- character draws of the current frame
  local drawOriginal = Voxel3D.draw
  Voxel3D.draw = function(mesh, texture, model, pull, sunModel)
    if capturando and mesh and malhaDeGente[mesh] and type(model) == "table" then
      -- WHERE this call came from. Without this I would have no way to know that the scene
      -- draws each character more than once per frame, and I would have read the
      -- duplicate as "two instances in the same place".
      local info = debug.getinfo(2, "Sl")
      quadro[#quadro + 1] = {
        nome = nomeDaMalha[mesh],
        m1 = model[1], m4 = model[4], m8 = model[8], m12 = model[12],
        temSol = sunModel ~= nil,
        pull = pull,
        de = info and (tostring(info.short_src):match("[^/]+$") .. ":" ..
          tostring(info.currentline)) or "?",
      }
    end
    return drawOriginal(mesh, texture, model, pull, sunModel)
  end

  local function limpaQuadro() quadro = {} end
  local function copiaQuadro()
    local c = {}
    for i, d in ipairs(quadro) do c[i] = d end
    return c
  end

  -- One observed frame: reset, wait for the draw to happen, return what came in.
  local function observa()
    limpaQuadro()
    capturando = true
    coroutine.yield()          -- this frame's draw runs now
    capturando = false
    return copiaQuadro()
  end

  -- --------------------------------------------------------------- world
  -- VSYNC OFF. With vsync on and the window occluded (which is the normal case
  -- when this runs from a shell, behind the editor), love.graphics.present()
  -- waits for a flip that macOS's compositor never schedules, and the entire loop runs
  -- at less than one frame per second. Symptom: the driver looks frozen right
  -- after entering the world, including the project's own drivers. It's not
  -- a freeze, it's the clock.
  if love.window and love.window.setVSync then pcall(love.window.setVSync, 0) end

  local function ambiente()
    return string.format("fps=%d visivel=%s foco=%s",
      love.timer.getFPS(),
      tostring(love.window and love.window.isVisible and love.window.isVisible()),
      tostring(love.window and love.window.hasFocus and love.window.hasFocus()))
  end

  nota("before the teleport (frame %d) %s", U.frame(), ambiente())
  local Pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")
  local mapa, tx, ty = Pouso.escolher(game, "VIRIDIAN_CITY", 17, 17)
  U.teleport(game, mapa, tx, ty, "down")
  nota("after the teleport (frame %d) %s", U.frame(), ambiente())
  U.wait(60)
  nota("after waiting 60 frames (frame %d) %s", U.frame(), ambiente())
  local ow = game.overworld
  if not (ow and game.stack:top() == ow and ow.entities) then
    veredito("P1", false, "nao cheguei ao mundo")
    return
  end
  nota("mapa: %s  entidades: %d", tostring(ow.map and ow.map.id), #ow.entities)

  -- The voxel pipeline needs to be on; without it Voxel3D.draw exits early
  -- (`if not (active and mesh) then return end`) and everything else measures zero, which
  -- is exactly the class of test that passes for a trivial reason.
  local desenhos = observa()
  local tentativas = 0
  while #desenhos == 0 and tentativas < 10 do
    U.tap(game, "3")
    U.wait(20)
    desenhos = observa()
    tentativas = tentativas + 1
  end
  nota("degraus de camera percorridos ate ver desenho: %d", tentativas)
  veredito("P1", #desenhos > 0,
    string.format("%d desenhos de personagem num quadro", #desenhos))
  if #desenhos == 0 then
    nota("with no character drawn there is nothing else to measure")
    love.graphics.captureScreenshot("vc_probe_sem_desenho.png")
    return
  end
  -- How many PASSES exist per frame, and where each one comes from. The scene
  -- draws the same character more than once (main pass, occlusion silhouette,
  -- etc). Without separating by call site, the duplicate disguises itself as
  -- "two instances in the same place" and fails a test that should pass.
  local porOrigem, ordemOrigem = {}, {}
  for _, d in ipairs(desenhos) do
    if not porOrigem[d.de] then
      porOrigem[d.de] = {}
      ordemOrigem[#ordemOrigem + 1] = d.de
    end
    local g = porOrigem[d.de]
    g[#g + 1] = d
  end
  nota("passes per frame: %d", #ordemOrigem)
  for _, origem in ipairs(ordemOrigem) do
    nota("  %s  %d desenhos  pull=%s",
      origem, #porOrigem[origem], tostring(porOrigem[origem][1].pull))
  end
  local principal = porOrigem[ordemOrigem[1]]
  for _, origem in ipairs(ordemOrigem) do
    if #porOrigem[origem] > #principal then principal = porOrigem[origem] end
  end
  nota("passada principal: %d desenhos (amostra dos 8 primeiros)", #principal)
  for i = 1, math.min(8, #principal) do
    local d = principal[i]
    nota("  %-28s m1=%.1f m4=%.2f m8=%.2f m12=%.2f sol=%s",
      d.nome, d.m1, d.m4, d.m8, d.m12, tostring(d.temSol))
  end

  -- ---------------------------------------------------------------- P2
  -- The right test is one of INCLUSION, not equality. The scene draws more people
  -- than ow.entities lists: NPCs from NEIGHBORING maps enter as ghosts
  -- (OverworldController.ghosts), and the first version of this test failed because
  -- of that, not because of a host defect. The honest question is: does EVERY entity of
  -- this map appear drawn at its world position?
  -- The key has to be the PAIR (px,py), not two independent sets: a
  -- draw at py=10 and another (from ANOTHER entity) at px=5 don't prove that
  -- there is a draw at (5,10). Separate sets let through any
  -- cross combination of one entity's px with another's py.
  local desenhado = {}
  for _, d in ipairs(principal) do
    local py = d.m12 - 8
    -- m[4] carries px directly, or px+16 when mirrored (and then m[1] = -1).
    local px = d.m1 < 0 and (d.m4 - 16) or d.m4
    desenhado[string.format("%.2f/%.2f", px, py)] = true
  end
  local faltando = {}
  for _, e in ipairs(ow.entities) do
    if not desenhado[string.format("%.2f/%.2f", e.px, e.py)] then
      faltando[#faltando + 1] = string.format("(%.0f,%.0f)", e.px, e.py)
    end
  end
  nota("entidades deste mapa: %d | desenhos na passada principal: %d " ..
    "(o excedente sao NPCs de mapa vizinho)", #ow.entities, #principal)
  veredito("P2", #faltando == 0, string.format(
    "entidades (px,py) sem desenho correspondente: [%s]",
    table.concat(faltando, " ")))

  -- ---------------------------------------------------------------- P3
  -- Two DIFFERENT instances have to give different (px,py) pairs; if
  -- they collide, they're indistinguishable and would animate in unison.
  --
  -- Before comparing, remove EXACT REPEATS. The same character is
  -- drawn more than once in the same frame by the same call site: the
  -- host draws the water-reflected copy through this very same function
  -- (VoxelScene.lua:604-610, "the water's reflection copy, drawn by this same
  -- function"). An exact repeat (same sheet, same frame, same position) is a
  -- copy, not a second person; the first version of this test counted each
  -- character colliding with itself and failed 25 times.
  local exatos, unicos, copias = {}, {}, 0
  for _, d in ipairs(principal) do
    local px = d.m1 < 0 and (d.m4 - 16) or d.m4
    local py = d.m12 - 8
    local exato = string.format("%s@%.2f/%.2f", d.nome, px, py)
    if exatos[exato] then
      copias = copias + 1
    else
      exatos[exato] = true
      unicos[#unicos + 1] = { nome = d.nome, px = px, py = py }
    end
  end
  local vistos, colisoes = {}, {}
  for _, d in ipairs(unicos) do
    local k = string.format("%.2f/%.2f", d.px, d.py)
    if vistos[k] then
      colisoes[#colisoes + 1] = string.format("%s com %s em (%s)",
        d.nome, vistos[k], k)
    end
    vistos[k] = d.nome
  end
  for _, c in ipairs(colisoes) do nota("  colisao real: %s", c) end
  nota("%d desenhos = %d personagens + %d copias exatas (reflexo na agua)",
    #principal, #unicos, copias)
  veredito("P3", #unicos >= 2 and #colisoes == 0, string.format(
    "%d personagens distintos, %d colisoes de posicao", #unicos, #colisoes))

  -- ---------------------------------------------------------------- P4
  -- A single NPC over 60 frames. The expected value is RECALCULATED from its live py
  -- every frame, not fixed once: the NPCs in this game wander on their own,
  -- and a frozen expected value would turn "the NPC walked" into "the measurement failed".
  -- With a live expected value, the question becomes the right one: is the drawn value ALWAYS the
  -- world py of that instance, whether it moves or not.
  local alvo
  for _, e in ipairs(ow.npcs or {}) do
    if not e.moving then alvo = e break end
  end
  local function bate(q, e)
    local esperado = e.py + 8
    for _, d in ipairs(q) do
      if math.abs(d.m12 - esperado) < 0.01 then return true, esperado end
    end
    return false, esperado
  end
  if not alvo then
    veredito("P4", false, "nenhum NPC parado neste mapa para acompanhar")
  else
    nota("NPC alvo: %s em px=%d py=%d", tostring(alvo.id), alvo.px, alvo.py)
    local desvios, amostras, andou = 0, 0, 0
    for _ = 1, 60 do
      local q = observa()
      local ok = bate(q, alvo)
      amostras = amostras + 1
      if not ok then desvios = desvios + 1 end
      if alvo.moving then andou = andou + 1 end
    end
    veredito("P4", desvios == 0, string.format(
      "%d/%d quadros em que o valor desenhado nao era o py do NPC " ..
      "(ele andou sozinho em %d deles)", desvios, amostras, andou))
  end

  -- ---------------------------------------------------------------- P5
  -- Mirror. The player facing left and facing right: one of the two is
  -- mirrored (m[1] negative). m[12] can't change; m[4] can, and we
  -- measure HOW MUCH instead of assuming.
  local jogador = ow.player
  local function achaJogador(q)
    for _, d in ipairs(q) do
      if math.abs(d.m12 - (jogador.py + 8)) < 0.01 then return d end
    end
  end
  U.tap(game, "left");  U.wait(24)
  local esq = achaJogador(observa())
  U.tap(game, "right"); U.wait(24)
  local dir = achaJogador(observa())
  if esq and dir then
    local dz = math.abs(esq.m12 - dir.m12)
    local dx = dir.m4 - esq.m4
    nota("esquerda m1=%.1f m4=%.2f m12=%.2f | direita m1=%.1f m4=%.2f m12=%.2f",
      esq.m1, esq.m4, esq.m12, dir.m1, dir.m4, dir.m12)
    veredito("P5", dz < 0.01, string.format(
      "m[12] mudou %.3f ao espelhar (tem que ser 0); m[4] mudou %.1f", dz, dx))
  else
    veredito("P5", false, "nao localizei o jogador nos dois lados")
  end

  -- ---------------------------------------------------------------- P6
  -- Camera step. The lean is rotateX; it affects the rotation part of the
  -- matrix, and must not affect the translation.
  if alvo then
    local ruins = 0
    for i = 1, 7 do
      U.tap(game, "3")
      U.wait(20)
      local ok, esperado = bate(observa(), alvo)
      if not ok then
        ruins = ruins + 1
        nota("  rung %d: no draw with m[12]=%.1f", i, esperado)
      end
    end
    veredito("P6", ruins == 0, string.format(
      "%d de 7 degraus de camera mudaram o valor do NPC", ruins))
  else
    -- WITHOUT A STILL NPC THERE IS NO VERDICT, and before this P6 would simply vanish:
    -- the whole block lived inside `if alvo then`, so a map without a still
    -- NPC removed the check from the summary and `todos` stayed true. P4
    -- right above already handles the same case by emitting a false verdict, which is
    -- the correct thing: not measuring is a result, not the absence of one.
    veredito("P6", false, "nao achei NPC parado para observar entre degraus")
  end

  -- ---------------------------------------------------------------- P7 and P8
  -- Walking. Two questions at the same time: does the PLAYER'S value move continuously
  -- (P7) and does the value of the STILL NPC not move along with the camera (P8).
  local antes, saltoMax, nan = nil, 0, 0
  local npcMudou, camAntes, camAndou = 0, nil, 0
  local achouJogador = 0
  for passo = 1, 24 do
    table.insert(game.input.pressQueue, "down")
    game.input.state["down"] = true
    local q = observa()
    local dj = achaJogador(q)
    if dj then
      achouJogador = achouJogador + 1
      if dj.m12 ~= dj.m12 then nan = nan + 1 end
      if antes then
        local salto = math.abs(dj.m12 - antes)
        if salto > saltoMax then saltoMax = salto end
      end
      antes = dj.m12
    end
    if alvo and not bate(q, alvo) then npcMudou = npcMudou + 1 end
    local cam = ow.camera
    if cam then
      if camAntes and (cam.x ~= camAntes.x or cam.y ~= camAntes.y) then
        camAndou = camAndou + 1
      end
      camAntes = { x = cam.x, y = cam.y }
    end
    if passo % 8 == 0 and antes then
      nota("  passo %d: jogador m12=%.1f  camera=(%.0f,%.0f)",
        passo, antes, ow.camera and ow.camera.x or -1,
        ow.camera and ow.camera.y or -1)
    end
  end
  game.input.state["down"] = false
  U.wait(20)
  nota("the camera moved in %d of the 24 walking frames", camAndou)

  -- P7 only counts if the player was located in some frame. Without this, if
  -- achaJogador never matches in any of the 24 frames, saltoMax stays at 0 and nan
  -- at 0, and the test would pass without having measured anything: the same trap that P8
  -- guards against with camAndou > 0, just on the player's side.
  veredito("P7", achouJogador > 0 and nan == 0 and saltoMax <= 4.01, string.format(
    "maior salto entre quadros: %.2f px; NaN em %d quadros; jogador localizado " ..
    "em %d de 24 quadros (se for 0, o teste nao valeu)", saltoMax, nan, achouJogador))
  -- P8 only counts if the camera actually moved. Without this the test would pass for
  -- the trivial reason that nothing moved, which is this house's trap.
  veredito("P8", npcMudou == 0 and camAndou > 0, string.format(
    "o valor do NPC divergiu do py dele em %d de 24 quadros; " ..
    "a camera andou em %d quadros (se for 0, o teste nao valeu)",
    npcMudou, camAndou))

  -- ------------------------------------------------------------- summary
  nota("")
  nota("=== resumo ===")
  local todos = true
  for _, v in ipairs(vereditos) do
    if not v.ok then todos = false end
    nota("%-4s %s", v.nome, v.ok and "PASSED" or "FAILED")
  end
  nota("VERDICT: %s", todos and "A POSICAO CHEGA LIMPA"
    or "ALGO CHEGOU SUJO, ler acima")

  love.graphics.captureScreenshot("vc_probe_fim.png")
  U.wait(20)

  -- Undo both wraps. A driver that leaves the host patched poisons
  -- any subsequent measurement in the same process.
  Voxel3D.draw = drawOriginal
  SpriteBillboards.mesh = meshOriginal
end
