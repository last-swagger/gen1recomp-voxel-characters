-- Adversarial tests for the comments-only gate.
--
--   luajit tools/so_comentarios_test.lua
--
-- The gate strips comments and compares the code underneath, and a whole
-- translation pass over the production file rides on it. So the case that
-- matters is not "does it work", it is: **can it report IDENTICAL while the
-- code differs?** A false FAIL costs someone five minutes. A false PASS lets a
-- changed line of the mod ship inside a thousand lines of rewritten prose.
--
-- Every case below is written as a pair plus the verdict it must produce, so
-- adding a case is one table entry.

local AQUI = arg[0]:match("^(.*)/[^/]+$") or "."
local MOTOR = AQUI .. "/so_comentarios.lua"

local tmp = os.getenv("TMPDIR") or "/tmp"
local function escreve(nome, txt)
  local caminho = tmp .. "/vc_soc_" .. nome
  local f = assert(io.open(caminho, "wb"))
  f:write(txt)
  f:close()
  return caminho
end

-- Runs the real tool as a process, because that is how it is used. Testing the
-- stripper as a library would miss the exit code, and the exit code is what
-- every caller reads.
local function compara(a, b)
  local pa, pb = escreve("a.lua", a), escreve("b.lua", b)
  local cmd = string.format("luajit %q %q %q > /dev/null 2>&1; echo $?",
                            MOTOR, pa, pb)
  local p = assert(io.popen(cmd))
  local code = tonumber((p:read("*a"):gsub("%s", "")))
  p:close()
  return code == 0 and "igual" or "diferente"
end

local CASOS = {
  {
    nome = "comentario simples traduzido",
    a = "-- portugues aqui\nlocal x = 1\n",
    b = "-- english here\nlocal x = 1\n",
    esperado = "igual",
  },
  {
    nome = "codigo muda junto com o comentario",
    a = "-- portugues\nlocal x = 1\n",
    b = "-- english\nlocal x = 2\n",
    esperado = "diferente",
  },
  {
    nome = "string curta e codigo, nao comentario",
    a = 'local s = "ola"\n',
    b = 'local s = "hello"\n',
    esperado = "diferente",
  },
  {
    nome = "duplo hifen DENTRO de string nao abre comentario",
    a = 'local s = "a -- b"\nlocal y = 1\n',
    b = 'local s = "a -- b"\nlocal y = 2\n',
    esperado = "diferente",
  },
  {
    nome = "comentario longo nivel 0",
    a = "--[[ pt ]]\nlocal x = 1\n",
    b = "--[[ en ]]\nlocal x = 1\n",
    esperado = "igual",
  },
  {
    nome = "comentario longo nivel 2, com ]] dentro",
    a = "--[==[ pt ]] ainda comentario ]==]\nlocal x = 1\n",
    b = "--[==[ en ]] still comment ]==]\nlocal x = 1\n",
    esperado = "igual",
  },
  {
    nome = "comentario longo nivel 2 escondendo mudanca de codigo",
    a = "--[==[ pt ]] c ]==]\nlocal x = 1\n",
    b = "--[==[ en ]] c ]==]\nlocal x = 2\n",
    esperado = "diferente",
  },
  {
    nome = "string longa nivel 2 e codigo",
    a = "local s = [==[ um ]] dois ]==]\n",
    b = "local s = [==[ one ]] two ]==]\n",
    esperado = "diferente",
  },
  {
    nome = "-- dentro de string longa nao vira comentario",
    a = "local s = [[ a -- b ]]\nlocal y = 1\n",
    b = "local s = [[ a -- b ]]\nlocal y = 2\n",
    esperado = "diferente",
  },
  {
    nome = "comentario na ultima linha sem newline final",
    a = "local x = 1\n-- pt",
    b = "local x = 1\n-- en",
    esperado = "igual",
  },
  {
    nome = "codigo na ultima linha sem newline final",
    a = "local x = 1",
    b = "local x = 2",
    esperado = "diferente",
  },
  {
    nome = "aspas escapadas nao terminam a string",
    a = 'local s = "a\\"-- b"\nlocal y = 1\n',
    b = 'local s = "a\\"-- b"\nlocal y = 2\n',
    esperado = "diferente",
  },
  {
    nome = "barra invertida no fim da string",
    a = 'local s = "a\\\\"\nlocal y = 1\n',
    b = 'local s = "a\\\\"\nlocal y = 2\n',
    esperado = "diferente",
  },
  {
    nome = "comentario no fim de linha de codigo",
    a = "local x = 1  -- pt\n",
    b = "local x = 1  -- en\n",
    esperado = "igual",
  },
  {
    nome = "codigo aparece DEPOIS de um comentario longo na mesma linha",
    a = "--[[ pt ]] local x = 1\n",
    b = "--[[ en ]] local x = 2\n",
    esperado = "diferente",
  },
  {
    nome = "linha nova inteira de codigo adicionada",
    a = "local x = 1\n",
    b = "local x = 1\nlocal y = 2\n",
    esperado = "diferente",
  },
  {
    nome = "comentario multilinha vira monolinha (numeracao muda)",
    a = "--[[ pt\n   segunda linha ]]\nlocal x = 1\n",
    b = "-- en\n--\nlocal x = 1\n",
    esperado = "igual",
  },
  {
    nome = "CRLF nos dois lados",
    a = "-- pt\r\nlocal x = 1\r\n",
    b = "-- en\r\nlocal x = 1\r\n",
    esperado = "igual",
  },
  {
    nome = "indentacao do codigo muda",
    a = "local t = {\n  x = 1,\n}\n",
    b = "local t = {\n      x = 1,\n}\n",
    esperado = "diferente",
  },
}

local ok, falhou = 0, 0
for _, c in ipairs(CASOS) do
  local obtido = compara(c.a, c.b)
  if obtido == c.esperado then
    ok = ok + 1
  else
    falhou = falhou + 1
    print(string.format("FALHOU  %s", c.nome))
    print(string.format("        esperado %s, obtido %s", c.esperado, obtido))
    -- A false PASS is the dangerous direction and is called out by name, so a
    -- summary line cannot make it look like any other failure.
    if c.esperado == "diferente" then
      print("        ESTE E O PERIGOSO: codigo mudou e o portao aprovou.")
    end
  end
end

print(string.format("\n%d/%d casos", ok, ok + falhou))
os.exit(falhou == 0 and 0 or 1)
