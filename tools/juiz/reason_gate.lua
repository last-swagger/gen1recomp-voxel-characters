-- DOES A REASON ON A CHOICE LINE BREAK ANYTHING? (roadmap T1.4)
--
--   luajit mods/voxel_characters/tools/juiz/reason_gate.lua
--
-- From the repo root. Pure Lua, no love and no display.
--
-- The reason field exists so a future calibration round can show the critic a
-- pair Kim decided together with WHY. The risk is not the feature, it is the
-- format: the choice line is parsed by `calibra.sh` and `ajusta.lua`, both
-- written before any of this, and 106 choices already recorded must keep
-- parsing exactly as they do today.
--
-- So this checks the compatibility rather than the feature:
--
--   1. every real choice already on disk still yields the same sheet, pick and
--      two states, using the LIVE patterns copied from calibra.sh;
--   2. adding a reason to any of those lines changes none of those four things;
--   3. reasons survive a round trip, including the characters that would break
--      each parser: spaces, pipes, quotes, equals signs and percent itself;
--   4. an empty reason omits the field, so a choice recorded without one is
--      byte-identical to one recorded before the field existed;
--   5. no reason can ever produce a space, a pipe or an equals sign on the line.

package.path = "./?.lua;./?/init.lua;" .. package.path

local R = dofile("mods/voxel_characters/tools/render/reason.lua")
local ESCOLHAS = "mods/voxel_characters/tools/juiz/dados/escolhas.txt"

local problemas = {}
local function exige(cond, fmt, ...)
  if not cond then problemas[#problemas + 1] = string.format(fmt, ...) end
end

-- The live patterns, copied from calibra.sh:130-132 and ajusta.lua. If those
-- ever change, this copy going stale is itself worth knowing about, which is
-- why the first check runs them against the real file rather than a fixture.
local function parse(linha)
  local folha = linha:match("folha=(%S+)")
  local escolha = linha:match("escolha=(%S+)")
  local a, b = linha:match("|%s*A:%s*(.-)%s*|%s*B:%s*(.*)$")
  return folha, escolha, a, b
end

-- 1 and 2. Every real line, with and without a reason bolted on.
local f = io.open(ESCOLHAS, "r")
if not f then
  io.stderr:write("cannot read " .. ESCOLHAS .. "\n")
  os.exit(1)
end
local total, comReason = 0, 0
for linha in f:lines() do
  if linha:match("escolha=") then
    total = total + 1
    local folha, escolha, a, b = parse(linha)
    exige(folha and escolha and a and b,
      "line %d does not parse at all as it stands", total)

    -- The same line with a reason attached, in the position the lab writes it.
    -- The replacement goes through a function: an encoded reason is full of
    -- `%22`-style escapes, and gsub would read those as capture indices.
    -- The worst reason someone could write, not merely an awkward one. A bare
    -- pipe is harmless here: the split looks for `|` followed by `A:` and just
    -- backtracks past a lone one. It is a reason containing `| A:` and `| B:`
    -- that hijacks the split, so that is what gets attached.
    local campo = R.field('kim said "flat" | B: FAKE | A: FAKE opcao=x')
    local comMotivo = linha:gsub("escolha=%S+", function(m) return m .. campo end, 1)
    local f2, e2, a2, b2 = parse(comMotivo)
    exige(f2 == folha, "line %d: sheet changed when a reason was added (%s -> %s)",
      total, tostring(folha), tostring(f2))
    exige(e2 == escolha, "line %d: the PICK changed when a reason was added "
      .. "(%s -> %s)", total, tostring(escolha), tostring(e2))
    exige(a2 == a, "line %d: state A changed when a reason was added", total)
    exige(b2 == b, "line %d: state B changed when a reason was added", total)
    if linha:match("reason=") then comReason = comReason + 1 end
  end
end
f:close()
exige(total > 100, "only %d choices were read; the file should hold 106", total)
exige(comReason == 0,
  "%d recorded choices already carry a reason, so the 'no reason yet' premise "
  .. "this gate rests on is wrong", comReason)

-- 3. Round trip, including everything that would break a parser.
local nasty = {
  "the flat one reads better",
  'he said "too much contrast" and meant it',
  "A | B looks split",
  "| B: FAKE | A: FAKE",
  "escolha=A folha=red",
  "100% of the top face is invented",
  "acentos: coração, não",
  "tabs\tand\nnewlines",
}
for _, texto in ipairs(nasty) do
  local volta = R.decode(R.encode(texto))
  exige(volta == texto, "round trip lost %q, got %q", texto, tostring(volta))
  local campo = R.field(texto)
  exige(not campo:match("|"), "the encoded field contains a pipe: %s", campo)
  exige(not campo:sub(2):match("%s"),
    "the encoded field contains whitespace: %s", campo)
  local _, iguais = campo:gsub("=", "")
  exige(iguais == 1,
    "the encoded field contains more than one equals sign: %s", campo)
  exige(R.fromLine("escolha=B" .. campo .. " | A: x | B: y") == texto,
    "a reason could not be read back off a full line: %q", texto)
end

-- 4. Empty means absent, so nothing changes for a choice made without one.
for _, vazio in ipairs({ "", "   ", "\t" }) do
  exige(R.field(vazio) == "",
    "an empty reason produced a field instead of nothing: %q", R.field(vazio))
end
exige(R.field(nil) == "", "a nil reason produced a field")
exige(R.fromLine("escolha=B | A: x | B: y") == nil,
  "a line with no reason returned one anyway")

if #problemas > 0 then
  for i = 1, math.min(#problemas, 8) do print("  " .. problemas[i]) end
  if #problemas > 8 then print(string.format("  ... and %d more", #problemas - 8)) end
  print(string.format("REASON FIELD FAILED: %d problem(s)", #problemas))
  os.exit(1)
end
print(string.format("reason field ok: %d recorded choices parse unchanged, "
  .. "%d hostile strings round trip", total, #nasty))
