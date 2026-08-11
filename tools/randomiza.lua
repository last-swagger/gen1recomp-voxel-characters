-- CANDIDATE PRESETS FOR THE JUDGE (roadmap T2.5, display-free half).
--
-- Pure Lua. No love, no display.
--
-- WHY A RANDOMISER IS WORTH ANYTHING HERE. The judge learns from pairs Kim
-- decided, and the pairs it has seen so far vary ONE option at a time from a
-- fixed base. That is a thin slice of the space and it is the slice somebody
-- chose by hand, so the judge has never been asked about a combination nobody
-- thought of. A randomiser's whole value is proposing looks a person would not
-- have typed.
--
-- WHY IT IS DETERMINISTIC. An explicit LCG with the same constants as
-- `tools/fx_sfx.lua`, seeded by the caller and never by the clock. This project
-- has already been burned by `os.time()` handing out the same seed twice inside
-- one second, and a generator that cannot be re-run identically cannot be
-- gated: every check would be measuring a different set from the one that
-- failed.
--
-- THERE IS NO "IDENTITY PRESET" TO EXCLUDE, and that is measured rather than
-- assumed. A preset assigns ONE tone to a whole region, so it could only
-- reproduce the original where that region already uses exactly one tone.
-- `tools/measure_regions.py --region-tones red` reports:
--
--     red body  3 tone(s)
--     red feet  2 tone(s)
--     red hair  2 tone(s)
--
-- Every region uses more than one, so every preset in the space is a visible
-- change and none of them renders the character unaltered. An earlier design
-- picked "all regions at the darkest tone" as a stand-in identity and excluded
-- it; that reference is arbitrary, it describes nothing in the art, and
-- excluding it would have hidden one perfectly good candidate for no reason.

local M = {}

local P = dofile("mods/voxel_characters/authored/preset.lua")

-- Only the regions this project can actually place on a sheet. `head` is in the
-- preset format and is deliberately unplaceable: slice 2 of T2.1 declined to
-- measure the head-and-shoulder line because it does not resolve from the side
-- view, and the harness refuses a preset naming it. Generating candidates that
-- are guaranteed to be rejected downstream would be a randomiser that mostly
-- wastes the judge's time.
M.REGIONS = { "hair", "body", "feet" }

function M.espaco()
  return (#P.RAMP) ^ (#M.REGIONS)
end

-- The LCG, written out rather than wrapped, so the constants are readable at
-- the point of use.
local function lcg(seed)
  local estado = seed % 4294967296
  return function(n)
    estado = (1664525 * estado + 1013904223) % 4294967296
    return (estado % n) + 1
  end
end

-- The whole space, in a fixed order, so the shuffle is the ONLY source of
-- variation. Enumerating and shuffling rather than rolling-and-retrying means
-- no duplicate is possible and nothing can loop: at 3^3 the space is small
-- enough that generating all of it is cheaper than checking for collisions.
local function todos(sheet)
  local out = {}
  local function anda(i, escolhas)
    if i > #M.REGIONS then
      local tones = {}
      for r, t in pairs(escolhas) do tones[r] = t end
      out[#out + 1] = { sheet = sheet, tones = tones }
      return
    end
    for t = 1, #P.RAMP do
      escolhas[M.REGIONS[i]] = t
      anda(i + 1, escolhas)
      escolhas[M.REGIONS[i]] = nil
    end
  end
  anda(1, {})
  return out
end

-- Returns `chosen, available`. When more are asked for than exist, it returns
-- everything and reports how many that was, rather than looping or silently
-- handing back fewer with no explanation.
function M.candidatos(sheet, n, seed)
  local espaco = todos(sheet)
  local disponiveis = #espaco
  local proximo = lcg(seed or 1)
  -- Fisher-Yates, so every ordering is reachable and no element is favoured by
  -- position. A naive "swap each with a random index" is not the same shuffle
  -- and skews toward the end of the list.
  for i = disponiveis, 2, -1 do
    local j = proximo(i)
    espaco[i], espaco[j] = espaco[j], espaco[i]
  end
  -- The clamp is for readability rather than safety: the copy below reads
  -- `espaco[i]`, which is already nil past the end, and assigning nil creates
  -- no entry. Removing it is an equivalent mutation and no gate catches it,
  -- which was measured rather than assumed. Kept because a caller reading this
  -- should not have to derive that.
  local quantos = math.min(n or disponiveis, disponiveis)
  local out = {}
  for i = 1, quantos do out[i] = espaco[i] end
  return out, disponiveis
end

return M
