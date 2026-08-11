-- EVERY STRING A GATE GREPS FOR IS STILL PRINTED BY SOMETHING (roadmap T1.5).
--
--   luajit mods/voxel_characters/tools/output_contract.lua
--   luajit mods/voxel_characters/tools/output_contract.lua --audit
--
-- From the repo root. No LOVE, no display, runs in milliseconds.
--
-- WHY THIS EXISTS. Half this project's gates work by running something under
-- LOVE and grepping its output. That makes the printed text an interface
-- between two files that never mention each other: `check.sh` greps
-- "modo escolha:", and the only thing that makes that work is a `print` in
-- `lab.lua` written months earlier.
--
-- Rename one side and the gate does not go red. It goes GREEN AND EMPTY: the
-- grep matches nothing, the count is zero, and whether that reads as a failure
-- depends on how the check was written. Several here would simply stop
-- measuring. That is the worst kind of breakage, and translating this output to
-- en-US means touching every one of those strings at once.
--
-- WHAT IT CHECKS. For each gate that greps, every PROSE literal it searches for
-- must appear in the source of something that prints. It is a static check, so
-- it needs no display and can run on every commit, which is the whole point:
-- the end-to-end proof is a full battery on a machine with a screen, and that
-- is far too slow to be the only thing standing between a rename and a silently
-- dead gate.
--
-- WHAT IT DELIBERATELY DOES NOT CHECK. That the string is printed in the right
-- circumstances, or that the number next to it means anything. Only that the
-- two halves still speak the same language. The battery remains the real proof.

local RAIZ = "mods/voxel_characters"

-- The files that grep, and where the text they grep for has to come from.
-- Listed rather than discovered, because "everything that greps" would sweep in
-- greps over files, logs and process lists, which are not this contract.
local CONSUMIDORES = {
  { arquivo = "tools/render/check.sh", produtores = { "tools/render" } },
  { arquivo = "tools/ingame/run.sh", produtores = { "tools/ingame" } },
  { arquivo = "tools/ingame/clip.sh", produtores = { "tools/ingame" } },
  { arquivo = "tools/ingame/trailer.sh", produtores = { "tools/ingame" } },
  { arquivo = "tools/ingame/monta.sh", produtores = { "tools/ingame" } },
  { arquivo = "tools/render/card.sh", produtores = { "tools/render" } },
}

-- Producers are searched as whole directories, so a string moving from one file
-- to another inside the harness is not reported as a break. It is not one.
local PRODUTORES_EXTRA = { "main.lua" }

-- Text this project greps but does not print, because something else does.
-- Listed with a reason apiece: an exemption without one is how a gate quietly
-- stops covering things.
local DE_FORA = {
  ["average:"] = "ffmpeg's psnr filter prints it, not us",
  ["driver error"] = "a diagnostic grep in run.sh over a string no driver has "
    .. "printed for some time; it is in a `head -3` of hints, not an "
    .. "assertion, so it fails open rather than green",
}

local AUDIT = (arg and arg[1] == "--audit")

