-- A CHARACTER PRESET, constrained so it cannot leave the art's tone system
-- (roadmap T2.2, slice 1).
--
-- Pure Lua. No love, no runtime, and nothing in the mod reads this yet: the
-- format and its rules are settled and gated before anything renders, the same
-- order T2.1 went in.
--
-- THE MEASUREMENT THIS IS BUILT ON. `tools/measure_regions.py --palette` over
-- every sheet the game has:
--
--     distinct tone ramps across 67 sheet(s):
--       67 sheet(s)  #000000 #555555 #aaaaaa
--
-- Sixty-seven sheets, one ramp, three values. Not "mostly", not "a family of
-- similar palettes": the same three bytes everywhere, which is what a Game Boy
-- four-shade palette looks like once the lightest shade is the transparent
-- background.
--
-- THAT SETTLES THE CRITIC'S OBJECTION, and settles it against the obvious
-- design. Reviewing this project's art, the critic argued that it has a
-- coherent two-level tone system and that an arbitrary hue picker manufactures
-- tones outside it. A colour wheel in a creator would do exactly that: every
-- colour it can produce except three is outside the system that every
-- character in the game shares.
--
-- So a preset does NOT choose colours. It chooses, for each body region, WHICH
-- OF THE EXISTING THREE TONES that region uses. Ash's cap can become the tone
-- his shirt already is. It cannot become a tone that has never appeared in this
-- game, because the format has no way to say that.
--
-- The pleasant consequence is that the roadmap's gate condition, "palette
-- choices are constrained to something the tone system can absorb, proven by
-- rendering the extremes rather than by argument", is answerable more strongly
-- than it was asked. There are no extremes to sample: the whole space is
-- 3^regions presets and every one of them is inside the ramp by construction.
-- The gate enumerates all of them.
--
-- WHAT A PRESET IS NOT. It is not save data: it is local visual state, and the
-- assumption is logged in the roadmap as reversible. It does not apply to NPC
-- sheets in this version. It ships no pixels.

local M = {}

-- The measured ramp, darkest first. Written as data rather than read from a
-- sprite at runtime because the mod must not depend on the player's cache to
-- know what a preset means; `tools/preset_gate.lua` re-measures the real
-- sheets and fails if this copy has drifted.
M.RAMP = { "000000", "555555", "aaaaaa" }

-- Regions a preset may tone. The same names the authored schema fixes, minus
-- `bag`, which no measured sheet has: see authored/sheets/red.lua.
M.REGIONS = { "head", "hair", "body", "feet" }

local REGIAO_VALIDA = {}
for _, r in ipairs(M.REGIONS) do REGIAO_VALIDA[r] = true end

-- One line, `key=value` separated by spaces, because it has to survive being
-- pasted into a Discord message and typed back out by hand. A JSON blob with
-- braces and quotes does not survive that, and this is small enough that the
-- extra structure buys nothing.
--
--   preset1 sheet=red head=3 hair=1 body=2 feet=1
--
-- The version prefix is first so a future format change can be recognised
-- rather than mis-parsed, which is the failure that makes people give up on a
-- text format.
M.VERSION = "preset1"

function M.serialise(p)
  local partes = { M.VERSION, "sheet=" .. tostring(p.sheet) }
  -- SORTED BY THE FIXED REGION ORDER, not by pairs(), so the same preset always
  -- produces the same bytes. Round-tripping is worthless if the serialiser is
  -- free to reorder: the card would differ from itself.
  for _, r in ipairs(M.REGIONS) do
    if p.tones and p.tones[r] then
      partes[#partes + 1] = r .. "=" .. tostring(p.tones[r])
    end
  end
  return table.concat(partes, " ")
end

function M.parse(texto)
  if type(texto) ~= "string" then return nil, "not a string" end
  texto = texto:gsub("^%s+", ""):gsub("%s+$", "")
  local versao = texto:match("^(%S+)")
  if versao ~= M.VERSION then
    return nil, string.format("unknown preset format %q; this build writes %s",
      tostring(versao), M.VERSION)
  end
  local p = { tones = {} }
  for chave, valor in texto:gmatch("(%w+)=(%w+)") do
    if chave == "sheet" then
      p.sheet = valor
    elseif REGIAO_VALIDA[chave] then
      p.tones[chave] = tonumber(valor)
      if p.tones[chave] == nil then
        return nil, string.format("region %s has tone %q, which is not a number",
          chave, valor)
      end
    else
      -- Refused, not ignored. A preset with a typo that silently loses a region
      -- renders a character nobody asked for and gives no clue why.
      return nil, string.format("unknown field %q in the preset", chave)
    end
  end
  local ok, err = M.validate(p)
  if not ok then return nil, err end
  return p
end

function M.validate(p)
  if type(p) ~= "table" then return false, "not a table" end
  if type(p.sheet) ~= "string" or p.sheet == "" then
    return false, "a preset has to name the sheet it applies to"
  end
  if type(p.tones) ~= "table" then return false, "no tones table" end
  local n = 0
  for r, t in pairs(p.tones) do
    n = n + 1
    if not REGIAO_VALIDA[r] then
      return false, string.format("%q is not a region a preset may tone", r)
    end
    if type(t) ~= "number" or t % 1 ~= 0 or t < 1 or t > #M.RAMP then
      -- THE WHOLE POINT OF THE FORMAT, in one condition. A tone is an INDEX
      -- into the measured ramp, so there is no way to express a colour the art
      -- does not already contain.
      return false, string.format(
        "region %s asks for tone %s, and the ramp this art uses has %d of them. "
        .. "A preset picks WHICH existing tone a part uses; it cannot invent one",
        r, tostring(t), #M.RAMP)
    end
  end
  if n == 0 then
    return false, "a preset with no toned regions changes nothing, and an empty "
      .. "preset that claims to be a preset is worse than no preset"
  end
  return true
end

-- The hex the art actually uses, for a preset's choice. Returns nil rather than
-- guessing, so a caller cannot paint with a default it did not ask for.
function M.hex(indice)
  return M.RAMP[indice]
end

return M
