# Resolves the tools' external binaries, or dies saying why.
#
# Exists because three tools had /opt/homebrew/bin/love hand-written in,
# which is the Homebrew path of ONE machine. On another machine the path
# does not exist, and then comes the real defect: `$($LOVE ... | grep ...)`
# with $LOVE absent returns an EMPTY string, and a check that compares two
# outputs passes by comparing empty with empty. The ruler went green without
# having measured anything.
#
# Applies to any machine: ssh's non-interactive shell does not load the
# profile, so /opt/homebrew/bin and /usr/local/bin are often outside PATH
# even when the binary is installed.
#
# Usage:  . "$(cd "$(dirname "$0")/.." && pwd)/tools_bin.sh"
#       $LOVE     always set, or the script already exited with an error
#       $FFMPEG   set if it exists, EMPTY if not (whoever needs it checks)

acha() {  # $1 = name on PATH, rest = candidate absolute paths
  local nome="$1"; shift
  local c
  # Explicit overrides must win over PATH so a quiet test launcher or a
  # machine-specific binary can actually be selected by the caller.
  for c in "$@" "$(command -v "$nome" 2>/dev/null)"; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

LOVE=$(acha love \
        "${LOVE_BIN:-}" \
        "/Applications/love.app/Contents/MacOS/love" \
        "$HOME/Applications/love.app/Contents/MacOS/love" \
        "/opt/homebrew/bin/love" \
        "/usr/local/bin/love") || {
  echo "ERROR: could not find the LOVE binary." >&2
  echo "  searched: PATH, \$LOVE_BIN, /Applications/love.app," >&2
  echo "            ~/Applications/love.app, /opt/homebrew, /usr/local" >&2
  echo "  fix: install LOVE 11.5 or point LOVE_BIN=/path/to/love" >&2
  exit 1
}
export LOVE

FFMPEG=$(acha ffmpeg "${FFMPEG_BIN:-}" "/opt/homebrew/bin/ffmpeg" "/usr/local/bin/ffmpeg") || FFMPEG=""
export FFMPEG

# THE LOVE LOCK. One tool at a time.
#
# run.sh, clip.sh and trailer.sh start with `pkill -x love`, because a
# previous LOVE still alive makes the next one start without getting
# anything. The side effect is that starting a tool KILLS any measurement in
# progress, and the truncated output reads as a short measurement instead of
# an interrupted one. It happened: the trailer killed a feature extraction
# halfway through and the partial file looked like a result.
#
# PROVEN, not just written down: (1) the second tool refuses and says who is
# holding it; (2) the lock is RELEASED when the tool fails, not only when it
# exits cleanly, because the trap covers EXIT INT TERM and not just the clean
# exit. The second case is what decides whether the lock is usable: one that
# stays stuck after an error teaches the person to delete the lock by reflex,
# and then they delete the one from a live measurement too.
#
# SHELL TRAP, paid for: in zsh a `trap ... EXIT` placed INSIDE a function
# fires when the FUNCTION returns, not when the script exits. These tools
# have a bash shebang, but a test written in the interactive shell (zsh)
# showed the lock disappearing on its own and for a minute it looked like it
# was not working.
#
# The lock is a directory, because mkdir is atomic on any filesystem. It
# stores the PID so a dead owner can be detected: without that, a tool that
# crashed leaves the lock forever and the next one has to delete it by hand,
# which teaches the person to delete the lock by reflex.
VC_TRAVA="${VC_TRAVA:-/tmp/vc-love.lock}"

# A TOOL THAT CALLS ANOTHER TOOL MUST NOT DEADLOCK ON ITSELF.
#
# The ruler was given the lock, correctly, because running beside another tool
# had just produced a false RED. But the ruler CALLS card.sh, which takes the
# lock too, and card.sh was then refused by the lock the ruler was holding. The
# ruler went red on two card checks that pass perfectly when run by hand.
#
# So the lock is reentrant across a process tree: whoever takes it exports
# VC_TRAVA_DONO with its own pid, and a child that sees an inherited value
# knows the machine is already ours and proceeds without taking anything. Only
# the process that actually created the lock releases it.
vc_trava_pega() {
  local quem="${1:-ferramenta}"
  if [ -n "${VC_TRAVA_DONO:-}" ]; then
    return 0
  fi
  if mkdir "$VC_TRAVA" 2>/dev/null; then
    echo "$$ $quem" > "$VC_TRAVA/dono"
    export VC_TRAVA_DONO=$$
    trap 'vc_trava_solta' EXIT INT TERM
    return 0
  fi
  local dono pid
  dono=$(cat "$VC_TRAVA/dono" 2>/dev/null || echo "?")
  pid=${dono%% *}
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    echo "orphan lock from $dono, recovering"
    rm -rf "$VC_TRAVA"
    vc_trava_pega "$quem"
    return $?
  fi
  echo "ANOTHER TOOL IS USING LOVE: $dono"
  echo "  Wait for it to finish. Starting now would kill its measurement and"
  echo "  the truncated output would look like a short result."
  return 1
}

vc_trava_solta() {
  [ -d "$VC_TRAVA" ] || return 0
  local dono
  dono=$(cat "$VC_TRAVA/dono" 2>/dev/null || echo "")
  case "$dono" in "$$ "*) rm -rf "$VC_TRAVA" ;; esac
}
