-- Does the durable execution state carry what the roadmap says it must?
--
--   luajit mods/voxel_characters/tools/execution_state_gate.lua
--
-- From the REPO ROOT, like every other gate here.
--
-- WHY THIS EXISTS. Roadmap T0.3 exists so a long autonomous run stays
-- recoverable across context compaction, a failed command, a remote machine and
-- a handoff. That only works if the state file actually holds the things a cold
-- session needs, and the first time this gate ran it found the V3 section
-- missing "Blocked on Kim": the one section the roadmap says agents are not
-- allowed to work around. Nobody noticed by reading, because the V2 history
-- below it has a "Blocked on Kim" table and the eye finds it there.
--
-- WHY IT READS THE ROADMAP INSTEAD OF A LIST. The required sections are
-- written down in `ROADMAP_V3.md` section 9.7. Copying them into this file
-- would create a second copy of the contract, and the second copy is the one
-- that goes stale: this repository already has that defect on record in the
-- life-safety ceiling test, which hand-copies maxima instead of reading the
-- mod's own table. So this parses 9.7 and demands whatever it finds there. Add
-- a required section to the roadmap and this gate starts requiring it, with no
-- edit here.
--
-- WHAT IT CHECKS, and deliberately nothing more. Presence and shape, never
-- prose quality:
--
--   1. every section 9.7 names exists as a heading in the LIVE part of the
--      state file (the V3 part, not the V2 history);
--   2. the live part comes before the history, so a cold session reads the
--      current state first;
--   3. the Current state block carries a date, because a measured block with
--      no date cannot be told from a stale one;
--   4. every workstream row has an owner, a state and evidence, and the
--      evidence is not the word "done" (the roadmap says evidence is a commit
--      or a measurement, never "done").
--
-- It is kept structural on purpose. A gate that fires on a legitimate edit gets
-- waived by the second day, and then it is not there at all.

package.path = "./?.lua;./?/init.lua;" .. package.path

local ROADMAP = "mods/voxel_characters/docs/ROADMAP_V3.md"
local ESTADO = "mods/voxel_characters/docs/EXECUTION_STATE.md"

local function lines(path)
  local f = io.open(path, "r")
  if not f then
    io.stderr:write("cannot read " .. path .. "\n")
    os.exit(1)
  end
  local out = {}
  for l in f:lines() do out[#out + 1] = l end
  f:close()
  return out
end

--------------------------------------------------------------------------
-- The contract, read from the roadmap
--------------------------------------------------------------------------
local function requiredSections()
  local src = lines(ROADMAP)
  local dentro, nomes = false, {}
  for _, l in ipairs(src) do
    if l:match("^###%s+9%.7") then
      dentro = true
    elseif dentro and l:match("^###%s") then
      break
    elseif dentro then
      -- "- **Blocked on Kim**, mirroring ..." gives "Blocked on Kim"
      local nome = l:match("^%-%s+%*%*(.-)%*%*")
      if nome then nomes[#nomes + 1] = nome end
    end
  end
  return nomes
end

--------------------------------------------------------------------------
-- The live part of the state file
--------------------------------------------------------------------------
-- Bounded by the two H1 headings. Everything below the V2 one is history and
-- does not count: a required section satisfied only by the historical record
-- would be exactly the false pass this gate was written after.
local function liveWindow()
  local src = lines(ESTADO)
  local inicio, fim
  for i, l in ipairs(src) do
    if not inicio and l:match("^#%s+Roadmap V3 execution") then inicio = i end
    if inicio and not fim and l:match("^#%s+Roadmap V2 execution") then fim = i end
  end
  if not inicio then
    io.stderr:write("EXECUTION_STATE.md has no '# Roadmap V3 execution' heading, "
      .. "so the live section cannot be located\n")
    os.exit(1)
  end
  return src, inicio, fim or (#src + 1)
end

local src, ini, fim = liveWindow()

local problemas = {}
local function fail(fmt, ...)
  problemas[#problemas + 1] = string.format(fmt, ...)
end

-- 1 and 2. Every required section present, inside the live window.
local headings = {}
for i = ini, fim - 1 do
  local h = src[i]:match("^#+%s+(.*)$")
  if h then headings[#headings + 1] = h end
end

local function temSecao(nome)
  local alvo = nome:lower()
  for _, h in ipairs(headings) do
    if h:lower():find(alvo, 1, true) then return true end
  end
  return false
end

local exigidas = requiredSections()
if #exigidas == 0 then
  io.stderr:write("could not read any required section from " .. ROADMAP
    .. " section 9.7; nothing was checked, which is not a pass\n")
  os.exit(1)
end

for _, nome in ipairs(exigidas) do
  if not temSecao(nome) then
    fail("the live section has no heading for %-18s (ROADMAP_V3.md 9.7 requires it)",
      "\"" .. nome .. "\"")
  end
end

-- 3. The current-state block has a date. Accepts an ISO date or the run stamp
-- the runner uses, because both are unambiguous.
local temData = false
for i = ini, fim - 1 do
  local l = src[i]
  if l:match("%d%d%d%d%-%d%d%-%d%d") or l:match("%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d") then
    temData = true
    break
  end
end
if not temData then
  fail("the live section carries no date; a measured block with no date cannot "
    .. "be told from a stale one")
end

-- 4. Workstream rows: owner, state and evidence all present, evidence not "done".
local emTabela, linhasTabela = false, 0
for i = ini, fim - 1 do
  local l = src[i]
  if l:match("^##%s") then
    emTabela = l:lower():find("workstream", 1, true) ~= nil
  elseif emTabela and l:match("^|") then
    -- skip the header and the |---|---| separator
    if not l:match("^|%s*%-%-") and not l:lower():match("^|%s*item%s*|") then
      local celulas = {}
      for c in l:gmatch("|([^|]*)") do celulas[#celulas + 1] = (c:gsub("^%s+", ""):gsub("%s+$", "")) end
      -- item | owner | files | state | evidence
      if #celulas >= 5 then
        linhasTabela = linhasTabela + 1
        local item, dono, estado, evid = celulas[1], celulas[2], celulas[4], celulas[5]
        if dono == "" then fail("workstream row %s has no owner", item) end
        if estado == "" then fail("workstream row %s has no state", item) end
        if evid == "" then
          fail("workstream row %s has no evidence", item)
        elseif evid:lower():gsub("[%*%s%.]", "") == "done" then
          fail("workstream row %s gives \"done\" as evidence; the roadmap asks "
            .. "for a commit or a measurement", item)
        end
      end
    end
  end
end
if linhasTabela == 0 then
  fail("the Workstreams table has no rows, so nothing is being tracked")
end

--------------------------------------------------------------------------
if #problemas > 0 then
  for _, p in ipairs(problemas) do print("  " .. p) end
  print(string.format("EXECUTION STATE INCOMPLETE: %d problem(s)", #problemas))
  os.exit(1)
end
print(string.format("execution state ok: %d required sections, %d workstream rows",
  #exigidas, linhasTabela))
