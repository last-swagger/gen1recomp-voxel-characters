-- HOST MATRIX PROBE: does this mod actually LOAD and ATTACH against the
-- voxel host that is enabled right now?
--
-- WHY THIS EXISTS. Every other in-game probe here assumes the mod is already
-- attached and then measures what it draws. None of them can fail the way
-- 1.8.0 failed in the field, which was earlier than any of them: the mod
-- loaded, found no usable host, and quietly registered its options rows with
-- nothing behind them. Every geometry gate still passed, because they all run
-- against the ONE host this machine had enabled. The community ran the other
-- two.
--
-- So this probe measures the two facts the geometry gates take for granted:
--
--   1. did `voxel_characters` survive the loader at all (state == "loaded")
--   2. did it find a host and patch it (`mod._hostReport()`)
--
-- and it does it WITHOUT drawing a frame of the overworld, so it is seconds
-- rather than minutes and one run per host is affordable.
--
-- Read by tools/ingame/hosts.sh, which enables one host at a time and diffs
-- the answers. Output goes to BOTH stdout (for the run log) and
-- vc_hosts.txt in the save dir (for the runner to parse), because a LOVE
-- process that is killed on timeout can lose the tail of its stdout.

local function linha(fmt, ...)
  local s = select("#", ...) > 0 and string.format(fmt, ...) or fmt
  print("[hosts] " .. s)
  return s
end

return function(game)
  io.stdout:setvbuf("line")
  local out = {}
  local function diz(fmt, ...) out[#out + 1] = linha(fmt, ...) end

  -- Give the loader a few frames to have finished; Game:load() has already
  -- run by the time the driver is created, but yielding once keeps this
  -- honest if that ever changes.
  coroutine.yield()

  local status = game and game.modStatus
  if not status then
    diz("FATAL: no modStatus on the game object")
  else
    -- WHICH VOXEL HOST WAS ACTUALLY ENABLED, from the engine's own view and
    -- not from the save file: `options.mods` is the flag, but a mod can be
    -- present-and-failed, and that distinction is the whole point here.
    local hosts = { potato_voxel = true, BATTLE_ART_VOXEL_FORK = true,
      DRAMALESS_SHAPE = true, DRAMATIC_SHAPE = true }
    for _, m in ipairs(status.available or {}) do
      if hosts[m.id] then
        diz("HOST %s version=%s state=%s error=%s", m.id, tostring(m.version),
          tostring(m.state), tostring(m.error))
      end
      if m.id == "voxel_characters" then
        diz("MOD  %s version=%s api=%s state=%s error=%s", m.id,
          tostring(m.version), tostring(m.api), tostring(m.state),
          tostring(m.error))
      end
    end
    for _, e in ipairs(status.errors or {}) do
      diz("LOADER ERROR %s", tostring(e))
    end
  end

  -- THE ATTACH ANSWER, which is the one that matters and is NOT in modStatus:
  -- a mod that loaded fine but found no host looks identical from outside.
  local loader = game and game.mods
  local exports = loader and loader.exports and loader.exports.voxel_characters
  if type(exports) == "table" and type(exports.hostReport) == "function" then
    local ok, rep = pcall(exports.hostReport)
    if ok and type(rep) == "table" then
      diz("ATTACH host=%s hostVersion=%s patched=%s draw=%s atlas=%s grid=%s",
        tostring(rep.host), tostring(rep.hostVersion), tostring(rep.patched),
        tostring(rep.drawPatched), tostring(rep.atlasPatched),
        tostring(rep.gridAvailable))
      if rep.why then diz("ATTACH why=%s", tostring(rep.why)) end
    else
      diz("ATTACH hostReport threw: %s", tostring(rep))
    end
  else
    diz("ATTACH no hostReport export (mod did not load, or is older than this probe)")
  end

  diz("end")

  pcall(function()
    love.filesystem.write("vc_hosts.txt", table.concat(out, "\n") .. "\n")
  end)
  love.event.quit()
  coroutine.yield()
end
