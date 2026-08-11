-- THE RANDOMISER IS REPRODUCIBLE AND ITS CANDIDATES ARE REAL (T2.5).
--
--   luajit mods/voxel_characters/tools/randomiza_gate.lua
--
-- From the repo root. Pure Lua, no LOVE, no display.
--
-- What a randomiser can quietly get wrong, and therefore what this checks:
--
--   1. the same seed gives the same candidates, or nothing that fails can be
--      re-run and no gate below means anything;
--   2. different seeds give different sets, or the seed is decoration and the
--      generator is handing out one list forever. Compared as SETS, not as
--      ordered lists, because two identical sets in a different order is still
--      one set of candidates;
--   3. every candidate is valid, checked against the preset format itself;
--   4. no set repeats a candidate, because showing Kim the same look twice
--      spends the scarcest thing this project has, which is his attention;
--   5. asking for more than exists returns everything, says how many that was,
--      and does not hang;
--   6. every candidate survives serialise and parse unchanged, or it cannot be
--      pasted into a card recipe or a judge pair;
--   7. no candidate can reproduce the original character, measured against the
--      real sprite rather than assumed.

local RAIZ = "mods/voxel_characters"
local R = dofile(RAIZ .. "/tools/randomiza.lua")
local P = dofile(RAIZ .. "/authored/preset.lua")

local problemas = {}
local function exige(cond, fmt, ...)
  if not cond then problemas[#problemas + 1] = string.format(fmt, ...) end
end

local function texto(p) return P.serialise(p) end
local function conjunto(lista)
  local s = {}
  for _, p in ipairs(lista) do s[texto(p)] = true end
  return s
end

-- 1. reproducible
do
  local a = R.candidatos("red", 5, 42)
  local b = R.candidatos("red", 5, 42)
  exige(#a == #b, "the same seed gave %d and %d candidates", #a, #b)
  for i = 1, math.min(#a, #b) do
    exige(texto(a[i]) == texto(b[i]),
      "seed 42 candidate %d differs between runs: %q against %q",
      i, texto(a[i]), texto(b[i]))
  end
end

-- 2. the seed matters, compared as sets
do
  local a, b = conjunto(R.candidatos("red", 5, 1)), conjunto(R.candidatos("red", 5, 2))
  local igual = true
  for k in pairs(a) do if not b[k] then igual = false end end
  for k in pairs(b) do if not a[k] then igual = false end end
  exige(not igual,
    "seed 1 and seed 2 produced the same SET of candidates, so the seed does "
    .. "nothing and every run shows Kim the same looks")
end

-- 3, 4 and 6, over several seeds and sizes
local totalGerado, nSeeds = 0, 0
for _, seed in ipairs({ 1, 7, 42, 99, 1234, 65535, 4294967295 }) do
  nSeeds = nSeeds + 1
  local lista = R.candidatos("red", 6, seed)
  local vistos = {}
  for i, p in ipairs(lista) do
    totalGerado = totalGerado + 1
    local ok, err = P.validate(p)
    exige(ok, "seed %d candidate %d is not a valid preset: %s",
      seed, i, tostring(err))
    local t = texto(p)
    exige(not vistos[t], "seed %d repeats %q", seed, t)
    vistos[t] = true
    local volta, perr = P.parse(t)
    exige(volta ~= nil, "seed %d candidate %q does not parse back: %s",
      seed, t, tostring(perr))
    if volta then
      exige(texto(volta) == t,
        "seed %d candidate %q serialises differently after a round trip: %q",
        seed, t, texto(volta))
    end
  end
end

-- 5. over-asking
do
  local inicio = os.clock()
  local lista, disponiveis = R.candidatos("red", R.espaco() + 1000, 3)
  local gasto = os.clock() - inicio
  -- COUNTED BY WALKING, not with `#`. A mutation that removed the clamp wrote
  -- nils past the end of the space, and `#` does not count nils, so the length
  -- still looked right and this check stayed green on a list full of holes.
  -- A caller iterating with ipairs would stop early; one indexing directly
  -- would get nil and crash somewhere else entirely.
  local reais, buracos = 0, 0
  for i = 1, R.espaco() + 1000 do
    if lista[i] ~= nil then
      reais = reais + 1
      if buracos > 0 then
        exige(false, "candidate %d comes after a gap, so the list has holes", i)
        break
      end
    else
      buracos = buracos + 1
    end
  end
  exige(reais == R.espaco(),
    "asked for %d and got %d real candidate(s); the whole space is %d",
    R.espaco() + 1000, reais, R.espaco())
  exige(disponiveis == R.espaco(),
    "the shortfall was not reported: the space is %d and it said %s",
    R.espaco(), tostring(disponiveis))
  -- Mechanical proof it is not retrying against a shrinking pool: enumerating
  -- and shuffling is bounded by the space, and a roll-and-retry design is not.
  exige(gasto < 2,
    "over-asking took %.1f s, which is what a roll-until-unique loop looks "
    .. "like as the pool empties", gasto)
end

-- 7. NO CANDIDATE CAN REPRODUCE THE ORIGINAL, and it is measured.
--
-- A preset assigns one tone to a whole region, so it could only reproduce a
-- region that already uses exactly one tone. Re-measured from the real sprite
-- rather than trusted from a comment, the same way preset_gate re-measures the
-- ramp: if a future sheet had a single-tone region, one candidate WOULD render
-- the character unchanged, and it should be excluded rather than shown to Kim
-- as a proposal.
do
  local p = io.popen("python3 " .. RAIZ ..
    "/tools/measure_regions.py --region-tones red 2>/dev/null")
  local saida = p and p:read("*a") or ""
  if p then p:close() end
  if saida == "" then
    exige(false, "could not measure tones per region; python3 is missing or "
      .. "measure_regions.py is broken, and this claim is unverified")
  else
    local regioes = 0
    for regiao, n in saida:gmatch("red%s+(%w+)%s+(%d+) tone") do
      regioes = regioes + 1
      exige(tonumber(n) > 1,
        "region %s uses a single tone in the original, so one candidate "
        .. "reproduces the character unchanged and should not be proposed",
        regiao)
    end
    exige(regioes >= 3,
      "only %d region(s) were measured; the claim that no candidate can "
      .. "reproduce the original rests on all of them", regioes)
  end
end

if #problemas > 0 then
  for i = 1, math.min(#problemas, 10) do print("  " .. problemas[i]) end
  if #problemas > 10 then
    print(string.format("  ... and %d more", #problemas - 10))
  end
  print(string.format("RANDOMISER FAILED: %d problem(s)", #problemas))
  os.exit(1)
end
print(string.format(
  "randomiser ok: %d candidates over %d seeds, all valid, distinct and "
  .. "reproducible; none can reproduce the original", totalGerado, nSeeds))
