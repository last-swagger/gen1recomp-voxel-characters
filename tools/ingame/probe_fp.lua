-- In-game gate for FIRST PERSON.
--
-- Since v1.3.0 this mod returned the flat card whenever first person
-- was active. It was not lack of support, it was a fix: Colonel_Aureliano
-- reported black spikes, and the card does not have the defect.
--
-- Reading the host, the defect is not the camera's, it is the DISTANCE's. The shader pushes
-- each vertex along its own ray toward the eye by `pull` units
-- (Voxel3D.lua:122-130); first person is step 6 and ANGLES_DEG[7] = 75
-- degrees, so pull = 6 world units with the tile worth 16; the near plane
-- sits at 1 unit when eye and focus are together. A vertex at distance d
-- ends up at d - 6: it crosses the near plane at d < 7 and goes behind the eye
-- at d < 6. The flat card survives because all its vertices cross
-- together; in a solid the corners are at different distances.
--
-- The offline suite already proves the MATH: sweeping 0 to 80 units, the passed pull
-- never reaches the eye, and breaking the clamp kills four checks. This file
-- measures the one thing the suite cannot: whether the right math reaches the SCREEN.
--
--   P1 it actually entered              the blend reaches 1; without it, everything below
--                                       would be measuring a different camera
--   P2 character is on screen           control by switching the whole mod on and off.
--                                       It's the first one I need because zero
--                                       difference has two opposite causes: the option
--                                       did not arrive, or there was nothing to change
--   P3 the solid appears                with character confirmed on screen, SOLID
--                                       differs from CARD
--   P4 the TRANSITION doesn't explode   sweeping the blend, the SOLID-CARD difference
--                                       stays on the order of the volume and not of the frame,
--                                       compared against a floor measured the SAME
--                                       way
--
-- P4 is what matters. The PLAYER'S OWN card is the catastrophic case,
-- because the camera is entering his head and the distance goes to zero, and the
-- host only hides that card after blend > 0.9. The range swept here is
-- exactly where the defect lived.
--
-- TWO TRAPS THIS FILE ALREADY PAID FOR, written so they don't repeat:
--
--   VoxelState.setLevel DOES NOT COMMAND. The owner of the step is the engine's
--   Pipelines, and Voxel.update(level) (VoxelState.lua:180) rewrites Voxel.level
--   from it every frame. The symptom of calling the wrong one was "the blend never
--   went up", which looks like the camera does not exist on this machine.
--
--   PHOTOGRAPHING BOTH SIDES WHILE THE CAMERA MOVES measures the camera. In the first
--   version this gave 80 to 94 percent of the frame differing, and nothing was a spike.
--   Each side now comes from its own entry with the same wait, and the sample
--   only counts if the two blends match.

