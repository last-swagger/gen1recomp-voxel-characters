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
-- A CHOICE MAY CARRY A REASON, and this file does not read it. `reason=` is an
-- optional percent-encoded token the laboratory writes before the first `|`,
-- so it is invisible to every pattern here: it has no space, so `key=(%S+)`
-- stops before it; no pipe, so the A/B split is untouched; and no equals sign
-- of its own, so `estadoCanonico` cannot mistake it for part of a state. The
-- reason is for the calibration experiment that shows a critic a decided pair
-- together with why, not for the fit. tools/juiz/reason_gate.sh runs the real
-- --estados over the recorded choices with and without one and requires the
-- two outputs to be byte-identical.
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
  local f = assert(io.open(caminho, "r"), "could not open " .. caminho)
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
  local f = assert(io.open(caminho, "r"), "could not open " .. caminho)
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
  local melhor = { nome = "none", treino = 0, teste = 0 }
  for j = 1, #X[1] do
    for _, sinal in ipairs({ 1, -1 }) do
      local w = {}
      for k = 1, #X[1] do w[k] = 0 end
      w[j] = sinal
      local t = acerta(X, y, treinoIdx, w)
      if t > melhor.treino then
        melhor = { nome = (nomes and nomes[j] or ("col" .. j)) ..
                     (sinal < 0 and " (negative)" or ""),
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

-- CROSS VALIDATION, because one fifth of a hundred choices is nineteen, and
-- nineteen cannot tell 63% from 77%.
--
-- The single holdout above was the right call while the machinery was being
-- proved: it is deterministic and cheap. But once real choices arrived it
-- produced a curve that swung from 60% to 86% with nothing changing except
-- how many rows were in the file, and a number that moves 26 points on its own
-- cannot be used to decide anything.
--
-- Five folds test EVERY choice exactly once, so the estimate uses all 99
-- instead of 19. Still deterministic, same fold for the same file. The spread
-- ACROSS folds is reported too, because it is the honest error bar and the
-- thing that says whether two numbers differ at all.
--
-- The best single column is run through the identical folds. Comparing a
-- cross-validated model against a single-holdout baseline would be comparing
-- two different measurements and calling the difference a result.
local function foldsDe(n, k)
  local folds = {}
  for f = 1, k do folds[f] = { treino = {}, teste = {} } end
  for i = 1, n do
    local f = (i - 1) % k + 1
    for g = 1, k do
      if g == f then folds[g].teste[#folds[g].teste + 1] = i
      else folds[g].treino[#folds[g].treino + 1] = i end
    end
  end
  return folds
end

function M.validaCruzado(X, y, nomes, k)
  k = k or 5
  local n = #X
  if n < k * 4 then return nil end
  local somaM, somaC, porFold = 0, 0, {}
  local colunaVence = {}
  for _, fold in ipairs(foldsDe(n, k)) do
    local media, desvio = padroniza(X, fold.treino)
    local Z = {}
    for i = 1, n do Z[i] = aplica(X[i], media, desvio) end
    local w = treina(Z, y, fold.treino)
    local acM = acerta(Z, y, fold.teste, w)
    local base = melhorColuna(Z, y, fold.treino, fold.teste, nomes)
    somaM, somaC = somaM + acM, somaC + base.teste
    porFold[#porFold + 1] = acM
    colunaVence[base.nome] = (colunaVence[base.nome] or 0) + 1
  end
  local mediaM, mediaC = somaM / k, somaC / k
  local varM = 0
  for _, a in ipairs(porFold) do varM = varM + (a - mediaM) ^ 2 end
  local nomeColuna, vezes = "?", 0
  for nome, c in pairs(colunaVence) do
    if c > vezes then nomeColuna, vezes = nome, c end
  end
  return { modelo = mediaM, coluna = mediaC, folds = porFold,
           desvio = math.sqrt(varM / k), nomeColuna = nomeColuna,
           vezes = vezes, k = k, n = n }
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
  io.stderr:write(string.format("%d choices, %d unique variants\n",
    #escolhas, #saida))
end

local function comandoAjusta(caminhoEscolhas, caminhoFeatures)
  local escolhas, pulos = lerEscolhas(caminhoEscolhas)
  local nomes, mapa = lerFeatures(caminhoFeatures)
  if not nomes then print("features.tsv has no header"); os.exit(1) end

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

  print(string.format("choices used      %d", #X))
  local nCegas, listaCegas = 0, {}
  for k, v in pairs(cegas) do
    nCegas = nCegas + v
    listaCegas[#listaCegas + 1] = string.format("%s x%d", k, v)
  end
  if nCegas > 0 then
    table.sort(listaCegas)
    print(string.format("blind features    %d  (%s)", nCegas,
      table.concat(listaCegas, ", ")))
    print("                  the two sides differ on screen and NO feature")
    print("                  distinguishes them. This is what remains to measure.")
  end
  print(string.format("skips             %d  (\"I see no difference\")", pulos))
  if faltando > 0 then
    print(string.format("missing features  %d  (run the extractor again)", faltando))
  end
  if #X < 20 then
    print("")
    print("TOO LITTLE DATA. With fewer than 20 choices, the out-of-sample")
    print("number swings more than the difference it is supposed to measure.")
    print("The fit is printed below, but do not decide anything from it.")
  end
  if #X < 5 then return end

  local r = M.ajusta(X, y, nomes)
  print("")
  print(string.format("train %d, test %d (one in five, by order)",
    r.treino, r.teste))
  print("")
  print("weights, on the standardised scale (positive pulls toward side A):")
  local ordem = {}
  for j = 1, #r.w do ordem[j] = j end
  table.sort(ordem, function(a, b) return math.abs(r.w[a]) > math.abs(r.w[b]) end)
  for _, j in ipairs(ordem) do
    print(string.format("  %-14s %+7.3f", nomes[j] or ("col" .. j), r.w[j]))
  end
  print("")
  print(string.format("training accuracy           %.1f%%", r.acTreino * 100))
  print(string.format("out-of-sample accuracy      %.1f%%", r.acTeste * 100))
  print(string.format("best single column          %.1f%% out (%s)",
    r.base.teste * 100, r.base.nome))
  print("")

  -- THE VERDICT COMES FROM CROSS VALIDATION, not from the single holdout
  -- above, whenever there is enough data for it. The holdout stays printed
  -- because it is what the model file records and what earlier rounds
  -- reported, but it tests 19 choices and swings 26 points on its own, so it
  -- is not something to decide on.
  local cv = M.validaCruzado(X, y, nomes, 5)
  if not cv then
    if r.acTeste > r.base.teste then
      print("THE MODEL BEATS THE BEST COLUMN (single holdout, little data).")
    else
      print("THE MODEL DOES NOT BEAT A SINGLE COLUMN on the single holdout.")
    end
    return
  end

  local margem = (cv.modelo - cv.coluna) * 100
  print(string.format("CROSS VALIDATION, %d folds, %d choices tested:",
    cv.k, cv.n))
  local partes = {}
  for _, a in ipairs(cv.folds) do
    partes[#partes + 1] = string.format("%.0f%%", a * 100)
  end
  print(string.format("  model         %.1f%%  (by fold: %s)",
    cv.modelo * 100, table.concat(partes, " ")))
  print(string.format("  best column   %.1f%%  (%s, in %d of %d folds)",
    cv.coluna * 100, cv.nomeColuna, cv.vezes, cv.k))
  print(string.format("  margin        %+.1f points", margem))
  print(string.format("  spread across folds %.1f points", cv.desvio * 100))
  print("")

  -- A margin smaller than the spread across folds is not a margin. Saying so
  -- out loud is the whole point: this project has published a difference that
  -- was inside its own noise before.
  if margem > cv.desvio * 100 then
    print("THE MODEL BEATS THE BEST SINGLE COLUMN: it learned a")
    print("combination, not just the strongest feature.")
  elseif margem > 0 then
    print("THE MARGIN IS SMALLER THAN THE SPREAD ACROSS FOLDS. The model")
    print("is ahead, but not by enough to claim that it wins.")
  else
    print("THE MODEL DOES NOT BEAT A SINGLE COLUMN. This is not a judge yet.")
    print("Two causes point in opposite directions: either more choices are")
    print("needed, or the preference driver is not in this feature list.")
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
  local nomes = { "top", "art", "quads", "noise1", "noise2" }
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
  print("judge selftest, 200 synthetic choices")
  print("  generating rule: top -2.0, art +1.5, the rest zero")
  for j = 1, #nomes do
    print(string.format("    %-8s fitted weight %+7.3f", nomes[j], r.w[j]))
  end
  print(string.format("  out-of-sample accuracy %.1f%%, best column %.1f%%",
    r.acTeste * 100, r.base.teste * 100))
  local ok = r.w[1] < -0.3 and r.w[2] > 0.2
    and math.abs(r.w[4]) < math.abs(r.w[1])
    and math.abs(r.w[5]) < math.abs(r.w[1])
    and r.acTeste >= 0.8 and r.acTeste > r.base.teste
  print("")
  if ok then
    print("SELFTEST OK: the fit recovers the sign that matters, keeps")
    print("noise near zero, and beats the best single column.")
    os.exit(0)
  end
  print("SELFTEST FAILED: the machinery cannot recover a rule that exists.")
  print("Do not feed it real choices until it is fixed.")
  os.exit(1)
end

------------------------------------------------------------------ o gerador

-- THE MODEL GOES OUT TO A FILE, not just to the screen. Without this the fit
-- dies with every run and nothing can SCORE a new variant.
local function comandoPesos(caminhoEscolhas, caminhoFeatures, saida)
  local escolhas = lerEscolhas(caminhoEscolhas)
  local nomes, mapa = lerFeatures(caminhoFeatures)
  if not nomes then print("features.tsv has no header"); os.exit(1) end
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
  if #X < 5 then print("too few choices to export a model"); os.exit(1) end
  local r = M.ajusta(X, y, nomes)
  local f = assert(io.open(saida, "w"))
  f:write("# judge model, generated by ajusta.lua --pesos\n")
  f:write(string.format("# %d choices, out-of-sample accuracy %.3f, "
    .. "best column %.3f\n", #X, r.acTeste, r.base.teste))
  for j = 1, #r.w do
    f:write(string.format("%s\t%.8f\t%.8f\t%.8f\n",
      nomes[j], r.w[j], r.media[j], r.desvio[j]))
  end
  f:close()
  print(string.format("model in %s (%d choices, out-of-sample %.1f%%)",
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
  if not nomes then print("features.tsv has no header"); os.exit(1) end
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
  io.stderr:write(string.format("%d pairs from %d candidates, criterion: %s\n",
    n, #cand, modelo and "model uncertainty" or "greatest distance (no model)"))
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
  if not nomes then print("features.tsv has no header"); os.exit(1) end
  local modelo = lerModelo(assert(caminhoModelo, "missing modelo.txt"))
  if not modelo then print("could not read the model"); os.exit(1) end

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
  if #linhas == 0 then print("no candidates"); os.exit(1) end
  -- WITHIN A SHEET, AND HEAD TO HEAD. Two corrections, both of them cases of
  -- a number that reads like a finding and is not one.
  --
  -- Sorting every candidate together put `seel` with SLAB at the top and
  -- `lance` with CARVED at the bottom. Those are different CHARACTERS, and the
  -- model was never shown a comparison between two characters: every choice it
  -- learned from was two variants of the SAME sheet, which is how rodada.sh
  -- builds pairs. A score gap across sheets is extrapolation past everything
  -- it was taught.
  --
  -- Then counting how often a setting appears among winners made every key
  -- look like a tie, because the candidate space is mostly SLAB, so slab is
  -- the commonest value among winners AND among losers. The comparison has to
  -- happen INSIDE the pair, where the character and every other setting are
  -- held constant by construction.
  local porFolha = {}
  for _, l in ipairs(linhas) do
    porFolha[l.folha] = porFolha[l.folha] or {}
    table.insert(porFolha[l.folha], l)
  end
  local nomesFolha = {}
  for f in pairs(porFolha) do nomesFolha[#nomesFolha + 1] = f end
  table.sort(nomesFolha)

  local duelo, total, mostradas = {}, 0, 0
  local n = tonumber(quantos) or 5
  io.stderr:write("\n== BEST AND WORST WITHIN EACH SHEET\n")
  for _, f in ipairs(nomesFolha) do
    local lista = porFolha[f]
    table.sort(lista, function(a, b) return a.z > b.z end)
    if #lista >= 2 then
      total = total + 1
      local topo, fundo = lista[1], lista[#lista]
      if mostradas < n then
        io.stderr:write(string.format(
          "  %-16s best %+7.2f   worst %+7.2f   (%d variants)\n",
          f, topo.z, fundo.z, #lista))
        mostradas = mostradas + 1
      end
      local vt, vf = {}, {}
      for k, v in topo.estado:gmatch("([%w_]+):([^,]+)") do vt[k] = v end
      for k, v in fundo.estado:gmatch("([%w_]+):([^,]+)") do vf[k] = v end
      for k, v in pairs(vt) do
        if vf[k] and vf[k] ~= v then
          duelo[k] = duelo[k] or {}
          local par = v .. " > " .. vf[k]
          duelo[k][par] = (duelo[k][par] or 0) + 1
        end
      end
      print(f .. "\t" .. topo.frame .. "\t" .. topo.clock .. "\t"
            .. topo.estado .. "\t" .. string.format("%.6f", topo.z))
    end
  end

  local chaves = {}
  for k in pairs(duelo) do chaves[#chaves + 1] = k end
  table.sort(chaves)
  io.stderr:write(string.format(
    "\n== HEAD TO HEAD: best against worst, across %d sheets\n\n", total))
  if #chaves == 0 then
    io.stderr:write("  the best and worst never differ in only one option\n")
  end
  for _, k in ipairs(chaves) do
    local pares = {}
    for par, c in pairs(duelo[k]) do pares[#pares + 1] = { par = par, c = c } end
    table.sort(pares, function(a, b) return a.c > b.c end)
    for i = 1, math.min(2, #pares) do
      io.stderr:write(string.format("  %-14s %-26s %2d sheets\n",
        i == 1 and k or "", pares[i].par, pares[i].c))
    end
  end
end

local cmd = arg and arg[1]
if cmd == "--ranking" then
  comandoRanking(assert(arg[2], "missing features.tsv"), arg[3], arg[4])
elseif cmd == "--estados" then comandoEstados(assert(arg[2], "missing escolhas.txt"))
elseif cmd == "--ajusta" then
  comandoAjusta(assert(arg[2], "missing escolhas.txt"),
                assert(arg[3], "missing features.tsv"))
elseif cmd == "--autoteste" then comandoAutoteste()
elseif cmd == "--pesos" then
  comandoPesos(assert(arg[2]), assert(arg[3]), arg[4] or "modelo.txt")
elseif cmd == "--pares" then
  comandoPares(assert(arg[2]), arg[3], arg[4])
else
  print("usage: ajusta.lua --estados <escolhas.txt>")
  print("     ajusta.lua --ajusta <escolhas.txt> <features.tsv>")
  print("     ajusta.lua --autoteste")
  os.exit(1)
end
