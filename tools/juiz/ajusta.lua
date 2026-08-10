-- THE JUDGE: turns Kim's choices into a model that ranks variants.
--
-- WHY IT HAS TO EXIST. This project measured, and did not assume, that an AI
-- redraw satisfies EVERY numeric constraint we have and still delivers worse
-- art. So no generator can be trained against the rulers we already have:
-- what is missing is a new ruler, and its only source is someone choosing
-- between two.
--
-- WHAT IT IS. Logistic regression over the feature DIFFERENCE between the two
-- sides of each pair, which is the Bradley-Terry form written the simplest
-- way possible. With dozens of choices, a linear model over a dozen columns
-- is the right capacity; a neural network with a hundred examples memorises.
--
-- THE GATE THAT DECIDES WHETHER IT IS A JUDGE OR DECORATION. Twenty percent
-- of the choices are held out of the fit, and the model has to get those
-- right better than the BEST SINGLE COLUMN. If it does not beat one column,
-- it learned nothing, it just memorised the features I chose. This number is
-- the most important thing this file prints.
--
-- Usage:
--   luajit ajusta.lua --estados <escolhas.txt>            lists the variants
--   luajit ajusta.lua --ajusta <escolhas.txt> <features.tsv>
--   luajit ajusta.lua --autoteste                         proves the machinery

local M = {}

------------------------------------------------------------------ util

