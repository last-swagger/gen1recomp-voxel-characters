-- Offline render harness for the Voxel Characters mod.
--
-- Loads mods/voxel_characters/main.lua under a stub of the host mod API and of
-- the Dramatic Shape namespace, builds the real geometry from the player's own
-- generated sprite sheets, and rasterizes it to a PNG contact sheet.
--
-- The point is a feedback loop that does not need a human at the keyboard:
-- every visual defect this mod has shipped so far was found by someone
-- watching a video. This lets the geometry be looked at directly, from any
-- angle, for every character, in seconds.
--
-- Run from the gen1recomp root:
--   love mods/voxel_characters/tools/render sprite=red shapes=slab,carved
--
-- The PNG lands in the LOVE save directory, path printed on stdout.

package.path = "./?.lua;./?/init.lua;" .. package.path

-- Sibling modules, split out of this file (roadmap item 19): LOVE loads
-- tools/render/ as the game, so require() finds these with no configuration.
-- Lab and Features are wired up with the harness's shared state further
-- down, once that state (drawCell, buildGeometry, ...) exists to hand over.
local AO = require("ao_proto")
local Lab = require("lab")
local Features = require("features")
-- One definition of the host's matrix, shared with the offline suite so the
-- laboratory cannot drift from what the suite proves (roadmap T1.1).
local HostMatrix = require("host_matrix")

-- ERROR GOES TO STDOUT AND KILLS THE PROCESS, instead of opening a window and waiting.
--
-- By default LOVE handles an error by opening a blue screen with the message
-- and WAITING FOR A KEY. From inside a script this is indistinguishable from
-- heavy work: the tool only dies on timeout, with an empty log, and the cause
-- is written on a window nobody is looking at. Happened three times in one
-- session.
--
-- I first tried to solve this by PHOTOGRAPHING the screen to read the
-- message. It was worse: on a work machine the photo captures whatever is in
-- front, and it captured a personal conversation twice. The images were
-- deleted and the idea was abandoned. The message has to come out through
-- where the script already reads, which is stdout.
function love.errorhandler(msg)
  msg = tostring(msg)
  io.stdout:write("LOVE ERROR: " .. msg .. "\n")
  io.stdout:write(debug.traceback("", 2) .. "\n")
  io.stdout:flush()
  os.exit(1)
end
love.errhand = love.errorhandler   -- LOVE 0.x/11.x use different names

local ROOT = "./"
-- By default measures the mod from the working tree, but accepts pointing to
-- another file via VOXEL_CHARS_MAIN. This exists so the real BEFORE can be
-- rendered from an already-released tag (`git show v1.4.1:main.lua > /tmp/x`)
-- instead of illustrating from memory what a fix changed: a release
-- comparison is a public claim, and a public claim needs measurement.
local MAIN_PATH = os.getenv("VOXEL_CHARS_MAIN")
  or (ROOT .. "mods/voxel_characters/main.lua")
-- A wrong path cannot become a hung process. Under `love`, a failing assert
-- opens the default error window instead of exiting, and whoever called
-- through a pipe (check.sh does that) receives NOTHING: the process hangs and
-- only dies with kill. Measured in a review. So the check is explicit and
-- comes before everything.
do
  local f = io.open(MAIN_PATH, "r")
  if f then f:close() else
    io.stderr:write("VOXEL_CHARS_MAIN points at a file that does not exist: "
      .. MAIN_PATH .. "\n")
    os.exit(2)
  end
end
local SPRITE_DIR = "assets/generated/sprites/"
-- Overridden by `spritedir=`, so a candidate sheet can be rendered side by
-- side with the original without writing anything to the player's cache.

--------------------------------------------------------------------------
-- arguments
--------------------------------------------------------------------------

local opts = {
  sprite = "red",
  shapes = "slab,carved,carved_plus",
  frames = "0",
  yaws = "0,30,60,90",
  -- The Voxel Mod's own ladder, VoxelState.ANGLES_DEG = {0,35,15,35,50,75}.
  -- Its angle is measured from top-down: 0 lays the card flat on the ground
  -- (leanCorrection returns pi/2) and 90 stands it upright. A camera pitch
  -- above the horizon is therefore 90 minus that, which is what `rungs`
  -- converts. Judging geometry at a pitch nobody visits is how you fix the
  -- wrong thing.
  rungs = "15,35,50,75",
  pitch = "",
  depth = "3",
  side_color = "body",
  out = "sheet.png",
  bg = "0.32,0.34,0.38",
  cell = "220",
  label = "1",
  palette = "obj",
  diff = "0",
  metrics = "0",
  ao = "0",
  recess = "",
  outline = "back",
  depthmap = "",
  shade = "",
  spritedir = "",
  aostrength = "",
  ground = "",
  blink = "",
  blinktime = "",
  blinkscan = "",
  selftest = "",
  topedge = "",
  opt = "",
  lab = "",
  -- `labshot=file.png` opens the laboratory, takes a photo and exits. Exists
  -- so the laboratory can be CHECKED without anyone pressing a key: an
  -- interactive tool nobody tests breaks silently.
  labshot = "",
  labab = "",
  -- Where choices land, and a simulated choice for the gate. The file is
  -- parametrisable because the gate must NOT write a made-up choice into the
  -- file that will train the judge: that would poison the data with the
  -- test tool itself.
  labfile = "escolhas.txt",
  -- T1.1: gives the stub a Voxel3D.draw, so the mod installs its draw wrap and
  -- the matrix-only options exist at all in here. Off by default because it
  -- changes what the mod installs, and every measurement this project trusts
  -- was taken without it.
  labmotion = "",
  -- Runs the lab for a few frames, prints what the motion preview did, quits.
  -- A lab that can only be inspected by looking at it cannot be gated.
  labquit = "",
  -- `labpares=<file>` makes the laboratory offer the pairs the judge
  -- requested, instead of rolling. See labParDoArquivo.
  labpares = "",
  labpick = "",
  -- `labreason=<text>` stashes a reason before the simulated choice, so the
  -- write path can be proved end to end without anyone typing. Typing is the
  -- one thing a headless gate cannot do, and it is exactly the part that would
  -- otherwise ship unchecked.
  labreason = "",
  -- `authprobe=1` answers one question and exits: can the mod actually FIND its
  -- authored sheets from in here? The suite proves the loader with a stubbed
  -- filesystem, which is the loader's logic and not the path. LOVE resolves
  -- relative paths against the GAME directory, and for the harness that is
  -- tools/render while `mod.path` is repo-relative, so the two can disagree and
  -- the only symptom would be AUTHORED REGIONS quietly doing nothing here.
  authprobe = "",
  -- `preset=<preset1 sheet=... head=N ...>` recolours the sheet before any
  -- geometry is built (roadmap T2.2). The laboratory is where the creator
  -- lives, per the roadmap: not a game-facing UI and not save data. Nothing in
  -- the shipped mod reads a preset, so the runtime is untouched.
  preset = "",
  -- `parts=hair:blue,feet:youngster` composes a character out of OTHER SHEETS'
  -- rows (roadmap T2.2, the part stack). Answers one of that item's open
  -- questions -- "are parts shipped as art, generated from existing sprites, or
  -- both?" -- with `generated`, which is the only answer that keeps the mod's
  -- promise: every pixel is still the player's own ROM art, just recombined, so
  -- provenance stays artist-only and nothing ships.
  parts = "",
  -- `spriteframes=N` says how many frames a sheet has instead of deriving it
  -- from `height / 16`. Needed to render a sheet whose cells are not 16 px: the
  -- mod's own `spriteLayout` is already resolution-agnostic and computes the
  -- cell from the sheet size and the frame count, so the only thing standing in
  -- the way was this harness assuming the count.
  spriteframes = "",
  -- `labregions=1` forces the region-boundary overlay (key `b` in the
  -- laboratory) on at startup, so the gate can screenshot it without a
  -- keypress: labshot runs with love.labkeys disabled (roadmap item 11).
  labregions = "",
  -- `features=<file>` reads one line per variant (sheet TAB key:value,...)
  -- and prints one TSV line of features per variant. It is the expensive half
  -- of the judge: it needs LOVE, a real sprite and the mod loaded. The cheap
  -- half, which fits the model, runs in plain luajit in tools/juiz.
  features = "",
}

-- The schema the mod itself registers, captured at the last build. The
-- laboratory builds its menu from here instead of keeping a copy: a parallel
-- table rots, and it has already rotted in this project (a new option went
-- without visual measurement because the tool did not know it existed).
local LAB_SCHEMA = nil
local MOD_CHUNK = nil

local function parseArgs(argv)
  for _, a in ipairs(argv or {}) do
    local k, v = a:match("^([%w_]+)=(.*)$")
    if k then opts[k] = v end
  end
end