return function(game)

  -- NOBODY IN THE ROOM BUT THE PLAYER, enforced instead of assumed.
  --
  -- This gate differences photographs of a room the ROM leaves empty. An
  -- INSTALL does not: a mod can put a real engine NPC on any map at runtime
  -- through the host's own OverworldState:addRuntimeObject, and
  -- overworld_wild_spawns does exactly that here. Measured 2026-08-13 in
  -- probe_walk, on this same map, by planting a wandering stranger one cell
  -- from the player: two photographs of the SAME pose with the SAME options
  -- went from 0 pixels apart to 639, which is most of a character, and the gate
  -- went red on a mod that was working.
  --
  -- So everyone who is not the player comes out of the three lists the host
  -- draws and updates from -- the same surgery the host performs on itself when
  -- a runtime object is dropped (OverworldController:2600, :3894). setMap
  -- rebuilds those lists, so it runs after every teleport, and `espera` repeats
  -- it every ten frames because a mod that adds its object back mid-run has to
  -- be caught mid-run.
  local retirados = 0
  local function soOJogador()
    local ow = game.overworld
    if not ow then return end
    local p = ow.player
    for _, lista in ipairs({ ow.entities or {}, ow.npcs or {}, ow.ghosts or {} }) do
      for i = #lista, 1, -1 do
        local e = lista[i]
        if (e.npc or e) ~= p then table.remove(lista, i); retirados = retirados + 1 end
      end
    end
  end
  local function espera(n)
    for i = 1, n do
      if i % 10 == 0 then soOJogador() end
      coroutine.yield()
    end
  end
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
    nota("%-3s %s  %s", nome, ok and "PASSED" or "FAILED", detalhe or "")
  end

  local function fim()
    nota("")
    local todos = true
    for _, v in ipairs(vereditos) do
      nota("%-3s %s", v.nome, v.ok and "PASSED" or "FAILED")
      todos = todos and v.ok
    end
    nota("VERDICT: %s", todos
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
    if not ok then nota("WARNING: the change of %s was NOT emitted", chave) end
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

  -- The host, through the same door the mod uses.
  -- ALL THREE HOSTS, not just the original. The mod accepts DRAMATIC_SHAPE, the
  -- battle art fork by absol89 and Dramaless by artyrambles (main.lua:37-47), and
  -- probe_life.lua already sweeps all three. This file only asked for the first, so in the
  -- fork that a good part of the community runs it failed at P0 and the whole gate
  -- was skipped, with nobody seeing the difference between "did not measure" and "measured and
  -- passed".
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

  -- COMING OUT IS WAITED FOR, NOT COUNTED, and this is the defect that made P4
  -- fail about half the runs on one machine and none on the other.
  --
  -- The blend is TIME-driven: `FirstPerson.update` moves it by
  -- `dt / BLEND_TIME` with BLEND_TIME = 0.45 s. This driver waited for it in
  -- FRAMES -- `sai(); U.wait(50)` -- and the first thing it does is turn vsync
  -- OFF, so a frame is however long the machine needs. On the Mac Studio a
  -- frame is 4.6 ms, so fifty of them are 0.23 s: HALF the time the blend needs
  -- to fall back to zero. `entra()` was then starting the climb from wherever
  -- the fall had got to, and two samples that stop at the same blend VALUE were
  -- reached along different curves, with the camera in different places.
  --
  -- What that looked like, measured inside a full battery on 2026-08-13:
  --
  --   blend 0.13   floor 16281 (18.6%)   discarded
  --   blend 0.21   floor     0           CARD-SOLID 4919
  --   blend 0.31   floor 21290 (24.3%)   discarded
  --   blend 0.42   floor 11492 (13.1%)   discarded
  --   blend 0.53   floor 21522 (24.6%)   discarded
  --   blend 0.64   floor     0           CARD-SOLID 2291
  --   blend 0.74   floor 45795 (52.3%)   discarded
  --   blend 0.83   floor 26445 (30.2%)   discarded
  --
  -- Six of eight thrown away, so `usadas >= 5` failed. The discard rule was
  -- right -- those samples measured the camera -- but it was catching a defect
  -- in the instrument, not in the scene. The render machine, at 8.9 ms a frame,
  -- got 0.45 s out of the same fifty frames and never saw it.
  --
  -- So the exit is waited out on the blend's own value, which is the state that
  -- actually decides, and needs no assumption about frame rate at all.
  local function saiEEspera()
    sai()
    for _ = 1, 900 do
      coroutine.yield()
      if blendAgora() <= 0 then break end
    end
    U.wait(5)
  end
  nota("FP_LEVEL do host: %d", FPLEVEL)

  -- RED'S ROOM, and the return to it tells a whole story.
  --
  -- First choice: Red's room, zero object events. Wrong, because at
  -- FULL blend the only character there is the player and the host hides his
  -- card above 0.9. The screen was left with nobody and the measurement gave zero, which reads
  -- as "the solid doesn't appear".
  --
  -- Second choice: pokemon center, "because there are people standing around". It measured with
  -- luck: one run found an NPC in the camera's cone and the next found
  -- none in the four directions. And when I finally matched the blends, the CARD
  -- against CARD floor gave 29 thousand out of 87 thousand samples, 33% of the frame, because
  -- that map has NPCs walking and the gate was measuring them.
  --
  -- Third, and the right one: Red's room AGAIN, but measuring at the MIDDLE of the blend
  -- instead of at the end. There the player's own card is in the scene by
  -- construction, and it's the worst case of the defect, because the camera is entering
  -- his head. Zero object events becomes the advantage it used to be again.
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

  -- ---------------------------------------------------------------- P1 and P2
  --
  -- THE FIRST PERSON CAMERA LOOKS WHERE THE PLAYER LOOKS, so the direction
  -- of the teleport decides whether there is a character in frame. Instead of me choosing
  -- a direction and hoping, the gate MEASURES all four: turns the whole mod on and off
  -- and keeps the one that changes the most. That's the same question as the negative control,
  -- answered once and reused.
  -- THE CONTROL MEASURES AGAINST THE PLAYER'S OWN CARD, and not against an NPC that
  -- might be in frame.
  --
  -- The previous version swept the four directions looking for someone in the scene. It
  -- refused the verdict when it didn't find one, which is correct, but found one by luck:
  -- same command, one run found 531 samples and the next found zero in the
  -- four. The probe teleports to a pokemon center and hopes for an NPC to be
  -- in the camera's cone, and where the NPCs are is not something it controls. A gate
  -- that fails for a reason unrelated to the code teaches you to run it again until it's
  -- green, and a gate that gets run again is not a gate.
  --
  -- The player is ALWAYS in the scene below blend 0.9: the host only hides his card
  -- above that (FirstPerson.hidePlayer), and the range below is exactly
  -- where the spike defect lived, because it's where the camera enters his
  -- head. So the control lives there: guaranteed, and in the case that matters.
  -- WAITING FOR THE BLEND, and not for a number of frames. Counting frames gave
  -- 0.64 on one side and 0.94 on the other, and the difference between the two photos became
  -- the CAMERA instead of the option: 62 thousand "control" samples that did not
  -- control anything. Stopping at a blend value makes the two sides match by
  -- construction.
  local ALVO = 0.55
  local function noBlend(alvo)
    saiEEspera()
    entra()
    for _ = 1, 240 do
      U.wait(1)
      if blendAgora() >= alvo then break end
    end
    local b = blendAgora()
    return b, captura()
  end

  saiEEspera()
  U.teleport(game, MAPA, PX, PY, "down")
  U.wait(20)
  soOJogador()
  espera(20)
  nota("%d stranger(s) taken out of the scene", retirados)

  -- THE CONTROL RUNS IN SOLID, and this already fooled me once. With FIRST PERSON
  -- set to CARD the mod returns the original card in this camera BY CONTRACT, so
  -- turning the whole mod on and off changes nothing and the control measures zero by
  -- design decision, not by lack of character in the scene. A control that
  -- can give zero for the right reason and for the wrong reason controls nothing.
  opcao("first_person", "solid")
  opcao("depth", 3); U.wait(8)
  local bCom, com = noBlend(ALVO)
  opcao("depth", "off"); U.wait(8)
  local bSem, sem = noBlend(ALVO)
  opcao("depth", 3); U.wait(8)
  total(com)
  local melhor = { dir = "down", delta = difere(com, sem) }
  nota("controle no blend %.2f e %.2f: mod on against desligado %d de %d",
       bCom, bSem, melhor.delta, total())
  veredito("P1", math.abs(bCom - bSem) <= 0.05 and bCom > 0.02 and bCom < 0.9,
    string.format("as duas medidas casaram no meio da entrada: blend %.2f e "
      .. "%.2f", bCom, bSem))
  if math.abs(bCom - bSem) > 0.05 then
    nota("different blends: the measurement would be of the camera, not the option")
    return fim()
  end

  veredito("P2", melhor.delta > total() * 0.002,
    string.format("ha personagem nosso na tela: %d de %d amostras (%.2f%%)",
      melhor.delta, total(), melhor.delta / total() * 100))
  if melhor.delta <= total() * 0.002 then
    nota("nem o card do proprio jogador aparece; nada abaixo mede a opcao")
    return fim()
  end

  -- From there on, always the same direction.
  local DIR = melhor.dir
  local function posiciona()
    saiEEspera()
    U.teleport(game, MAPA, PX, PY, DIR)
    U.wait(20)
    soOJogador()
    espera(20)
  end

  -- ---------------------------------------------------------------- P3
  -- At the SAME blend as the control, because that's where a character is guaranteed to exist.
  local function ladoNoBlend(modo)
    opcao("first_person", modo); U.wait(8)
    return noBlend(ALVO)
  end
  local b1, c1 = ladoNoBlend("card")
  local b2, c2 = ladoNoBlend("card")
  local b3, s1 = ladoNoBlend("solid")
  local piso = difere(c1, c2)
  local sinal = difere(c1, s1)
  nota("blend %.2f/%.2f/%.2f: floor CARD-CARD %d, signal CARD-SOLID %d of %d",
       b1, b2, b3, piso, sinal, total())
  veredito("P3", sinal > piso * 2 + 20,
    string.format("o SOLID muda a tela: %d contra piso %d", sinal, piso))

  -- ---------------------------------------------------------------- P4
  --
  -- THE FLOOR COMES FROM THE SAME PROCEDURE. Comparing the difference against a number
  -- I picked by hand would measure my own guess; comparing against CARD-CARD
  -- done with the same output, same input and same wait measures only what the
  -- option changed. Everything the scene does on its own in that interval shows up in both.
  -- Also by blend, and not by frame. With frame counting the transition
  -- floor reached 39 thousand out of 87 thousand samples, almost the whole ceiling: the
  -- two sides stopped at different blends and the difference was the camera.
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
    -- A SAMPLE WHOSE OWN FLOOR IS LARGE MEASURES THE SCENE, NOT THE OPTION.
    --
    -- Matching blends was the only discard rule, and it is necessary but not
    -- sufficient. Measured across four runs of an unchanged build, P4 failed
    -- twice: once with floor 51679 and signal 61280, once with floor 48568 and
    -- signal 51328, against runs where the floor was 0 and the signal 5206.
    -- The blends matched in all of them. Something else moved.
    --
    -- When the CARD-CARD control already differs by half the frame, the
    -- CARD-SOLID number from the same sample is that same movement plus
    -- whatever the option did, and there is no way to separate them
    -- afterwards. So the sample is thrown away rather than reasoned about.
    --
    -- 5% is far above the 0 a settled scene produces and far below the ~55%
    -- the bad samples produced, so it is not a threshold tuned to make
    -- anything pass: nothing sits near it.
    local PISO_MAX = total() * 0.05
    if math.abs(bA - bF) > 0.03 or math.abs(bA - bS) > 0.03 then
      descartadas = descartadas + 1
      nota("  discarded: blends %.2f / %.2f / %.2f did not agree", bA, bF, bS)
    else
      local p = difere(imgA, imgF)
      local d = difere(imgA, imgS)
      if p > PISO_MAX then
        descartadas = descartadas + 1
        nota("  discarded: blend %.2f with floor %d (%.1f%%), the scene was not"
             .. " parada", bA, p, p / total() * 100)
      else
        usadas = usadas + 1
        if d > piorSinal then piorSinal, piorBlend, piorPiso = d, bA, p end
        nota("  blend %.2f   floor %d (%.1f%%)   CARD-SOLID %d (%.1f%%)",
             bA, p, p / total() * 100, d, d / total() * 100)
      end
    end
  end
  saiEEspera()

  -- THE CRITERION. An honest solid differs from the card in the BODY and nothing else, and the
  -- body in first person is large, so a tight ceiling would fail the
  -- feature working. The spike is different in kind: the black wedge comes out of the
  -- body and sweeps the frame. Half the frame separates the two with margin on both
  -- sides, and the floor measured with the same procedure says how much of that is the scene.
  local TETO = total() * 0.5
  -- CEILING AND FLOOR. With only a ceiling, P4 doesn't distinguish "did not explode" from "did not
  -- draw": a SOLID that fell back to the card during the transition would give a
  -- zero signal, which is <= ceiling, and would pass. P3 doesn't cover this because it measures at the
  -- target blend, not on the sweep.
  veredito("P4", usadas >= 5 and piorSinal <= TETO
      and piorSinal > piorPiso * 2 + 100,
    string.format("pior CARD-SOLID na transicao %d (%.1f%%) no blend %.2f, "
      .. "entre o piso %d e o teto %d (50%%); %d usadas, %d descartadas",
      piorSinal, piorSinal / total() * 100, piorBlend, piorPiso,
      math.floor(TETO), usadas, descartadas))

  opcao("first_person", "card")
  fim()
end
