-- THE AUTHORED LAYER'S SCHEMA, and nothing else yet (roadmap T2.1, slice 1).
--
-- Pure Lua. No love, no runtime, and NOTHING IN THE MOD READS THIS FILE. That
-- is the point of the first slice: the shape of the data and the rules it has
-- to obey are settled and gated before a single authored pixel is drawn.
--
-- WHY THIS LAYER IS DANGEROUS AND THEREFORE STARTS AS DATA. The mod's promise
-- is that it derives everything from the player's own ROM. An authored layer
-- ships material the artist did not draw and the ROM does not contain, which
-- changes the mod's identity, not just its output. The roadmap accepts that
-- trade on the condition that it is disclosed plainly and that pure runtime
-- stays the default and the control. A schema that cannot express a dishonest
-- state is the cheapest way to keep that promise, and it is much cheaper now
-- than after there is art to migrate.
--
-- THE THREE PROVENANCE CLASSES, which is the whole reason this exists:
--
--   artist    pixels sampled from the player's own sprite sheet. Front and
--             back faces today.
--   invented  surface this mod computes and no artist drew: sides, top,
--             bottom. Honest, and already reported.
--   authored  pixels shipped WITH THE MOD. Today this is always zero, and it
--             must be reported as zero rather than omitted, because a number
--             that appears only when it is non-zero teaches nobody to look
--             for it.
--
-- The metric has always split art from invented. Splitting authored out of
-- invented is the change: shipped material is not "surface the mod computed",
-- and folding the two together would let an art pack hide inside a number that
-- already reads as high.

local M = {}

M.PROVENANCE = { "artist", "invented", "authored" }

-- What a sheet may declare. Anything not listed is refused, rather than
-- ignored: a typo that is silently dropped is a rule that silently does not
-- apply, and this schema exists precisely to make an accident impossible.
M.CAMPOS = {
  kind = { obrigatorio = true, valores = { living = true, object = true } },
  regions = { obrigatorio = false, apenas = "living" },
  responsiveness = { obrigatorio = false, apenas = "living" },
  deformation = { obrigatorio = false, apenas = "living" },
  overlays = { obrigatorio = false },
  -- Bounds read off the real sprite by tools/measure_regions.py. Not written by
  -- hand: the gate re-measures and fails on any disagreement, which is what
  -- makes this file's numbers worth reading.
  measured = { obrigatorio = false },
  -- Which frames a light-tone measurement may be read as the cap. Needed
  -- because the same measurement means the cap from the front and reaches the
  -- hands from behind, so the frame list is part of the claim.
  hairFrames = { obrigatorio = false, exige = "hair" },
  note = { obrigatorio = false },
}

-- Fields a measured frame may carry. An allowlist again, for the same reason:
-- a misspelled bound that is silently ignored is a bound nobody is checking.
M.MEDIDAS = {
  top = true, bottom = true, left = true, right = true,
  lightFreeBottom = true, footSplit = true, bob = true,
}

-- Region names, fixed rather than free text. `PART LAG` currently cuts the
-- body into four bands found from cap rows; the reason authored regions are
-- worth anything is that they could let it cut along a bag strap instead. That
-- only works if the names mean the same thing on every sheet.
M.REGIONS = {
  head = true, hair = true, body = true, bag = true, feet = true,
}

-- Overlay types. A sprite replacement is NOT one of them and never becomes one
-- by adding a string here: the roadmap's line is that authored material guides
-- the result and does not replace the artist's pixels. Anything that could
-- cover a whole sheet belongs to a different item and a different decision.
M.OVERLAYS = {
  eyes = true,        -- a few texels, at the eye anchor
  rim = true,         -- an accent along a silhouette edge
  shading_mask = true -- guides where shading falls, carries no colour of its own
}

local function ehLista(t)
  if type(t) ~= "table" then return false end
  local n = 0
  for k in pairs(t) do
    n = n + 1
    if type(k) ~= "number" then return false end
  end
  return n == #t
end

