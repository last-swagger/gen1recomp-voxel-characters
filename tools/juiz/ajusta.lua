-- O JUIZ: transforma as escolhas do Kim num modelo que ordena variantes.
--
-- POR QUE ELE PRECISA EXISTIR. Este projeto mediu, e nao supos, que um
-- redesenho por IA satisfaz TODA restricao numerica que a gente tem e ainda
-- entrega arte pior. Entao nenhum gerador pode ser treinado contra as reguas
-- que a gente ja possui: falta uma regua nova, e a unica fonte dela e alguem
-- escolhendo entre dois.
--
-- O QUE ELE E. Regressao logistica sobre a DIFERENCA de features entre os dois
-- lados de cada par, que e a forma Bradley-Terry escrita do jeito mais simples
-- possivel. Com dezenas de escolhas, um modelo linear sobre uma duzia de
-- colunas e a capacidade certa; rede neural com cem exemplos decora.
--
-- O GATE QUE DECIDE SE ELE E JUIZ OU ENFEITE. Vinte por cento das escolhas
-- ficam de fora do ajuste, e o modelo tem que acertar essas melhor do que a
-- MELHOR COLUNA SOZINHA. Se nao ganha de uma coluna, ele nao aprendeu nada,
-- so decorou as features que eu escolhi. Este numero e a coisa mais importante
-- que este arquivo imprime.
--
-- Uso:
--   luajit ajusta.lua --estados <escolhas.txt>            lista as variantes
--   luajit ajusta.lua --ajusta <escolhas.txt> <features.tsv>
--   luajit ajusta.lua --autoteste                         prova a maquinaria

local M = {}

------------------------------------------------------------------ util

