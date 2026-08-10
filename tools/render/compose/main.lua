-- Composes render-harness sheets into one labelled image.
--
-- Two modes, because a release needs two different pictures.
--
-- STACK (default) is the working picture: `label=path` pairs stacked with a
-- caption bar, for looking at a change without launching the game.
--
--   love mods/voxel_characters/tools/render/compose \
--     out=fix.png "Before (v1.2.2)=/path/a.png" "After (v1.3.0)=/path/b.png"
--
-- CARD is the published picture: a before and after with numbered callouts
-- down the side, each one pointing at the place in the AFTER image where it
-- happens. It exists because a release note that says "improved shading"
-- teaches nobody anything, and a picture that shows where to look does.
--
--   love mods/voxel_characters/tools/render/compose mode=card out=card.png \
--     title="Voxel Characters 1.6.0" \
--     before="Before|flat slab|/path/a.png" \
--     after="After|shading options on|/path/b.png" \
--     point="0.62,0.30|FRONT SHAPE|Steps the front face into three tones." \
--     point="0.50,0.88|GROUND SHADE|Host-style contact shade at the feet."
--
-- The two modes parse their arguments DIFFERENTLY and that is deliberate.
-- Stack cuts at the LAST `=`, because a caption with an equals sign is normal
-- ("t=0.4") and a path with one is not; cutting at the first broke it twice.
-- Card cuts at the FIRST `=` and separates its own fields with `|`, because a
-- callout sentence is prose and prose contains equals signs far more often
-- than it contains pipes.
--
-- WHY THE BEFORE IS NOT DRAWN FROM MEMORY. The harness reads
-- VOXEL_CHARS_MAIN, so the "before" half can be rendered from a released tag
-- (`git show v1.5.0:main.lua > /tmp/before.lua`) instead of being illustrated
-- from what we remember the old build looking like. A comparison in a release
-- note is a public claim, and a public claim needs a measurement behind it.

-- ERRORS GO TO STDOUT AND KILL THE PROCESS, instead of opening a window and
-- waiting for a key. Same handler every other tool here installs, and the same
-- reason: from inside a script a waiting window is indistinguishable from
-- heavy work, so the tool dies at the timeout with an empty log.
do
  local function handler(msg)
    io.stdout:write("ERRO DE LOVE: " .. tostring(msg) .. "\n")
    io.stdout:write(debug.traceback("", 2) .. "\n")
    io.stdout:flush()
    os.exit(1)
  end
  love.errorhandler = handler
  love.errhand = handler
end

-- A refusal is a decision, not a crash: it exits non-zero WITHOUT a traceback.
-- `love.event.quit(1)` only schedules a quit, so a caller reading the exit
-- code saw 0 and read the refusal as a success. That is the exact shape of
-- the defect this file's own guard exists to catch, so it is worth the four
-- lines to not have it here too.
local function refuse(...)
  for _, line in ipairs({ ... }) do io.stdout:write(line .. "\n") end
  io.stdout:flush()
  os.exit(1)
end

local BAR = 30
local PAD = 10
local items, opts = {}, { out = "compare.png", title = "" }

local function loadImageData(path)
  local f = io.open(path, "rb")
  if not f then
    refuse("ERROR: no such file: " .. tostring(path))
  end
  local bytes = f:read("*a")
  f:close()
  local fd = love.filesystem.newFileData(bytes, path:match("[^/]+$"))
  return love.image.newImageData(fd)
end

local function loadPng(path)
  return love.graphics.newImage(loadImageData(path))
end

--------------------------------------------------------------------------
-- card mode
--------------------------------------------------------------------------

local card = nil

-- The card's own palette. Kept here and not sampled from the images because a
-- card is a document, not a screenshot: it should look the same whichever
-- sprite it is about.
local INK = {
  bg      = { 0.11, 0.12, 0.15 },
  panel   = { 0.15, 0.16, 0.20 },
  frame   = { 0.28, 0.30, 0.36 },
  title   = { 0.95, 0.96, 0.98 },
  label   = { 0.86, 0.88, 0.92 },
  sub     = { 0.58, 0.62, 0.70 },
  accent  = { 0.35, 0.73, 0.55 },
  body    = { 0.78, 0.81, 0.86 },
  callout = { 0.42, 0.46, 0.55 },
}

