-- A REASON ON A CHOICE, encoded so no existing parser notices (roadmap T1.4).
--
-- Pure Lua, no love, so the laboratory can require it and the gates can
-- `dofile` it, the same arrangement `host_matrix.lua` already uses.
--
-- WHY THIS IS ENCODED RATHER THAN WRITTEN PLAINLY. The choice line is read by
-- two tools that were written before any of this existed:
--
--   calibra.sh:132   linha:match("|%s*A:%s*(.-)%s*|%s*B:%s*(.*)$")
--   ajusta.lua       the same shape
--
-- The two option states are split on `|`, and the second one is captured with
-- `(.*)$`, which swallows everything to the end of the line. So a reason cannot
-- go at the end, and it cannot contain a pipe anywhere. Fields are also read as
-- `key=(%S+)`, so it cannot contain a space either, and it must not contain a
-- literal `=` or it could be mistaken for the start of another field.
--
-- Percent-encoding removes all four problems at once: the result is one token
-- with no space, no pipe, no equals sign and no quote. Placed right after
-- `escolha=`, next to the decision it explains, it is invisible to every
-- pattern above.
--
-- THE RULE THIS KEEPS. The 106 choices already recorded have no reason, and
-- they must parse exactly as they do today, byte for byte, forever. A format
-- that needs its old records migrated is a format that loses them.

local M = {}

-- Everything outside a small safe set is encoded, rather than encoding a list
-- of known-bad characters. A denylist is one new parser away from being wrong;
-- an allowlist is only ever too cautious.
function M.encode(texto)
  if texto == nil then return nil end
  texto = tostring(texto)
  if texto:match("^%s*$") then return nil end
  return (texto:gsub("[^%w%-%.~_]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

function M.decode(token)
  if token == nil or token == "" then return nil end
  return (tostring(token):gsub("%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end))
end

-- The field as it appears on a choice line, or the empty string when there is
-- no reason. Empty means the field is OMITTED entirely, so a choice recorded
-- without one is byte-identical to a choice recorded before this existed.
function M.field(texto)
  local cod = M.encode(texto)
  if not cod then return "" end
  return " reason=" .. cod
end

function M.fromLine(linha)
  return M.decode(tostring(linha):match("reason=(%S+)"))
end

return M
