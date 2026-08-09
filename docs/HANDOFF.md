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

## Two machines, and the boundary is not a choice

`ssh mbp` reaches the MacBook Pro. It has `git`, `python3`, `luajit` and the
`claude` CLI, plus both repos under `~/Projects/gen1recomp`. Two things bite in
a non-interactive shell: `brew` lives at `/usr/local/bin/brew` and is off the
PATH, and there is no passwordless sudo.

**The MBP runs 485 of 486.** The one failure is a test reading
`assets/generated/sprites/lorelei.png`, which is derived from the player's own
ROM at first boot and is in no clone. So:

- **MBP:** code, and everything that does not touch ROM-derived art.
- **This machine:** every visual gate, because they all read the extracted
  sprites and the LOVE save cache. Also the release.

Consequence worth stating plainly: **no visual change can be called done from
the MBP.** Green there is 485/486; green here is 546 plus four visual gates.

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