local function ler(caminho)
  local f = io.open(caminho, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function listar(dir)
  local out = {}
  local p = io.popen("find " .. RAIZ .. "/" .. dir ..
                     " -type f \\( -name '*.lua' -o -name '*.sh' \\) 2>/dev/null")
  if not p then return out end
  for linha in p:lines() do out[#out + 1] = linha end
  p:close()
  return out
end

-- The literals a shell line greps FOR. Taking every quoted string on any line
-- that mentions grep was the first attempt and it was far too crude: it
-- collected the option values passed INTO the harness on the same line
-- (`opt="front_shape:0.12"`), pieces of nested quoting out of a pipeline, and
-- `head -1`. Sixteen false alarms, which is how a gate gets switched off.
--
-- So the pattern is anchored on the command: `grep`, its flags, then the first
-- quoted argument, which is the only one that is the search text.
local function literaisDaLinha(linha)
  local achados = {}
  local pos = 1
  while true do
    local s, e = linha:find("[%s|(]grep%s", pos)
    if not s then s, e = linha:find("^grep%s", pos) end
    if not s then break end
    local resto = linha:sub(e)
    -- flags, then the argument
    resto = resto:gsub("^%s*", "")
    while resto:match("^%-%S+%s") do resto = resto:gsub("^%-%S+%s*", "") end
    local lit = resto:match('^"([^"]*)"') or resto:match("^'([^']*)'")
    if lit then achados[#achados + 1] = lit end
    pos = e + 1
  end
  for pad in linha:gmatch("sed %-nE? '([^']+)'") do
    -- `s/.*piso (-?[0-9]+).*/\1/p` -- the middle is what has to still be printed
    local corpo = pad:match("^s/(.-)/") or pad
    achados[#achados + 1] = corpo
  end
  return achados
end

-- PROSE, not regex machinery and not identifiers. A literal counts when it
-- holds a run of letters that reads like a word someone wrote, and it is
-- skipped when it is plainly a pattern, a path or a variable.
local function ehProsa(s)
  if #s < 4 then return false end
  if s:match("^%$") or s:match("^%-") then return false end
  if s:match("%$%{?%w") then return false end          -- has a shell variable
  if s:match("^%^?%[") or s:match("%[%^") then return false end
  if s:match("^%%") or s:match("^s/") then return false end
  if s:match("/") and not s:match("%s") then return false end  -- a path
  -- At least two letter-runs, or one long one: "IoU [0-9.]*" counts, "[0-9]+"
  -- does not.
  local letras = 0
  for _ in s:gmatch("%a%a%a+") do letras = letras + 1 end
  return letras >= 1
end

-- The part of the literal that is fixed text, with the regex machinery cut off.
-- `grep -oE 'fim, [0-9]+ fotos'` has to be looked for as "fim," and "fotos",
-- not as itself, because the producer prints a number where the class is.
local function pedacosFixos(s)
  local pedacos = {}
  -- `.` counts as machinery too: `grep -o 'modo escolha: .*'` left a stray
  -- trailing dot and reported a live pair as broken.
  local limpo = s:gsub("%[[^%]]*%]", "\1"):gsub("[%(%)%|%*%+%?%^%$%.\\]", "\1")
  -- A RUN OF TWO OR MORE SPACES IS A FORMAT BOUNDARY, not text. check.sh greps
  -- "front  niveis" because the harness pads the face name into a column; the
  -- word "front" is data and appears nowhere in the source, so looking for the
  -- pair as one string reports a healthy gate as broken.
  limpo = limpo:gsub("  +", "\1")
  for p in limpo:gmatch("[^\1]+") do
    p = p:gsub("^%s+", ""):gsub("%s+$", "")
    if #p >= 4 and p:match("%a%a%a") then pedacos[#pedacos + 1] = p end
  end
  return pedacos
end

-- THE CONSUMERS ARE NOT PRODUCERS, and leaving them in made this gate useless.
--
-- The first version searched whole directories, and `tools/render` contains
-- `check.sh`. So when `lab.lua` stopped printing "modo escolha:", the string was
-- still found: in check.sh's own grep line. The gate confirmed that check.sh
-- greps what check.sh greps. Four deliberate half-done renames all passed.
--
-- A gate whose corpus includes the thing being checked is not measuring
-- anything. Every consumer is excluded from every producer corpus.
local ehConsumidor = {}
for _, c in ipairs(CONSUMIDORES) do ehConsumidor[RAIZ .. "/" .. c.arquivo] = true end

local fontes = {}
local function fonteDe(dirs)
  local chave = table.concat(dirs, ",")
  if fontes[chave] then return fontes[chave] end
  local todo = {}
  for _, d in ipairs(dirs) do
    for _, f in ipairs(listar(d)) do
      if not ehConsumidor[f] then todo[#todo + 1] = ler(f) or "" end
    end
  end
  for _, extra in ipairs(PRODUTORES_EXTRA) do
    todo[#todo + 1] = ler(RAIZ .. "/" .. extra) or ""
  end
  -- LUA CONCATENATION IS JOINED BACK UP. `driver.lua` prints
  --   "VC driver: controle piso %d, mod ligado contra " .. "desligado %d"
  -- and the string run.sh greps for straddles the break, so it is present in
  -- the output and absent from the source. Removing the `" .. "` seams makes
  -- the corpus read the way the output does.
  local juntado = table.concat(todo, "\n"):gsub('"%s*%.%.%s*"', "")
  fontes[chave] = juntado
  return fontes[chave]
end

local frouxas = {}
local function fonteFrouxa(dirs)
  local chave = table.concat(dirs, ",")
  if not frouxas[chave] then frouxas[chave] = fonteDe(dirs):gsub("%s+", " ") end
  return frouxas[chave]
end

local problemas, verificados = {}, 0
for _, c in ipairs(CONSUMIDORES) do
  local texto = ler(RAIZ .. "/" .. c.arquivo)
  if not texto then
    problemas[#problemas + 1] = c.arquivo .. " does not exist"
  else
    local fonte = fonteDe(c.produtores)
    local n = 0
    for linha in texto:gmatch("[^\n]+") do
      local corte = linha:match("^%s*#")
      if not corte then
        for _, lit in ipairs(literaisDaLinha(linha)) do
          if ehProsa(lit) then
            for _, pedaco in ipairs(pedacosFixos(lit)) do
              n = n + 1
              verificados = verificados + 1
              -- Padding is not a rename. `printf "%-8s niveis"` puts a run of
              -- spaces in the output that is nowhere in the source, so a miss
              -- is retried with whitespace collapsed on both sides before it
              -- counts as a broken pair.
              local frouxo = pedaco:gsub("%s+", " ")
              if DE_FORA[pedaco] then
                -- counted, not required
              elseif not fonte:find(pedaco, 1, true)
                 and not fonteFrouxa(c.produtores):find(frouxo, 1, true) then
                problemas[#problemas + 1] = string.format(
                  "%s greps %q, which nothing under %s prints any more",
                  c.arquivo, pedaco, table.concat(c.produtores, " or "))
              end
            end
          end
        end
      end
    end
    if AUDIT then
      print(string.format("   %-34s %d literal(s) checked", c.arquivo, n))
    end
  end
end

if #problemas > 0 then
  for i = 1, math.min(#problemas, 12) do print("  " .. problemas[i]) end
  if #problemas > 12 then
    print(string.format("  ... and %d more", #problemas - 12))
  end
  print(string.format("OUTPUT CONTRACT FAILED: %d broken pair(s)", #problemas))
  os.exit(1)
end
print(string.format(
  "output contract ok: %d grepped literal(s), every one still printed somewhere",
  verificados))