local function splitList(s)
  local out = {}
  for piece in tostring(s):gmatch("[^,]+") do
    out[#out + 1] = piece:match("^%s*(.-)%s*$")
  end
  return out
end

local function numbers(s)
  local out = {}
  for _, piece in ipairs(splitList(s)) do out[#out + 1] = tonumber(piece) end
  return out
end

--------------------------------------------------------------------------
-- host stubs
--
-- Same shape as tests/voxel_chars_test.lua, with two differences: the image
-- comes from a real PNG instead of a synthetic pixel table, and newMesh keeps
-- the raw vertex list instead of building a GPU mesh. Keeping the verts is
-- what lets one built mesh be drawn under many cameras: main.lua caches by
-- (def, frame, depth, pitch), so a camera baked into the mesh would be
-- silently reused by the next cell.
--------------------------------------------------------------------------

local function loadImageData(path)
  local f = assert(io.open(path, "rb"), "cannot open " .. path)
  local bytes = f:read("*a")
  f:close()
  local fd = love.filesystem.newFileData(bytes, path:match("[^/]+$"))
  return love.image.newImageData(fd)
end

-- A PRESET, APPLIED TO A SHEET (roadmap T2.2).
--
-- Recolours whole rows of the sprite before any mesh is built, so everything
-- downstream -- the builders, the provenance metric, the silhouette checks --
-- sees an ordinary sheet and needs no knowledge of presets at all.
--
-- WHY THE SILHOUETTE AND THE PROVENANCE CANNOT MOVE, and this is the roadmap's
-- first gate condition answered by construction rather than by hope. A preset
-- only ever writes a NEW COLOUR into an ALREADY OPAQUE pixel. It never changes
-- alpha, never adds or removes a pixel, and never touches geometry. So the
-- silhouette is the same set of pixels and the provenance is the same set of
-- faces, necessarily, for every preset that exists. The gate measures it anyway,
-- because "necessarily" has been wrong here before.
--
-- WHICH ROWS BELONG TO WHICH REGION comes from the MEASURED bounds in
-- authored/sheets/<sheet>.lua, never from a guess:
--
--   hair   the rows above the first light tone, and only on the frames the
--          measurement says read as a cap
--   feet   the rows from the measured foot split down
--   body   what is left between them
--
-- `head` IS DELIBERATELY UNPLACEABLE. Slice 2 refused to measure the
-- head-and-shoulder line because it does not resolve from the side view, and a
-- rule tuned until one frame agreed would be a rule fitted to one sheet. So a
-- preset naming `head` is REFUSED here rather than approximated. The format can
-- express it, this sheet cannot place it, and inventing a boundary would put a
-- guessed number back into the one path built to avoid them.
local function aplicaPreset(imageData, texto, sheetName)
  local Preset = dofile("mods/voxel_characters/authored/preset.lua")
  local p, err = Preset.parse(texto)
  if not p then return nil, err end
  if p.sheet ~= sheetName then
    return nil, string.format("the preset is for %q and this is %q",
      tostring(p.sheet), tostring(sheetName))
  end
  local folha = dofile("mods/voxel_characters/authored/sheets/" .. sheetName .. ".lua")
  if not (folha and folha.measured) then
    return nil, sheetName .. " ships no measured bounds, so a preset has no "
      .. "rows to apply itself to"
  end
  if p.tones.head then
    return nil, "this sheet has no measured head boundary, and guessing one "
      .. "would put an invented number into the path built to avoid them"
  end
  local capOk = {}
  for _, q in ipairs(folha.hairFrames or {}) do capOk[q] = true end

  local function hexPara(i)
    local h = Preset.hex(i)
    return tonumber(h:sub(1, 2), 16) / 255,
           tonumber(h:sub(3, 4), 16) / 255,
           tonumber(h:sub(5, 6), 16) / 255
  end

  local w, h = imageData:getDimensions()
  local trocados = 0
  for quadro, m in pairs(folha.measured) do
    local y0 = quadro * 16
    if y0 + 15 < h then
      for ly = 0, 15 do
        local regiao
        if m.footSplit and ly >= m.footSplit then regiao = "feet"
        elseif capOk[quadro] and m.lightFreeBottom and ly <= m.lightFreeBottom
          then regiao = "hair"
        elseif m.top and ly >= m.top and ly <= m.bottom then regiao = "body" end
        local escolha = regiao and p.tones[regiao]
        if escolha then
          local r, g, b = hexPara(escolha)
          for lx = 0, w - 1 do
            local _, _, _, a = imageData:getPixel(lx, y0 + ly)
            -- OPAQUE PIXELS ONLY. Writing colour into a transparent pixel is
            -- how a recolour quietly grows the silhouette.
            if a > 0 then
              imageData:setPixel(lx, y0 + ly, r, g, b, a)
              trocados = trocados + 1
            end
          end
        end
      end
    end
  end
  if trocados == 0 then
    return nil, "the preset matched no rows, so it would render identically to "
      .. "the original and the comparison would prove nothing"
  end
  return trocados
end

-- A PART STACK, BUILT FROM THE PLAYER'S OWN SHEETS (roadmap T2.2).
--
-- Copies the measured rows of a region out of a DONOR sheet and into the base
-- one. Every pixel written came from the player's ROM, so the provenance metric
-- still reports artist pixels and the authored count stays zero: this is
-- recombination, not authorship, and it is the only version of a part picker
-- that does not break the mod's core promise.
--
-- WHY THE SEAM IS MEASURED AND NOT JUDGED. Donor sheets have different
-- silhouettes, so a hair region from a wider head leaves a step where it meets
-- the base body. Whether a given step looks wrong is Kim's call and not a
-- gate's, so this reports the largest width jump at a seam as a NUMBER and
-- refuses nothing on those grounds. What it does refuse is the case with no
-- taste in it at all: a donor that cannot supply the region.
local function aplicaPartes(imageData, spec, sheetName, dirSprites)
  local Preset = dofile("mods/voxel_characters/authored/preset.lua")
  local base = dofile("mods/voxel_characters/authored/sheets/" .. sheetName .. ".lua")
  if not (base and base.measured) then
    return nil, sheetName .. " ships no measured bounds, so a region has no rows"
  end
  local capOk = {}
  for _, q in ipairs(base.hairFrames or {}) do capOk[q] = true end

  local maiorSalto, trocados = 0, 0
  for par in spec:gmatch("[^,]+") do
    local regiao, doador = par:match("^%s*(%w+)%s*:%s*([%w_]+)%s*$")
    if not regiao then return nil, "unreadable part spec: " .. par end
    if regiao == "head" then
      return nil, "this project has no measured head boundary; see T2.1 slice 2"
    end
    local okD, dImg = pcall(loadImageData, dirSprites .. doador .. ".png")
    if not okD then return nil, "no donor sheet at " .. doador end
    local dw, dh = dImg:getDimensions()
    local w, h = imageData:getDimensions()
    if dw ~= w then
      return nil, string.format("%s is %d wide and %s is %d; a part swap needs "
        .. "the same cell width", doador, dw, sheetName, w)
    end
    for quadro, m in pairs(base.measured) do
      local y0 = quadro * 16
      if y0 + 15 < h and y0 + 15 < dh then
        for ly = 0, 15 do
          local aqui
          if m.footSplit and ly >= m.footSplit then aqui = "feet"
          elseif capOk[quadro] and m.lightFreeBottom
            and ly <= m.lightFreeBottom then aqui = "hair"
          elseif m.top and ly >= m.top and ly <= m.bottom then aqui = "body" end
          if aqui == regiao then
            local largAntes, largDepois = 0, 0
            for lx = 0, w - 1 do
              local _, _, _, a = imageData:getPixel(lx, y0 + ly)
              if a > 0 then largAntes = largAntes + 1 end
              local r, g, b, da = dImg:getPixel(lx, y0 + ly)
              imageData:setPixel(lx, y0 + ly, r, g, b, da)
              if da > 0 then largDepois = largDepois + 1 end
            end
            trocados = trocados + 1
            local salto = math.abs(largDepois - largAntes)
            if salto > maiorSalto then maiorSalto = salto end
          end
        end
      end
    end
  end
  if trocados == 0 then
    return nil, "the part spec matched no rows, so nothing was composed"
  end
  return trocados, maiorSalto
end

local function makeVoxelHandle(imageData)
  local modules = {}
  local V = {}
  local original = function(def, frame)
    return { original = true, def = def, frame = frame }
  end
  function V.require(name)
    if modules[name] then return modules[name] end
    if name == "Voxel3D" then
      modules[name] = {
        FORMAT = {
          { "VertexPosition", "float", 3 },
          { "VertexTexCoord", "float", 2 },
          { "VertexShade", "float", 1 },
        },
        -- Mirrors Voxel3D.lua:412-420 statement for statement. The test
        -- suite's stub packs these into two multiple assignments, which in
        -- LuaJIT leaves holes (1 2 3 nil nil nil 7 ...) because `#map` is
        -- resolved before the assignments land. No test asserts on the map,
        -- so that never surfaced.
        pushQuad = function(map, n)
          local b = n * 4
          map[#map + 1] = b + 1
          map[#map + 1] = b + 2
          map[#map + 1] = b + 3
          map[#map + 1] = b + 1
          map[#map + 1] = b + 3
          map[#map + 1] = b + 4
        end,
        newMesh = function(verts, map)
          if #verts == 0 then return nil end
          local copy = {}
          for i, v in ipairs(verts) do
            copy[i] = { v[1], v[2], v[3], v[4], v[5], v[6] }
          end
          local mapCopy = {}
          for i, n in ipairs(map or {}) do mapCopy[i] = n end
          return {
            verts = copy,
            map = mapCopy,
            -- The mod applies the blink with pcall(mesh.setVertex, ...).
            -- Without this method on the stub the call fails silently and the
            -- harness never sees any blink, which looks like the feature not
            -- working. Two forms, like LOVE's Mesh: a table of attributes, or
            -- the loose attributes. The mod tries the table form first and
            -- only falls back to the loose one if it fails, so a stub that
            -- accepts anything stores the TABLE inside the vertex and the
            -- error shows up far from here, in whoever does arithmetic with
            -- the position.
            setVertex = function(self, i, a, b, c, d, e, f)
              if type(i) ~= "number" or i < 1 or i > #self.verts then
                error("setVertex: indice fora da faixa", 0)
              end
              if type(a) == "table" then
                self.verts[i] = { a[1], a[2], a[3], a[4], a[5], a[6] }
              else
                self.verts[i] = { a, b, c, d, e, f }
              end
            end,
            setVertexMap = function(self, m) self.map = m end,
            setTexture = function(self, tex) self.texture = tex end,
            release = function(self) self.released = true end,
          }
        end,
      }

      -- THE DRAW CHANNEL, opt-in (roadmap T1.1).
      --
      -- This stub deliberately had no `draw`, and that is why the laboratory
      -- is blind to every option living in the model matrix: the mod asks
      -- `probeCapabilities` whether Voxel3D.draw exists, finds it does not,
      -- and never installs its draw wrap. No wrap, no BREATH, no SWAY, no
      -- MOTION LAG, no ATTENTION, no PART LAG.
      --
      -- OPT-IN ON PURPOSE, and this is the part that protects the ruler.
      -- Handing every harness mode a draw channel would change what the mod
      -- installs in EVERY measurement this project trusts, including the IoU
      -- and provenance numbers the ruler asserts. The lab asks for it; nothing
      -- else does; and the ruler's output has to come out identical either way,
      -- which is a claim to verify rather than assume.
      --
      -- It records instead of rendering. The caller passes the synthetic host
      -- matrix from tools/render/host_matrix.lua and reads back what the mod's
      -- wrap made of it. That way the preview runs the mod's real transform
      -- code rather than a second copy of the algebra, which is the mistake
      -- this file already avoids everywhere else.
      if opts.labmotion == "1" then
        modules[name].drawCalls = {}
        modules[name].draw = function(mesh, texture, model, pull, sunModel)
          local calls = modules["Voxel3D"].drawCalls
          calls[#calls + 1] = {
            mesh = mesh, texture = texture, model = model,
            pull = pull, sunModel = sunModel,
          }
        end
      end
    elseif name == "ImageCache" then
      modules[name] = { get = function() return imageData end }
    elseif name == "SpriteBillboards" then
      modules[name] = { mesh = original, shadowQuad = original }
    elseif name == "VoxelState" then
      modules[name] = { angle = math.pi / 2 }
    elseif name == "VoxelScene" then
      -- pi/2 pins leanCorrection() to zero, so the geometry arrives upright
      -- and this harness owns the camera outright.
      modules[name] = { spriteLean = math.pi / 2 }
    elseif name == "FirstPerson" then
      modules[name] = { cardBlend = function() return 0 end }
    else
      error("unexpected module " .. tostring(name))
    end
    return modules[name]
  end
  return { id = "DRAMATIC_SHAPE", version = "1.5.0", exports = { lib = V } }
end

local function makeMod(handle, stored)
  local schema, rows, events = nil, {}, {}
  local function noop() end
  local mod = {
    id = "voxel_characters",
    version = "0.0.0",
    path = "mods/voxel_characters",
    options = {},
    hooks = {},
    events = {},
    log = { info = noop, warn = noop, error = noop },
  }
  function mod.options:define(s) schema = s; mod._schema = s end
  function mod.options:get(key)
    if stored and stored[key] ~= nil then return stored[key] end
    for _, row in ipairs(schema or {}) do
      if row.key == key then return row.default end
    end
  end
  function mod.hooks:wrap(name, fn) rows[name] = fn end
  function mod.events:on(name, fn) events[name] = fn end
  function mod.find(id)
    if id == "DRAMATIC_SHAPE" then return handle end
  end
  mod._rows, mod._events = rows, events
  return mod
end

-- The original flat card, built here rather than through the mod, so a sheet
-- can put "what the Voxel Mod draws today" next to "what we draw instead".
-- Without it a misread of the sprite layout would look like a geometry defect.
local function flatCard(imageData, frames, frame)
  local sheetW, sheetH = imageData:getDimensions()
  local cellH = sheetH / frames
  local u0, u1 = 0, 1
  -- Y up, matching the mod: buildSlabMesh emits `lowY - ly`, so the sprite's
  -- bottom row sits at y = 0 and the sheet's v runs the other way.
  local vTop, vBottom = frame * cellH / sheetH, (frame + 1) * cellH / sheetH
  return {
    verts = {
      { 0, 0, 0, u0, vBottom, 1 },
      { sheetW, 0, 0, u1, vBottom, 1 },
      { sheetW, cellH, 0, u1, vTop, 1 },
      { 0, cellH, 0, u0, vTop, 1 },
    },
    map = { 1, 2, 3, 1, 3, 4 },
  }
end

local LAST_HANDLE = nil
-- Kept for authprobe: the question is whether the MOD resolves its authored
-- sheets from in here, and only the mod can answer that.
local LAST_MOD = nil
local LABMOTION_DITO = false

local function buildGeometry(imageData, def, frame, shape, depth, sideColor)
  package.loaded["src.render.Assets"] = nil
  package.loaded["src.mods.Semver"] = nil
  local handle = makeVoxelHandle(imageData)
  -- Kept so the laboratory can reach the SAME host instance the mesh was built
  -- under, and therefore the same wrapped Voxel3D.draw. A fresh handle would
  -- have a fresh mod with fresh life state, and the preview would restart its
  -- animation on every frame.
  LAST_HANDLE = handle
  local stored = {
    depth = depth, shape = shape, side_color = sideColor,
    ground_shade = opts.ground ~= "" and opts.ground or nil,
    blink = opts.blink ~= "" and "on" or nil,
    top_edge = opts.topedge ~= "" and opts.topedge or nil,
  }
  -- Generic mod option pass-through: `opt=key:value,key:value`.
  --
  -- Before this, every new mod option required editing this file, and one
  -- implementation round went without visual measurement precisely because
  -- the new option had no way to reach here and the implementer was
  -- forbidden from touching the ruler. A tool that needs to be edited for
  -- every feature is not a tool, it is a step.
  --
  -- A numeric value is converted, because the mod stores some options as
  -- number and others as string (FRONT_SHAPE_VALUES = { "off", 0.12, ... })
  -- and passing "0.12" where it expects 0.12 falls back to the default
  -- without warning. An unknown key must NOT pass silently: a typo turns into
  -- "I measured with the option off and did not notice", which is exactly the
  -- mistake I made passing `low` where the mod stores 0.12. Validation runs
  -- after the mod registers, because only then does the schema exist.
  local pedidas = {}
  for par in tostring(opts.opt):gmatch("[^,]+") do
    local chave, valor = par:match("^%s*([%w_]+)%s*:%s*(.-)%s*$")
    if chave then
      stored[chave] = tonumber(valor) or valor
      pedidas[#pedidas + 1] = chave
    else
      print("OPCAO MAL FORMADA, esperava chave:valor e veio: " .. tostring(par))
      love.event.quit(2)
    end
  end
  local mod = makeMod(handle, stored)
  LAST_MOD = mod
  -- The chunk is compiled ONCE and re-executed per build. Before this it
  -- reparsed 2800 lines for every mesh, which nobody noticed with twenty
  -- cells and which dominates the cost when the laboratory builds hundreds
  -- to find out which options touch the geometry. Re-executing is what
  -- matters: every execution returns a fresh mod, with its own state.
  local Voxel3D = handle.exports.lib.require("Voxel3D")
  local drawAntes = Voxel3D.draw
  MOD_CHUNK = MOD_CHUNK or assert(loadfile(MAIN_PATH))
  MOD_CHUNK(mod)

  -- T1.1: DID THE WRAP ACTUALLY INSTALL?
  --
  -- Asked out loud because the obvious evidence is worthless here. With the
  -- draw channel added, a still render comes out byte-identical to one without
  -- it, and that is equally consistent with "the wrap installed and changed
  -- nothing on a static frame" and with "the wrap never installed at all". A
  -- bridge to nowhere looks exactly like a bridge.
  --
  -- So the stub's own function is remembered before the mod loads, and
  -- compared after. If the mod replaced it, the draw channel is live and the
  -- matrix-only options exist in here. If it did not, say so loudly rather
  -- than let a later preview quietly show nothing.
  -- ONCE, not once per build. The laboratory reloads the mod for every mesh it
  -- constructs, and classifying the options builds hundreds: the first version
  -- of this printed 2799 identical lines and buried everything else in the log,
  -- which is its own kind of useless. The fact is worth stating exactly once.
  if opts.labmotion == "1" and not LABMOTION_DITO then
    LABMOTION_DITO = true
    if Voxel3D.draw and Voxel3D.draw ~= drawAntes then
      print("LABMOTION: the mod wrapped Voxel3D.draw, the life channel is live")
    else
      print("LABMOTION FAILED: the mod did NOT wrap Voxel3D.draw, so nothing "
        .. "matrix-based can be previewed. Check probeCapabilities.")
    end
  end
  LAB_SCHEMA = mod._schema or LAB_SCHEMA
  if #pedidas > 0 then
    local conhecidas = {}
    for _, row in ipairs(mod._schema or {}) do
      if row.key then conhecidas[row.key] = true end
    end
    for _, chave in ipairs(pedidas) do
      if not conhecidas[chave] then
        print("UNKNOWN OPTION: " .. chave ..
          "  (o mod nao define essa chave; a medicao sairia com o padrao " ..
          "e voce nao notaria)")
        love.event.quit(2)
      end
    end
  end
  local SpriteBillboards = handle.exports.lib.require("SpriteBillboards")
  local mesh
  local mesh = SpriteBillboards.mesh(def, frame)

  -- Searches for the instant the blink closes, without replicating the mod's
  -- phase formula, which would be testing the implementation against itself.
  -- The mesh is cached and mutated in place, so calling again with a
  -- different clock is cheap.
  if opts.blinkscan == "1" and mesh and mesh.verts then
    local realTime = love.timer.getTime
    local function uvSig(mm)
      local t = {}
      for i = 1, #mm.verts do
        local v = mm.verts[i]
        t[i] = string.format("%.5f_%.5f", v[4] or -1, v[5] or -1)
      end
      return table.concat(t, "|")
    end
    love.timer.getTime = function() return 0 end
    local open = uvSig(SpriteBillboards.mesh(def, frame))
    local hit
    for step = 1, 1000 do
      local t = step * 0.01
      love.timer.getTime = function() return t end
      if uvSig(SpriteBillboards.mesh(def, frame)) ~= open then hit = t break end
    end
    love.timer.getTime = realTime
    print(hit and string.format("BLINKSCAN closes at t=%.2f s", hit)
               or "BLINKSCAN does not close in 10 s")
  end

  if mesh and mesh.original then
    return nil, "fell back to the flat card"
  end
  return mesh
end

--------------------------------------------------------------------------
-- camera
--
-- Vertices arrive in sprite-pixel space: x right, y down, z depth. They are
-- transformed here rather than in a shader so the projection is inspectable
-- from Lua and cannot silently disagree with a matrix upload convention.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- provenance
--
-- Every visible pixel came from one of five surfaces, and only two of them
-- carry the artist's pixels. Front and back sample the original sprite; side,
-- top and bottom are invented by this mod. A metric built on RGB cannot tell
-- them apart, because all five draw from the same four-tone palette. This
-- classifies per quad instead.
--
-- Classification is GEOMETRIC, from the quad's winding, verified statement by
-- statement against both builders (main.lua:637-651 for SLAB, :955-978 for
-- CARVED). Both agree:
--
--   +Z front    -Z back    +/-X side    -Y top    +Y bottom
--
-- The Y signs read backwards and that is fine: what matters is that they are
-- consistent and derived from geometry, not from OBJ_SHADE. Per-vertex ambient
-- occlusion would make the shade channel useless as a label, and AO is the
-- next thing we want to try.
--------------------------------------------------------------------------

local KINDS = { "front", "back", "side", "top", "bottom", "side_e", "side_w" }
-- Provenance only distinguishes art from invented surface, so the two sides
-- count as one. The separation exists for shading, not for the metric.
local PROV_KIND = { side_e = "side", side_w = "side" }
-- Host's Voxel3D.FACE_SHADE, the value each face of the WORLD receives.
local HOST_SHADE = {
  front = 0.90, back = 0.68, top = 1.00, bottom = 0.55,
  side_e = 0.84, side_w = 0.72,
}
local SHADE_OVERRIDE = nil
local KIND_INDEX = {}
for i, k in ipairs(KINDS) do KIND_INDEX[k] = i end

-- Original art versus surface this mod invented.
local IS_ART = { front = true, back = true }

-- buildCarvedMesh rotates the whole mesh per role about the vertical axis
-- (main.lua:920-932): role 1 is a half turn, role 2 a quarter turn. Undoing it
-- puts every mesh back in one frame of reference before the normal is read.
local ROLE_TURN = { [0] = 0, [1] = math.pi, [2] = math.pi / 2 }

local function classifyQuad(v1, v2, v3, turn)
  local e1x, e1y, e1z = v2[1] - v1[1], v2[2] - v1[2], v2[3] - v1[3]
  local e2x, e2y, e2z = v3[1] - v1[1], v3[2] - v1[2], v3[3] - v1[3]
  local nx = e1y * e2z - e1z * e2y
  local ny = e1z * e2x - e1x * e2z
  local nz = e1x * e2y - e1y * e2x
  if turn and turn ~= 0 then
    local c, s = math.cos(-turn), math.sin(-turn)
    nx, nz = nx * c - nz * s, nx * s + nz * c
  end
  local ax, ay, az = math.abs(nx), math.abs(ny), math.abs(nz)
  if ay >= ax and ay >= az then
    return ny < 0 and "top" or "bottom"
  elseif az >= ax then
    return nz > 0 and "front" or "back"
  end
  -- East and west kept separate. The mod today paints both with a single
  -- value, and the world around it uses 0.84 against 0.72: the host's light
  -- comes from the southeast and the two faces of a block do not receive it
  -- equally.
  return nx > 0 and "side_e" or "side_w"
end

-- Independent second opinion, from the shade constants in main.lua:44. It
-- cannot separate front from top (both 1.0), so it only ever contradicts the
-- geometry on the other three. A disagreement means one of the two readings is
-- stale, which is exactly what should stop a run rather than skew a metric.
local SHADE_KIND = { [0.68] = "back", [0.78] = "side", [0.55] = "bottom" }

local function classifyMesh(mesh, role)
  local turn = ROLE_TURN[role or 0] or 0
  local kinds, counts, conflicts = {}, {}, 0
  for _, k in ipairs(KINDS) do counts[k] = 0 end
  for i = 1, #mesh.verts, 4 do
    local v1, v2, v3 = mesh.verts[i], mesh.verts[i + 1], mesh.verts[i + 2]
    local kind = classifyQuad(v1, v2, v3, turn)
    local expected = SHADE_KIND[v1[6]]
    if expected and expected ~= kind then conflicts = conflicts + 1 end
    kinds[(i - 1) / 4 + 1] = kind
    counts[kind] = counts[kind] + 1
  end
  return kinds, counts, conflicts
end


local function bounds(verts)
  local b = {
    minX = math.huge, maxX = -math.huge,
    minY = math.huge, maxY = -math.huge,
    minZ = math.huge, maxZ = -math.huge,
  }
  for _, v in ipairs(verts) do
    b.minX, b.maxX = math.min(b.minX, v[1]), math.max(b.maxX, v[1])
    b.minY, b.maxY = math.min(b.minY, v[2]), math.max(b.maxY, v[2])
    b.minZ, b.maxZ = math.min(b.minZ, v[3]), math.max(b.maxZ, v[3])
  end
  return b
end

-- Model units of vertical view. A Gen 1 sprite cell is 16 px tall, so this
-- leaves margin for the pitch foreshortening without rescaling per cell:
-- every cell in a sheet must be measurable against every other one.
local VIEW_UNITS = 22

local function project(verts, cam)
  local out = {}
  local cy, cs = math.cos(cam.yaw), math.sin(cam.yaw)
  local cp, sp = math.cos(cam.pitch), math.sin(cam.pitch)
  for i, v in ipairs(verts) do
    local x, y, z = v[1] - cam.cx, v[2] - cam.cy, v[3] - cam.cz
    local rx = x * cy - z * cs
    local rz = x * cs + z * cy
    local ry2 = y * cp - rz * sp
    local rz2 = y * sp + rz * cp
    local px = cam.screenX + rx * cam.scale
    local py = cam.screenY - ry2 * cam.scale  -- model Y is up, screen Y is down
    -- Negated: the mod puts the front face at z = 0 and extrudes toward
    -- negative z, so without this the "less" depth test keeps the BACK of the
    -- slab. That renders the sprite art at OBJ_SHADE.back (0.68) and reads as
    -- a colour bug in the mod, which is what it looked like until FLAT and
    -- SLAB were put side by side at yaw 0.
    -- This shader returns clip space untouched, bypassing LOVE's transform, so
    -- nothing compensates for a canvas rendering bottom up. Without the flip
    -- the provenance pass is vertically mirrored against the visible one and
    -- every row is scored against a different row's pixels.
    local ndcY = 1 - py / cam.height * 2
    if cam.flipY then ndcY = -ndcY end
    out[i] = {
      px / cam.width * 2 - 1,
      ndcY,
      math.max(-0.999, math.min(0.999, -rz2 / cam.depthRange)),
      v[4], v[5], v[6],
    }
  end
  return out
end

-- Same rotation as project(), stopping at screen pixels instead of clip
-- space. project()'s output only means anything to the custom mesh shader,
-- which bypasses LOVE's own transform; ordinary 2D calls (love.graphics.line,
-- .polygon) read the normal pixel-space transform, so the laboratory's region
-- overlay (roadmap item 11) needs this form to draw a cap's row as a plain
-- line over the character.
local function projectScreen(verts, cam)
  local out = {}
  local cy, cs = math.cos(cam.yaw), math.sin(cam.yaw)
  local cp, sp = math.cos(cam.pitch), math.sin(cam.pitch)
  for i, v in ipairs(verts) do
    local x, y, z = v[1] - cam.cx, v[2] - cam.cy, v[3] - cam.cz
    local rx = x * cy - z * cs
    local rz = x * cs + z * cy
    local ry2 = y * cp - rz * sp
    out[i] = {
      cam.screenX + rx * cam.scale,
      cam.screenY - ry2 * cam.scale,
    }
  end
  return out
end

--------------------------------------------------------------------------
-- render
--------------------------------------------------------------------------

-- The generated sheets are the Game Boy's four shades as grey (255/170/85/0);
-- the engine colourises at draw time. Doing the same four-entry lookup here is
-- what makes a render comparable to a screenshot instead of to a mask.
local SHADER = [[
varying float vShade;
#ifdef VERTEX
attribute float VertexShade;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vShade = VertexShade;
  return vertex_position;
}
#endif
#ifdef PIXEL
uniform vec3 pal0;
uniform vec3 pal1;
uniform vec3 pal2;
uniform vec3 pal3;
// When set, vShade carries a surface class instead of a light factor and the
// pass paints flat identity colours. Alpha discard still runs, so the
// silhouette of the provenance pass matches the visible one exactly.
uniform float provenance;
// Quando ligado, vShade carrega a celula de origem da face de topo,
// codificada como (lx + ly*16)/255, e o passe pinta isso em cinza. Serve para
// separar "a cor mudou" de "a superficie mudou de dono" entre duas poses.
uniform float cellid;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 t = Texel(tex, tc);
  if (t.a < 0.5) discard;
  if (cellid > 0.5) {
    if (vShade < 0.0) discard;
    return vec4(vShade, vShade, vShade, 1.0);
  }
  if (provenance > 0.5) {
    int k = int(vShade + 0.5);
    // Alpha rides the draw colour instead of a hardcoded 1.0, so the same
    // pass that backs computeMetrics can also be reused as a translucent
    // overlay on top of the textured character (laboratory region overlay,
    // roadmap item 11). computeMetrics always draws at alpha 1, so its
    // readback is unaffected.
    if (k == 1) return vec4(0.0, 1.0, 0.0, color.a);  // front, original art
    if (k == 2) return vec4(0.0, 0.5, 0.0, color.a);  // back, original art
    if (k == 3) return vec4(1.0, 0.0, 0.0, color.a);  // side, invented
    if (k == 4) return vec4(0.0, 0.0, 1.0, color.a);  // top, invented
    return vec4(1.0, 1.0, 0.0, color.a);              // bottom, invented
  }
  float g = t.r;
  vec3 c = pal3;
  if (g > 0.833) c = pal0;
  else if (g > 0.5) c = pal1;
  else if (g > 0.167) c = pal2;
  return vec4(c * vShade, 1.0);
}
#endif
]]

-- Game Boy OBJ palette for the player and most overworld people, taken from
-- the note in src/render/PaletteFX.lua:107.
local PALETTES = {
  obj = { { 1, 1, 1 }, { 1, 0.518, 0.518 }, { 0.580, 0.227, 0.227 }, { 0, 0, 0 } },
  grey = { { 1, 1, 1 }, { 0.667, 0.667, 0.667 }, { 0.333, 0.333, 0.333 }, { 0, 0, 0 } },
}

local state = {}

local function fail(msg)
  print("ERROR: " .. msg)
  love.event.quit(1)
end

-- ------------------------------------------------------------- selftest
--
-- The harness is this base's ruler, and for a long time nobody checked the
-- ruler. Ten defects in a single session were ITS OWN, passing themselves off
-- as mod defects: inverted depth sign, which made the art appear at the back
-- shade and read as a colour bug; pitch measured from the wrong end of the
-- ladder; Y-down against a Y-up mod; a canvas that renders bottom to top,
-- making every row get scored against another row's pixels; a bbox pivot
-- hiding misalignment; frame count fixed at 6; a stub without setVertex; a
-- stub accepting the wrong form of setVertex; and sampling too coarse for a
-- 0.12 s window.
--
-- Each one cost a full diagnostic cycle pointed at the wrong place. These
-- assertions run in seconds and fail in the right place.
local function selftest()
  local fails, checks = 0, 0
  local function check(ok, name, detail)
    checks = checks + 1
    if not ok then
      fails = fails + 1
      print("FAIL " .. name .. (detail and ("  " .. detail) or ""))
    end
  end

  local data = loadImageData(SPRITE_DIR .. "red.png")
  local sheetW, sheetH = data:getDimensions()

  -- 1. Frame count comes from height, the way the engine does it, never from a constant.
  check(math.floor(sheetH / 16) == 6, "frames vem da altura da folha",
        "red.png deu " .. tostring(sheetH / 16))

  -- 2. The stub's setVertex accepts BOTH forms of LOVE's Mesh. The mod tries
  --    the table form first; a permissive stub stores the table inside the
  --    vertex and the error shows up far away, in whoever does arithmetic
  --    with the position.
  local probe = makeVoxelHandle(data).exports.lib.require("Voxel3D")
    .newMesh({ { 1, 2, 3, 4, 5, 6 } }, { 1, 2, 3, 1, 3, 4 })
  probe:setVertex(1, { 9, 8, 7, 6, 5, 4 })
  check(probe.verts[1][1] == 9 and probe.verts[1][4] == 6,
        "setVertex aceita a forma de tabela")
  probe:setVertex(1, 1, 2, 3, 4, 5, 6)
  check(probe.verts[1][1] == 1 and probe.verts[1][4] == 4,
        "setVertex aceita a forma de escalares")

  -- 3. Axis convention: the mod emits Y up and the front at z = 0. If
  --    either one inverts, this catches it before it turns into a diagnostic.
  local def = { image = SPRITE_DIR .. "red.png", frames = 6 }
  local mesh = buildGeometry(data, def, 0, "slab", 3, "body")
  check(mesh ~= nil, "malha SLAB constroi")
  if mesh then
    local b = bounds(mesh.verts)
    check(b.maxZ == 0, "frente esta em z = 0", "maxZ=" .. tostring(b.maxZ))
    check(b.minZ < 0, "corpo extruda para z negativo",
          "minZ=" .. tostring(b.minZ))
    check(b.minY == 0, "pe do sprite esta em y = 0",
          "minY=" .. tostring(b.minY))
    -- face classification by winding, the basis of every provenance metric
    local kinds = classifyMesh(mesh, 0)
    local seen = {}
    for _, k in ipairs(kinds) do seen[k] = true end
    check(seen.front and seen.back and seen.top,
          "classificacao acha frente, tras e topo")
  end

  print(string.format("harness selftest: %d/%d", checks - fails, checks))
  return fails == 0
end

function love.load(argv)
  parseArgs(argv)
  -- FIRST, because it answers a question about the environment rather than
  -- about a render, and because at chunk scope `opts` has not been parsed yet:
  -- the first version of this probe sat above and silently never fired.
  if opts.authprobe == "1" then
    -- ONE QUESTION, and it is about the filesystem rather than about the mod:
    -- can a repo-relative `mod.path` be resolved from in here? LOVE resolves
    -- relative paths against the GAME directory, which for the harness is
    -- tools/render and for the real game is the repo root. The loader's own
    -- logic is already proved by the suite against a stubbed filesystem; what
    -- that cannot prove is the path, and a path that does not resolve would
    -- make AUTHORED REGIONS silently do nothing in every card and judge pair.
    -- Builds one mesh first, because the mod is loaded lazily and asking an
    -- unloaded mod what it can see answers nothing.
    local okImg, img = pcall(loadImageData,
      (opts.spritedir ~= "" and opts.spritedir or SPRITE_DIR) .. "/red.png")
    if okImg then
      pcall(buildGeometry, img, { image = "red.png", frames = 6 },
        0, "slab", 3, "body")
    end
    local caminho = "mods/voxel_characters/authored/sheets/red.lua"
    local viu = love.filesystem.getInfo and love.filesystem.getInfo(caminho)
    local direto = io.open(caminho, "r")
    if direto then direto:close() end
    local aqui = love.filesystem.getSource and love.filesystem.getSource()
    local raiz = tostring(aqui):gsub("/mods/voxel_characters/tools/render$", "")
    print(string.format("AUTHPROBE love=%s source=%s root=%s mount=%s fs=%s",
      tostring(love.getVersion and select(1, love.getVersion())),
      tostring(aqui), raiz, "n/a", viu and "FOUND" or "MISSING")
      .. "  io=" .. (direto and "FOUND" or "MISSING")
      .. "  mod=" .. (function()
        local m = LAST_MOD and LAST_MOD._authoredRegions
          and LAST_MOD._authoredRegions("red")
        if not m then return "NIL" end
        local n = 0; for _ in pairs(m) do n = n + 1 end
        return n .. " frames"
      end)())
    return love.event.quit()
  end
  if opts.selftest == "1" then
    local ok = selftest()
    return love.event.quit(ok and 0 or 1)
  end
  if opts.lab == "1" then return love.labsetup() end
  if opts.features ~= "" then return love.features() end
  -- Before any mesh is built: these parameters change geometry.
  if opts.shade == "host" then SHADE_OVERRIDE = HOST_SHADE end
  if tonumber(opts.aostrength) then AO.setAoStrength(tonumber(opts.aostrength)) end
  -- Freezes the clock before any mesh is built. The blink is a 0.12 s window
  -- in a period with a phase per sheet; instead of replicating the formula,
  -- which would be testing the implementation against itself, the gate
  -- renders a strip of instants and looks at which one closes the eye.
  if tonumber(opts.blinktime) then
    local t = tonumber(opts.blinktime)
    love.timer.getTime = function() return t end
  end
  AO.setRecessOverride(tonumber(opts.recess))
  AO.setOutlineFront(opts.outline == "front")
  if opts.depthmap ~= "" then
    local chunk = assert(loadfile(opts.depthmap), "depthmap ilegivel")
    AO.setDepthMap(chunk())
  end

  local sprites = splitList(opts.sprite)
  local shapes = splitList(opts.shapes)
  local frames = numbers(opts.frames)
  local yaws = numbers(opts.yaws)
  local cell = tonumber(opts.cell) or 220
  local depth = tonumber(opts.depth) or 3

  -- Every combination is one cell. Columns are yaw, so a row reads as one
  -- turntable; rows are (sprite, frame, shape), so a defect that only shows
  -- in one builder sits directly above the builder that does not have it.
  local pitches = {}
  if opts.pitch ~= "" then
    for _, p in ipairs(numbers(opts.pitch)) do
      pitches[#pitches + 1] = { deg = p, label = string.format("pitch %d", p) }
    end
  else
    for _, rung in ipairs(numbers(opts.rungs)) do
      pitches[#pitches + 1] = { deg = 90 - rung, label = "rung " .. rung }
    end
  end

  local rows = {}
  for _, sprite in ipairs(sprites) do
    local path = (opts.spritedir ~= "" and opts.spritedir or SPRITE_DIR)
      .. sprite .. ".png"
    local ok, data = pcall(loadImageData, path)
    if not ok then return fail("no sprite at " .. path) end
    if opts.parts ~= "" then
      local n, salto = aplicaPartes(data, opts.parts, sprite,
        (opts.spritedir ~= "" and opts.spritedir or SPRITE_DIR))
      if not n then return fail("parts: " .. tostring(salto)) end
      print(string.format("PARTS %s composed onto %s, %d row(s), widest seam "
        .. "step %d px", opts.parts, sprite, n, salto))
    end
    if opts.preset ~= "" then
      local n, err = aplicaPreset(data, opts.preset, sprite)
      if not n then return fail("preset: " .. tostring(err)) end
      print(string.format("PRESET %s applied to %s, %d texel(s) recoloured",
        opts.preset, sprite, n))
    end
    -- The engine derives frame count from sheet height, not from a constant
    -- (src/import/RomExtractor.lua:481, src/render/SpriteRenderer.lua:86).
    -- Hardcoding 6 turns nurse.png (16x48, three frames) into six 8px frames
    -- and boulder.png (16x16, one frame) into six 2px ones, which is precisely
    -- the three-frame carve path this mod added in v1.2.0.
    local sw, sh = data:getDimensions()
    local quadros = tonumber(opts.spriteframes)
      or math.max(1, math.floor(sh / 16))
    local def = { image = path, frames = quadros }
    local texture = love.graphics.newImage(data)
    texture:setFilter("nearest", "nearest")
    for _, frame in ipairs(frames) do
      for _, shape in ipairs(shapes) do
        local mesh, why
        local wantAO = shape:find("_ao") ~= nil
        shape = shape:gsub("_ao$", "")
        local reliefSolid
        if wantAO then end
        if shape == "flat" then
          mesh = flatCard(data, def.frames, frame)
        elseif shape == "sculpt" then
          mesh, reliefSolid = AO.sculptMesh(data, def.frames, frame, "naive")
        elseif shape == "sculptc" then
          mesh, reliefSolid = AO.sculptMesh(data, def.frames, frame, "contour")
        else
          mesh, why = buildGeometry(data, def, frame, shape, depth,
                                    opts.side_color)
        end
        local sheetW, sheetH = data:getDimensions()
        local occ = reliefSolid or ((shape == "slab")
          and AO.slabOccupancy(data, def.frames, frame, sheetW,
                            sheetH / def.frames, depth) or nil)
        -- Only the carved builders rotate per role; buildSlabMesh emits every
        -- frame in the same frame of reference (main.lua:608-613).
        local role = (shape == "carved" or shape == "carved_plus")
          and (frame % 3) or 0
        local kinds, quadKinds, conflicts
        if mesh then
          kinds, quadKinds, conflicts = classifyMesh(mesh, role)
          if conflicts > 0 then
            print(string.format(
              "WARNING %s f%d %s: %d quads where winding and OBJ_SHADE disagree",
              sprite, frame, shape, conflicts))
          end
        end
        for _, pitch in ipairs(pitches) do
          rows[#rows + 1] = {
            sprite = sprite, frame = frame, shape = shape,
            pitch = math.rad(pitch.deg), pitchLabel = pitch.label,
            mesh = mesh, why = why, texture = texture,
            cellW = sheetW, cellH = sheetH / def.frames,
            kinds = kinds, quadKinds = quadKinds, role = role, occ = occ,
            ao = wantAO,
            shapeLabel = shape:upper() .. (wantAO and "+AO" or ""),
          }
        end
      end
    end
  end
  if #rows == 0 then return fail("nothing to render") end

  local labelH = opts.label == "1" and 18 or 0
  local width = cell * #yaws
  local height = (cell + labelH) * #rows
  love.window.setMode(width, height, { depth = 24, vsync = 0 })

  state.rows, state.yaws, state.cell, state.labelH = rows, yaws, cell, labelH
  state.width, state.height = width, height
  state.ao = opts.ao == "1"
  state.shader = love.graphics.newShader(SHADER)
  local pal = PALETTES[opts.palette] or PALETTES.obj
  for i = 1, 4 do state.shader:send("pal" .. (i - 1), pal[i]) end
  state.bg = numbers(opts.bg)
  state.frames = 0

  local quads = 0
  for _, row in ipairs(rows) do
    if row.mesh then
      quads = quads + math.floor(#row.mesh.verts / 4)
      if row.quadKinds then
        local t = {}
        for _, k in ipairs(KINDS) do t[#t + 1] = k .. "=" .. row.quadKinds[k] end
        print("    quads por face: " .. table.concat(t, "  "))
      end
      local b = bounds(row.mesh.verts)
      print(string.format(
        "%s f%d %-12s quads=%4d  x[%.1f..%.1f] y[%.1f..%.1f] z[%.1f..%.1f] idx=%d",
        row.sprite, row.frame, row.shape, math.floor(#row.mesh.verts / 4),
        b.minX, b.maxX, b.minY, b.maxY, b.minZ, b.maxZ, #row.mesh.map))
    else
      print(string.format("%s f%d %-12s NO MESH (%s)",
        row.sprite, row.frame, row.shape, tostring(row.why)))
    end
  end
  print(string.format("cells=%d quads=%d canvas=%dx%d",
    #rows * #yaws, quads, width, height))
end

-- Pivot on the sprite CELL, and on z = 0, the plane the flat card occupies.
--
-- This used to pivot on each mesh's own bounding box, because until v1.3.0
-- the mod dropped the cell's empty padding and rebased geometry on the
-- opaque bounds. That made a cell pivot wrong and a bbox pivot merely
-- approximate: a sheet whose art is off centre inside its cell, like
-- snorlax, still read as misaligned against the card. Now that the mod
-- emits in cell coordinates on both axes, the cell is the shared frame of
-- reference and the comparison against FLAT is exact rather than indicative.
--
-- Extracted out of drawCell so the laboratory's region overlay (roadmap item
-- 11) can project its own points (the cap rows) through the EXACT camera
-- drawCell used for the character, instead of a second copy that could drift.
local function cellCamera(row, yaw, x, y, size, asProvenance)
  local b = bounds(row.mesh.verts)
  return {
    yaw = yaw, pitch = row.pitch,
    cx = (row.cellW or (b.minX + b.maxX)) / 2,
    cy = (row.cellH or (b.minY + b.maxY)) / 2,
    cz = 0,
    scale = size / VIEW_UNITS,
    screenX = x + size / 2,
    screenY = y + size / 2,
    width = state.width, height = state.height, flipY = asProvenance,
    -- generous so nothing clips; the depth test only needs ordering
    depthRange = math.max(64, (b.maxY - b.minY) * 2),
  }
end

local function drawCell(row, yaw, x, y, size, asProvenance, asCellId, asOverlay)
  if not row.mesh then return end
  -- TRAP 12, found by an agent that prototyped and checked, and that I
  -- reproduced: a DEEP shape overflows its own cell and invades the
  -- neighbouring one, contaminating its measurement. `red.png` on CARVED goes
  -- to z = -13 on a sprite 16 wide, and at a large `cell` the projection of
  -- that crosses the border. Measured: with `cell=220`, which is the
  -- DEFAULT, SLAB measures 73.4% alone and 70.7% in a contact sheet next to
  -- CARVED. At 140, 100, 80 and 60 it did not leak, which is worse than
  -- leaking always: the defect only showed up at the default, and disappeared
  -- as soon as someone tried to reproduce it with a smaller cell.
  --
  -- The scissor closes this by construction, for every measurement and every
  -- draw, instead of becoming one more rule of use someone has to remember.
  -- Every cell can only paint inside itself.
  local prevScissor = { love.graphics.getScissor() }
  love.graphics.setScissor(x, y, size, size)
  local cam = cellCamera(row, yaw, x, y, size, asProvenance)

  -- T1.1 slice 2: an optional MESH-SPACE transform, applied before projecting.
  --
  -- This is how the laboratory previews the options that live in the draw
  -- matrix. `row.lifeDelta` is not computed here and not computed anywhere in
  -- this harness: it is `H^-1 * M'`, the difference between the host matrix
  -- handed to the mod and the matrix the mod's own wrap returned. The algebra
  -- of breath, sway, lag, footfall and attention stays in main.lua, where it
  -- ships, so a preview cannot agree with itself and disagree with the game.
  --
  -- Nothing sets `row.lifeDelta` unless labmotion is on, so every existing
  -- measurement takes the same path it always took. Verified rather than
  -- asserted: the ruler passes with this present, and a render with the flag on
  -- is byte-identical to one with it off.
  local fonte = row.mesh.verts
  if row.lifeDelta then
    local movidos = {}
    for i = 1, #fonte do
      local v = fonte[i]
      local vx, vy, vz = HostMatrix.apply(row.lifeDelta, v[1], v[2], v[3])
      movidos[i] = { vx, vy, vz, v[4], v[5], v[6] }
    end
    fonte = movidos
  end
  local verts = project(fonte, cam)
  if SHADE_OVERRIDE and not asProvenance then
    for i = 1, #row.mesh.verts, 4 do
      local v = SHADE_OVERRIDE[row.kinds[(i - 1) / 4 + 1]]
      if v then
        for j = 0, 3 do verts[i + j][6] = v end
      end
    end
  end
  if (state.ao or row.ao) and row.occ and not asProvenance then
    local hist, n, sum, minf = {}, 0, 0, 1
    for i = 1, #row.mesh.verts, 4 do
      local f = AO.quadAO(row.mesh.verts, i, row.occ)
      for j = 0, 3 do
        verts[i + j][6] = verts[i + j][6] * f[j + 1]
        local bucket = math.floor(f[j + 1] * 20 + 0.5) / 20
        hist[bucket] = (hist[bucket] or 0) + 1
        n, sum = n + 1, sum + f[j + 1]
        if f[j + 1] < minf then minf = f[j + 1] end
      end
    end
    if not state.aoReported then
      state.aoReported = true
      local keys = {}
      for k in pairs(hist) do keys[#keys + 1] = k end
      table.sort(keys)
      local parts = {}
      for _, k in ipairs(keys) do
        parts[#parts + 1] = string.format("%.2f:%d(%.0f%%)", k, hist[k],
          hist[k] / n * 100)
      end
      print(string.format("AO em %d vertices  media %.3f  minimo %.3f",
        n, sum / n, minf))
      print("  distribuicao  " .. table.concat(parts, "  "))
    end
  end
  if asCellId then
    local cellBottom = (row.cellH or 16) - 1
    for i = 1, #row.mesh.verts, 4 do
      local kind = row.kinds[(i - 1) / 4 + 1]
      local val = -1
      if kind == "top" then
        local q = row.mesh.verts
        local minX = math.min(q[i][1], q[i+1][1], q[i+2][1], q[i+3][1])
        local qy = q[i][2]
        local lx = math.floor(minX + 0.001)
        local ly = cellBottom + 1 - math.floor(qy + 0.001)
        if lx >= 0 and lx < 16 and ly >= 0 and ly < 16 then
          val = (lx + ly * 16) / 255
        end
      end
      for j = 0, 3 do verts[i + j][6] = val end
    end
  end
  -- asOverlay reuses the provenance colour mapping (front/back/side/top/
  -- bottom) WITHOUT asProvenance's Y-flip, which only exists for the
  -- offscreen metrics canvas read back bottom-up. This is what lets the
  -- laboratory's region overlay (roadmap item 11) draw the same kind colours
  -- straight to the screen, translucent, on top of the textured character.
  if asProvenance or asOverlay then
    for i, v in ipairs(verts) do
      local k = row.kinds[math.floor((i - 1) / 4) + 1]
      v[6] = KIND_INDEX[PROV_KIND[k] or k]
    end
  end
  local mesh = love.graphics.newMesh(
    { { "VertexPosition", "float", 3 },
      { "VertexTexCoord", "float", 2 },
      { "VertexShade", "float", 1 } },
    verts, "triangles", "static")
  mesh:setVertexMap(row.mesh.map)
  mesh:setTexture(row.texture)
  love.graphics.draw(mesh)
  mesh:release()
  love.graphics.setScissor(unpack(prevScissor))
end

-- Wire up the Lab and Features modules with the state and helpers they need,
-- now that all of it exists: drawCell just above is the last piece either
-- one reads. LAB_SCHEMA is exposed as a getter rather than a value because
-- buildGeometry keeps reassigning it as the mod re-registers per build.
local ctx = {
  opts = opts,
  state = state,
  SPRITE_DIR = SPRITE_DIR,
  SHADER = SHADER,
  PALETTES = PALETTES,
  loadImageData = loadImageData,
  buildGeometry = buildGeometry,
  classifyMesh = classifyMesh,
  drawCell = drawCell,
  cellCamera = cellCamera,
  projectScreen = projectScreen,
  fail = fail,
  getLabSchema = function() return LAB_SCHEMA end,
  -- T1.1: the lab previews matrix-only options through the mod's own draw
  -- wrap. It needs the shared host matrix and a way to reach the draw channel;
  -- both are nil-safe when labmotion is off.
  HostMatrix = HostMatrix,
  motionOn = function() return opts.labmotion == "1" end,
  voxel3D = function() return LAST_HANDLE and
    LAST_HANDLE.exports.lib.require("Voxel3D") or nil end,
}
Lab.init(ctx)
Features.init(ctx)

-- Render the same sheet with identity colours instead of art, read it back,
-- and count. This is the fitness function: a number for how much of what the
-- player sees is the artist's work and how much is surface this mod made up.
local function computeMetrics(screen)
  local w, h = state.width, state.height
  local colour = love.graphics.newCanvas(w, h)
  local depth = love.graphics.newCanvas(w, h,
    { format = "depth24", readable = false })
  love.graphics.setCanvas({ colour, depthstencil = depth })
  love.graphics.clear(0, 0, 0, 0, true, true)
  love.graphics.setDepthMode("less", true)
  love.graphics.setShader(state.shader)
  state.shader:send("provenance", 1)
  -- Explicit and not inherited: the shader's provenance branch now scales
  -- alpha by the draw colour (so the laboratory overlay can be translucent),
  -- and this readback depends on every provenance pixel being fully opaque.
  love.graphics.setColor(1, 1, 1, 1)
  local cell, labelH = state.cell, state.labelH
  for r, row in ipairs(state.rows) do
    local y = (r - 1) * (cell + labelH) + labelH
    for c, yawDeg in ipairs(state.yaws) do
      drawCell(row, math.rad(yawDeg), (c - 1) * cell, y, cell, true)
    end
  end
  state.shader:send("provenance", 0)
  love.graphics.setShader()
  love.graphics.setDepthMode("always", false)
  love.graphics.setCanvas()

  local img = colour:newImageData()
  local function kindAt(r, g, b, a)
    if a < 0.5 then return nil end
    if g > 0.75 and r < 0.25 then return "front" end
    if g > 0.25 and r < 0.25 and b < 0.25 then return "back" end
    if r > 0.75 and g > 0.75 then return "bottom" end
    if r > 0.75 then return "side" end
    if b > 0.75 then return "top" end
    return nil
  end

  if opts.histogram == "1" then
    local seen = {}
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r, g, b, a = img:getPixel(x, y)
        local key = string.format("%.2f,%.2f,%.2f,%.2f", r, g, b, a)
        seen[key] = (seen[key] or 0) + 1
      end
    end
    local list = {}
    for k, v in pairs(seen) do list[#list + 1] = { k, v } end
    table.sort(list, function(p, q) return p[2] > q[2] end)
    print("provenance canvas colours:")
    for i = 1, math.min(#list, 10) do
      print(string.format("  %s  x%d", list[i][1], list[i][2]))
    end
  end

  -- Silhouette leak: pixels this mod draws that the original card for the SAME
  -- frame does not cover. At zero pitch and zero yaw the two silhouettes must
  -- agree, because the slab is built over the union of every walk frame and
  -- relies on the shader's alpha discard to clip each frame back down. A face
  -- whose UV resolves into another frame escapes that clip, and the report from
  -- the field is "all of Red's sprites appear at once while walking sideways".
  local flatAt = {}
  for r, row in ipairs(state.rows) do
    if row.shape == "flat" then
      flatAt[row.sprite .. "|" .. row.frame .. "|" .. row.pitchLabel] = r
    end
  end
  if next(flatAt) then
    print("")
    print("silhouette against the original card, same frame")
    print("  leak   drawn where the card is empty; must be 0 at yaw 0 pitch 0")
    print("  miss   card covers it, this mod does not")
    for r, row in ipairs(state.rows) do
      local fr = flatAt[row.sprite .. "|" .. row.frame .. "|" .. row.pitchLabel]
      if fr and fr ~= r then
        local yF = (fr - 1) * (cell + labelH) + labelH
        local yR = (r - 1) * (cell + labelH) + labelH
        for c, yawDeg in ipairs(state.yaws) do
          local x0 = (c - 1) * cell
          local leak, miss, both = 0, 0, 0
          for y = 0, cell - 1 do
            for x = 0, cell - 1 do
              local _, _, _, af = img:getPixel(x0 + x, yF + y)
              local _, _, _, ar = img:getPixel(x0 + x, yR + y)
              local inF, inR = af >= 0.5, ar >= 0.5
              if inR and not inF then leak = leak + 1
              elseif inF and not inR then miss = miss + 1
              elseif inF then both = both + 1 end
            end
          end
          local union = leak + miss + both
          print(string.format(
            "  %-11s %-9s yaw %2d   leak %5d   miss %5d   IoU %.3f",
            row.shape, row.pitchLabel, yawDeg, leak, miss,
            union > 0 and both / union or 0))
        end
      end
    end
  end

  -- Silhouette of every row against row 1. Two walk frames of the same builder
  -- must NOT have the same outline: if they do, the shell being drawn is the
  -- union of every pose rather than the pose being asked for.
  do
    local y1 = labelH
    print("")
    print("silhouette against row 1")
    for r = 2, #state.rows do
      local row = state.rows[r]
      local yR = (r - 1) * (cell + labelH) + labelH
      for c, yawDeg in ipairs(state.yaws) do
        local x0 = (c - 1) * cell
        local diff, both = 0, 0
        for y = 0, cell - 1 do
          for x = 0, cell - 1 do
            local _, _, _, a1 = img:getPixel(x0 + x, y1 + y)
            local _, _, _, a2 = img:getPixel(x0 + x, yR + y)
            local in1, in2 = a1 >= 0.5, a2 >= 0.5
            if in1 ~= in2 then diff = diff + 1
            elseif in1 then both = both + 1 end
          end
        end
        print(string.format("  row %d %-11s f%d yaw %2d   differing %5d   IoU %.4f",
          r, row.shape, row.frame, yawDeg, diff,
          (diff + both) > 0 and both / (diff + both) or 0))
      end
    end
  end

  -- Crosses provenance with the visible image: for each face kind, how much
  -- of it reaches the eye as the darkest tone. The Gen 1 outline is black and
  -- surrounds the whole figure; if it dominates the invented faces, the
  -- character reads as a dark block no matter how much volume it has.
  if screen then
    print("")
    print("share of each face kind that reaches the eye as the darkest tone")
    for r, row in ipairs(state.rows) do
      local y0 = (r - 1) * (cell + labelH) + labelH
      for c, yawDeg in ipairs(state.yaws) do
        local x0 = (c - 1) * cell
        local dark, tot, darkAll, totAll = {}, {}, 0, 0
        for _, k in ipairs(KINDS) do dark[k], tot[k] = 0, 0 end
        for y = 0, cell - 1 do
          for x = 0, cell - 1 do
            local kind = kindAt(img:getPixel(x0 + x, y0 + y))
            if kind then
              local sr, sg, sb = screen:getPixel(x0 + x, y0 + y)
              local isDark = (sr + sg + sb) / 3 < 0.12
              tot[kind] = tot[kind] + 1
              totAll = totAll + 1
              if isDark then
                dark[kind] = dark[kind] + 1
                darkAll = darkAll + 1
              end
            end
          end
        end
        if totAll > 0 then
          local parts = {}
          for _, k in ipairs({ "front", "top", "side", "bottom" }) do
            if tot[k] > 0 then
              parts[#parts + 1] = string.format("%s %.0f%%", k,
                dark[k] / tot[k] * 100)
            end
          end
          print(string.format("  %-11s yaw %2d   preto total %.1f%%   (%s)",
            row.shape, yawDeg, darkAll / totAll * 100,
            table.concat(parts, "  ")))
        end
      end
    end
  end

  -- Identity of the cell that generated each top pixel. Separates "the
  -- colour changed" from "the surface changed owner", which are different defects.
  if screen and #state.rows > 1 then
    local cbuf = love.graphics.newCanvas(w, h)
    local cdep = love.graphics.newCanvas(w, h, { format = "depth24", readable = false })
    love.graphics.setCanvas({ cbuf, depthstencil = cdep })
    love.graphics.clear(0, 0, 0, 0, true, true)
    love.graphics.setDepthMode("less", true)
    love.graphics.setShader(state.shader)
    state.shader:send("cellid", 1)
    for r, row in ipairs(state.rows) do
      local y = (r - 1) * (cell + labelH) + labelH
      for c, yawDeg in ipairs(state.yaws) do
        drawCell(row, math.rad(yawDeg), (c - 1) * cell, y, cell, false, true)
      end
    end
    state.shader:send("cellid", 0)
    love.graphics.setShader()
    love.graphics.setDepthMode("always", false)
    love.graphics.setCanvas()
    local cimg = cbuf:newImageData()
    print("")
    print("origem da face de topo, linha 1 contra as outras")
    local y1 = labelH
    for r = 2, #state.rows do
      local row = state.rows[r]
      local yR = (r - 1) * (cell + labelH) + labelH
      for c, yawDeg in ipairs(state.yaws) do
        local x0 = (c - 1) * cell
        local both, sameCell, diffCell = 0, 0, 0
        for y = 0, cell - 1 do
          for x = 0, cell - 1 do
            local _, _, _, a1 = cimg:getPixel(x0 + x, y1 + y)
            local _, _, _, a2 = cimg:getPixel(x0 + x, yR + y)
            if a1 >= 0.5 and a2 >= 0.5 then
              both = both + 1
              local v1 = select(1, cimg:getPixel(x0 + x, y1 + y))
              local v2 = select(1, cimg:getPixel(x0 + x, yR + y))
              if math.abs(v1 - v2) < 0.002 then sameCell = sameCell + 1
              else diffCell = diffCell + 1 end
            end
          end
        end
        if both > 0 then
          print(string.format(
            "  f%d yaw %2d   topo em ambas %5d   mesma celula %5d   celula diferente %5d (%.1f%%)",
            row.frame, yawDeg, both, sameCell, diffCell, diffCell / both * 100))
        end
      end
    end
    cbuf:release(); cdep:release()
  end

  -- Colour stability of the top face between poses. Angelus's report is
  -- "the top of the head flickers while walking": if the SAME screen
  -- position is a top face in two poses and the colour changes, that is the
  -- flicker, measured.
  if screen and #state.rows > 1 then
    print("")
    print("cor da face de topo na mesma posicao, linha 1 contra as outras")
    local y1 = labelH
    for r = 2, #state.rows do
      local row = state.rows[r]
      local yR = (r - 1) * (cell + labelH) + labelH
      for c, yawDeg in ipairs(state.yaws) do
        local x0 = (c - 1) * cell
        local both, differ = 0, 0
        for y = 0, cell - 1 do
          for x = 0, cell - 1 do
            local k1 = kindAt(img:getPixel(x0 + x, y1 + y))
            local k2 = kindAt(img:getPixel(x0 + x, yR + y))
            if k1 == "top" and k2 == "top" then
              both = both + 1
              local a1, b1, c1 = screen:getPixel(x0 + x, y1 + y)
              local a2, b2, c2 = screen:getPixel(x0 + x, yR + y)
              if math.abs(a1 - a2) + math.abs(b1 - b2) + math.abs(c1 - c2) > 0.06 then
                differ = differ + 1
              end
            end
          end
        end
        if both > 0 then
          print(string.format(
            "  %-11s f%d yaw %2d   topo em ambas %5d   cor diferente %5d  (%.1f%%)",
            row.shape, row.frame, yawDeg, both, differ, differ / both * 100))
        end
      end
    end
  end

  -- FACE-CLASS BOUNDARY DENSITY, which is what Z-fighting looks like when you
  -- cannot watch the screen flicker (from the Kanto HD-Voxel spec's item 7).
  --
  -- Two coplanar surfaces competing for the depth buffer do not produce a clean
  -- wrong answer, they produce an ALTERNATING one: neighbouring pixels get
  -- different faces, sprayed across a region that should belong to one. The
  -- provenance pass already labels every pixel with the face it came from, so
  -- the signature is measurable without a human watching a spin: count how
  -- often two adjacent drawn pixels disagree about their face, as a share of
  -- drawn pixels.
  --
  -- Clean geometry puts those disagreements only along real edges, so the number
  -- is small and moves smoothly as the camera turns. Z-fighting spikes it at the
  -- yaw where two faces become coplanar. The gate compares each yaw against the
  -- MEDIAN OF THE SWEEP rather than a fixed threshold, because the honest value
  -- depends on the shape, the cell size and how much silhouette is edge.
  print("")
  print("face boundary density per cell: adjacent drawn pixels that disagree")
  print("  about which face they came from, as a share of drawn pixels. A spike")
  print("  at one yaw is what Z-fighting looks like when it cannot be watched")
  for r, row in ipairs(state.rows) do
    local y0 = (r - 1) * (cell + labelH) + labelH
    for c, yawDeg in ipairs(state.yaws) do
      local x0 = (c - 1) * cell
      local desenhados, fronteiras = 0, 0
      for y = 0, cell - 1 do
        for x = 0, cell - 1 do
          local aqui = kindAt(img:getPixel(x0 + x, y0 + y))
          if aqui then
            desenhados = desenhados + 1
            -- Left and up only: every adjacent pair is then counted once.
            if x > 0 then
              local esq = kindAt(img:getPixel(x0 + x - 1, y0 + y))
              if esq and esq ~= aqui then fronteiras = fronteiras + 1 end
            end
            if y > 0 then
              local cima = kindAt(img:getPixel(x0 + x, y0 + y - 1))
              if cima and cima ~= aqui then fronteiras = fronteiras + 1 end
            end
          end
        end
      end
      if desenhados > 0 then
        print(string.format("  ZFIGHT %-11s %-9s yaw %3d   %6.2f%%   drawn %d",
          row.shape, row.pitchLabel, yawDeg, fronteiras / desenhados * 100,
          desenhados))
      end
    end
  end

  print("")
  print("provenance at the visible pixel level")
  print("  art%   share of drawn pixels sampling the original sprite art")
  print("  top%   share taken by upward faces, which carry no art at all")
  -- THE THIRD NUMBER, AND WHY IT IS PRINTED WHILE IT IS ALWAYS ZERO
  -- (roadmap T2.1). Provenance used to split two ways: the artist's pixels
  -- against surface this mod computed. An authored layer ships a third kind,
  -- pixels that came WITH THE MOD, and folding those into "invented" would let
  -- an art pack hide inside a number that already reads high.
  --
  -- It reads 0.0% on every line today because the mod ships no authored
  -- pixels, and it is printed anyway. A number that appears only once it is
  -- non-zero teaches nobody to look for it, and the first release that ships
  -- one authored texel is exactly the release where somebody should already
  -- know where to look. `tools/authored_gate.lua` holds the zero to its word.
  print("  auth%  share shipped WITH THE MOD, drawn by neither the artist nor")
  print("         the runtime. Zero until an authored layer ships pixels")
  for r, row in ipairs(state.rows) do
    local y0 = (r - 1) * (cell + labelH) + labelH
    for c, yawDeg in ipairs(state.yaws) do
      local x0 = (c - 1) * cell
      local n = {}
      for _, k in ipairs(KINDS) do n[k] = 0 end
      local drawn = 0
      for y = 0, cell - 1 do
        for x = 0, cell - 1 do
          local kind = kindAt(img:getPixel(x0 + x, y0 + y))
          if kind then n[kind] = n[kind] + 1; drawn = drawn + 1 end
        end
      end
      if drawn > 0 then
        local art = (n.front + n.back) / drawn * 100
        -- Authored pixels have no face class of their own yet, because none
        -- are drawn. When they are, they get their own `kindAt` label rather
        -- than being inferred, for the same reason the other five are
        -- geometric: a metric that guesses its own inputs is decoration.
        local auth = 0
        print(string.format(
          "  %-11s %-9s yaw %2d   art %5.1f%%   auth %5.1f%%   top %5.1f%%   side %5.1f%%   base %5.1f%%",
          row.shape, row.pitchLabel, yawDeg, art, auth, n.top / drawn * 100,
          n.side / drawn * 100, n.bottom / drawn * 100))
      end
    end
  end

  -- TONAL STRUCTURE, per face class.
  --
  -- The art% above is PURE provenance: it counts where the surface came
  -- from, and the pass that measures it reuses the shade channel to carry the
  -- face's class, so it is blind to lighting BY CONSTRUCTION. No shading
  -- option can move it, not even in principle. That left two features of
  -- this branch with no ruler at all, judged only by eye.
  --
  -- This measures something else: how much STRUCTURE exists in the drawn
  -- surface. A flat cap has a single tone level and zero amplitude. A
  -- stepped dome has three. It does not decide whether it looks good, and
  -- does not try to: that lesson was already paid for when an AI redraw
  -- satisfied every numeric constraint and delivered worse art. It serves to
  -- say WHAT CHANGED and to catch regressions.
  print("")
  print("estrutura tonal na superficie desenhada, por classe de face")
  print("  niveis  quantos tons distintos aparecem (chapado = 1)")
  print("  ampl    diferenca entre o tom mais claro e o mais escuro")
  print("  desvio  desvio medio em torno do tom medio da classe")
  -- `desvio` exists because `niveis` and `ampl` do NOT distinguish strengths.
  -- Measured by an adversarial review: FRONT SHAPE at 0.12, 0.17 and 0.22
  -- reported `niveis 7 ampl 0.596` on all THREE, while 2382 of 43600 pixels
  -- of the frame actually differed between the first and the last. In other
  -- words, the ruler said "same" with 5% of the screen changed.
  --
  -- The cause is that counting buckets is a PRESENCE test: as soon as the
  -- third tone band appears, the count saturates, and raising the strength
  -- only pushes the tones further apart without creating a new bucket. `ampl`
  -- also saturates, because the lightest and darkest pixels tend to be the
  -- same texels at every strength. The mean deviation does not saturate: it
  -- grows together with the separation.
  for r, row in ipairs(state.rows) do
    local y0 = (r - 1) * (cell + labelH) + labelH
    for c, yawDeg in ipairs(state.yaws) do
      local x0 = (c - 1) * cell
      local tons, lo, hi, soma, cont = {}, {}, {}, {}, {}
      local vals = {}
      for _, k in ipairs(KINDS) do
        tons[k] = {}; lo[k] = 2; hi[k] = -1; soma[k] = 0; cont[k] = 0
        vals[k] = {}
      end
      for y = 0, cell - 1 do
        for x = 0, cell - 1 do
          local kind = kindAt(img:getPixel(x0 + x, y0 + y))
          if kind then
            local sr, sg, sb = screen:getPixel(x0 + x, y0 + y)
            local lum = sr * 0.3 + sg * 0.6 + sb * 0.1
            -- quantise into 64 buckets: the adversarial review showed that
            -- counting unique floating point values always returns "many",
            -- for a nice gradient just as much as for noise, so it discriminates nothing.
            tons[kind][math.floor(lum * 64 + 0.5)] = true
            if lum < lo[kind] then lo[kind] = lum end
            if lum > hi[kind] then hi[kind] = lum end
            soma[kind] = soma[kind] + lum
            cont[kind] = cont[kind] + 1
            vals[kind][cont[kind]] = lum
          end
        end
      end
      for _, k in ipairs({ "front", "top" }) do
        local n = 0
        for _ in pairs(tons[k]) do n = n + 1 end
        if n > 0 then
          local media = soma[k] / cont[k]
          local desvio = 0
          for i = 1, cont[k] do desvio = desvio + math.abs(vals[k][i] - media) end
          desvio = desvio / cont[k]
          print(string.format(
            "  %-11s %-9s yaw %2d   %-6s niveis %2d   ampl %.3f   desvio %.4f",
            row.shape, row.pitchLabel, yawDeg, k, n, hi[k] - lo[k], desvio))
        end
      end
    end
  end
  colour:release()
  depth:release()
end


function love.draw()
  if opts.lab == "1" then return love.labdraw() end
  -- The window carries its own depth buffer (conf.lua sets t.window.depth),
  -- so the whole sheet is one depth-tested pass with no canvas juggling.
  love.graphics.clear(state.bg[1], state.bg[2], state.bg[3], 1, true, true)
  love.graphics.setDepthMode("less", true)
  love.graphics.setShader(state.shader)
  love.graphics.setColor(1, 1, 1, 1)

  local cell, labelH = state.cell, state.labelH
  for r, row in ipairs(state.rows) do
    local y = (r - 1) * (cell + labelH) + labelH
    for c, yawDeg in ipairs(state.yaws) do
      drawCell(row, math.rad(yawDeg), (c - 1) * cell, y, cell)
    end
  end

  love.graphics.setShader()
  love.graphics.setDepthMode("always", false)
  for r, row in ipairs(state.rows) do
    local y = (r - 1) * (cell + labelH)
    if labelH > 0 then
      love.graphics.setColor(0, 0, 0, 0.55)
      love.graphics.rectangle("fill", 0, y, state.width, labelH)
      love.graphics.setColor(1, 1, 1, 1)
      local text = string.format("%s  frame %d  %s%s  %s%s", row.sprite,
        row.frame, row.shapeLabel or row.shape:upper(), "", row.pitchLabel,
        row.why and ("  [" .. row.why .. "]") or "")
      love.graphics.print(text, 6, y + 2)
    end
  end
end

-- Compare every row against row 1, cell for cell. The eye cannot be trusted
-- with a 16x16 sprite blown up 16 times: judging these by looking already
-- produced one wrong diagnosis in this file's own history. A count of
-- differing pixels can be asserted on.
local function reportDiff(img)
  local cell, labelH = state.cell, state.labelH
  local base = state.rows[1]
  print(string.format("baseline row 1: %s frame %d %s %s",
    base.sprite, base.frame, base.shape:upper(), base.pitchLabel))
  for r = 2, #state.rows do
    local row = state.rows[r]
    for c = 1, #state.yaws do
      local x0 = (c - 1) * cell
      local y0 = (r - 1) * (cell + labelH) + labelH
      local b0 = labelH
      local differing, opaque = 0, 0
      for y = 0, cell - 1 do
        for x = 0, cell - 1 do
          local ar, ag, ab = img:getPixel(x0 + x, b0 + y)
          local br, bg, bb = img:getPixel(x0 + x, y0 + y)
          local d = math.abs(ar - br) + math.abs(ag - bg) + math.abs(ab - bb)
          if d > 0.02 then differing = differing + 1 end
          opaque = opaque + 1
        end
      end
      print(string.format("row %d yaw %d  %-12s %-9s  differing %5d / %d  (%.1f%%)",
        r, state.yaws[c], row.shape, row.pitchLabel, differing, opaque,
        differing / opaque * 100))
    end
  end
end

function love.update(dt)
  if opts.lab == "1" then return love.labupdate(dt) end
  state.frames = (state.frames or 0) + 1
  if state.frames == 3 then
    love.graphics.captureScreenshot(function(img)
      img:encode("png", opts.out)
      print("WROTE " .. love.filesystem.getSaveDirectory() .. "/" .. opts.out)
      if opts.diff == "1" and #state.rows > 1 then reportDiff(img) end
      if opts.metrics == "1" then computeMetrics(img) end
    end)
  elseif state.frames > 6 then
    love.event.quit()
  end
end

function love.keypressed(key)
  if opts.lab == "1" then return love.labkeys(key) end
  if key == "escape" then love.event.quit() end
end

-- Typed characters only reach the laboratory while it is asking for a reason.
-- Everywhere else the letters are commands, and swallowing them here would
-- silently disable the whole keyboard.
function love.textinput(t)
  if opts.lab == "1" and love.labtexto then love.labtexto(t) end
end
