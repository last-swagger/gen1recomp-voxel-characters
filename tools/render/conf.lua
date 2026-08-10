function love.conf(t)
  t.window.title = "voxel_characters render harness"
  t.window.width = 1280
  t.window.height = 800
  t.window.vsync = 0
  t.window.resizable = false
  t.window.depth = 24

  -- Roadmap T0.2: the controlled runner asks for the window to be parked off
  -- the visible area, so a batch of renders stops taking the screen away from
  -- whoever is using the machine.
  --
  -- ONLY THE POSITION MOVES, and that restraint is the point. This harness
  -- draws into a canvas and encodes it (love.graphics.newCanvas / setCanvas),
  -- so the pixels never depend on the window reaching a display. Size, depth
  -- and vsync are what the output DOES depend on, so none of them is touched
  -- here: changing them under a flag would mean the runner silently measured
  -- a different scene, which is the one thing T0.2 is not allowed to do.
  --
  -- vsync is already 0 above, which matters here: an occluded window with
  -- vsync on stalls the whole love.run loop (docs/TRAPS.md, 5 frames in 90
  -- seconds), and off the visible area counts as occluded.
  --
  -- UNVERIFIED as of this commit: no delta has been measured between this and
  -- a normal window. tools/runner/deltas.txt has no entry, so the runner
  -- stamps every native-offscreen run UNMEASURED.
  if os.getenv("VC_RUNNER_OFFSCREEN") == "1" then
    t.window.x = -4000
    t.window.y = -4000
  end
  t.modules.audio = false
  t.modules.sound = false
  t.modules.physics = false
  t.modules.joystick = false
end
