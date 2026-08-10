-- Proves that a diff touched ONLY comments, by comparing the code underneath.
--
--   luajit tools/so_comentarios.lua <antes.lua> <depois.lua>
--
-- WHY THIS EXISTS. Roadmap item 2 rewrites over 3500 Portuguese comment lines
-- into en-US, across files that hold the whole mod. Those comments sit inside
-- the production file, so a translation pass is an edit to `main.lua`, and the
-- failure mode is a rewritten line of CODE hiding among a thousand rewritten
-- lines of prose. Reading the diff does not catch that: the diff is enormous
-- and every line looks like the change you asked for.
--
-- So do not read it. Strip the comments from both sides and require the rest
-- to be identical. A translation that touches code fails mechanically, and it
-- fails on the line that did it.
--
-- The suite is not a substitute. 603 checks passing says the behaviour they
-- cover is unchanged; it does not say the code is unchanged, and this pass
-- edits files the suite exercises indirectly at best (the harness, the probes).

local function lerArquivo(caminho)
  local f = io.open(caminho, "rb")
  if not f then
    io.stderr:write("nao consegui abrir: " .. tostring(caminho) .. "\n")
    os.exit(2)
  end
  local s = f:read("*a")
  f:close()
  return s
end

-- Strips comments, keeps everything else, and keeps LINE NUMBERS intact by
-- emitting one output line per input line. Without that, the report points at
-- a line that does not exist in either file.
--
-- Strings are code and stay. A comment marker inside a string is not a comment,
-- which is the case a regex-based version gets wrong, and this file exists
-- precisely because "looks right" is not good enough here.
local function tiraComentarios(src, nome)
  -- LINE ENDINGS ARE NORMALISED FIRST, and this is a correctness fix, not
  -- tidiness. LuaJIT accepts a bare CR as a line break. The short-comment
  -- branch below ended a comment at the next `\n`, so given
  --
  --     local x = 1 -- comment<CR>local y = 2<CR>
  --
  -- the comment swallowed `local y = 2` as well, and the gate reported the
  -- code as identical while it differed. That is a false PASS, which is the
  -- one direction this tool must never fail in. Found by an independent
  -- review after nineteen hand-written adversarial cases missed it.
  --
  -- The cost, stated so nobody rediscovers it as a bug: a change of line
  -- ending INSIDE a long string is now invisible to this gate. That is a
  -- deliberate trade. Being blind to `\r\n` versus `\n` inside one string is
  -- survivable; being blind to every line after a comment is not.
  src = src:gsub("\r\n", "\n"):gsub("\r", "\n")

  local out, i, n = {}, 1, #src
  local linha = {}

  local function empurra(c)
    linha[#linha + 1] = c
    if c == "\n" then
      out[#out + 1] = table.concat(linha)
      linha = {}
    end
  end

  -- A long bracket is [=*[ ... ]=*] with matching numbers of equals signs.
  -- Returns the level, or nil when the position is not a long bracket open.
  local function nivelColchete(pos)
    if src:sub(pos, pos) ~= "[" then return nil end
    local j = pos + 1
    local eq = 0
    while src:sub(j, j) == "=" do eq = eq + 1; j = j + 1 end
    if src:sub(j, j) == "[" then return eq, j + 1 end
    return nil
  end

  -- An UNTERMINATED long bracket is refused, not swallowed.
  --
  -- The previous version returned "end of file" when it could not find the
  -- closer, so a file with a stray `--[[` had everything after it stripped.
  -- Two such files then compared equal no matter what code they contained,
  -- which is a false PASS on input that is not even valid Lua. Refusing is
  -- correct and cheap: the file cannot compile anyway, and the person needs
  -- to know which line opened the bracket.
  local naoFechou = nil
  local function fimDoColchete(pos, eq)
    local fecha = "]" .. string.rep("=", eq) .. "]"
    local a = src:find(fecha, pos, true)
    if not a then
      local ateAqui = src:sub(1, pos)
      local _, linhas = ateAqui:gsub("\n", "")
      naoFechou = { eq = eq, linha = linhas + 1 }
      return n + 1, n + 1
    end
    return a, a + #fecha
  end

  while i <= n do
    local c = src:sub(i, i)

    if c == "-" and src:sub(i + 1, i + 1) == "-" then
      -- Comment. A long comment can span lines; a short one ends at the break.
      local eq, corpo = nivelColchete(i + 2)
      if eq then
        local a, depois = fimDoColchete(corpo, eq)
        -- Keep the line breaks the comment swallowed, so numbering survives.
        for _ = 1, select(2, src:sub(i, depois - 1):gsub("\n", "")) do empurra("\n") end
        i = depois
      else
        local quebra = src:find("\n", i, true)
        i = quebra and (quebra + 1) or (n + 1)
        empurra("\n")
      end

    elseif c == '"' or c == "'" then
      -- Short string. Escapes matter: "\\" ends, "\"" does not.
      local aspas = c
      empurra(c)
      i = i + 1
      while i <= n do
        local d = src:sub(i, i)
        empurra(d)
        if d == "\\" then
          i = i + 1
          if i <= n then empurra(src:sub(i, i)) end
        elseif d == aspas then
          i = i + 1
          break
        end
        i = i + 1
      end

    else
      local eq, corpo = nivelColchete(i)
      if eq then
        local a, depois = fimDoColchete(corpo, eq)
        for k = i, depois - 1 do empurra(src:sub(k, k)) end
        i = depois
      else
        empurra(c)
        i = i + 1
      end
    end
  end
  if #linha > 0 then out[#out + 1] = table.concat(linha) end
  if naoFechou then
    io.stderr:write(string.format(
      "%s: colchete longo aberto na linha %d e nunca fechado (nivel %d).\n"
      .. "  Isso nem compila, e o comparador nao pode responder nada sobre o\n"
      .. "  que vem depois: tudo dali para baixo seria engolido como se fosse\n"
      .. "  comentario, e dois arquivos diferentes sairiam iguais.\n",
      tostring(nome), naoFechou.linha, naoFechou.eq))
    os.exit(3)
  end
  return out
end

-- Trailing whitespace is what a comment strip leaves behind on a line that was
-- code followed by a comment, so it is normalised away. Indentation is NOT:
-- a change in indentation is a change to the code's shape and worth reporting.
local function normaliza(l)
  return (l:gsub("%s+$", ""))
end

local antes = tiraComentarios(lerArquivo(arg[1] or ""), arg[1])
local depois = tiraComentarios(lerArquivo(arg[2] or ""), arg[2])

local problemas = {}
local maior = math.max(#antes, #depois)
for k = 1, maior do
  local a, b = normaliza(antes[k] or ""), normaliza(depois[k] or "")
  if a ~= b then
    problemas[#problemas + 1] = { linha = k, antes = a, depois = b }
  end
end

if #problemas == 0 then
  print(string.format("SO COMENTARIOS: o codigo e identico (%d linhas)", maior))
  os.exit(0)
end

print(string.format("CODIGO MUDOU em %d linha(s):", #problemas))
for k = 1, math.min(#problemas, 25) do
  local p = problemas[k]
  print(string.format("  linha %d", p.linha))
  print("    antes : " .. p.antes)
  print("    depois: " .. p.depois)
end
if #problemas > 25 then
  print(string.format("  ... e mais %d", #problemas - 25))
end
os.exit(1)
