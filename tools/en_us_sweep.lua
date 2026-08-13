-- IS THE TOOL SURFACE en-US? (roadmap T1.5)
--
--   luajit mods/voxel_characters/tools/en_us_sweep.lua           gate
--   luajit mods/voxel_characters/tools/en_us_sweep.lua --audit   full report
--
-- From the REPO ROOT, like every other gate here.
--
-- WHY A SWEEP AND NOT A ONE-OFF PASS. The handoff recorded en-US as DONE
-- because a sweep for Portuguese function words in COMMENTS came back clean.
-- That was true and it was not the whole surface: the text these tools PRINT is
-- still largely Portuguese, and a contributor reads that before they read a
-- comment. A second one-off pass would leave the same hole open for whatever
-- gets written next, so this is a gate.
--
-- WHAT IT DISTINGUISHES, and getting this wrong is why the first attempt was
-- useless. A naive grep for Portuguese words matched:
--
--   * function and variable names (`avalia`, `veredito`, `saida`), which are
--     internal and not what anybody reads;
--   * file names in string form (`card_antes.png`), which are data;
--   * option VALUES that are part of a tool's command line (`VC_CLIP_DEGRAU=alto`),
--     where a rename is a breaking change and not a translation.
--
-- So this extracts the CONTENTS of string literals on lines that print, strips
-- format specifiers and variable interpolations, and only then looks for
-- Portuguese. Identifiers never enter the comparison.
--
-- THE SCOPE LIVES IN DATA. `tools/en_us_scope.txt` says which paths are surface
-- (must be clean) and which are deferred, each with a reason. Two failure
-- modes, both real:
--
--   1. a Portuguese string in a SURFACE path: a regression, fails;
--   2. a deferred entry that no longer matches anything: a stale exemption,
--      fails. An exemption nobody removed silently covers the next regression,
--      which is how a gate stops gating.

package.path = "./?.lua;./?/init.lua;" .. package.path

local RAIZ = "mods/voxel_characters"
local ESCOPO = RAIZ .. "/tools/en_us_scope.txt"
local AUDIT = (arg[1] == "--audit")
-- `--file <path>` lists every hit in one file whatever zone it is in. That is
-- the view you want while converting something currently deferred: the audit
-- deliberately prints only counts for deferred paths, so working through one
-- of them would otherwise mean editing the scope file just to see the list.
local SOFILE = (arg[1] == "--file") and arg[2] or nil

--------------------------------------------------------------------------
-- Portuguese function words that do not collide with English.
--
-- Kept tight on purpose: a word that is also English, or that only ever appears
-- as an identifier, produces noise, and a noisy gate gets waived. Every entry
-- here was seen in a printed string in this repository.
--------------------------------------------------------------------------
local PT = {
  "nao", "nenhum", "nenhuma", "falhou", "passou", "arquivo", "arquivos",
  "pasta", "malha", "quadro", "quadros", "folha", "folhas", "escolha",
  "escolhas", "veredito", "receita", "aviso", "erro", "faltando",
  "esperado", "esperados", "checagem", "checagens", "vazio", "vazia",
  "iguais", "difere", "diferem", "trava", "piso", "rodada", "precisa",
  "ferramenta", "comeco", "achou", "sobra", "medida", "medidas", "linhas",
  "usando", "gerando", "lendo", "rodando", "salvando", "pronto", "prontos",
  "certo", "errado", "tentando", "abrindo", "fechando", "guardado",
}

