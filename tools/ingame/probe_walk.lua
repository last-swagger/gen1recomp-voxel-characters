-- NEITHER POSE MAY LOSE THE BODY COLOUR THE OTHER ONE FINDS.
--
--   POKEPORT_VERSION=blue POKEPORT_DRIVER=mods/voxel_characters/tools/ingame/probe_walk.lua \
--     love .
--
-- WHY THIS EXISTS, and nothing offline reaches it.
--
-- Every SLAB face this mod invents -- top, bottom, sides -- carries no art: the
-- artist only ever drew the front. SIDE COLOR: BODY searches inward from the
-- silhouette for the first non-outline texel and paints the face with it, and
-- `bodyTexelInFrame` RETURNS THE OUTLINE WHEN THAT SEARCH FAILS. The outline is
-- black. Whether the search succeeds depends on the row, and the walking pose
-- is the standing pose shifted down one row (a deliberate step in the original
-- art), so a face that finds body while standing can fail while walking: it
-- goes black on one pose and comes back on the next.
--
-- That report has arrived three times -- AngelusRole in v1.4.2, Kim on the HD
-- sheet in v1.6.x, Kim again on the shipped defaults -- and every time the
-- offline suite was green, because the defect is a UV landing on the wrong
-- texel and the suite reads geometry. Two of the three fixes (v1.2.2's fixed
-- reference frames, v1.4.2's poseOffset) exist only in prose and in checks that
-- cannot see a pixel.
--
-- WHAT IT MEASURES, and why it is not what the two earlier attempts measured:
--
--   * measuring colour across the whole FRAME lets the defect through, because
--     one character is a couple of percent of a screen full of scenery
--     (probe_hd learned this the hard way and let a grey character pass its own
--     mutation test);
--   * counting black across a WALK lets it through the other way: the character
--     crosses the room and the box fills with different furniture. Measured on
--     a real forty frame walk, the black count inside a fixed screen box swings
--     between 2150 and 3556, all of it scenery.
--
-- SO IT ISOLATES THE CHARACTER WITH A THIRD PHOTOGRAPH: the same cell with
-- VOXEL CHARS: OFF, which is the host's own flat card on the same ground. Every
-- pixel where the card and the solid differ is the character and nothing else,
-- found without knowing where it stands. Inside that set it counts black, once
-- with SIDE COLOR: OUTLINE (which hands every new face the original texel and
-- never searches for anything, so it is the yardstick: this is how black the
-- character is when the search does not run) and once with SIDE COLOR: BODY.
-- What BODY takes off that number is how well the inward search is working, in
-- pixels, on screen.
--
-- DIFFERENCING THE TWO SIDE COLOR RENDERS AGAINST EACH OTHER DOES NOT WORK, and
-- the first version of this gate did exactly that and was structurally unable
-- to fail: a face whose search GIVES UP is painted with the outline, which is
-- what OUTLINE would have painted anyway, so it comes out identical under both
-- settings and drops out of the difference before anything can count it. The
-- gate was measuring only the faces that had succeeded. Both mutation tests
-- below sailed through it.
--
-- AND IT DOES ALL OF THAT TWICE, once per walk pose, AT THE SAME POSITION. The
-- host animates a blocked step without moving the cell (Player.lua:189, issue
-- #230), so pushing into a wall turns the pose over while the camera, the
-- scenery and the character stay exactly put. Both poses are checked because
-- the two defects this family has actually shipped break one pose each: the
-- unscaled search fails standing, the missing pose compensation fails walking.
-- A gate that photographed one pose would have caught one of the two and
-- reported itself green on the other.
--
-- FIVE CHECKS, and three of them exist to stop an empty green:
--
--   W1 the poses came out as asked and the character never left the cell;
--   W2 nothing ELSE in the frame moved. Measured as a second photograph of the
--      first pose, taken last, through the same path;
--   W3 the character is really in frame and OUTLINE really does leave black
--      there to be removed;
--   W4 standing, BODY removes a real share of it;
--   W5 walking, likewise. Either one collapsing is the regression.
--
-- WHAT THIS GATE DOES NOT SEE, written down because the omission is deliberate
-- and it is exactly where the report that prompted the gate turned out to live.
--
-- Everything that moves on its own is pinned OFF below, so that two
-- photographs differ only by the pose. That makes the measurement possible and
-- it makes this gate blind to the whole LIFE channel. Measured with the same
-- instrument -- pose pinned, cell fixed, character isolated against the flat
-- card -- as the share of the character's pixels whose luminance swings by more
-- than 0.15 across 60 frames, and the mean swing:
--
--                            FRONT SHAPE: OFF      FRONT SHAPE: HIGH
--   nothing moving              0.0%  0.0000          0.0%  0.0000
--   BLINK alone                 0.0%  0.0000          0.0%  0.0000
--   PART LAG alone              0.0%  0.0000          0.0%  0.0000
--   BREATH: SUBTLE (ships on)   4.9%  0.0274          3.8%  0.0169
--   BREATH: NORMAL              4.3%  0.0227          0.7%  0.0032
--   SWAY: NORMAL               10.9%  0.0638          2.5%  0.0149
--
-- So the flicker Kim reported is real, it needs a GEOMETRIC life option running
-- (BREATH or SWAY; BLINK and PART LAG produce none of it), and the affected
-- pixels lie on the horizontal boundaries between sprite rows -- which is what
-- "umas linhas da figurinha quebram" describes. It is sub-pixel resampling of
-- an unfiltered sheet on a solid that is being moved by fractions of a screen
-- pixel, and 65.7% of Red is exactly RGB(0,0,0), so the neighbour a boundary
-- resamples toward is usually black.
--
-- FRONT SHAPE IS NOT ITS CAUSE, and the test that says so is worth keeping:
-- rebuilding the OFF path to emit one quad per pixel, so its geometry is
-- identical to the ON path and no run-width T-junction survives, left SWAY at
-- 10.9% and 0.0641 -- unchanged. The only remaining difference between the two
-- columns is the shade, and a darker pixel swings less in absolute luminance
-- under the same motion. FRONT SHAPE: OFF does not create the flicker; it
-- leaves the front face at full brightness, so the same swing reads as a bright
-- line breaking into black instead of as texture. That is why turning the
-- option off is what made Kim notice it.
--
-- None of that is gated here. Gating it needs a threshold nobody has agreed on
-- yet, because some of the swing is the honest cost of moving pixel art in 3D.
--
-- FRONT SHAPE IS PINNED OFF, and not for a neutral reason: its stepped shading
-- darkens the front face toward each run's edge on purpose, which adds dark
-- pixels that have nothing to do with this defect. It is also the setting the
-- last report came in on.
return function(game)
  local function log(f, ...) print("[walk] " .. string.format(f, ...)) end
  local U = dofile("tests/drivers/util.lua")
  local vereditos, todos = {}, true
  local function veredito(nome, ok, detalhe)
    if not ok then todos = false end
    vereditos[#vereditos + 1] = { nome = nome, ok = ok }
    log("%s  %s  %s", nome, ok and "PASSED" or "FAILED", detalhe or "")
  end
  local function fim()
    log("")
    for _, v in ipairs(vereditos) do log("%-3s %s", v.nome, v.ok and "PASSED" or "FAILED") end
    log("VERDICT: %s",
      todos and "BOTH POSES KEEP THEIR BODY COLOUR" or "LER ACIMA")
    U.wait(10)
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
    return game.mods and game.mods.events
      and pcall(game.mods.events.emit, game.mods.events, "mod.options_changed",
        { mod = "voxel_characters", key = chave, value = valor })
  end

  -- Near-black on a screen the host has already lit. The outline this mod can
  -- wrongly hand to a face is the darkest tone in the sheet; nothing the art
  -- puts on a character's body comes near this.
  local function preto(r, g, b) return math.max(r, g, b) < 0.18 end

  -- Walks two photographs once and reports only about the pixels that DIFFER:
  -- how many there are, and how many of them are black in the SECOND one.
  local function recorte(a, b)
    if not (a and b) then return { mudados = 0, pretoB = 0 } end
    local r = { mudados = 0, pretoB = 0 }
    for y = 0, a:getHeight() - 1, 2 do
      for x = 0, a:getWidth() - 1, 2 do
        local r1, g1, b1 = a:getPixel(x, y)
        local r2, g2, b2 = b:getPixel(x, y)
        if math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2) > 0.05 then
          r.mudados = r.mudados + 1
          if preto(r2, g2, b2) then r.pretoB = r.pretoB + 1 end
        end
      end
    end
    return r
  end

  log("=== gate do WALK ===")
  local pouso = dofile("mods/voxel_characters/tools/ingame/pouso.lua")
  -- UPSTAIRS IN RED'S HOUSE, and the room is chosen rather than inherited.
  -- Oak's lab is where the other probes stand, and it has people in it who walk
  -- on their own: measured there, two photographs of the SAME pose with the
  -- SAME options differed by 1648 pixels, which is most of a character. This
  -- room has nobody in it, and the same measurement gives 0.
  local MAPA = os.getenv("VC_MAP") or "REDS_HOUSE_2F"
  local X0 = tonumber(os.getenv("VC_X")) or 4
  local Y0 = tonumber(os.getenv("VC_Y")) or 4
  local SO_ESTA = os.getenv("VC_FACING")

  -- A cell we may stand on with a WALL next to it, because the wall is what
  -- keeps the walk in one place. `pouso.recusa` answers "may I stand here"; the
  -- map's own `isWalkableCell` answers "is that a wall". A door is neither, and
  -- the first version of this walked through one and lost the map.
  local okML, MapLoader = pcall(require, "src.world.MapLoader")
  local map = okML and select(2, pcall(MapLoader.load, game.data, MAPA)) or nil
  local DELTA = { { "down", 0, 1 }, { "up", 0, -1 }, { "left", -1, 0 }, { "right", 1, 0 } }
  local function parede(cx, cy)
    if not map then return false end
    local ok, andavel = pcall(map.isWalkableCell, map, cx, cy)
    return not (ok and andavel == true)
  end
  local ax, ay, encosto
  for raio = 0, 12 do
    for dx = -raio, raio do
      for dy = -raio, raio do
        if math.max(math.abs(dx), math.abs(dy)) == raio and not encosto then
          local cx, cy = X0 + dx, Y0 + dy
          if not pouso.recusa(map, nil, cx, cy) then
            for _, d in ipairs(DELTA) do
              if (not SO_ESTA or SO_ESTA == d[1]) and parede(cx + d[2], cy + d[3]) then
                ax, ay, encosto = cx, cy, d[1]
                break
              end
            end
          end
        end
      end
    end
    if encosto then break end
  end
  if not encosto then
    veredito("W1", false, string.format(
      "nenhuma celula perto de %s %d,%d tem parede ao lado, entao nao ha onde "
      .. "andar sem sair do lugar", MAPA, X0, Y0))
    return fim()
  end

  U.teleport(game, MAPA, ax, ay, encosto)
  U.wait(60)
  if not (game.overworld and game.stack:top() == game.overworld) then
    veredito("W1", false, "nao cheguei ao mundo")
    return fim()
  end
  local p = game.overworld.player

  -- Everything that moves on its own is pinned off: BREATH, SWAY and BLINK
  -- would each change the picture between two photographs for a reason that is
  -- not the pose, and W2 would report them as somebody walking through.
  local FIXO = {
    depth = 3, shape = "slab", ground_shade = "on", top_edge = "on",
    front_shape = "off", top_dome = "off", step_weight = "off",
    grid_chars = "off", blink = "off", breath = "off", sway = "off",
    lag = "off", footfall = "off", attention = "off", part_lag = "off",
    -- HD SPRITE: ON, AND THIS IS THE WHOLE REASON THE GATE CAN GO RED.
    --
    -- On the ordinary 16 px sheet the outline is ONE pixel thick, so a four
    -- step inward search essentially cannot fail and the branch that hands a
    -- face the outline's black is unreachable. Measured: forcing
    -- BODY_SEARCH_LIMIT down to 1 on the 16 px sheet moved the black count by
    -- five pixels out of two thousand. Pointing the gate there would be
    -- pointing it at a configuration where the defect does not exist.
    --
    -- On the 64 px HD sheet the outline is four pixels thick, the search really
    -- does run out, and that is where the flicker was reported and fixed. The
    -- sheet ships with the mod (hd/red.png) so this costs nothing to set up.
    hd_sprite = "on", first_person = "card", demo_fx = "off",
    authored_regions = "off",
  }
  for k, v in pairs(FIXO) do opcao(k, v) end
  U.wait(45)

  -- HOLD THE POSE STILL WHILE THE SHUTTER IS OPEN, and this is the correction
  -- that turned the gate from noise into a measurement. Pushing into the wall
  -- animates the walk, but it does not stop: `walkPhase` is
  -- `(animClock % 16) >= 4 and < 12`, so the standing half of the cycle is only
  -- four frames wide. A screenshot takes a frame or two to come back, and the
  -- first version simply waited for the phase it wanted and then opened the
  -- shutter -- which regularly landed on the OTHER pose. Two photographs
  -- labelled "standing" then differed by 549 of the 599 pixels the option was
  -- supposed to move, and W2 correctly refused the whole run.
  --
  -- So the probe pins the clock instead of chasing it: `animClock` is held at a
  -- value in the middle of the wanted half and `bumpFrames` is kept armed, the
  -- same two fields the engine's own in-place bonk writes (Player.lua:194-197).
  -- Pinning the clock pins the mirrored cycle too (`flip` is
  -- `floor(animClock/16) % 2`, Player.lua:273), so the alternating foot cannot
  -- change under the shutter either. The direction stays held: the engine is
  -- really performing a blocked step, this only stops the film from advancing.
  --
  -- 1 and 6 are the middles of the two halves, three and five frames clear of
  -- the nearest boundary.
  local RELOGIO = { [0] = 1, [1] = 6 }
  local function empurra(fase)
    table.insert(game.input.pressQueue, encosto)
    game.input.state[encosto] = true
    if fase then
      p.bumpFrames = 8
      p.animClock = RELOGIO[fase]
    end
  end
  local function fotoNaFase(fase)
    -- Long enough for the pinned pose to be drawn, and for a mesh built on its
    -- first draw to be on screen before the shutter opens.
    for _ = 1, 12 do empurra(fase); coroutine.yield() end
    if p:walkPhase() ~= fase then return nil end
    local pronto
    love.graphics.captureScreenshot(function(d) pronto = d end)
    for _ = 1, 120 do
      empurra(fase)
      coroutine.yield()
      if pronto then return p:walkPhase() == fase and pronto or nil end
    end
  end

  local cx0, cy0 = p.cellX, p.cellY
  local fotos, faltou = {}, nil
  for _, cor in ipairs({ "chapa", "outline", "body" }) do
    opcao("depth", cor == "chapa" and "off" or 3)
    opcao("side_color", cor == "chapa" and "outline" or cor)
    -- Released while the mesh cache clears: holding the direction here would
    -- only spin the walk clock, and `fotoNaFase` re-arms it anyway.
    game.input.state[encosto] = false
    U.wait(45)
    for _, fase in ipairs({ 0, 1 }) do
      local f = fotoNaFase(fase)
      if not f then faltou = string.format("%s fase %d", cor, fase) end
      fotos[cor .. fase] = f
    end
  end
  -- THE FLOOR: the first pose and the first colour, all over again, through the
  -- same path. It is the only way to know how much two photographs differ for a
  -- reason that is not the thing being measured.
  opcao("depth", 3)
  opcao("side_color", "outline")
  game.input.state[encosto] = false
  U.wait(45)
  fotos.piso = fotoNaFase(0)
  game.input.state[encosto] = false

  veredito("W1", not faltou and fotos.piso
    and p.cellX == cx0 and p.cellY == cy0, string.format(
    "andando de encontro a parede %s em %s %d,%d; celula %d,%d -> %d,%d "
    .. "(tem de nao sair do lugar)%s", encosto, MAPA, ax, ay, cx0, cy0,
    p.cellX, p.cellY, faltou and (", faltou a foto de " .. faltou) or ""))
  if not (fotos.outline0 and fotos.outline1 and fotos.body0 and fotos.body1
    and fotos.piso) then
    return fim()
  end

  -- THE CHARACTER, ISOLATED, WITHOUT KNOWING WHERE IT STANDS. VOXEL CHARS: OFF
  -- draws the host's flat card in the same cell; the solid draws over the same
  -- ground. Every pixel where the two photographs differ belongs to the
  -- character and to nothing else. Unlike differencing the two SIDE COLOR
  -- renders against each other, this set does NOT drop the faces where the
  -- search failed -- and those are exactly the faces the defect is made of,
  -- which is why the first version of this gate was structurally unable to see
  -- it: a face that gives up looks identical under both settings, so it fell
  -- out of the comparison before it could be counted.
  local regB = { [0] = recorte(fotos.chapa0, fotos.body0),
                 [1] = recorte(fotos.chapa1, fotos.body1) }
  local regO = { [0] = recorte(fotos.chapa0, fotos.outline0),
                 [1] = recorte(fotos.chapa1, fotos.outline1) }
  local piso = recorte(fotos.outline0, fotos.piso)

  -- A QUARTER, and the number is not a taste call: two photographs of the same
  -- pose with the same options differ by 0 pixels here, while the character
  -- itself is some eight hundred. Anything approaching that means something
  -- else moved -- Oak's lab has people who walk on their own, which is why the
  -- default map is the one upstairs room that has nobody in it.
  veredito("W2", piso.mudados <= math.max(regB[0].mudados, 1) * 0.25,
    string.format("duas fotos da MESMA pose com as MESMAS opcoes diferem em %d "
      .. "pixels contra %d que o personagem ocupa; acima de um quarto o que "
      .. "mudou nao e so ele", piso.mudados, regB[0].mudados))

  veredito("W3", regB[0].mudados > 300 and regB[1].mudados > 300
    and regO[0].pretoB > 100 and regO[1].pretoB > 100, string.format(
    "o personagem ocupa %d pixels parado e %d andando, e OUTLINE deixa %d e %d "
    .. "deles pretos (sem isso, tudo abaixo mede o conjunto vazio)",
    regB[0].mudados, regB[1].mudados, regO[0].pretoB, regO[1].pretoB))

  -- A TENTH, and both sides of the number are measured. Ran on this exact map
  -- and cell against the fixed build and against each of the two defects this
  -- family has actually shipped, deliberately restored one at a time:
  --
  --                                          standing   walking
  --   fixed                                    14.5%     21.4%
  --   BODY_SEARCH_LIMIT left unscaled on HD      4.3%     20.4%
  --   poseOffset removed from sideUv/verticalUv 14.5%      3.0%
  --
  -- Each defect collapses exactly the pose it breaks, and leaves the other one
  -- alone: the unscaled search fails on the standing pose, and the missing pose
  -- compensation only ever mattered on the walking one -- which is why a gate
  -- that photographs a single pose would have caught one of the two and called
  -- itself green. A tenth sits between 4.3 and 14.5 and between 3.0 and 20.4.
  local function tirou(fase)
    local pretoO = regO[fase].pretoB
    if pretoO <= 0 then return 0 end
    return (pretoO - regB[fase].pretoB) / pretoO
  end
  for _, fase in ipairs({ 0, 1 }) do
    local nome = fase == 0 and "W4" or "W5"
    local pose = fase == 0 and "parado" or "andando"
    veredito(nome, tirou(fase) >= 0.10, string.format(
      "%s: dos %d pixels que OUTLINE deixa pretos no personagem, BODY tira %d "
      .. "(%.1f%%). Uma face nova cujo bodyTexelInFrame desiste recebe o "
      .. "OUTLINE, que e preto, entao a busca falhando aparece aqui como uma "
      .. "queda", pose, regO[fase].pretoB,
      regO[fase].pretoB - regB[fase].pretoB, tirou(fase) * 100))
  end

  opcao("depth", 3)
  opcao("side_color", "outline")
  fim()
end
