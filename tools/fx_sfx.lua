-- TWO SHORT SOUNDS FOR THE FX DEMO (roadmap T2.3 slice 2), generated.
--
--   luajit mods/voxel_characters/tools/fx_sfx.lua <out-dir>
--
-- Writes fireball.wav, bolt.wav and silence.wav. Pure Lua: no LOVE, no display,
-- no external tool, so the whole thing can be gated on any machine.
--
-- WHY GENERATED AND NOT COMMITTED. Two small WAVs in the repository would be
-- simpler to play and worse to trust: a committed file is checked once, when
-- somebody looks at it, and after that the gate can only confirm the bytes have
-- not changed. A generator is code, so `audio_gate.sh` can re-derive the sound
-- on every run and answer the question that matters, which is whether what this
-- project produces is audible and inside its ceiling. It also keeps binary
-- blobs out of a repository whose whole promise is that it ships no assets.
--
-- DETERMINISTIC ON PURPOSE. `math.random` is seeded differently per run and
-- differs between Lua builds, so the noise comes from a small LCG written out
-- here. Two runs produce byte-identical files, which is what lets the gate
-- compare them and catch a generator that has quietly started drifting.
--
-- THE SOUNDS, and they are deliberately small:
--
--   fireball  a downward whoosh, noise through a lowpass whose cutoff falls,
--             so it reads as something leaving the hand and travelling away
--   bolt      a crack, a short burst with a fast decay and a high ring on top,
--             so it reads as an impact rather than a departure
--
-- Neither is Gen 1 authentic and neither pretends to be. They exist to prove
-- the channel: a demo that draws an effect and stays silent is half a
-- demonstration.

local TAXA = 22050        -- plenty for two short effects, and small on disk
-- PEAK AMPLITUDE, chosen with room rather than to the limit. At 0.30 the two
-- effects measured -7.9 and -7.4 dBFS, which passes a -6 ceiling by under two
-- decibels: enough for a resample or a different encoder to push it over, and
-- close enough to the limit that a demo effect would sit on top of the game's
-- own music. 0.22 lands them near -10.5, still plainly audible.
local TETO = 0.22

-- A tiny LCG. Numbers are the classic Numerical Recipes constants; the point is
-- reproducibility, not statistical quality.
local function ruido(estado)
  return function()
    estado = (1664525 * estado + 1013904223) % 4294967296
    return (estado / 2147483648) - 1     -- -1 .. 1
  end
end

local function escreveWav(caminho, amostras)
  local f = assert(io.open(caminho, "wb"))
  local n = #amostras
  local dados = n * 2
  local function u32(v)
    return string.char(v % 256, math.floor(v / 256) % 256,
                       math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
  end
  local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
  f:write("RIFF", u32(36 + dados), "WAVE")
  f:write("fmt ", u32(16), u16(1), u16(1), u32(TAXA), u32(TAXA * 2), u16(2), u16(16))
  f:write("data", u32(dados))
  for i = 1, n do
    local v = amostras[i]
    if v > 1 then v = 1 elseif v < -1 then v = -1 end
    local s = math.floor(v * 32767 + 0.5)
    if s < 0 then s = s + 65536 end
    f:write(u16(s))
  end
  f:close()
end

-- fireball: noise through a one-pole lowpass whose cutoff falls over the sound,
-- with a soft attack so it does not click. The falling cutoff is what makes it
-- read as travelling away rather than as a burst.
local function fireball()
  local dur = 0.38
  local n = math.floor(TAXA * dur)
  local rnd = ruido(20260810)
  local out, y = {}, 0
  for i = 1, n do
    local t = i / n
    local corte = 0.42 * (1 - t) ^ 2 + 0.02
    y = y + corte * (rnd() - y)
    local ataque = math.min(1, i / (TAXA * 0.02))
    local queda = (1 - t) ^ 1.6
    out[i] = y * ataque * queda * TETO * 2.2
  end
  return out
end

-- bolt: a crack. A very short noise burst with an almost instant decay, plus a
-- high tone that rings briefly on top, which is what separates it by ear from
-- the fireball rather than only by length.
local function bolt()
  local dur = 0.16
  local n = math.floor(TAXA * dur)
  local rnd = ruido(99001122)
  local out = {}
  for i = 1, n do
    local t = i / n
    local queda = math.exp(-t * 22)
    local anel = math.sin(2 * math.pi * 2100 * (i / TAXA)) * math.exp(-t * 30)
    out[i] = (rnd() * 0.75 + anel * 0.45) * queda * TETO * 1.5
  end
  return out
end

local function silencio()
  local out = {}
  for i = 1, math.floor(TAXA * 0.2) do out[i] = 0 end
  return out
end

local destino = arg[1]
if not destino then
  io.stderr:write("usage: fx_sfx.lua <out-dir>\n")
  os.exit(2)
end
escreveWav(destino .. "/fireball.wav", fireball())
escreveWav(destino .. "/bolt.wav", bolt())
escreveWav(destino .. "/silence.wav", silencio())
print("fx sfx written to " .. destino)
