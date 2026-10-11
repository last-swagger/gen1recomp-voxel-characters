-- Fail fast when a game probe would land on the ROM importer instead of in game.
local version, root = arg[1], arg[2]
if not version or not root then
  io.stderr:write("usage: cache_ready.lua <game> <save-directory>\n")
  os.exit(2)
end

local prefix = version .. "/"
local okVersion, GameVersion = pcall(require, "src.core.GameVersion")
if okVersion and GameVersion.cachePrefix then
  prefix = GameVersion.cachePrefix(version)
end

local fs = { prefix = prefix }
local function caminho(rel)
  return root .. "/" .. fs.prefix .. rel
end
function fs.read(rel)
  local arquivo = io.open(caminho(rel), "rb")
  if not arquivo then return nil end
  local conteudo = arquivo:read("*a")
  arquivo:close()
  return conteudo
end
function fs.exists(rel)
  local arquivo = io.open(caminho(rel), "rb")
  if not arquivo then return false end
  arquivo:close()
  return true
end

local okContract, CacheContract = pcall(require, "src.import.CacheContract")
if not okContract then
  if fs.exists("rom-cache.complete") then
    print("CACHE READY (legacy engine marker; full cache contract unavailable)")
    return
  end
  io.stderr:write("CACHE NOT READY: no rom-cache.complete for " .. version .. "\n")
  os.exit(1)
end

if CacheContract.isReady(version, fs) then
  print("CACHE READY: " .. version)
  return
end

local _ok, ausente = CacheContract.allRequiredFilesExist(version, fs)
io.stderr:write("CACHE NOT READY: " .. version)
if ausente then io.stderr:write("; missing required output: " .. tostring(ausente)) end
io.stderr:write("; reimport this game's ROM before running an in-game probe\n")
os.exit(1)
