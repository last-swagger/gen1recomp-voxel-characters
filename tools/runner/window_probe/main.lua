-- WHERE DID THE WINDOW ACTUALLY GO?
--
--   bash mods/voxel_characters/tools/love.sh mods/voxel_characters/tools/runner/window_probe
--   VC_RUNNER_OFFSCREEN=1 bash ... (same)
--
-- The native-offscreen backend asks for the window at -4000,-4000 and the
-- whole value of the mode rests on the window actually going there. macOS is
-- free to clamp a window back onto a display, and if it does, the mode buys
-- nothing while looking like it works: the renders would still be correct, so
-- no pixel comparison would ever notice.
--
-- So this asks the window where it is, instead of anyone assuming. It prints
-- one PASSOU or FALHOU so the runner's verdict rule engages the same way it
-- does for every other gate here.
--
-- WHAT IT PROVES AND WHAT IT DOES NOT. love.window.getPosition returns the
-- position SDL granted, relative to the display the window is on, which is
-- enough to catch clamping. It is a proxy for "nobody sees it", not a
-- photograph of the screen: a window can be off the desktop rectangle and
-- still be composited somewhere exotic. Confirming with human eyes once is
-- still worth doing, and after that this is the thing that can run unattended.

local function saida(...)
  io.write(string.format(...), "\n")
  io.flush()
end

function love.load()
  local pedido = os.getenv("VC_RUNNER_OFFSCREEN") == "1"
  local x, y, tela = love.window.getPosition()
  local w, h = love.graphics.getDimensions()
  local n = love.window.getDisplayCount()

  saida("mode         %s", pedido and "offscreen requested" or "normal")
  saida("position     x=%d y=%d display=%d", x, y, tela)
  saida("window       %dx%d", w, h)
  saida("displays     %d", n)

  -- Does the window rectangle touch the desktop rectangle of ANY display?
  -- getPosition is relative to its own display, so the window's own display is
  -- the one that decides; the others are reported for context.
  local visivel = false
  for i = 1, n do
    local dw, dh = love.window.getDesktopDimensions(i)
    saida("display %d    %dx%d", i, dw, dh)
    if i == tela then
      local cruza = (x < dw) and (x + w > 0) and (y < dh) and (y + h > 0)
      if cruza then visivel = true end
    end
  end

  saida("on screen    %s", tostring(visivel))

  if pedido then
    if visivel then
      saida("W1 FALHOU    offscreen was requested and the window is ON a display.")
      saida("             macOS clamped it back. The mode buys nothing as built:")
      saida("             try a separate user session, Space, or display instead.")
    else
      saida("W1 PASSOU    offscreen requested and the window is off every display")
    end
  else
    -- The control. Without it, "off screen" under the flag could just be how
    -- this machine always reports, and the probe would be measuring nothing.
    if visivel then
      saida("W1 PASSOU    normal mode puts the window on a display, as expected")
    else
      saida("W1 FALHOU    normal mode is ALREADY off screen, so this probe cannot")
      saida("             tell the two modes apart and proves nothing here.")
    end
  end

  love.event.quit(0)
end

function love.draw() end