-- Returns ok, {problems}. Never throws: a schema check that crashes on bad
-- input tells you less than one that reports what was wrong with it.
function M.validate(nome, folha)
  local erros = {}
  local function erro(fmt, ...) erros[#erros + 1] = string.format(fmt, ...) end

  if type(folha) ~= "table" then
    return false, { string.format("%s: not a table", tostring(nome)) }
  end

  for chave in pairs(folha) do
    if not M.CAMPOS[chave] then
      erro("%s: unknown field %q. Fields are refused rather than ignored, "
        .. "because a typo that is dropped is a rule that does not apply",
        nome, tostring(chave))
    end
  end

  local kind = folha.kind
  if not kind then
    erro("%s: no kind. Every sheet is living or object, and the difference is "
      .. "what stops an item ball breathing", nome)
  elseif not M.CAMPOS.kind.valores[kind] then
    erro("%s: kind %q is neither living nor object", nome, tostring(kind))
  end

  -- THE RULE THE OBJECT FIXTURE EXISTS FOR. Regions, responsiveness and
  -- deformation are properties of something alive. An object that carries them
  -- is one rule away from being animated, and this project already has the
  -- precedent: poke_ball and boulder are pinned to zero life by hand in
  -- main.lua because a general rule made them pulse.
  for chave, regra in pairs(M.CAMPOS) do
    if regra.exige and folha[chave] ~= nil
       and not (folha.regions and folha.regions[regra.exige]) then
      erro("%s: %s is about the %s region, which this sheet does not declare",
        nome, chave, regra.exige)
    end
    if regra.apenas and folha[chave] ~= nil and kind ~= regra.apenas then
      erro("%s: %s is only for a %s sheet, and this one is %s. An object that "
        .. "carries living metadata is one rule away from being animated",
        nome, chave, regra.apenas, tostring(kind))
    end
  end

  if folha.regions ~= nil then
    if type(folha.regions) ~= "table" then
      erro("%s: regions is not a table", nome)
    else
      for r in pairs(folha.regions) do
        if not M.REGIONS[r] then
          erro("%s: unknown region %q. The names are fixed so that a region "
            .. "means the same thing on every sheet", nome, tostring(r))
        end
      end
    end
  end

  if folha.overlays ~= nil then
    if not ehLista(folha.overlays) then
      erro("%s: overlays is not a list", nome)
    else
      for _, o in ipairs(folha.overlays) do
        local tipo = type(o) == "table" and o.type or o
        if not M.OVERLAYS[tipo] then
          erro("%s: overlay %q is not one of the guiding types. Authored "
            .. "material guides the artist's pixels; it does not replace them",
            nome, tostring(tipo))
        end
      end
    end
  end

  if folha.measured ~= nil then
    if type(folha.measured) ~= "table" then
      erro("%s: measured is not a table", nome)
    else
      local n = 0
      for quadro, m in pairs(folha.measured) do
        n = n + 1
        if type(quadro) ~= "number" or quadro < 0 or quadro % 1 ~= 0 then
          erro("%s: measured is keyed by frame number, got %s",
            nome, tostring(quadro))
        elseif type(m) ~= "table" then
          erro("%s: measured frame %s is not a table", nome, tostring(quadro))
        else
          for campo, v in pairs(m) do
            if not M.MEDIDAS[campo] then
              erro("%s: frame %s carries unknown measurement %q",
                nome, tostring(quadro), tostring(campo))
            elseif type(v) ~= "number" or v % 1 ~= 0 then
              erro("%s: frame %s %s is %s, and every bound is a whole row or "
                .. "column", nome, tostring(quadro), campo, tostring(v))
            end
          end
          -- A box has to be a box. This is cheap and it catches the shape of
          -- error a hand edit makes: a swapped pair, or a bound left behind
          -- when the other moved.
          if m.top and m.bottom and m.top > m.bottom then
            erro("%s: frame %s has top %d below bottom %d",
              nome, tostring(quadro), m.top, m.bottom)
          end
          if m.left and m.right and m.left > m.right then
            erro("%s: frame %s has left %d right of right %d",
              nome, tostring(quadro), m.left, m.right)
          end
          if m.footSplit and m.bottom and m.footSplit > m.bottom then
            erro("%s: frame %s splits at row %d, below the figure's last row %d",
              nome, tostring(quadro), m.footSplit, m.bottom)
          end
        end
      end
      if n == 0 then
        erro("%s: measured is present and empty. An empty measurement claims "
          .. "the sheet was measured and says nothing, which is worse than "
          .. "leaving it out", nome)
      end
    end
  end

  if folha.hairFrames ~= nil then
    if not ehLista(folha.hairFrames) then
      erro("%s: hairFrames is not a list of frame numbers", nome)
    else
      for _, q in ipairs(folha.hairFrames) do
        if type(q) ~= "number" then
          erro("%s: hairFrames holds %s, which is not a frame number",
            nome, tostring(q))
        elseif folha.measured and folha.measured[q] == nil then
          erro("%s: hairFrames names frame %s, which has no measurement to "
            .. "read as the cap", nome, tostring(q))
        end
      end
    end
  end

  if folha.responsiveness ~= nil then
    local v = folha.responsiveness
    if type(v) ~= "number" or v < 0 or v > 1 then
      erro("%s: responsiveness must be a number from 0 to 1, got %s",
        nome, tostring(v))
    end
  end

  return #erros == 0, erros
end

-- Every sheet ships with zero authored pixels today. The count is a function
-- rather than a constant so that the day it stops being zero, every caller
-- already asks the right question.
function M.authoredPixels(folha)
  if type(folha) ~= "table" or not folha.overlays then return 0 end
  local n = 0
  for _, o in ipairs(folha.overlays) do
    n = n + ((type(o) == "table" and o.pixels) or 0)
  end
  return n
end

return M
