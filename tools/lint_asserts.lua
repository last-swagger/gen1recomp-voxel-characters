-- Acha CHECAGEM QUE NAO CHECA: chamada a um predicado cujo valor de retorno e
-- descartado.
--
-- POR QUE ISTO EXISTE. A suite tinha seis linhas assim:
--
--     close(pullEm(20, 6), 4, "a 20 unidades o pull cede para 4")
--
-- `close(a, b)` DEVOLVE um booleano; ele nao registra checagem nenhuma. A
-- mensagem era um terceiro argumento ignorado. As seis rodavam, passavam,
-- e nao contavam: o total pulou de 552 para 558 quando foram consertadas.
-- Nenhuma delas teria pego a mutacao que existiam para pegar.
--
-- E o pior da familia: elas LEEM como assercao. Quem revisa passa o olho e ve
-- uma checagem com mensagem. So contando o total dava para notar.
--
-- COMO DECIDE O QUE E PREDICADO, e por que nao por lista escrita na mao: uma
-- lista apodrece no proximo helper. A regra e estrutural. Um `local function`
-- que TEM `return` e NAO chama nenhuma funcao de assercao e um predicado: ele
-- devolve uma resposta em vez de registrar um veredito. Quem registra veredito
-- chama `check` ou `eq` la dentro, ou e `check`/`eq`.
--
-- Uso:
--   luajit mods/voxel_characters/tools/lint_asserts.lua [arquivo...]
-- Sem argumento, olha a suite. Sai diferente de zero quando acha alguma.

local ASSERTIVAS = { check = true, eq = true, fail = true }

local function lerLinhas(caminho)
  local f = assert(io.open(caminho, "r"), "nao consegui abrir " .. caminho)
  local linhas = {}
  for l in f:lines() do linhas[#linhas + 1] = l end
  f:close()
  return linhas
end

-- QUE FUNCAO E PREDICADO. A primeira versao desta regra dizia "tem return e
-- nao chama assercao", e isso marcou cinquenta funcoes, incluindo fabricas
-- como makeVoxelHandle e loadWith, que legitimamente sao chamadas pelo efeito
-- colateral. Regra larga demais nao e um linter, e ruido que ninguem le.
--
-- A regra apertada: TODO `return` da funcao devolve booleano. Ou seja uma
-- comparacao, um literal true/false, ou nada. Uma funcao assim so existe para
-- ser perguntada; descartar a resposta dela e sempre erro.
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

-- Uma chamada e DESCARTADA quando ela e a instrucao INTEIRA. Duas coisas
-- disfarcam disso e as duas apareceram na primeira corrida:
--
--   continuacao de expressao. `close(v[6], 0.90) or close(...)` comeca a linha
--   com o predicado, mas a linha anterior termina em `and (`, entao o valor
--   esta sendo consumido. Marcar isso e ruido, e ruido treina a pessoa a
--   ignorar o linter.
--
--   chamada usada como argumento. Ai a linha nao comeca com o nome.
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
  print(string.format("%d checagem(ns) que nao checam. Envolva em check(...).", total))
  os.exit(1)
end
print("nenhuma checagem descartada")