local function dividir(s, sep)
  local out = {}
  for p in tostring(s):gmatch("[^" .. sep .. "]+") do out[#out + 1] = p end
  return out
end

-- "depth=3 side_color=body" becomes "depth:3,side_color:body", which is the
-- format the feature extractor accepts. Sorted by key, so the same state
-- always produces the same string and deduplication works.
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
    -- Four identity columns (sheet, frame, clock, state) and the rest is
    -- feature. The clock and the frame enter the KEY because the same
    -- variant measured at a different instant is a different measurement,
    -- and it was confusing the two that made BLINK pairs come out with zero
    -- difference.
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

-- z-score per column, calculated ONLY on the training set. Standardising
-- using the whole set would leak test information into the fit, and the
-- out-of-sample accuracy would stop meaning what it promises.
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

-- THE OPPONENT: each column alone, with the sign chosen ON THE TRAINING SET.
-- Beating this is the minimum for the model to have learned some combination
-- instead of just reproducing the strongest column.
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

-- Deterministic split: one in every five goes to the test set, by the ORDER
-- in which the choice was made. No randomness on purpose, so the printed
-- number is the same across two runs and a regression cannot be mistaken for
-- bad luck.
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
      -- ZERO DIFFERENCE IS NOT A CHOICE, IT IS A HOLE IN THE FEATURE LIST.
      --
      -- The two sides exist and are visibly different on screen, otherwise
      -- the laboratory would not have offered the pair. If the features do
      -- not distinguish them, it is because none of them sees what changed.
      -- Letting the line into the fit would be worse than discarding it: with
      -- dif = 0 the model scores z = 0, always predicts "A", gets every A
      -- choice right and every B choice wrong, and that goes into the
      -- accuracy's denominator as if it were information.
      --
      -- So the line drops out of the fit AND gets reported by option, because
      -- the list of them is the most useful answer this file produces: it is
      -- the list of what is left to measure.
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

-- THE MACHINERY PROVEN BEFORE SPENDING KIM'S TIME.
--
-- Thirty human choices are expensive. If the fit has a defect, the cost
-- shows up after them. So the selftest generates SYNTHETIC choices from a
-- known rule and checks that the model recovers it. If it cannot recover a
-- rule that is really there, there is no point feeding it real data.
local function comandoAutoteste()
  math.randomseed(20260809)
  local nomes = { "topo", "arte", "quads", "ruido1", "ruido2" }
  -- The rule: whoever has LESS top and MORE art wins. The other three do not count.
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

-- THE MODEL GOES OUT TO A FILE, not just to the screen. Without this the fit
-- dies with every run and nothing can SCORE a new variant.
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

-- THE PAIRS THAT TEACH THE MOST, and not the ones the roll delivers.
--
-- Thirty of Kim's choices are this project's expensive input. Rolled, a good
-- share land on pairs the model already gets right with its eyes closed and
-- that therefore move no weight. Asking specifically for the pairs where the
-- model is ON THE FENCE makes each choice worth several, and it is the only
-- way for thirty choices to turn into a model instead of noise.
--
-- With no model yet (the first round), the order is by GREATEST feature
-- distance: obviously different pairs first, which is what you want to start
-- separating the columns.
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
            score = math.abs(z)          -- smaller = more on the fence
          else
            local d = 0
            for k = 1, #dif do d = d + dif[k] * dif[k] end
            score = -math.sqrt(d)        -- greatest distance first
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

-- RANKING: what the model would choose, given a space of candidates.
--
-- This is the point of the whole thing. Everything before it collects and
-- fits; this is where the model finally does something a person would
-- otherwise have to do by hand, which is to look at hundreds of variants and
-- say which ones are worth looking at.
--
-- The score is the same linear form the fit produced, applied to one variant
-- instead of to a difference between two: sum of weight times the
-- standardised feature. Higher means the model expects Kim to prefer it.
--
-- IT PRINTS BOTH ENDS ON PURPOSE. The top alone is not evidence of anything:
-- if the model learned nothing, its top ten and its bottom ten look equally
-- arbitrary and equally plausible. Seeing them side by side is what makes the
-- question answerable by eye, and a model whose worst ten look fine is a
-- model that is not working, whatever its holdout number says.
local function comandoRanking(caminhoFeatures, caminhoModelo, quantos)
  local nomes, mapa = lerFeatures(caminhoFeatures)
  if not nomes then print("features.tsv sem cabecalho"); os.exit(1) end
  local modelo = lerModelo(assert(caminhoModelo, "falta o modelo.txt"))
  if not modelo then print("nao consegui ler o modelo"); os.exit(1) end

  local linhas = {}
  for chave, v in pairs(mapa) do
    local folha, qf, qt, estado = chave:match("^(.-)\t(.-)\t(.-)\t(.*)$")
    local z = 0
    for k = 1, math.min(#v, #modelo.w) do
      local d = modelo.desvio[k] ~= 0 and modelo.desvio[k] or 1
      z = z + modelo.w[k] * ((v[k] - modelo.media[k]) / d)
    end
    linhas[#linhas + 1] = { folha = folha, frame = qf, clock = qt,
                            estado = estado, z = z }
  end
  if #linhas == 0 then print("nenhum candidato"); os.exit(1) end
  table.sort(linhas, function(a, b) return a.z > b.z end)

  local n = math.min(tonumber(quantos) or 10, math.floor(#linhas / 2))
  local function bloco(rotulo, de, ate, passo)
    io.stderr:write("\n== " .. rotulo .. "\n")
    for i = de, ate, passo do
      local l = linhas[i]
      io.stderr:write(string.format("  %+7.3f  %-16s %s\n", l.z, l.folha,
        l.estado:gsub("blink:on,breath:0.01,first_person:card,footfall:off,lag:off,sway:off,", "")))
      print(l.folha .. "\t" .. l.frame .. "\t" .. l.clock .. "\t" .. l.estado
            .. "\t" .. string.format("%.6f", l.z))
    end
  end
  bloco("O QUE O MODELO ACHA QUE VOCE PREFERE", 1, n, 1)
  bloco("O QUE ELE ACHA QUE VOCE REJEITA", #linhas, #linhas - n + 1, -1)
  io.stderr:write(string.format("\n%d candidatos, faixa de score %.3f a %.3f\n",
    #linhas, linhas[#linhas].z, linhas[1].z))
end

local cmd = arg and arg[1]
if cmd == "--ranking" then
  comandoRanking(assert(arg[2], "falta o features.tsv"), arg[3], arg[4])
elseif cmd == "--estados" then comandoEstados(assert(arg[2], "falta o escolhas.txt"))
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
