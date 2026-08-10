-- Config for the window probe. Mirrors the offscreen branch in
-- tools/render/conf.lua on purpose: the probe has to be parked by the SAME
-- mechanism it is measuring, or it would be reporting on a different setup
-- than the one the harness runs under.
function love.conf(t)
  t.window.title = "voxel_characters window probe"
  t.window.width = 320
  t.window.height = 200
  t.window.vsync = 0
  t.window.resizable = false
  t.modules.audio = false
  t.modules.sound = false
  t.modules.physics = false
  t.modules.joystick = false

  if os.getenv("VC_RUNNER_OFFSCREEN") == "1" then
    t.window.x = -4000
    t.window.y = -4000
  end
end
