-- Finds a CHECK THAT DOES NOT CHECK: a call to a predicate whose return value
-- is discarded.
--
-- WHY THIS EXISTS. The suite had six lines like this:
--
--     close(pullEm(20, 6), 4, "at 20 units the pull gives way to 4")
--
-- `close(a, b)` RETURNS a boolean; it does not register any check on its
-- own. The message was an ignored third argument. The six ran, passed, and
-- did not count: the total jumped from 552 to 558 when they were fixed.
-- None of them would have caught the mutation they existed to catch.
--
-- And the worst part of the family: they READ like an assertion. Whoever
-- reviews glances over and sees a check with a message. Only counting the
-- total made it noticeable.
--
-- HOW IT DECIDES WHAT IS A PREDICATE, and why not by a hand-written list: a
-- list rots at the next helper. The rule is structural. A `local function`
-- that HAS a `return` and calls NO assertion function is a predicate: it
-- returns an answer instead of registering a verdict. Whoever registers a
-- verdict calls `check` or `eq` inside it, or is `check`/`eq` itself.
--
-- Usage:
--   luajit mods/voxel_characters/tools/lint_asserts.lua [file...]
-- With no argument, looks at the suite. Exits non-zero when it finds one.

local ASSERTIVAS = { check = true, eq = true, fail = true }

local function lerLinhas(caminho)
  local f = assert(io.open(caminho, "r"), "nao consegui abrir " .. caminho)
  local linhas = {}
  for l in f:lines() do linhas[#linhas + 1] = l end
  f:close()
  return linhas
end

-- WHICH FUNCTION IS A PREDICATE. The first version of this rule said "has a
-- return and calls no assertion", and that flagged fifty functions,
-- including factories like makeVoxelHandle and loadWith, which are
-- legitimately called for their side effect. A rule that is too broad is not
-- a linter, it is noise nobody reads.
--
-- The tight rule: EVERY `return` of the function returns a boolean. That is,
-- a comparison, a true/false literal, or nothing. A function like that only
-- exists to be asked; discarding its answer is always a mistake.
local function pareceBooleano(expr)
  expr = expr:match("^%s*(.-)%s*$")
  if expr == "" then return false end
  if expr == "true" or expr == "false" then return true end
  if expr:match("[=~<>]=") or expr:match("[<>]") then return true end
  if expr:match("^not%s") then return true end
  return false
end

local function achaPredicados(linhas)
  local predicados = {}
  local atual, todosBool, algumReturn = nil, true, false
  local function fecha()
    if atual and algumReturn and todosBool and not ASSERTIVAS[atual] then
      predicados[atual] = true
    end
    atual, todosBool, algumReturn = nil, true, false
  end
  for _, l in ipairs(linhas) do
    local nome = l:match("^local function ([%w_]+)%s*%(")
      or l:match("^%s%s+local function ([%w_]+)%s*%(")
    if nome then
      fecha()
      atual = nome
    end
    if atual then
      local expr = l:match("^%s*return%s+(.*)$")
      if expr then
        algumReturn = true
        if not pareceBooleano(expr) then todosBool = false end
      end
      if l:match("^end$") then fecha() end
    end
  end
  fecha()
  return predicados
end

-- A call is DISCARDED when it is the WHOLE statement. Two things disguise
-- this and both showed up on the first run:
--
--   expression continuation. `close(v[6], 0.90) or close(...)` starts the
--   line with the predicate, but the previous line ends in `and (`, so the
--   value is being consumed. Flagging this is noise, and noise trains the
--   person to ignore the linter.
--
--   a call used as an argument. Then the line does not start with the name.
local function continuacao(anterior)
  local a = (anterior or ""):gsub("%s+$", "")
  return a:match("[%(,]$") ~= nil
    or a:match("%f[%w]and$") ~= nil
    or a:match("%f[%w]or$") ~= nil
    or a:match("%f[%w]not$") ~= nil
    or a:match("=$") ~= nil
end

local function achaDescartadas(linhas, predicados)
  local achados = {}
  for i, l in ipairs(linhas) do
    local corpo = l:match("^%s*(.-)%s*$")
    if corpo ~= "" and not corpo:match("^%-%-") then
      local nome = corpo:match("^([%w_]+)%s*%(")
      if nome and predicados[nome] and not continuacao(linhas[i - 1]) then
        achados[#achados + 1] = { linha = i, nome = nome, texto = corpo }
      end
    end
  end
  return achados
end

local alvos = {}
for i = 1, #arg do alvos[#alvos + 1] = arg[i] end
if #alvos == 0 then
  alvos[1] = "mods/voxel_characters/tests/voxel_chars_test.lua"
end

local total = 0
for _, caminho in ipairs(alvos) do
  local linhas = lerLinhas(caminho)
  local predicados = achaPredicados(linhas)
  local nomes = {}
  for k in pairs(predicados) do nomes[#nomes + 1] = k end
  table.sort(nomes)
  print(string.format("%s: %d predicados (%s)", caminho, #nomes,
    table.concat(nomes, ", ")))
  local achados = achaDescartadas(linhas, predicados)
  for _, a in ipairs(achados) do
    print(string.format("  %s:%d  %s devolve booleano e o retorno e descartado",
      caminho, a.linha, a.nome))
    print(string.format("      %s", a.texto:sub(1, 90)))
  end
  total = total + #achados
end

if total > 0 then
  print("")
  print(string.format("%d check(s) that check nothing. Wrap them in check(...).", total))
  os.exit(1)
end
print("no discarded checks")
