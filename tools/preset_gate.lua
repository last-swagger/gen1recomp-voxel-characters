-- A PRESET ROUND-TRIPS, AND CANNOT LEAVE THE ART'S TONE SYSTEM (T2.2 slice 1).
--
--   luajit mods/voxel_characters/tools/preset_gate.lua
--
-- From the repo root. Pure Lua, no LOVE, no display, milliseconds.
--
-- The roadmap's gate for the character creator asks for a preset that
-- "serialises to a small text or JSON blob, reloads, and renders the same card
-- byte for byte", and for palette choices "constrained to something the tone
-- system can absorb, proven by rendering the extremes rather than by argument".
--
-- Rendering is a later slice and needs a display. What can be proved now,
-- offline and on every commit, is the half that makes rendering meaningful: if
-- the format does not round-trip exactly, two identical cards is luck; and if
-- the format can express a colour the art does not contain, no amount of
-- careful rendering keeps the creator inside the tone system.
--
-- THE SPACE IS SMALL ENOUGH TO EXHAUST, which is better than sampling extremes.
-- A preset assigns each of four regions one of three measured tones, so there
-- are 3^4 = 81 fully specified presets, plus every subset of regions. This
-- enumerates all of them and round-trips each. "Prove it by rendering the
-- extremes" was the roadmap asking for a sample because it assumed a continuous
-- space; the constrained format turns it into a finite one.

local RAIZ = "mods/voxel_characters"
local P = dofile(RAIZ .. "/authored/preset.lua")