--------------------------------------------------------------------------
local function lines(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local out = {}
  for l in f:lines() do out[#out + 1] = l end
  f:close()
  return out
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Everything a human might read coming out of these tools.
--
-- INCLUDING WHAT IS WRITTEN INTO ARTEFACTS, not only what reaches a terminal.
-- The first version missed `handle:write(...)`, and the gap was not
-- theoretical: `tools/juiz/dados/modelo.txt` carries a Portuguese header
-- ("# modelo do juiz, gerado por ajusta.lua --pesos") that a contributor reads
-- when they open the judge's model. A file this project generates and keeps is
-- as much its surface as a log line.
local function isOutputLine(l)
  return l:find("echo%s") or l:find("print%s*%(") or l:find("printf")
      or l:find("io%.write") or l:find("nota%s*%(") or l:find("diga%s")
      or l:find("say%s") or l:find("io%.stderr:write") or l:find(":write%s*%(")
end

-- Comment lines are already en-US and are not the surface. Checking them again
-- would re-report a solved problem and bury the open one.
local function isComment(l)
  local t = trim(l)
  return t:sub(1, 1) == "#" or t:sub(1, 2) == "--"
end

-- PER-LINE EXEMPTION, and it has to carry a reason.
--
--   echo "FALHOU"   # en-us: fixture, proves the PT branch still fires
--
-- Needed because some Portuguese in a surface file is legitimately not product
-- text: the clearest case is a TEST FIXTURE for the Portuguese branch of a
-- verdict regex. The regexes in this repository accept `FALHOU|FAILED`, and a
-- suite that only ever feeds them the English half leaves the other half
-- unexercised, which is the "a branch nothing exercises looks exactly like one
-- that works" defect. So the escape hatch exists, and requiring a reason after
-- the marker is what stops it from becoming a silent mute button.
local function exemptLine(l)
  local motivo = l:match("[#%-][#%-]?%s*en%-us:%s*(.+)$")
  if motivo and trim(motivo) ~= "" then return true end
  return false
end

-- The CONTENTS of string literals, with everything that is not prose removed:
-- format specifiers, shell and Lua interpolations, and paths. What is left is
-- the text a person reads.
local function proseOf(l)
  local pedacos = {}
  for s in l:gmatch('"([^"]*)"') do pedacos[#pedacos + 1] = s end
  for s in l:gmatch("'([^']*)'") do pedacos[#pedacos + 1] = s end
  local texto = table.concat(pedacos, " ")
  texto = texto:gsub("%%%-?%d*%.?%d*[sdfxq]", " ")   -- %s %d %-44s %.1f
  texto = texto:gsub("%${[^}]*}", " ")               -- ${VAR}
  texto = texto:gsub("%$%(?[%w_]+%)?", " ")          -- $VAR $(cmd)
  texto = texto:gsub("[%w_%-%./]+%.%a%a%a?%a?", " ") -- file.ext, paths
  texto = texto:gsub("[%w_]+=[%w_%.%-]+", " ")       -- key=value on a command line
  return texto
end

local function ptWordsIn(texto)
  local baixo = " " .. texto:lower() .. " "
  local achados = {}
  for _, w in ipairs(PT) do
    -- Word boundaries by character class, so `erro` does not match `error`.
    --
    -- UNDERSCORE COUNTS AS PART OF THE WORD, and leaving it out made the gate
    -- cry wolf on its own repository: Lua's `%w` is letters and digits only, so
    -- in `VC_TRAVA_DONO` the underscores around TRAVA read as boundaries and
    -- the identifier was reported as Portuguese prose. Identifiers are exactly
    -- what this sweep exists NOT to flag, and a gate that fires on correct
    -- input gets waived by the second day.
    if baixo:find("[^%w_]" .. w .. "[^%w_]") then achados[#achados + 1] = w end
  end
  return achados
end

--------------------------------------------------------------------------
-- The scope file
--------------------------------------------------------------------------
local function readScope()
  local src = lines(ESCOPO)
  if not src then
    io.stderr:write("cannot read " .. ESCOPO .. "\n")
    os.exit(1)
  end
  local regras = {}
  for _, l in ipairs(src) do
    if not l:match("^%s*#") and trim(l) ~= "" then
      local padrao, zona, motivo = l:match("^(%S+)%s+(%S+)%s+(.*)$")
      if padrao then
        regras[#regras + 1] = { padrao = padrao, zona = zona,
                                motivo = trim(motivo), hits = 0, ficheiros = 0 }
      end
    end
  end
  return regras
end

-- First matching rule wins, so a specific path can sit above a broad one.
local function zoneOf(regras, caminho)
  for _, r in ipairs(regras) do
    local p = r.padrao:gsub("%-", "%%-"):gsub("%.", "%%."):gsub("%*%*", ".*"):gsub("%*", "[^/]*")
    if caminho:find("^" .. p .. "$") or caminho:find("^" .. p) then return r end
  end
  return nil
end

--------------------------------------------------------------------------
-- Walk
--------------------------------------------------------------------------
-- `.claude` IS PRUNED, and the reason is a red battery nobody caused.
--
-- Agent worktrees land in `mods/voxel_characters/.claude/worktrees/<id>/`, and
-- a worktree is a full second copy of this repository. The walk found the copy,
-- reported `.claude/worktrees/agent-…/tools/so_comentarios_test.lua` as an
-- undeclared file printing Portuguese, and the battery went red -- for a file
-- that IS declared, at its real path, one directory up. Every commit was
-- blocked until the worktree was deleted, which is a gate failing on a
-- condition its subject cannot fix.
--
-- Declaring the copied path in the scope file would not work either: the id in
-- the path is different for every agent, and a scope rule that stops matching
-- fails the gate on purpose (see en_us_scope.txt).
local function fileList()
  local p = io.popen("find " .. RAIZ .. " -name .claude -prune -o "
    .. "-type f \\( -name '*.sh' -o -name '*.lua' "
    .. "-o -name '*.command' \\) -print | sort")
  local out = {}
  for l in p:lines() do out[#out + 1] = l end
  p:close()
  return out
end

if SOFILE then
  local src = lines(SOFILE)
  if not src then io.stderr:write("cannot read " .. SOFILE .. "\n"); os.exit(1) end
  local marcado, n = false, 0
  for i, l in ipairs(src) do
    if isComment(l) then
      if exemptLine(l) then marcado = true end
    elseif trim(l) == "" then marcado = false end
    if not isComment(l) and not exemptLine(l) and not marcado and isOutputLine(l) then
      local palavras = ptWordsIn(proseOf(l))
      if #palavras > 0 then
        n = n + 1
        print(string.format("%4d  [%s]  %s", i, table.concat(palavras, ","),
          trim(l):sub(1, 96)))
      end
    end
  end
  print(string.format("\n%d line(s) in %s", n, SOFILE))
  os.exit(0)
end

local regras = readScope()
if #regras == 0 then
  io.stderr:write("the scope file declares no rules; nothing was checked, "
    .. "which is not a pass\n")
  os.exit(1)
end

local problemas, relatorio = {}, {}
local totalSuperficie, totalDiferido = 0, 0

for _, caminho in ipairs(fileList()) do
  local rel = caminho
  local src = lines(caminho)
  local regra = zoneOf(regras, rel)
  local achadosArquivo = {}
  if src then
    -- The marker applies to its own line OR to the lines of the statement
    -- right below it, because a reason worth writing rarely fits as a trailing
    -- comment. A blank line or a non-comment, non-output line ends its reach,
    -- so an exemption cannot drift down a file and quietly cover something it
    -- was never about.
    local marcado = false
    for n, l in ipairs(src) do
      if isComment(l) then
        if exemptLine(l) then marcado = true end
      elseif trim(l) == "" then
        marcado = false
      end
      if not isComment(l) and not exemptLine(l) and not marcado and isOutputLine(l) then
        local palavras = ptWordsIn(proseOf(l))
        if #palavras > 0 then
          achadosArquivo[#achadosArquivo + 1] =
            { linha = n, palavras = palavras, texto = trim(l):sub(1, 78) }
        end
      end
    end
  end
  if #achadosArquivo > 0 then
    local zona = regra and regra.zona or "UNDECLARED"
    if regra then
      regra.hits = regra.hits + #achadosArquivo
      regra.ficheiros = regra.ficheiros + 1
    end
    relatorio[#relatorio + 1] = { rel = rel, zona = zona, achados = achadosArquivo }
    if zona == "surface" then
      totalSuperficie = totalSuperficie + #achadosArquivo
      for _, a in ipairs(achadosArquivo) do
        problemas[#problemas + 1] = string.format(
          "%s:%d prints Portuguese (%s)", rel, a.linha,
          table.concat(a.palavras, ", "))
      end
    elseif zona == "UNDECLARED" then
      problemas[#problemas + 1] = string.format(
        "%s is not declared in en_us_scope.txt, and it prints Portuguese "
        .. "(%d line(s)). Declare it as surface or as deferred with a reason.",
        rel, #achadosArquivo)
    else
      totalDiferido = totalDiferido + #achadosArquivo
    end
  end
end

-- A deferred rule that matches nothing is an exemption nobody removed.
for _, r in ipairs(regras) do
  if r.zona ~= "surface" and r.hits == 0 then
    problemas[#problemas + 1] = string.format(
      "the scope rule \"%s %s\" no longer matches any Portuguese output. "
      .. "Delete it: a stale exemption covers the next regression silently.",
      r.padrao, r.zona)
  end
end

--------------------------------------------------------------------------
if AUDIT then
  print("en-US sweep, full audit")
  print("")
  local porZona = {}
  for _, r in ipairs(relatorio) do
    porZona[r.zona] = porZona[r.zona] or {}
    table.insert(porZona[r.zona], r)
  end
  for _, zona in ipairs({ "surface", "UNDECLARED", "deferred-needs-love",
                          "deferred-full-battery", "deferred-api", "internal" }) do
    local grupo = porZona[zona]
    if grupo then
      print(("== %s"):format(zona))
      for _, r in ipairs(grupo) do
        print(("   %-38s %d line(s)"):format(r.rel:gsub("^" .. RAIZ .. "/", ""),
          #r.achados))
        if zona == "surface" or zona == "UNDECLARED" then
          for _, a in ipairs(r.achados) do
            print(("      %d  %s"):format(a.linha, a.texto))
          end
        end
      end
      print("")
    end
  end
  print(("surface lines: %d    deferred lines: %d"):format(totalSuperficie, totalDiferido))
end

if #problemas > 0 then
  if not AUDIT then
    for _, p in ipairs(problemas) do print("  " .. p) end
  else
    print("")
    for _, p in ipairs(problemas) do print("  " .. p) end
  end
  print(("EN-US SWEEP FAILED: %d problem(s)"):format(#problemas))
  os.exit(1)
end
print(("en-US sweep ok: surface clean, %d deferred line(s) declared with reasons")
  :format(totalDiferido))
