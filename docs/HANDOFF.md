# Handoff, 2026-08-09

Where the work is, what is proven, what is waiting on a person, and how to run
everything. Written for a session that starts with none of today's context.

## State in one paragraph

**v1.6.0 is released and, for the first time, installable from inside the game.**
Branch `vida-v2` carries unreleased work on top of it: `FOOTFALL`, `CAMERA FIT`,
a gate that presses keys in the real options menu, clips that label themselves,
and a tool that asks the game whether a release is installable. Nothing on that
branch is pushed. Nothing on it has been judged by eye.

## The gates, all of them

From the **gen1recomp root**, never from the mod directory:

```
luajit mods/voxel_characters/tests/voxel_chars_test.lua      546 checks, the maths
bash mods/voxel_characters/tools/render/check.sh             the ruler checks itself
python3 tools/modkit.py validate mods/voxel_characters       packaging

POKEPORT_VERSION=blue POKEPORT_DRIVER=mods/voxel_characters/tools/ingame/probe_life.lua love .
                                                             10 pixel checks of the life channel
POKEPORT_VERSION=blue POKEPORT_DRIVER=mods/voxel_characters/tools/ingame/menu.lua love .
                                                             8 checks pressing real keys

bash mods/voxel_characters/tools/ingame/run.sh <dir>         11 screenshots in the real game
bash mods/voxel_characters/tools/ingame/clip.sh <dir> <k=v>  side by side video
bash mods/voxel_characters/tools/release_check.sh            does the GAME accept the release?
```

Green today: **546/546**, `REGUA OK`, `10/10`, `8/8`, `GATE OK 11 fotos`, `ok valid`.

The core repo's own suite is red with 18 pre-existing failures. Verified against
a baseline without this mod. Ignore it.

## Two machines, both with a full test room

`ssh mbp` reaches the MacBook Pro, and as of 2026-08-09 it runs **the entire
battery**, with the same numbers this machine reports: 546/546, `REGUA OK`,
10/10 pixel, 8/8 menu (16 rows ours, 34 from elsewhere, `BREATH` at index 46),
`GATE OK`, `CLIPE OK`, `RELEASE OK`.

A clone alone cannot do that. What a second machine needs, none of it in git:

```
~/Applications/love.app                            rsync'd (universal binary)
baserom.gb  +  assets/generated/                   derived from the owner's ROM
mods/DramaticShapeVoxelMod                         the host; without it we no-op
mods/gen1_modern_ui                                changes the menu row count
~/Library/Application Support/LOVE/pokemon-love2d  save, options, blue cache
luajit, ffmpeg, gh                                 brew
```

Two non-interactive-shell traps: `brew` is at `/usr/local/bin` and off the PATH,
and there is no passwordless sudo, which is why LOVE went to `~/Applications`
rather than `/Applications`. The save dir has a space in its path and Apple's
`rsync` mishandles it: use `tar czf - … | ssh mbp tar xzf -`.

An earlier version of this file claimed the visual gates could only run here.
That was wrong. Nothing was blocked; files had not been copied.

**What is still true:** a fresh clone scores 485/486, failing on
`assets/generated/sprites/lorelei.png`. That is the suite reporting an unbuilt
test room, not a broken test.

Code moves between the machines by `git bundle --all` + `scp` + `git fetch`
from `/tmp`, so nothing is pushed. Screenshots never match byte for byte across
machines: wandering NPCs and the day cycle differ. Compare visually, or compare
the harness's numbers.

## What is waiting on Kim's eye

Numbers cannot answer any of these.

1. **`FOOTFALL`** at `NORMAL`. Clip in `~/Desktop/voxel-characters-vida/clipes/`.
2. **`CAMERA FIT`'s criterion.** The table is measured, but the bar chosen was
   "hold the art share the current default already ships", 73.4%. Defensible,
   still a choice.
3. **`FRONT SHAPE`, `TOP DOME`, `STEP WEIGHT`**, which have never been seen by
   him on a real screen.

## The next step that was agreed

The preference loop. `clip.sh <dir> breath=0.010:0.035` films two levels against
each other, labelled A and B with a line saying what to watch. Kim picks. After
enough picks, the choices are training signal for a judge that is not `art%`.

This matters because of a measured fact: **an AI redraw in this project once
satisfied every numeric constraint and produced worse art.** An agent iterating
against the gates we own will converge on something that scores well and looks
wrong. The missing piece is the judge, not the generator.

## Standing rules that are not obvious from the code

- **Kim posts to Discord. Never me.** I prepare drafts.
- **Every visual change new to the mod ships off.** Once the community has seen
  and approved one, turning it on by default becomes the conservative choice.
  That is why `BLINK` and `BREATH` now ship on.
- **Every release credits reporters by name, and public text has no em dashes.**
- Local commits on a feature branch are routine. **Push, tag and release need
  Kim's word.**

## The three things most likely to waste the next session

1. **Running a driver with vsync on.** An occluded window stalls LOVE's whole
   loop at under a frame per second, and it looks exactly like the game hanging
   at the launcher. Every driver here calls `love.window.setVSync(0)`.
2. **Measuring a sub-pixel effect in a busy map.** Wandering NPCs and the day
   cycle put thousands of pixels in the baseline. `REDS_HOUSE_2F` has zero
   object events and is where the subtle gates measure.
3. **Trusting a pixel count across runs.** The camera rung persists in the save
   and rescales every count. The same option measured 266 in one run and 9 in
   the next. Magnitude belongs in the offline suite, where the number is the
   matrix and not a pixel.
