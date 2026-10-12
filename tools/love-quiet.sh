#!/bin/bash
# Run a LOVE test without taking over the desktop. Output remains connected to
# the caller so the existing gates can read their normal verdicts.
set -u

if [ "$(uname -s)" != "Darwin" ]; then
  echo "love-quiet.sh is macOS-only; set LOVE_BIN to the LOVE executable" >&2
  exit 2
fi

REAL_LOVE="${VC_LOVE_REAL_BIN:-$(command -v love 2>/dev/null || true)}"
if [ -z "$REAL_LOVE" ] || [ ! -x "$REAL_LOVE" ]; then
  for candidate in "/Applications/love.app/Contents/MacOS/love" \
                   "$HOME/Applications/love.app/Contents/MacOS/love" \
                   "/opt/homebrew/bin/love" "/usr/local/bin/love"; do
    if [ -x "$candidate" ]; then REAL_LOVE="$candidate"; break; fi
  done
fi
[ -n "$REAL_LOVE" ] && [ -x "$REAL_LOVE" ] || {
  echo "LOVE executable not found; set VC_LOVE_REAL_BIN" >&2
  exit 1
}

# Warm System Events before LOVE starts so hiding its window does not wait for
# the first Apple Events launch while the game is already on screen.
/usr/bin/osascript -e 'tell application "System Events" to get name' \
  >/dev/null 2>&1 || {
  echo "Could not access System Events to hide the LOVE test window" >&2
  exit 1
}

"$REAL_LOVE" "$@" &
LOVE_PID=$!
oculta() {
  /usr/bin/osascript -e '
on run argv
  set targetPid to (item 1 of argv) as integer
  tell application "System Events"
    set targetProcess to first application process whose unix id is targetPid
    set visible of targetProcess to false
  end tell
end run' "$LOVE_PID" >/dev/null 2>&1
}
(
  while kill -0 "$LOVE_PID" 2>/dev/null; do
    oculta
    sleep 0.2
  done
) &
HIDER_PID=$!

wait "$LOVE_PID"
RESULT=$?
kill "$HIDER_PID" 2>/dev/null || true
wait "$HIDER_PID" 2>/dev/null || true
exit "$RESULT"
