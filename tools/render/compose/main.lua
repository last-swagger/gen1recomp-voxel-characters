-- Stacks render-harness sheets into one labelled image.
--
-- The harness labels each row with sprite, frame, builder and camera rung, but
-- a before-and-after needs a caption the harness cannot know, because "before"
-- is a different checkout. This takes `label=path` pairs and produces one PNG
-- that can be looked at without launching the game.
--
--   love mods/voxel_characters/tools/render/compose \
--     out=fix.png "Antes (v1.2.2)=/path/a.png" "Depois (v1.3.0)=/path/b.png"

local BAR = 30
local PAD = 10
local items, opts = {}, { out = "compare.png", title = "" }

local function loadPng(path)
  local f = io.open(path, "rb")
  if not f then
    print("ERROR: sem arquivo: " .. tostring(path))
    love.event.quit(1)
    error("missing " .. tostring(path), 0)
  end
  local bytes = f:read("*a")
  f:close()
  local fd = love.filesystem.newFileData(bytes, path:match("[^/]+$"))
  return love.graphics.newImage(love.image.newImageData(fd))
end

function love.load(argv)
  for _, a in ipairs(argv or {}) do
    -- Corta no ULTIMO `=`, nao no primeiro: legenda com sinal de igual e
    -- normal ("t=0.4"), caminho com sinal de igual nao e. Cortar no primeiro
    -- ja quebrou duas vezes e o sintoma aparece como arquivo inexistente.
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