local problemas = {}
local function exige(cond, fmt, ...)
  if not cond then problemas[#problemas + 1] = string.format(fmt, ...) end
end

-- 1. THE RAMP IN THE CODE IS THE RAMP IN THE ART.
--
-- preset.lua carries the three tones as data so the mod does not have to read
-- the player's sprite cache to know what a preset means. A copy can drift, so
-- it is re-measured here against the real sheets. This is the same rule the
-- authored region bounds live under: the sprite is the source of truth.
do
  local p = io.popen("python3 " .. RAIZ ..
    "/tools/measure_regions.py --palette 2>/dev/null")
  local saida = p and p:read("*a") or ""
  if p then p:close() end
  if saida == "" then
    exige(false, "could not re-measure the tone ramp; python3 is missing or "
      .. "measure_regions.py is broken, and the ramp below is unverified")
  else
    local folhas, tons = saida:match("(%d+) sheet%(s%)%s+(#%x+ ?[^\n]*)")
    local medidos = {}
    for hex in (tons or ""):gmatch("#(%x%x%x%x%x%x)") do
      medidos[#medidos + 1] = hex
    end
    exige(#medidos == #P.RAMP,
      "the art uses %d tone(s) and preset.lua carries %d", #medidos, #P.RAMP)
    for i, hex in ipairs(medidos) do
      exige(P.RAMP[i] == hex,
        "ramp position %d is %s in the art and %s in preset.lua",
        i, hex, tostring(P.RAMP[i]))
    end
    -- ONE ramp, not several. If sheets ever disagree, a preset means different
    -- things on different characters and the whole format needs rethinking
    -- rather than patching.
    local quantas = 0
    for _ in saida:gmatch("sheet%(s%)%s+#") do quantas = quantas + 1 end
    exige(quantas == 1,
      "the sheets no longer share ONE tone ramp (%d distinct). A preset would "
      .. "mean a different colour depending on who is wearing it", quantas)
    if #medidos == #P.RAMP and quantas == 1 then
      print(string.format("  %-38s %d sheet(s), %s",
        "one measured ramp", tonumber(folhas) or 0, table.concat(medidos, " ")))
    end
  end
end

-- 2. EVERY PRESET IN THE SPACE ROUND-TRIPS, exactly.
local total = 0
do
  local R = P.REGIONS
  local function anda(i, escolhas)
    if i > #R then
      local tones, n = {}, 0
      for r, t in pairs(escolhas) do tones[r] = t; n = n + 1 end
      if n == 0 then return end
      total = total + 1
      local original = { sheet = "red", tones = tones }
      local texto = P.serialise(original)
      local volta, err = P.parse(texto)
      if not volta then
        exige(false, "%q did not parse back: %s", texto, tostring(err))
        return
      end
      exige(volta.sheet == original.sheet,
        "%q lost its sheet", texto)
      for r, t in pairs(tones) do
        exige(volta.tones[r] == t,
          "%q came back with %s=%s", texto, r, tostring(volta.tones[r]))
      end
      for r in pairs(volta.tones) do
        exige(tones[r] ~= nil, "%q gained a region %s it did not have", texto, r)
      end
      -- Serialising the parsed copy must give the same bytes, or the format has
      -- two spellings for one preset and "the same card byte for byte" is not
      -- something it can promise.
      exige(P.serialise(volta) == texto,
        "%q serialises differently after a round trip: %q",
        texto, P.serialise(volta))
      return
    end
    -- Every region either absent or one of the measured tones.
    anda(i + 1, escolhas)
    for t = 1, #P.RAMP do
      escolhas[R[i]] = t
      anda(i + 1, escolhas)
      escolhas[R[i]] = nil
    end
  end
  anda(1, {})
  exige(total >= 80,
    "only %d preset(s) were enumerated; the space should be every subset of "
    .. "%d regions over %d tones", total, #P.REGIONS, #P.RAMP)
end

-- 3. THE REFUSALS. A format is worth what it turns away.
local RECUSAS = {
  { "a tone below the ramp",
    { sheet = "red", tones = { head = 0 } } },
  { "a tone above the ramp, which is the colour-picker case",
    { sheet = "red", tones = { head = 4 } } },
  { "a fractional tone", { sheet = "red", tones = { head = 1.5 } } },
  { "a tone that is not a number",
    { sheet = "red", tones = { head = "#ff00ff" } } },
  { "a region no sheet has", { sheet = "red", tones = { moustache = 1 } } },
  { "a preset with no sheet", { tones = { head = 1 } } },
  { "a preset that tones nothing", { sheet = "red", tones = {} } },
  { "not a table at all", "preset1 sheet=red head=1" },
}
for _, caso in ipairs(RECUSAS) do
  local ok = P.validate(caso[2])
  exige(not ok, "validate ACCEPTED %s", caso[1])
end
-- The positive control, or the validator might simply refuse everything.
exige(P.validate({ sheet = "red", tones = { head = 1, feet = 3 } }),
  "validate refused an ordinary preset, so the refusals above prove nothing")

-- 4. TEXT THAT SHOULD NOT PARSE, which is a different surface from a bad table:
-- this is what arrives when somebody pastes a preset out of a chat window.
local TEXTO_RUIM = {
  { "an unknown format version", "preset9 sheet=red head=1" },
  { "no version at all", "sheet=red head=1" },
  { "a colour where a tone index goes", "preset1 sheet=red head=aabbcc" },
  { "an unknown field", "preset1 sheet=red hat=1" },
  { "a tone outside the ramp", "preset1 sheet=red head=7" },
  { "nothing at all", "" },
}
for _, caso in ipairs(TEXTO_RUIM) do
  local p, err = P.parse(caso[2])
  exige(p == nil, "parse ACCEPTED %s: %q", caso[1], caso[2])
  exige(err ~= nil and err ~= "",
    "parse refused %s with no reason, so whoever pasted it learns nothing",
    caso[1])
end
exige(P.parse("preset1 sheet=red head=1 feet=3") ~= nil,
  "parse refused an ordinary preset line, so the refusals above prove nothing")

-- 5. Whitespace a chat client adds must not change the preset. This is the
-- difference between a format that survives being pasted and one that only
-- works when a program wrote it.
do
  local base = "preset1 sheet=red head=2 body=1"
  for _, sujo in ipairs({ "  " .. base, base .. "   ", " " .. base .. " " }) do
    local a, b = P.parse(base), P.parse(sujo)
    exige(a and b and P.serialise(a) == P.serialise(b),
      "%q and %q parsed to different presets", base, sujo)
  end
end

if #problemas > 0 then
  for i = 1, math.min(#problemas, 10) do print("  " .. problemas[i]) end
  if #problemas > 10 then
    print(string.format("  ... and %d more", #problemas - 10))
  end
  print(string.format("PRESET FAILED: %d problem(s)", #problemas))
  os.exit(1)
end
print(string.format(
  "preset ok: %d preset(s) round-trip exactly, %d refusal(s) enforced, no "
  .. "colour outside the art's ramp is expressible",
  total, #RECUSAS + #TEXTO_RUIM))
