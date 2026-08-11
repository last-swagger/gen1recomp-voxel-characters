-- THE AUTHORED LAYER SHIPS NOTHING, AND CANNOT LIE ABOUT IT (roadmap T2.1).
--
--   luajit mods/voxel_characters/tools/authored_gate.lua
--
-- From the repo root. Pure Lua, no LOVE, no display.
--
-- The authored layer is the one item in this roadmap whose risk is identity
-- rather than engineering. A mod that quietly starts drawing its own pixels
-- while its README says it derives everything from your ROM has broken
-- something a gate cannot repair. So the first slice ships no pixels at all,
-- and this proves it, from several directions at once:
--
--   1. every authored sheet validates against the schema;
--   2. the schema REFUSES what it should: unknown fields, an object carrying
--      living metadata, an unknown region, an overlay type that could stand in
--      for the artist's work, a responsiveness outside 0..1. Each refusal is
--      exercised, because a validator nobody has watched reject anything is a
--      validator that accepts everything;
--   3. the total authored pixel count is ZERO, so today's honest report is
--      "we ship none";
--   4. every sheet's `kind` agrees with `STILL_OBJECTS` in the mod's own
--      source, which is where the runtime already decides what is alive. Two
--      places that disagree about whether an item ball breathes is how the
--      item ball ends up breathing;
--   5. the authored path has exactly ONE entry point, it is shut by default,
--      and the loader refuses object sheets. Slice 1 asserted the runtime
--      never mentioned the layer at all; slice 3 wired it in, so that
--      assertion expired loudly and was replaced rather than deleted. The
--      byte-identical evidence itself lives in the suite and the ruler;
--   6. the measured finding is pinned: PART LAG cuts bands from the CELL, and
--      the sheet's bob says how far that is off the body. A characterisation,
--      so the slice that fixes it has something to show it changed.

local RAIZ = "mods/voxel_characters"
local Schema = dofile(RAIZ .. "/authored/schema.lua")