local function setInk(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

local function splitPipe(s)
  local out = {}
  for piece in (tostring(s) .. "|"):gmatch("(.-)|") do out[#out + 1] = piece end
  return out
end

local CARD_W_TEXT = 460   -- width of the callout column
local CARD_GAP    = 34    -- gutter between the images and the callouts
local CARD_MARGIN = 28

-- The harness renders a character into a fixed square cell, so most of that
-- cell is background. Two things go wrong if the card draws it as it comes.
-- The picture is mostly empty, and worse, a callout's coordinates are a
-- fraction of the CELL rather than of the character, so "the feet" is a
-- different number for every sprite and has to be found by trial.
--
-- So find the content and crop to it. The box is the UNION of both halves,
-- never each one's own, because cropping them separately re-centres them
-- against each other and the before and after appear to jump.
local function contentBox(id, bg, tol)
  local w, h = id:getWidth(), id:getHeight()
  local x0, y0, x1, y1 = w, h, -1, -1
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b = id:getPixel(x, y)
      if math.abs(r - bg[1]) > tol or math.abs(g - bg[2]) > tol
         or math.abs(b - bg[3]) > tol then
        if x < x0 then x0 = x end
        if y < y0 then y0 = y end
        if x > x1 then x1 = x end
        if y > y1 then y1 = y end
      end
    end
  end
  if x1 < x0 then return 0, 0, w, h end   -- all background: crop nothing
  return x0, y0, x1 - x0 + 1, y1 - y0 + 1
end

-- How many pixels actually differ between the two halves.
--
-- This exists because of a defect this project has already shipped once, in
-- the clip tool: an option written to the save without emitting the event, so
-- the cached mesh never rebuilt and the two sides of the comparison were the
-- same image. A card is a stronger claim than a clip, because it names four
-- changes in writing next to a picture, so it refuses rather than warns.
local function diffPixels(a, b)
  if a:getWidth() ~= b:getWidth() or a:getHeight() ~= b:getHeight() then
    return -1
  end
  local n = 0
  for y = 0, a:getHeight() - 1 do
    for x = 0, a:getWidth() - 1 do
      local r1, g1, b1 = a:getPixel(x, y)
      local r2, g2, b2 = b:getPixel(x, y)
      if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 then n = n + 1 end
    end
  end
  return n
end

-- Loads both halves, refuses an empty comparison, and crops when asked.
-- The refusal happens whether or not cropping is on, because "did anything
-- change" is not a cropping question.
local function prepareHalves(c, pad)
  local ab, aa = loadImageData(c.before.path), loadImageData(c.after.path)

  local n = diffPixels(ab, aa)
  if n == 0 then
    refuse("ERROR: before and after are the same image, pixel for pixel.",
           "  A card claims a change in writing. Refusing to draw one that",
           "  did not happen. Check that the option reached the build.")
  end
  print(string.format("halves differ in %s pixels",
    n < 0 and "size, so in all" or tostring(n)))

  -- DIFFERENT CANVAS SIZES ARE REFUSED, not cropped around.
  --
  -- The crop box was the union of both content boxes but clamped to the
  -- BEFORE image's dimensions, so when the after image was larger, anything
  -- past the before image's edge vanished from the published card. No error,
  -- no refusal, exit 0, and an AFTER panel that could be entirely empty with
  -- the callouts pointing at nothing. Found by review, reproduced.
  --
  -- Clamping each half to its own size instead would keep the pixels and lose
  -- the alignment, which is worse: a before and after is a claim that THIS
  -- became THAT, and that claim needs one framing. Two canvas sizes mean the
  -- two halves were not filmed the same way, and the honest answer is to say
  -- so. This is reachable in normal use: `before_tag=` renders the old half
  -- with a different version's code, and cell size is a harness argument.
  if ab:getWidth() ~= aa:getWidth() or ab:getHeight() ~= aa:getHeight() then
    refuse(string.format(
      "ERROR: the two halves are different sizes (%dx%d and %dx%d).",
      ab:getWidth(), ab:getHeight(), aa:getWidth(), aa:getHeight()),
      "  A before and after claims one thing became another, and that needs",
      "  one framing. Render both halves with the same cell= and the same",
      "  camera, or pass crop=0 and accept that they will not line up.")
  end

  if not c.crop then
    for _, part in ipairs({ c.before, c.after }) do
      part.w, part.h = part.image:getWidth(), part.image:getHeight()
    end
    return
  end

  -- THE BACKGROUND COLOUR COMES FROM THE CORNERS, PLURAL.
  --
  -- Reading pixel (0,0) alone inverts the whole thing when the character
  -- touches that corner: the character becomes "background" and is excluded,
  -- the canvas becomes "content" and is kept, and every callout fraction then
  -- addresses the wrong box. Found by review, reproduced with a block in the
  -- corner. Four corners with a majority is cheap and cannot be fooled by one
  -- of them being covered.
  local function corDeFundo(id)
    local w, h = id:getWidth(), id:getHeight()
    local cantos = {}
    for _, p in ipairs({ {0,0}, {w-1,0}, {0,h-1}, {w-1,h-1} }) do
      local r, g, b = id:getPixel(p[1], p[2])
      cantos[#cantos + 1] = { r, g, b }
    end
    for i = 1, #cantos do
      local iguais = 0
      for j = 1, #cantos do
        local a, b = cantos[i], cantos[j]
        if math.abs(a[1]-b[1]) < 0.01 and math.abs(a[2]-b[2]) < 0.01
           and math.abs(a[3]-b[3]) < 0.01 then iguais = iguais + 1 end
      end
      if iguais >= 3 then return cantos[i] end
    end
    return nil
  end

  local bg = corDeFundo(ab)
  if not bg then
    -- No corner agrees with the others, so there is no background to find and
    -- cropping would be a guess. Draw the images whole and say why.
    print("aviso: nao achei cor de fundo nos cantos, entao nao vou recortar")
    for _, part in ipairs({ c.before, c.after }) do
      part.w, part.h = part.image:getWidth(), part.image:getHeight()
    end
    return
  end
  local x1, y1, w1, h1 = contentBox(ab, bg, 0.02)
  local x2, y2, w2, h2 = contentBox(aa, bg, 0.02)
  local x0, y0 = math.min(x1, x2), math.min(y1, y2)
  local x3, y3 = math.max(x1 + w1, x2 + w2), math.max(y1 + h1, y2 + h2)
  x0, y0 = math.max(0, x0 - pad), math.max(0, y0 - pad)
  x3 = math.min(ab:getWidth(), x3 + pad)
  y3 = math.min(ab:getHeight(), y3 + pad)
  local bw, bh = x3 - x0, y3 - y0
  for _, part in ipairs({ c.before, c.after }) do
    part.quad = love.graphics.newQuad(x0, y0, bw, bh,
      part.image:getWidth(), part.image:getHeight())
    part.w, part.h = bw, bh
  end
  return bw, bh
end

local function parseCard(argv)
  local c = { title = "", out = "card.png", crop = true, points = {} }
  for _, a in ipairs(argv or {}) do
    -- `[%w_]+` cannot match `=`, so this cuts at the FIRST one.
    local k, v = a:match("^([%w_]+)=(.*)$")
    if k == "out" or k == "title" then
      c[k] = v
    elseif k == "crop" then
      c.crop = (v ~= "0" and v ~= "off")
    elseif k == "before" or k == "after" then
      local f = splitPipe(v)
      -- Two fields means label and path; three means label, sublabel, path.
      -- The path is always last, so a missing sublabel cannot silently become
      -- the filename.
      local path = f[#f]
      c[k] = { label = f[1] or "", sub = (#f >= 3) and f[2] or "", path = path }
    elseif k == "point" then
      local f = splitPipe(v)
      local px, py = tostring(f[1]):match("^%s*([%d%.]+)%s*,%s*([%d%.]+)%s*$")
      c.points[#c.points + 1] = {
        x = tonumber(px), y = tonumber(py),
        title = f[2] or "", text = f[3] or "",
      }
    end
  end
  return c
end

local function cardMeasure(c)
  c.fTitle = love.graphics.newFont(24)
  c.fLabel = love.graphics.newFont(17)
  c.fSub   = love.graphics.newFont(12)
  c.fHead  = love.graphics.newFont(14)
  c.fPoint = love.graphics.newFont(14)
  c.fBody  = love.graphics.newFont(12)
  c.fNum   = love.graphics.newFont(15)

  c.before.image = loadPng(c.before.path)
  c.after.image  = loadPng(c.after.path)
  prepareHalves(c, 8)

  -- The sublabel is usually the longest string on the left (it lists the
  -- options that are on), and leaving it out of the width made it run under
  -- the callout panel. Anything drawn in this column has to be measured here.
  local imgW = math.max(c.before.w, c.after.w)
  imgW = math.max(imgW, c.fLabel:getWidth(c.before.label),
                        c.fLabel:getWidth(c.after.label),
                        c.fSub:getWidth(c.before.sub),
                        c.fSub:getWidth(c.after.sub))

  -- Left column: label, image, arrow, label, image.
  local ARROW = 44
  c.leftW = imgW
  local labelH = c.fLabel:getHeight() + (c.before.sub ~= "" and c.fSub:getHeight() or 0) + 6
  c.labelH = labelH
  c.leftH = labelH + c.before.h + ARROW + labelH + c.after.h
  c.arrowH = ARROW

  -- Right column: a heading, then one block per callout.
  -- `blockY`, never `p.y`. The callout's own y is the FRACTION of the after
  -- image it points at; an earlier version stored the layout position in the
  -- same field and every tether flew off the bottom of the card, because
  -- `afterY + 30 * imageHeight` is a long way down.
  local headH = c.fHead:getHeight() + 16
  local textLimit = CARD_W_TEXT - 44
  local stack = 0
  for i, p in ipairs(c.points) do
    p.titleH = c.fPoint:getHeight()
    local _, lines = c.fBody:getWrap(p.text, textLimit)
    p.bodyH = #lines * c.fBody:getHeight()
    p.h = p.titleH + 4 + p.bodyH
    stack = stack + p.h + (i < #c.points and 20 or 0)
  end

  -- Spread the callouts down the full height of the images when there is room.
  -- Bunched at the top they all tether from nearly the same place, and the
  -- lines cross each other on the way to points that are far apart.
  local room = c.leftH - headH - stack
  local extra = (#c.points > 1 and room > 0) and (room / (#c.points - 1)) or 0
  if extra > 46 then extra = 46 end
  local y = headH
  for i, p in ipairs(c.points) do
    p.blockY = y
    y = y + p.h + (i < #c.points and (20 + extra) or 0)
  end
  c.rightH = y
  c.headH = headH
  c.textLimit = textLimit

  local titleH = (c.title ~= "") and (c.fTitle:getHeight() + 18) or 0
  c.titleH = titleH
  c.w = CARD_MARGIN * 2 + c.leftW + CARD_GAP + CARD_W_TEXT
  -- The TITLE has to fit too. Everything else in the layout was measured and
  -- the heading was not, so a long one ran off the right edge and was cut mid
  -- word, on the one line of the card a reader looks at first.
  local precisa = CARD_MARGIN * 2 + c.fTitle:getWidth(c.title)
  if c.title ~= "" and precisa > c.w then c.w = precisa end
  c.h = CARD_MARGIN * 2 + titleH + math.max(c.leftH, c.rightH)
  return c
end

local function drawArrow(x, y, h)
  setInk(INK.callout)
  love.graphics.setLineWidth(2)
  love.graphics.line(x, y + 8, x, y + h - 14)
  love.graphics.polygon("fill", x - 6, y + h - 16, x + 6, y + h - 16, x, y + h - 6)
end

local function drawCard(c)
  setInk(INK.bg)
  love.graphics.rectangle("fill", 0, 0, c.w, c.h)

  local x0, y0 = CARD_MARGIN, CARD_MARGIN
  if c.title ~= "" then
    love.graphics.setFont(c.fTitle)
    setInk(INK.title)
    love.graphics.print(c.title, x0, y0)
    y0 = y0 + c.titleH
  end

  -- Right panel behind the callouts, so the two halves read as two things.
  local rx = x0 + c.leftW + CARD_GAP
  setInk(INK.panel)
  love.graphics.rectangle("fill", rx - 16, y0 - 10,
    CARD_W_TEXT + 16, math.max(c.leftH, c.rightH) + 20, 6, 6)

  -- Left column.
  local function half(part, y)
    love.graphics.setFont(c.fLabel)
    setInk(INK.label)
    love.graphics.print(part.label, x0, y)
    if part.sub ~= "" then
      love.graphics.setFont(c.fSub)
      setInk(INK.sub)
      love.graphics.print(part.sub, x0, y + c.fLabel:getHeight() + 1)
    end
    local iy = y + c.labelH
    local ix = x0 + (c.leftW - part.w) / 2
    setInk(INK.frame)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", ix - 1, iy - 1, part.w + 2, part.h + 2)
    love.graphics.setColor(1, 1, 1, 1)
    if part.quad then
      love.graphics.draw(part.image, part.quad, ix, iy)
    else
      love.graphics.draw(part.image, ix, iy)
    end
    return ix, iy, iy + part.h
  end

  local _, _, beforeBottom = half(c.before, y0)
  drawArrow(x0 + c.leftW / 2, beforeBottom, c.arrowH)
  local afterX, afterY = half(c.after, beforeBottom + c.arrowH)

  -- Right column: heading and callouts, each tethered to the after image.
  love.graphics.setFont(c.fHead)
  setInk(INK.accent)
  love.graphics.print("KEY CHANGES", rx, y0)

  for i, p in ipairs(c.points) do
    local py = y0 + p.blockY

    setInk(INK.accent)
    love.graphics.setFont(c.fNum)
    love.graphics.print(tostring(i), rx, py - 1)

    love.graphics.setFont(c.fPoint)
    setInk(INK.label)
    love.graphics.print(p.title, rx + 26, py)

    love.graphics.setFont(c.fBody)
    setInk(INK.body)
    love.graphics.printf(p.text, rx + 26, py + p.titleH + 4, c.textLimit, "left")

    -- The tether. A callout that does not say WHERE is a caption, and the
    -- whole point of this format is that it points.
    --
    -- Routed as an elbow through the gutter, not as a straight line. Straight
    -- from the text to the point crosses the BEFORE image on the way down,
    -- and a diagram that draws over the thing it is explaining is worse than
    -- one with no lines at all.
    if p.x and p.y then
      local tx = afterX + p.x * c.after.w
      local ty = afterY + p.y * c.after.h
      -- The channel clears the whole left COLUMN, not just the image. The
      -- sublabel lists the options that are on and is routinely wider than a
      -- cropped character, so a channel measured from the image ran a line
      -- straight through that sentence.
      local channel = x0 + c.leftW + 12
      setInk(INK.callout)
      love.graphics.setLineWidth(1)
      love.graphics.line(rx - 22, py + 8, channel, py + 8, channel, ty, tx, ty)
      love.graphics.circle("fill", tx, ty, 3)
      setInk(INK.accent)
      love.graphics.circle("line", tx, ty, 5)
    end
  end
end

--------------------------------------------------------------------------

function love.load(argv)
  -- Pixel art scaled or filtered turns to mush, and this tool exists to show
  -- pixels. Nearest before any image is created.
  love.graphics.setDefaultFilter("nearest", "nearest")

  local mode = "stack"
  for _, a in ipairs(argv or {}) do
    if a == "mode=card" then mode = "card" end
  end

  if mode == "card" then
    card = parseCard(argv)
    if not card.before or not card.after then
      refuse("ERROR: card mode needs before= and after=")
    end
    cardMeasure(card)
    love.window.setMode(card.w, card.h, { vsync = 0 })
    opts.out, opts.w, opts.h = card.out, card.w, card.h
    opts.frames = 0
    print(string.format("card: %d callouts into %dx%d", #card.points, card.w, card.h))
    return
  end

  for _, a in ipairs(argv or {}) do
    -- Cuts at the LAST `=`, not the first: a caption with an equals sign is
    -- normal ("t=0.4"), a path with one is not. Cutting at the first already
    -- broke twice and the symptom shows up as a nonexistent file.
    local k, v = a:match("^(.*)=([^=]*)$")
    if k == "out" or k == "title" then
      opts[k] = v
    elseif k then
      items[#items + 1] = { label = k, path = v }
    end
  end
  if #items == 0 then
    print("ERROR: nothing to compose")
    return love.event.quit(1)
  end

  local head = opts.title ~= "" and (BAR + PAD) or 0
  local w, h = 0, head + PAD
  -- The width has to fit the captions too, not just the sheets. A clipped
  -- caption on a before-and-after is worse than no caption: it looks like the
  -- image is the whole story when the sentence naming the defect is missing.
  local font = love.graphics.getFont()
  for _, it in ipairs(items) do
    it.image = loadPng(it.path)
    w = math.max(w, it.image:getWidth(), font:getWidth(it.label) + PAD * 2)
    h = h + BAR + it.image:getHeight() + PAD
  end
  if opts.title ~= "" then
    w = math.max(w, font:getWidth(opts.title) + PAD * 2)
  end
  w = w + PAD * 2

  love.window.setMode(w, h, { vsync = 0 })
  opts.w, opts.h, opts.head = w, h, head
  opts.frames = 0
  print(string.format("composing %d sheets into %dx%d", #items, w, h))
end

function love.draw()
  if card then return drawCard(card) end
  love.graphics.clear(0.13, 0.14, 0.17, 1)
  local y = 0
  if opts.head > 0 then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(opts.title, PAD, 8)
    y = opts.head
  end
  y = y + PAD
  for _, it in ipairs(items) do
    love.graphics.setColor(0.22, 0.46, 0.35, 1)
    love.graphics.rectangle("fill", 0, y, opts.w, BAR)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(it.label, PAD, y + 8)
    y = y + BAR
    love.graphics.draw(it.image, PAD, y)
    y = y + it.image:getHeight() + PAD
  end
end

function love.update()
  opts.frames = (opts.frames or 0) + 1
  if opts.frames == 3 then
    love.graphics.captureScreenshot(function(img)
      img:encode("png", opts.out)
      print("WROTE " .. love.filesystem.getSaveDirectory() .. "/" .. opts.out)
    end)
  elseif opts.frames > 6 then
    love.event.quit()
  end
end
