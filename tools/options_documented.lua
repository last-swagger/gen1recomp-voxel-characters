-- Does every player-facing option actually appear in the docs a player reads?
--
--   luajit mods/voxel_characters/tools/options_documented.lua
--
-- From the REPO ROOT, like every other gate here: it loads the mod under the
-- outer repository's love stub, and `require("tests.love_stub")` resolves
-- against the current directory (see docs/TRAPS.md).
--
-- WHY THIS EXISTS. Four player-facing options landed on `vida-v2` after
-- v1.6.0 and the docs did not follow them: `ATTENTION`, `PART LAG` and
-- `FIRST PERSON` were in no doc at all, `FOOTFALL` was in the README and not
-- in the changelog, and CHANGELOG.md's [Unreleased] section opened with
-- "Nothing here changes what a player sees", which was true the hour it was
-- written and wrong four times over by the end of the day.
--
-- That is not a documentation nicety. `release.sh` builds the release body
-- from CHANGELOG.md, so the next publish would have shipped four options no
-- note mentions, and a player who cannot find an option in the README has no
-- way to know it exists: our rows sit at index 43 of 48 in the game's options
-- menu.
--
-- WHY IT READS THE SCHEMA INSTEAD OF A LIST. A hand-written list of options
-- in a gate is a second copy of the menu, and the second copy is the one that
-- goes stale: this repository already has that exact defect recorded, in the
-- life-safety ceiling test, which writes its maxima by hand instead of
-- reading them from the mod's own table, so a new and stronger level would
-- not be covered by it. So this loads `main.lua` and captures the schema the
-- mod itself hands to `mod.options:define`. A new option is covered here the
-- moment it is added to `OPTIONS`, with no edit to this file, and an option
-- that is renamed is checked under its new name automatically.
--
-- WHAT IT DOES NOT COVER, named rather than implied. It does not check the
-- check count the README advertises next to the test command, because
-- deriving that means running the suite this gate is a step alongside. It
-- does not read the wording of an entry: it proves a player can find the
-- option and its levels, not that the prose is any good.

package.path = "./?.lua;./?/init.lua;" .. package.path

local MAIN = os.getenv("VOXEL_CHARS_MAIN") or "mods/voxel_characters/main.lua"
local README = "mods/voxel_characters/README.md"
local CHANGELOG = "mods/voxel_characters/CHANGELOG.md"

local ok, stub = pcall(require, "tests.love_stub")
if not ok then
  io.stderr:write("cannot load tests.love_stub: run this from the REPO ROOT\n")
  os.exit(1)
end
love = stub

--------------------------------------------------------------------------
-- The schema, straight out of the mod
--------------------------------------------------------------------------
-- The same door the offline suite uses (`loadWith` plus a capturing
-- `mod.options:define`). The schema is generated from `OPTIONS` and is
-- registered unconditionally, so it lists every option regardless of what a
-- host can do; the MENU hides the life rows on a host with no draw channel,
-- but an option that exists on any host is an option that needs a doc.
local function readSchema()
  local schema
  local function noop() end
  local mod = {
    id = "voxel_characters",
    version = "0.0.0",
    path = "mods/voxel_characters",
    options = {}, hooks = {}, events = {},
    log = { info = noop, warn = noop, error = noop },
  }
  function mod.options:define(s) schema = s end
  function mod.options:get(key)
    for _, row in ipairs(schema or {}) do
      if row.key == key then return row.default end
    end
  end
  function mod.hooks:wrap() end
  function mod.events:on() end
  function mod.find() return nil end

  local chunk, err = loadfile(MAIN)
  if not chunk then
    io.stderr:write("cannot load " .. MAIN .. ": " .. tostring(err) .. "\n")
    os.exit(1)
  end
  chunk(mod)
  if not schema or #schema == 0 then
    io.stderr:write("the mod registered no option schema; nothing was checked, "
      .. "which is not the same as a pass\n")
    os.exit(1)
  end
  return schema
end

-- The level whose VALUE is the registered default, reported by its menu
-- LABEL, because the label is what the README documents ("default SUBTLE")
-- and the value is what the code carries (0.010).
local function defaultLabel(row)
  for _, choice in ipairs(row.choices or {}) do
    if choice[2] == row.default then return choice[1] end
  end
  return nil
end