local problemas = {}
local function exige(cond, fmt, ...)
  if not cond then problemas[#problemas + 1] = string.format(fmt, ...) end
end

local function ler(caminho)
  local f = io.open(caminho, "r")
  if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end

-- 1. every sheet validates
local nomes = {}
local p = io.popen("ls " .. RAIZ .. "/authored/sheets/*.lua 2>/dev/null")
for linha in p:lines() do nomes[#nomes + 1] = linha end
p:close()
exige(#nomes >= 2,
  "expected at least a living sheet and an object sheet, found %d", #nomes)

local folhas, autoradosTotal = {}, 0
for _, caminho in ipairs(nomes) do
  local nome = caminho:match("([^/]+)%.lua$")
  local ok, folha = pcall(dofile, caminho)
  if not ok then
    exige(false, "%s does not load: %s", nome, tostring(folha))
  else
    folhas[nome] = folha
    local valido, erros = Schema.validate(nome, folha)
    if not valido then
      for _, e in ipairs(erros) do exige(false, "%s", e) end
    end
    autoradosTotal = autoradosTotal + Schema.authoredPixels(folha)
  end
end

exige(folhas.red ~= nil, "no living fixture: authored/sheets/red.lua is missing")
exige(folhas.red and folhas.red.measured ~= nil,
  "the living fixture declares no measured block. Slice 2's whole claim is that "
  .. "these bounds are read off the sprite rather than estimated, and a sheet "
  .. "with regions and no measurements is the state that claim replaced")
exige(folhas.poke_ball ~= nil,
  "no object fixture: authored/sheets/poke_ball.lua is missing, and it is the "
  .. "one that stops a rule making an item ball breathe")

-- 2. THE REFUSALS, each one exercised.
--
-- Every case here is a sheet the schema MUST reject. A validator is only worth
-- what it turns away, and this list is the specification of that.
local RECUSAS = {
  { "an object carrying regions",
    { kind = "object", regions = { head = true } } },
  { "an object carrying responsiveness",
    { kind = "object", responsiveness = 0.5 } },
  { "an object carrying deformation weights",
    { kind = "object", deformation = { head = 1 } } },
  { "a sheet with no kind at all", { regions = { head = true } } },
  { "a kind that is neither living nor object", { kind = "prop" } },
  { "a misspelled field", { kind = "living", regoins = { head = true } } },
  { "an unknown region name",
    { kind = "living", regions = { moustache = true } } },
  { "an overlay that replaces the sprite",
    { kind = "living", overlays = { { type = "sprite" } } } },
  { "responsiveness above 1",
    { kind = "living", responsiveness = 1.5 } },
  { "responsiveness that is not a number",
    { kind = "living", responsiveness = "high" } },
  { "a sheet that is not a table at all", "living" },
  -- Slice 2: the measured block. Every one of these is a shape a hand edit
  -- makes, which is the point, because the numbers are supposed to come out of
  -- tools/measure_regions.py and not out of anybody's head.
  { "a measurement with a misspelled bound",
    { kind = "living", measured = { [0] = { tops = 1 } } } },
  { "a bound that is not a whole row",
    { kind = "living", measured = { [0] = { top = 1.5 } } } },
  { "a box whose top is below its bottom",
    { kind = "living", measured = { [0] = { top = 9, bottom = 2 } } } },
  { "a box whose left is right of its right",
    { kind = "living", measured = { [0] = { left = 9, right = 2 } } } },
  { "a foot split below the figure's last row",
    { kind = "living", measured = { [0] = { bottom = 15, footSplit = 20 } } } },
  { "a measured block that is present and empty",
    { kind = "living", measured = {} } },
  { "measured keyed by something that is not a frame",
    { kind = "living", measured = { front = { top = 0 } } } },
  { "hairFrames without a declared hair region",
    { kind = "living", measured = { [0] = { top = 0 } }, hairFrames = { 0 } } },
  { "hairFrames naming a frame that was never measured",
    { kind = "living", regions = { hair = true },
      measured = { [0] = { top = 0 } }, hairFrames = { 4 } } },
}
for _, caso in ipairs(RECUSAS) do
  local rotulo, folha = caso[1], caso[2]
  local valido = Schema.validate("fixture", folha)
  exige(not valido,
    "the schema ACCEPTED %s, so it is not enforcing that rule", rotulo)
end

-- The positive control for the refusals: a minimal valid sheet of each kind
-- must still pass, or the validator is simply refusing everything.
for _, caso in ipairs({
  { "a minimal living sheet", { kind = "living" } },
  { "a minimal object sheet", { kind = "object" } },
  { "a living sheet with real regions",
    { kind = "living", regions = { head = true, bag = true } } },
  { "a sheet measured the way the tool writes it",
    { kind = "living", regions = { hair = true },
      measured = { [0] = { top = 0, bottom = 15, left = 1, right = 14,
                           lightFreeBottom = 3, footSplit = 15, bob = 0 } },
      hairFrames = { 0 } } },
}) do
  local valido, erros = Schema.validate("control", caso[2])
  exige(valido, "the schema REFUSED %s: %s", caso[1],
    table.concat(erros or {}, "; "))
end

-- 3. zero authored pixels
exige(autoradosTotal == 0,
  "the authored layer now ships %d pixel(s). That is not a defect in itself, "
  .. "but it means the disclosure draft and the provenance report have to be "
  .. "revisited before this ships, and this gate has to start comparing a "
  .. "real authored-off render instead of asserting zero", autoradosTotal)

-- 4. kind agrees with the runtime's own list
local fonte = ler(RAIZ .. "/main.lua") or ""
local bloco = fonte:match("local STILL_OBJECTS = {(.-)}")
if not bloco then
  exige(false, "STILL_OBJECTS could not be found in main.lua, so the authored "
    .. "layer's idea of what is alive cannot be checked against the runtime's")
else
  for nome, folha in pairs(folhas) do
    local pinado = bloco:find(nome .. "%s*=%s*true") ~= nil
    local deviaSerObjeto = pinado
    local ehObjeto = (folha.kind == "object")
    exige(ehObjeto == deviaSerObjeto,
      "%s is %s in authored/, but main.lua's STILL_OBJECTS %s it. Two places "
      .. "disagreeing about whether something is alive is how an item ball "
      .. "ends up breathing", nome, folha.kind,
      pinado and "pins" or "does not pin")
  end
end

-- 5. THE RUNTIME READS IT NOW, SO THE OFF PATH IS PROVED DIFFERENTLY.
--
-- Slice 1's version of this asserted that `main.lua` never mentioned the
-- authored layer, which made "off changes nothing" true by construction. Slice
-- 3 wires the layer into PART LAG, so that argument expired -- and it expired
-- LOUDLY, with instructions, which is the whole reason it was written as an
-- assertion instead of a comment.
--
-- What replaces it is the guard itself, checked in three parts. The real
-- byte-identical evidence lives in two places this gate cannot reach: the
-- offline suite builds one mesh each way and requires the band ranges to be
-- identical with the option off, and the ruler renders the whole battery.
-- What is checkable here is that there is exactly ONE way in and that it is
-- shut by default.
do
  local entradas = 0
  for _ in fonte:gmatch('optionState%.authored_regions%s*==%s*"on"') do
    entradas = entradas + 1
  end
  exige(entradas == 1,
    "the authored path has %d entry points in main.lua. It must have exactly "
    .. "one: every additional guard is another place the off path can stop "
    .. "being off, and none of them is covered by the control below", entradas)

  -- Default OFF, read out of the option's own definition rather than trusted.
  local bloco = fonte:match('key = "authored_regions".-defaultIndex = (%d+)')
  exige(bloco == "1",
    "AUTHORED REGIONS does not default to the first level (defaultIndex is %s). "
    .. "Pure runtime has to stay the default, not merely be reachable",
    tostring(bloco))
  local niveis = fonte:match('key = "authored_regions".-levels = {(.-)}%s*,')
  exige(niveis and niveis:match('{ "OFF"'),
    "AUTHORED REGIONS's first level is not OFF, so defaulting to the first one "
    .. "does not mean what the line above assumes")

  -- Objects are refused at the loader, not merely at the schema. The schema
  -- governs the DATA; this governs what the runtime does with a sheet that got
  -- past it, which is the case that would actually animate an item ball.
  exige(fonte:match('folha%.kind == "living"') ~= nil,
    "the runtime loader no longer requires kind == \"living\". An object sheet "
    .. "carrying measurements would be segmented, which is the one outcome "
    .. "this fixture exists to prevent")
  if entradas == 1 and bloco == "1" then
    print("  authored path: one entry point, default OFF, living-only")
  end
end

-- 6. THE FINDING THIS SLICE MEASURED, pinned so it cannot drift unnoticed.
--
-- `PART LAG` cuts the body into bands with `math.floor(y / cellH * REGION_BANDS)`.
-- That divides the CELL, not the figure. The measured sheet says the walking
-- frames sit lower in the cell than the standing frames, so on those frames
-- every band boundary lands that far up the body from where it lands when
-- standing: the neck line moves, mid-stride, for no reason a viewer could name.
--
-- This is a characterisation, not a complaint. It asserts what is true of the
-- DEFAULT path, which is still the cell rule and still ships that way. Slice 3
-- added `AUTHORED REGIONS`, which cuts the figure instead, but it is off until
-- somebody turns it on, so the number below is what a player gets. Two halves, and both have to
-- hold for the number to mean anything:
--
--   the band rule still divides by the cell height, and
--   the sheet's largest bob is still what the docs say it is.
--
-- Fixing PART LAG to cut from the figure makes the first half fail. That is
-- correct: the finding is then retired on purpose, by editing this, rather than
-- quietly outliving the defect it describes.
local BOB_ESPERADO = 1
do
  local regra = fonte:match("math%.floor%(y%s*/%s*cellH%s*%*%s*REGION_BANDS%)")
  exige(regra ~= nil,
    "the PART LAG band rule no longer divides by cellH. If the bands now follow "
    .. "the figure, this characterisation has served its purpose and should be "
    .. "deleted along with the note in EXECUTION_STATE; if they divide by "
    .. "something else again, the note is simply wrong now")

  local bobMax = 0
  for _, folha in pairs(folhas) do
    for _, m in pairs(folha.measured or {}) do
      if m.bob and m.bob > bobMax then bobMax = m.bob end
    end
  end
  exige(bobMax == BOB_ESPERADO,
    "the largest measured bob is %d rows and the write-ups say %d. The bands "
    .. "are cut from the cell, so the bob IS the misalignment, and the number "
    .. "in the docs has to move with it", bobMax, BOB_ESPERADO)
  if regra and bobMax == BOB_ESPERADO then
    print(string.format(
      "  PART LAG cuts the cell by default, %d row(s) off the body on a bobbing "
      .. "frame; AUTHORED REGIONS cuts the figure instead", bobMax))
  end
end

if #problemas > 0 then
  for i = 1, math.min(#problemas, 10) do print("  " .. problemas[i]) end
  if #problemas > 10 then
    print(string.format("  ... and %d more", #problemas - 10))
  end
  print(string.format("AUTHORED LAYER FAILED: %d problem(s)", #problemas))
  os.exit(1)
end
print(string.format(
  "authored layer ok: %d sheet(s), %d refusal(s) enforced, %d authored pixel(s) "
  .. "shipped, the path is off by default",
  #nomes, #RECUSAS, autoradosTotal))