local function dividir(s, sep)
  local out = {}
  for p in tostring(s):gmatch("[^" .. sep .. "]+") do out[#out + 1] = p end
  return out
end

-- "depth=3 side_color=body" vira "depth:3,side_color:body", que e o formato
-- que o extrator de features aceita. Chave ordenada, para o mesmo estado
-- produzir sempre a mesma string e a deduplicacao funcionar.
local function estadoCanonico(texto)
  local pares = {}
  for k, v in tostring(texto):gmatch("([%w_]+)=([^%s]+)") do
    pares[#pares + 1] = { k = k, v = v }
  end
  table.sort(pares, function(a, b) return a.k < b.k end)
  local partes = {}
  for _, p in ipairs(pares) do partes[#partes + 1] = p.k .. ":" .. p.v end
  return table.concat(partes, ",")
end

local function lerEscolhas(caminho)
  local f = assert(io.open(caminho, "r"), "nao consegui abrir " .. caminho)
  local escolhas, pulos = {}, 0
  for linha in f:lines() do
    local folha = linha:match("folha=(%S+)")
    local escolha = linha:match("escolha=(%S+)")
    local opcao = linha:match("opcao=(%S+)")
    local a, b = linha:match("|%s*A:%s*(.-)%s*|%s*B:%s*(.*)$")
    if folha and escolha and a and b then
      if escolha == "pulo" then
        pulos = pulos + 1
      elseif escolha == "A" or escolha == "B" then
        escolhas[#escolhas + 1] = {
          folha = folha, opcao = opcao, escolha = escolha,
          frame = linha:match("frame=(%d+)") or "0",
          clock = linha:match("clock=([%d%.]+)") or "0",
          a = estadoCanonico(a), b = estadoCanonico(b),
        }
      end
    end
  end
  f:close()
  return escolhas, pulos
end

local function lerFeatures(caminho)
  local f = assert(io.open(caminho, "r"), "nao consegui abrir " .. caminho)
  local nomes, mapa = nil, {}
  for linha in f:lines() do
    local campos = {}
    for c in (linha .. "\t"):gmatch("(.-)\t") do campos[#campos + 1] = c end
    -- Quatro colunas de identidade (folha, quadro, relogio, estado) e o resto
    -- e feature. O relogio e o quadro entram na CHAVE porque a mesma variante
    -- medida noutro instante e outra medicao, e foi confundir as duas que fez
    -- pares de BLINK sairem com diferenca zero.
    local ID = 4
    if linha:sub(1, 1) == "#" then
      nomes = {}
      for i = ID + 1, #campos do nomes[#nomes + 1] = campos[i] end
    elseif nomes and #campos > ID then
      local v = {}
      for i = ID + 1, #campos do v[#v + 1] = tonumber(campos[i]) or 0 end
      mapa[table.concat({ campos[1], campos[2], campos[3], campos[4] }, "\t")] = v
    end
  end
  f:close()
  return nomes, mapa
end

------------------------------------------------------------------ modelo

-- z-score por coluna, calculado SO no treino. Padronizar usando o conjunto
-- inteiro vazaria informacao do teste para dentro do ajuste, e a acuracia
-- fora da amostra deixaria de significar o que ela promete.
local function padroniza(X, indices)
  local d = #X[1]
  local media, desvio = {}, {}
  for j = 1, d do
    local s, n = 0, 0
    for _, i in ipairs(indices) do s = s + X[i][j]; n = n + 1 end
    media[j] = n > 0 and s / n or 0
    local v = 0
    for _, i in ipairs(indices) do
      local e = X[i][j] - media[j]; v = v + e * e
    end
    desvio[j] = n > 0 and math.sqrt(v / n) or 0
    if desvio[j] < 1e-9 then desvio[j] = 1 end
  end
  return media, desvio
end

local function aplica(x, media, desvio)
  local out = {}
  for j = 1, #x do out[j] = (x[j] - media[j]) / desvio[j] end
  return out
end

local function sigmoide(z)
  if z >= 0 then return 1 / (1 + math.exp(-z)) end
  local e = math.exp(z)
  return e / (1 + e)
end

local function treina(X, y, indices, passos, taxa, l2)
  local d = #X[1]
  local w = {}
  for j = 1, d do w[j] = 0 end
  for _ = 1, (passos or 4000) do
    local g = {}
    for j = 1, d do g[j] = 0 end
    for _, i in ipairs(indices) do
      local z = 0
      for j = 1, d do z = z + w[j] * X[i][j] end
      local err = sigmoide(z) - y[i]
      for j = 1, d do g[j] = g[j] + err * X[i][j] end
    end
    local n = math.max(1, #indices)
    for j = 1, d do
      w[j] = w[j] - (taxa or 0.3) * (g[j] / n + (l2 or 0.01) * w[j])
    end
  end
  return w
end

local function acerta(X, y, indices, w)
  local ok = 0
  for _, i in ipairs(indices) do
    local z = 0
    for j = 1, #w do z = z + w[j] * X[i][j] end
    local prev = z >= 0 and 1 or 0
    if prev == y[i] then ok = ok + 1 end
  end
  return #indices > 0 and ok / #indices or 0
end

-- O ADVERSARIO: cada coluna sozinha, com o sinal escolhido NO TREINO. Bater
-- isso e o minimo para o modelo ter aprendido alguma combinacao em vez de so
-- reproduzir a coluna mais forte.
local function melhorColuna(X, y, treinoIdx, testeIdx, nomes)
  local melhor = { nome = "nenhuma", treino = 0, teste = 0 }
  for j = 1, #X[1] do
    for _, sinal in ipairs({ 1, -1 }) do
      local w = {}
      for k = 1, #X[1] do w[k] = 0 end
      w[j] = sinal
      local t = acerta(X, y, treinoIdx, w)
      if t > melhor.treino then
        melhor = { nome = (nomes and nomes[j] or ("col" .. j)) ..
                     (sinal < 0 and " (negativa)" or ""),
                   treino = t, teste = acerta(X, y, testeIdx, w) }
      end
    end
  end
  return melhor
end

-- Divisao deterministica: um em cada cinco vai para o teste, pela ORDEM em
-- que a escolha foi feita. Sem sorteio de proposito, para o numero impresso
-- ser o mesmo em duas execucoes e uma piora nao poder ser confundida com azar.
local function divide(n)
  local treino, teste = {}, {}
  for i = 1, n do
    if i % 5 == 0 then teste[#teste + 1] = i else treino[#treino + 1] = i end
  end
  return treino, teste
end

function M.ajusta(X, y, nomes)
  local n = #X
  local treinoIdx, testeIdx = divide(n)
  local media, desvio = padroniza(X, treinoIdx)
  local Z = {}
  for i = 1, n do Z[i] = aplica(X[i], media, desvio) end
  local w = treina(Z, y, treinoIdx)
  local base = melhorColuna(Z, y, treinoIdx, testeIdx, nomes)
  return {
    n = n, treino = #treinoIdx, teste = #testeIdx,
    w = w, media = media, desvio = desvio,
    acTreino = acerta(Z, y, treinoIdx, w),
    acTeste = acerta(Z, y, testeIdx, w),
    base = base,
  }
end

------------------------------------------------------------------ comandos

local function comandoEstados(caminho)
  local escolhas = lerEscolhas(caminho)
  local vistos, saida = {}, {}
  for _, e in ipairs(escolhas) do
    local pre = e.folha .. "\t" .. e.frame .. "\t" .. e.clock .. "\t"
    for _, chave in ipairs({ pre .. e.a, pre .. e.b }) do
      if not vistos[chave] then
        vistos[chave] = true
        saida[#saida + 1] = chave
      end
    end
  end
  for _, l in ipairs(saida) do print(l) end
  io.stderr:write(string.format("%d escolhas, %d variantes unicas\n",
    #escolhas, #saida))
end

local function comandoAjusta(caminhoEscolhas, caminhoFeatures)
  local escolhas, pulos = lerEscolhas(caminhoEscolhas)
  local nomes, mapa = lerFeatures(caminhoFeatures)
  if not nomes then print("features.tsv sem cabecalho"); os.exit(1) end

  local X, y, faltando, cegas = {}, {}, 0, {}
  for _, e in ipairs(escolhas) do
    local pre = e.folha .. "\t" .. e.frame .. "\t" .. e.clock .. "\t"
    local fa, fb = mapa[pre .. e.a], mapa[pre .. e.b]
    if fa and fb then
      local dif, zero = {}, true
      for j = 1, #fa do
        dif[j] = fa[j] - fb[j]
        if math.abs(dif[j]) > 1e-9 then zero = false end
      end
      -- DIFERENCA ZERO NAO E UMA ESCOLHA, E UM BURACO NA LISTA DE FEATURES.
      --
      -- Os dois lados existem e sao visivelmente diferentes na tela, senao o
      -- laboratorio nao teria oferecido o par. Se as features nao distinguem,
      -- e porque nenhuma delas enxerga o que mudou. Deixar a linha entrar no
      -- ajuste seria pior que descartar: com dif = 0 o modelo pontua z = 0,
      -- preve sempre "A", acerta toda escolha A e erra toda B, e isso vai para
      -- o denominador da acuracia como se fosse informacao.
      --
      -- Entao a linha sai do ajuste E e reportada por opcao, porque a lista
      -- delas e a resposta mais util que este arquivo produz: e a lista do que
      -- falta medir.
      if zero then
        cegas[e.opcao or "?"] = (cegas[e.opcao or "?"] or 0) + 1
      else
        X[#X + 1] = dif
        y[#y + 1] = (e.escolha == "A") and 1 or 0
      end
    else
      faltando = faltando + 1
    end
  end

  print(string.format("escolhas usadas   %d", #X))
  local nCegas, listaCegas = 0, {}
  for k, v in pairs(cegas) do
    nCegas = nCegas + v
    listaCegas[#listaCegas + 1] = string.format("%s x%d", k, v)
  end
  if nCegas > 0 then
    table.sort(listaCegas)
    print(string.format("features cegas    %d  (%s)", nCegas,
      table.concat(listaCegas, ", ")))
    print("                  os dois lados diferem na tela e NENHUMA feature")
    print("                  distingue. Esta e a lista do que falta medir.")
  end
  print(string.format("pulos             %d  (\"nao vejo diferenca\")", pulos))
  if faltando > 0 then
    print(string.format("sem features      %d  (rode o extrator de novo)", faltando))
  end
  if #X < 20 then
    print("")
    print("POUCO DADO. Com menos de 20 escolhas o numero fora da amostra")
    print("oscila mais do que a diferenca que ele deveria medir. O ajuste sai")
    print("abaixo, mas nao decida nada com ele.")
  end
  if #X < 5 then return end

  local r = M.ajusta(X, y, nomes)
  print("")
  print(string.format("treino %d, teste %d (um em cada cinco, pela ordem)",
    r.treino, r.teste))
  print("")
  print("pesos, na escala padronizada (positivo puxa para o lado A):")
  local ordem = {}
  for j = 1, #r.w do ordem[j] = j end
  table.sort(ordem, function(a, b) return math.abs(r.w[a]) > math.abs(r.w[b]) end)
  for _, j in ipairs(ordem) do
    print(string.format("  %-14s %+7.3f", nomes[j] or ("col" .. j), r.w[j]))
  end
  print("")
  print(string.format("acuracia no treino          %.1f%%", r.acTreino * 100))
  print(string.format("acuracia FORA da amostra    %.1f%%", r.acTeste * 100))
  print(string.format("melhor coluna sozinha       %.1f%% fora (%s)",
    r.base.teste * 100, r.base.nome))
  print("")
  if r.acTeste > r.base.teste then
    print("O MODELO GANHA DA MELHOR COLUNA SOZINHA: ele aprendeu uma")
    print("combinacao, e nao so a feature mais forte.")
  else
    print("O MODELO NAO GANHA DE UMA COLUNA SOZINHA. Isso nao e juiz ainda.")
    print("Duas causas, e elas pedem coisas opostas: ou faltam escolhas, ou o")
    print("que decide a preferencia nao esta em nenhuma feature desta lista.")
  end
end

-- A MAQUINARIA PROVADA ANTES DE GASTAR O TEMPO DO KIM.
--
-- Trinta escolhas humanas sao caras. Se o ajuste tiver um defeito, o custo
-- aparece depois delas. Entao o autoteste gera escolhas SINTETICAS a partir de
-- uma regra conhecida e confere que o modelo a recupera. Se ele nao recupera
-- uma regra que existe de verdade, nao adianta alimenta-lo com dado real.
local function comandoAutoteste()
  math.randomseed(20260809)
  local nomes = { "topo", "arte", "quads", "ruido1", "ruido2" }
  -- A regra: quem tem MENOS topo e MAIS arte ganha. Os outros tres nao contam.
  local verdade = { -2.0, 1.5, 0, 0, 0 }
  local X, y = {}, {}
  for _ = 1, 200 do
    local dif = {}
    for j = 1, #nomes do dif[j] = (math.random() - 0.5) * 2 end
    local z = 0
    for j = 1, #nomes do z = z + verdade[j] * dif[j] end
    X[#X + 1] = dif
    y[#y + 1] = (z + (math.random() - 0.5) * 0.4) > 0 and 1 or 0
  end
  local r = M.ajusta(X, y, nomes)
  print("autoteste do juiz, 200 escolhas sinteticas")
  print("  regra usada para gerar: topo -2.0, arte +1.5, o resto zero")
  for j = 1, #nomes do
    print(string.format("    %-8s peso ajustado %+7.3f", nomes[j], r.w[j]))
  end
  print(string.format("  acuracia fora da amostra %.1f%%, melhor coluna %.1f%%",
    r.acTeste * 100, r.base.teste * 100))
  local ok = r.w[1] < -0.3 and r.w[2] > 0.2
    and math.abs(r.w[4]) < math.abs(r.w[1])
    and math.abs(r.w[5]) < math.abs(r.w[1])
    and r.acTeste >= 0.8 and r.acTeste > r.base.teste
  print("")
  if ok then
    print("AUTOTESTE OK: o ajuste recupera o sinal de quem manda, deixa o")
    print("ruido perto de zero, e ganha da melhor coluna sozinha.")
    os.exit(0)
  end
  print("AUTOTESTE FALHOU: a maquinaria nao recupera nem uma regra que existe.")
  print("Nao alimente com escolhas de verdade ate consertar.")
  os.exit(1)
end

------------------------------------------------------------------ o gerador

-- O MODELO SAI EM ARQUIVO, e nao so na tela. Sem isso o ajuste morre a cada
-- execucao e nada consegue PONTUAR uma variante nova.
local function comandoPesos(caminhoEscolhas, caminhoFeatures, saida)
  local escolhas = lerEscolhas(caminhoEscolhas)
  local nomes, mapa = lerFeatures(caminhoFeatures)
  if not nomes then print("features.tsv sem cabecalho"); os.exit(1) end
  local X, y = {}, {}
  for _, e in ipairs(escolhas) do
    local pre = e.folha .. "\t" .. e.frame .. "\t" .. e.clock .. "\t"
    local fa, fb = mapa[pre .. e.a], mapa[pre .. e.b]
    if fa and fb then
      local dif, zero = {}, true
      for j = 1, #fa do
        dif[j] = fa[j] - fb[j]
        if math.abs(dif[j]) > 1e-9 then zero = false end
      end
      if not zero then
        X[#X + 1] = dif
        y[#y + 1] = (e.escolha == "A") and 1 or 0
      end
    end
  end
  if #X < 5 then print("poucas escolhas para exportar modelo"); os.exit(1) end
  local r = M.ajusta(X, y, nomes)
  local f = assert(io.open(saida, "w"))
  f:write("# modelo do juiz, gerado por ajusta.lua --pesos\n")
  f:write(string.format("# %d escolhas, acuracia fora da amostra %.3f, "
    .. "melhor coluna %.3f\n", #X, r.acTeste, r.base.teste))
  for j = 1, #r.w do
    f:write(string.format("%s\t%.8f\t%.8f\t%.8f\n",
      nomes[j], r.w[j], r.media[j], r.desvio[j]))
  end
  f:close()
  print(string.format("modelo em %s (%d escolhas, fora da amostra %.1f%%)",
    saida, #X, r.acTeste * 100))
end

local function lerModelo(caminho)
  local f = io.open(caminho, "r")
  if not f then return nil end
  local nomes, w, media, desvio = {}, {}, {}, {}
  for linha in f:lines() do
    if linha:sub(1, 1) ~= "#" then
      local n, a, b, c = linha:match("^(%S+)\t(%S+)\t(%S+)\t(%S+)$")
      if n then
        nomes[#nomes + 1] = n
        w[#w + 1] = tonumber(a) or 0
        media[#media + 1] = tonumber(b) or 0
        desvio[#desvio + 1] = tonumber(c) or 1
      end
    end
  end
  f:close()
  return (#nomes > 0) and { nomes = nomes, w = w, media = media,
                            desvio = desvio } or nil
end

-- OS PARES QUE MAIS ENSINAM, e nao os que o sorteio entregar.
--
-- Trinta escolhas do Kim sao o insumo caro deste projeto. Sorteadas, boa parte
-- cai em pares que o modelo ja acerta de olhos fechados e que portanto nao
-- movem nenhum peso. Pedir justamente os pares em que o modelo esta EM CIMA DO
-- MURO faz cada escolha valer varias, e e o unico jeito de trinta escolhas
-- virarem um modelo em vez de ruido.
--
-- Sem modelo ainda (a primeira rodada), a ordem e por MAIOR distancia de
-- feature: pares obviamente diferentes primeiro, que e o que se quer para
-- comecar a separar as colunas.
local function comandoPares(caminhoFeatures, caminhoModelo, quantos)
  local nomes, mapa = lerFeatures(caminhoFeatures)
  if not nomes then print("features.tsv sem cabecalho"); os.exit(1) end
  local modelo = caminhoModelo and lerModelo(caminhoModelo) or nil

  -- Agrupa por (folha, quadro, relogio): so faz sentido comparar variantes da
  -- mesma folha na mesma condicao.
  local grupos = {}
  for chave, v in pairs(mapa) do
    local folha, qf, qt, estado = chave:match("^(.-)\t(.-)\t(.-)\t(.*)$")
    local g = folha .. "\t" .. qf .. "\t" .. qt
    grupos[g] = grupos[g] or {}
    grupos[g][#grupos[g] + 1] = { estado = estado, v = v }
  end

  local cand = {}
  for g, lista in pairs(grupos) do
    for i = 1, #lista do
      for j = i + 1, #lista do
        local dif, zero = {}, true
        for k = 1, #lista[i].v do
          dif[k] = lista[i].v[k] - lista[j].v[k]
          if math.abs(dif[k]) > 1e-9 then zero = false end
        end
        if not zero then
          local score
          if modelo then
            local z = 0
            for k = 1, math.min(#dif, #modelo.w) do
              z = z + modelo.w[k] * (dif[k] / (modelo.desvio[k] ~= 0
                and modelo.desvio[k] or 1))
            end
            score = math.abs(z)          -- menor = mais em cima do muro
          else
            local d = 0
            for k = 1, #dif do d = d + dif[k] * dif[k] end
            score = -math.sqrt(d)        -- maior distancia primeiro
          end
          cand[#cand + 1] = { g = g, a = lista[i].estado, b = lista[j].estado,
                              score = score }
        end
      end
    end
  end
  table.sort(cand, function(x, y) return x.score < y.score end)
  local n = math.min(tonumber(quantos) or 30, #cand)
  for i = 1, n do
    local c = cand[i]
    print(c.g .. "\t" .. c.a .. "\t" .. c.b)
  end
  io.stderr:write(string.format("%d pares de %d candidatos, criterio: %s\n",
    n, #cand, modelo and "incerteza do modelo" or "maior distancia (sem modelo)"))
end

local cmd = arg and arg[1]
if cmd == "--estados" then comandoEstados(assert(arg[2], "falta o escolhas.txt"))
elseif cmd == "--ajusta" then
  comandoAjusta(assert(arg[2], "falta o escolhas.txt"),
                assert(arg[3], "falta o features.tsv"))
elseif cmd == "--autoteste" then comandoAutoteste()
elseif cmd == "--pesos" then
  comandoPesos(assert(arg[2]), assert(arg[3]), arg[4] or "modelo.txt")
elseif cmd == "--pares" then
  comandoPares(assert(arg[2]), arg[3], arg[4])
else
  print("uso: ajusta.lua --estados <escolhas.txt>")
  print("     ajusta.lua --ajusta <escolhas.txt> <features.tsv>")
  print("     ajusta.lua --autoteste")
  os.exit(1)
end
