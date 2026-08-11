-- Makes LOVE report errors over stdout and EXIT, instead of opening a window and waiting.
--
-- Every driver in this directory starts by calling this. By default LOVE
-- handles an error by opening a screen with the message and waiting for a
-- key; from inside a script that is indistinguishable from heavy work, and
-- the tool only dies on timeout, with an empty log, while the cause sits
-- written on a window nobody is looking at. Three times in one session.
--
-- The alternative I tried before, photographing the screen to read the
-- message, was worse: on a work machine the photo picks up whatever is in
-- front, and it caught a personal conversation twice. The images were deleted
-- and the idea abandoned. The message has to come out where the script already reads.
return function()
  local function handler(msg)
    msg = tostring(msg)
    io.stdout:write("LOVE ERROR: " .. msg .. "\n")
    io.stdout:write(debug.traceback("", 2) .. "\n")
    io.stdout:flush()
    os.exit(1)
  end
  love.errorhandler = handler
  love.errhand = handler
end
