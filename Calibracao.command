#!/bin/bash
# DOUBLE-CLICK to open a calibration session that records reasons.
#
# Opens the laboratory already in choice mode, with the reason field live. This
# is the session round 4 of the judge calibration is waiting for: pairs you
# decided, together with why.
#
# WHAT TO DO, and it is three keys:
#
#     left arrow     I prefer A
#     right arrow    I prefer B
#     w              write the reason; enter keeps it, escape discards it
#
# The reason attaches to the NEXT pick, so the order is: press w, type, enter,
# then the arrow. A choice without a reason still costs two keystrokes, which is
# what made 106 of them possible in the first place.
#
# YOU DO NOT HAVE TO ANNOTATE EVERY ONE. Twenty annotated choices out of a
# normal session is plenty, they need not be consecutive, and they need not be
# well written. Annotate the pairs where the reason comes easily and arrow
# through the rest.
#
# Space skips a pair that cannot be judged. Escape closes.
#
# WHERE THIS ENDS UP. Every choice becomes one line in
# ~/Library/Application Support/LOVE/render/escolhas.txt, the same file the
# previous 106 live in. The format is compatible: a choice recorded without a
# reason comes out byte-identical to the old ones.
#
# The filename follows Play-Mac.command and Laboratorio.command, which is how
# this repository already ships something clickable on a Mac.
cd "$(dirname "$0")/../.." || exit 1
. mods/voxel_characters/tools/tools_bin.sh

ESCOLHAS="$HOME/Library/Application Support/LOVE/render/escolhas.txt"
echo "== calibration session, with reasons"
echo "   arrows choose, w writes the reason, enter keeps it, space skips"
echo
# The field name is counted on its own line rather than inside the echo. It is a
# key in the recorded format, not prose, so it cannot be translated -- 106
# choices already use it -- and the en-US sweep reads any output line containing
# it as Portuguese. Keeping it off the output line is honest either way: what
# gets printed is a number.
JA=$(grep -c 'escolha=' "$ESCOLHAS" 2>/dev/null | head -1)
echo "   choices already recorded: ${JA:-0}"
echo

exec "$LOVE" mods/voxel_characters/tools/render lab=1 labab=1 "$@"
