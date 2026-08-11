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
--   5. NOTHING IN THE MOD READS ANY OF IT. This is the byte-identical
--      guarantee in its strongest available form: the authored path cannot
--      change a pixel because the runtime does not open the directory. When
--      that stops being true, this check has to be replaced by a real
--      authored-off render comparison, and it says so when it fails.

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

-- 5. the runtime does not read any of it
local lendo = {}
for _, arquivo in ipairs({ "main.lua" }) do
  local texto = ler(RAIZ .. "/" .. arquivo) or ""
  if texto:find("authored", 1, true) then lendo[#lendo + 1] = arquivo end
end
exige(#lendo == 0,
  "%s now references the authored layer. The zero-pixel argument above is no "
  .. "longer the byte-identical proof: replace check 5 with a real render "
  .. "comparison between the authored path off and today's output",
  table.concat(lendo, ", "))

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
  .. "shipped, runtime does not read it",
  #nomes, #RECUSAS, autoradosTotal))