local function levelLabels(row)
  local out = {}
  for _, choice in ipairs(row.choices or {}) do out[#out + 1] = choice[1] end
  return out
end

--------------------------------------------------------------------------
-- Reading files, and matching a WORD rather than a substring
--------------------------------------------------------------------------
local function lines(path)
  local f = io.open(path, "r")
  if not f then
    io.stderr:write("cannot read " .. path .. "\n")
    os.exit(1)
  end
  local out = {}
  for line in f:lines() do out[#out + 1] = line end
  f:close()
  return out
end

-- main.lua as ONE string, for the comment-against-code check further down: a
-- line list cannot see a comment and the `defaultIndex` below it at the same
-- time.
local function slurp(path)
  local f = io.open(path, "r")
  if not f then
    io.stderr:write("cannot read " .. path .. "\n")
    os.exit(1)
  end
  local t = f:read("*a"); f:close(); return t
end

local MAIN_SRC = slurp("mods/voxel_characters/main.lua")

local function escape(s)
  return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"))
end

-- A STANDALONE token, and the boundary is the whole point. `MOTION LAG`
-- contains `ON`, so a plain substring search would let any line that
-- mentions MOTION LAG stand in as documentation of GROUND SHADE's ON level.
-- Levels are short and uppercase (`ON`, `LOW`, `1`), which is exactly the
-- shape that hides inside other words.
--
-- BOUNDARY BY CHARACTER, NOT BY `%f[%W]`, and this cost a false alarm before
-- it was written this way. The first version asked for a word frontier after
-- the match, which cannot fire when the token itself ends in punctuation:
-- `CARVED+` ends in `+`, `+` is already a non-word character, so there is no
-- word-to-nonword transition to find and the gate reported the SHAPE row as
-- missing a level the README lists in plain sight. A gate that cries wolf on
-- correct input is worse than one that misses, because it gets waived by the
-- second day and then it is not there at all. So: find the literal, then
-- require the characters on either side not to be alphanumeric.
local function hasWord(haystack, word)
  local from = 1
  while true do
    local s, e = haystack:find(word, from, true)
    if not s then return false end
    local before = s > 1 and haystack:sub(s - 1, s - 1) or ""
    local after = haystack:sub(e + 1, e + 1)
    if not before:match("%w") and not after:match("%w") then return true end
    from = s + 1
  end
end

--------------------------------------------------------------------------
-- README: the option table a player reads
--------------------------------------------------------------------------
-- A row is a line inside a fenced block that starts at column zero with an
-- uppercase letter and has a column gap (two or more spaces) after the
-- label. That is the README's own format, and scoping to it is what stops
-- prose from counting: `FIRST PERSON` appears in the STATUS table as a
-- STATUS VALUE, and `SHAPE` appears in half the prose in the file, neither
-- of which tells a player the option exists or what it is set to.
local function readmeRows()
  local blocks, current, inFence = {}, nil, false
  for _, line in ipairs(lines(README)) do
    if line:match("^```") then
      if inFence then
        blocks[#blocks + 1] = current
        current, inFence = nil, false
      else
        current, inFence = {}, true
      end
    elseif inFence then
      if line:match("^%u") and line:match("^%S[^\n]-%s%s") then
        current[#current + 1] = line
      end
    end
  end
  return blocks
end

-- The options block is the fenced block carrying the most schema labels.
-- Found rather than assumed, because the README has other fenced blocks (the
-- CAMERA FIT measurements, the test commands) and hard-coding "the third
-- fence" would break on the next edit to the file.
local function optionsBlock(blocks, schema)
  local best, bestScore = {}, -1
  for _, block in ipairs(blocks) do
    local score = 0
    for _, row in ipairs(schema) do
      for _, line in ipairs(block) do
        if line:find("^" .. escape(row.label) .. "%s") then
          score = score + 1
          break
        end
      end
    end
    if score > bestScore then best, bestScore = block, score end
  end
  return best
end

--------------------------------------------------------------------------
-- The checks
--------------------------------------------------------------------------
local schema = readSchema()
local readmeLines = lines(README)
local changelogLines = lines(CHANGELOG)
local block = optionsBlock(readmeRows(), schema)

local problems = {}
local function fail(fmt, ...)
  problems[#problems + 1] = string.format(fmt, ...)
end

for _, row in ipairs(schema) do
  local label, levels, def = row.label, levelLabels(row), defaultLabel(row)

  -- 1. README: the option has a row, listing every level and its default.
  local rowLine
  for _, line in ipairs(block) do
    if line:find("^" .. escape(label) .. "%s") then rowLine = line break end
  end
  if not rowLine then
    fail("README.md has no options row for %-13s (add it to the options block)",
      label)
  else
    for _, level in ipairs(levels) do
      if not hasWord(rowLine, level) then
        fail("README.md row for %-13s does not list its %s level", label, level)
      end
    end
    -- The FIRST token after `default`, compared exactly. Not a search for the
    -- label anywhere in the row: the trailing description is prose, and
    -- "default OFF   turns ON the outline" would otherwise document a default
    -- of ON. An exact token also needs no boundary rule at all.
    local documentedDefault = rowLine:match("default%s+(%S+)")
    if def and documentedDefault ~= def then
      fail("README.md row for %-13s says default %s, the code registers %s",
        label, tostring(documentedDefault), def)
    end
  end

  -- 1b. THE COMMENT MUST NOT CONTRADICT THE CODE.
  --
  -- `BREATH`'s own comment said "Default OFF per the house rule" while its
  -- `defaultIndex` was 2, so the source lied about itself. The 1.6.0 release note
  -- then repeated the comment rather than the code, and the error survived a
  -- release: a reader who trusted either one would have told a player that
  -- nothing breathes by default.
  --
  -- The README was RIGHT the whole time, and the check above proved it, which is
  -- exactly why this gap was invisible. A gate that compares two documents can
  -- be green while a third contradicts both.
  do
    local bloco = MAIN_SRC:match("key = \"" .. escape(tostring(row.key)) .. "\".-defaultIndex%s*=%s*%d+")
    if bloco then
      -- QUOTED TEXT IS NOT A CLAIM. This check's first run flagged BREATH
      -- again, for the comment that EXPLAINS the old defect by quoting it:
      -- `"Default OFF per the house rule"` appears there inside quotes,
      -- describing what the comment used to say. A gate that cannot tell an
      -- assertion from a citation makes it impossible to document the very
      -- error it exists to catch, and the fix for that would be to delete the
      -- explanation, which is exactly backwards.
      --
      -- So quoted runs are stripped before the search. Anything a comment
      -- attributes to somebody else, including its own past, stops counting as
      -- what it currently claims.
      local semCitacao = bloco:gsub('"[^"]*"', " "):gsub("`[^`]*`", " "):lower()
      local mentira = semCitacao:match("default[s]?%s+off")
        or semCitacao:match("ships%s+off")
        or semCitacao:match("enters%s+as%s+an%s+option%s+turned%s+off")
      if mentira and def ~= levels[1] then
        fail("%-13s comment says it defaults OFF and the code registers %s. A "
          .. "comment that contradicts the line below it is worse than none",
          label, tostring(def))
      end
    end
  end

  -- 2. CHANGELOG: an entry that names the option AND at least one of its
  -- levels on the same line. The level is what separates an entry that
  -- introduces an option from a passing mention: `FIRST PERSON` appeared
  -- twice in this file while the option was undocumented, both times as a
  -- value of the read-only STATUS row.
  local documented = false
  for _, line in ipairs(changelogLines) do
    if line:find(escape(label)) then
      for _, level in ipairs(levels) do
        if hasWord(line, level) then documented = true break end
      end
    end
    if documented then break end
  end
  if not documented then
    fail("CHANGELOG.md has no entry naming %-13s with one of its levels "
      .. "(%s)", label, table.concat(levels, " / "))
  end
end

-- 3. The row count the README states in prose, against the rows it lists.
-- Both sides are read from the file, so nothing here is a constant that can
-- drift: the prose number and the table have to agree with each other, and
-- the table has to contain every option above.
local stated
for _, line in ipairs(readmeLines) do
  local n = line:match("(%d+)%s+rows under")
  if n then stated = tonumber(n) break end
end
if not stated then
  fail("README.md does not state a row count as \"<n> rows under `OPTIONS`\", "
    .. "so the count cannot be checked against the table")
elseif stated ~= #block then
  fail("README.md says %d rows under OPTIONS and its options block lists %d",
    stated, #block)
end

--------------------------------------------------------------------------
-- Verdict
--------------------------------------------------------------------------
if #problems > 0 then
  for _, p in ipairs(problems) do print("  " .. p) end
  print(string.format("OPTION DOCS INCOMPLETE: %d problem(s) across %d options",
    #problems, #schema))
  os.exit(1)
end
print(string.format("option docs ok: %d options, %d rows documented",
  #schema, #block))
