-- Grava os quadros de um clipe lado a lado: o mesmo lugar, a mesma camera, o
-- mesmo numero de quadros, uma vez com a opcao desligada e uma vez com ela
-- ligada. Quem monta o video e o clip.sh, com ffmpeg.
--
-- POR QUE ISTO EXISTE: BREATH, SWAY e MOTION LAG so significam alguma coisa no
-- TEMPO. Foto parada nao julga nenhuma das tres, e ate agora a unica forma de
-- mostrar o efeito para alguem era pedir para a pessoa abrir o jogo. Um clipe
-- de tres segundos resolve isso, e e tambem o que a comunidade consegue ver
-- numa mensagem de Discord.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  io.stdout:setvbuf("line")
  -- Sem isto o laco anda a menos de um quadro por segundo com a janela
  -- ocluida, e gravar 200 quadros levaria minutos. Ver tools/ingame/driver.lua.
  if love.window and love.window.setVSync then pcall(love.window.setVSync, 0) end

  local function log(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    print("[clip] " .. (ok and s or tostring(fmt)))
  end

  local OPT = os.getenv("VC_CLIP_OPT") or "breath=0.020"
  local CHAVE, VALOR = OPT:match("^([%w_]+)=(.+)$")
  if not CHAVE then log("opcao ilegivel: %s", OPT); return end
  local NUM = tonumber(VALOR) or VALOR
  local QUADROS = tonumber(os.getenv("VC_CLIP_FRAMES")) or 96
  local PASSO = tonumber(os.getenv("VC_CLIP_STEP")) or 2  -- captura 1 em cada N
  local ZOOM = tonumber(os.getenv("VC_CLIP_ZOOM")) or 0

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
    if not ok then log("AVISO: a troca de %s NAO foi emitida", chave) end
    return ok
  end

  -- POUSO. Ver tools/ingame/pouso.lua: U.teleport nao valida nada, e por isso
  -- o jogador aterrissava em cima de placa e de mesa nas fotos do gate.
  local pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")
  local mapa, x, y = pouso.escolher(game,
    os.getenv("VC_MAP") or "OAKS_LAB",
    tonumber(os.getenv("VC_X")) or 5,
    tonumber(os.getenv("VC_Y")) or 10)
  U.teleport(game, mapa, x, y, os.getenv("VC_FACING") or "down")
  U.wait(60)
  if not (game.overworld and game.stack:top() == game.overworld) then
    log("nao cheguei ao mundo"); return
  end
  log("mapa %s em (%d,%d)", mapa, x, y)

  -- POR QUE FECHADO E NAO NA RUA. Na rua o ceu tem ciclo de dia, e como os dois
  -- lados sao gravados um depois do outro, o degrade do fundo muda entre eles:
  -- quem olha o lado a lado ve o ceu diferente antes de ver o personagem
  -- respirar, e a diferenca que importa fica em segundo plano. Dentro do
  -- laboratorio nao ha ceu, e ainda tem gente parada o bastante para mostrar
  -- que cada um respira na sua fase.
  --
  -- ZOOM ZERO POR PADRAO. Forcar zoom no jogo puxa a camera para um angulo
  -- baixo e o quadro vira parede e chao. Quem aproxima e o RECORTE no clip.sh,
  -- depois, sobre o que o jogo desenhou: o personagem fica sempre perto do
  -- centro porque a camera o segue, entao recortar o centro basta e nao mexe em
  -- nada da cena.
  U.tap(game, "3")
  U.wait(30)
  for _ = 1, ZOOM do
    if game.zoomStep then game:zoomStep(1) end
  end
  U.wait(30)

  -- BLINK desligado durante o clipe: ele anima olho no tempo e apareceria nos
  -- dois lados, confundindo quem tenta ver o que a opcao muda.
  opcao("blink", "off")
  opcao("breath", "off"); opcao("sway", "off"); opcao("lag", "off")
  U.wait(30)

  -- MOTION LAG so existe com o personagem SE MOVENDO: parado, a mola esta em
  -- repouso e os dois lados sairiam identicos, o que faria o clipe provar que a
  -- feature nao faz nada. Entao para essa opcao os dois lados andam, e andam
  -- IGUAL: mesma direcao, mesmo numero de quadros, invertendo no meio para o
  -- personagem nao sair do enquadramento.
  local ANDA = (CHAVE == "lag") or os.getenv("VC_CLIP_ANDAR") == "1"

  local function grava(tag)
    for i = 1, QUADROS do
      if ANDA then
        local dir = (math.floor((i - 1) / 24) % 2 == 0) and "left" or "right"
        table.insert(game.input.pressQueue, dir)
        game.input.state[dir] = true
        game.input.state[dir == "left" and "right" or "left"] = false
      end
      love.graphics.captureScreenshot(string.format("vc_clip_%s_%04d.png", tag, i))
      for _ = 1, PASSO do coroutine.yield() end
    end
    if ANDA then
      game.input.state["left"] = false
      game.input.state["right"] = false
      U.wait(45)  -- deixa a mola voltar ao repouso antes do proximo lado
    end
    log("lado %s gravado%s", tag, ANDA and " (andando)" or "")
  end

  -- Lado esquerdo: desligado.
  grava("off")

  -- Lado direito: a opcao pedida. MOTION LAG so aparece com o personagem se
  -- movendo, entao para ela os dois lados andam; para as outras, os dois lados
  -- ficam parados. O que os dois lados nunca fazem e coisas diferentes.
  opcao(CHAVE, NUM)
  U.wait(30)
  grava("on")

  log("quadros por lado: %d", QUADROS)
  U.wait(10)
end
