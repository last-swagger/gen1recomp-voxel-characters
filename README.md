# Voxel Characters

The voxel world is 3D. The people in it are flat cards.

This mod fixes that, and then keeps going: it builds each character a real body
out of their own pixels, and then gives that body something to do. They breathe.
They shift their weight. They lean into a step and settle when they stop.

Nothing here is drawn by us. Every pixel on screen is the artist's, read from
your own game files at runtime. We only decide where those pixels sit in space
and how they move.

It is a companion mod. It contains no code from any voxel mod, ships no art,
and modifies nothing on disk. Turn it off and the original flat card is back on
the next frame.

## Install

**You need two mods: a voxel mod, and this one.** This mod does nothing on its
own, because it works by extending a voxel mod that is already running.

1. **Install a voxel mod first.** Any of these works:
   - **Dramatic Shape Voxel Mod** by DramaticShape, the original
   - **Battle Art Voxel Fork** by absol89
   - **Dramaless Shape Voxel Mod** by artyrambles

2. **Download `voxel_characters.zip`** from the
   [latest release](https://github.com/last-swagger/gen1recomp-voxel-characters/releases/latest).

3. **In game: `MODS`, then `Import mod .zip`.** Pick the file you downloaded.

4. **Enable Voxel Characters** in the mod list, and restart when it asks.

5. **Open `OPTIONS` and scroll down.** You are looking for a row that says
   `STATUS`. If it says `ACTIVE`, you are done, and everything below it is
   yours to play with.

You need gen1recomp `0.1.51` or newer.

### It is installed and nothing looks different

Open `OPTIONS`, scroll to the `STATUS` row, and read it. That row exists
because three different people hit three different problems that all looked
identical from the outside, and none of them could tell which one they had.

| STATUS says | What happened |
|---|---|
| `NO HOST` | No voxel mod is running that this one can attach to. Install one, or enable it. |
| `OFF` | `VOXEL CHARS` is set to `OFF`. Set it to `3`. |
| `ACTIVE` | It is working. If you still see no difference, your camera is at the flat 2D rung. Press `3` to cycle the voxel camera. |
| `FIRST PERSON` | On purpose. A solid body does not belong in a first person camera, so we hand back the flat card while you are in one. |
| `REPLACED` | Another mod took over the same drawing function after we did. |
| `MASK ERROR` / `BUILD ERROR` / `DRAW ERROR` | Something went wrong reading or building sprites. The characters fall back to flat cards instead of breaking. |

There is a second row, `LIFE`, that reports the animation channel the same way.
`NO CHANNEL` means your voxel mod is too old for it; everything else still
works, and the three animation rows simply do not appear.

### It says a version conflict

Some voxel mod releases declare a conflict with this one in their manifest.
That is their file, not ours, and we cannot change it from here. If you hit it,
say so in the community thread and we will sort it out with whoever maintains
that fork.

## What you can turn on

Fourteen rows under `OPTIONS`. The first two are read only. **Everything that
changes how the game looks starts turned off**, so installing this mod never
changes your game until you decide it should.

```
STATUS         read only, see above
LIFE           read only, the animation channel

VOXEL CHARS    OFF / 1 / 2 / 3 / 5 / 10          default 3      how thick
SIDE COLOR     BODY / OUTLINE                    default BODY   what the new faces are painted with
SHAPE          SLAB / CARVED / CARVED+           default SLAB   how the body is built
GROUND SHADE   OFF / ON                          default OFF    contact shadow at the feet
BLINK          OFF / ON                          default OFF    they blink
TOP EDGE       OFF / ON                          default ON     darkens exposed top faces

FRONT SHAPE    OFF / LOW / MED / HIGH            default OFF    false roundness on the front
TOP DOME       OFF / LOW / HIGH                  default OFF    a domed head instead of a flat lid
STEP WEIGHT    OFF / LOW / HIGH                  default OFF    the body follows the step

BREATH         OFF / SUBTLE / NORMAL / STRONG    default OFF    they breathe
SWAY           OFF / SUBTLE / NORMAL             default OFF    idle weight shift
MOTION LAG     OFF / SUBTLE / NORMAL             default OFF    the body arrives after the step
```

**If you only try one thing, try `BREATH: SUBTLE`.** It is half a pixel of
movement and it is the difference between a diorama of statues and a town.

Every character breathes on their own clock, so a room full of people does not
pulse in unison. A few sheets have their own temperament: someone asleep
breathes slowly and does not sway, a swimmer sways more, a guard at attention
barely moves. Item balls and boulders do not breathe at all, for reasons that
should be obvious the moment you picture the alternative.

### SHAPE, in one paragraph each

**SLAB** takes the sprite and gives it thickness, like a cookie cutter. Fast,
predictable, and it keeps every one of the artist's pixels facing you.

**CARVED** builds a real volume by intersecting the three views the game
already has of each character: front, back and side. It looks like 3D Dot Game
Heroes. It also loses detail, and that is not a bug we can fix: a shape built
from silhouettes cannot reconstruct a dent. An armpit, the gap between an arm
and the body, the space between the legs, none of them survive, because none of
them shows up in any silhouette.

**CARVED+** is CARVED with tone relief added back.

## What it does not do

- **Battles.** They go through a different drawing path with only two views of
  each character, front and back. No side view means no depth information, so
  there is nothing to build a body out of.
- **First person.** Handed back as a flat card on purpose.
- **Furniture, terrain, buildings.** That is the voxel mod's job, not ours.

It does cover item balls on the ground, because the game draws those as
characters too.

## How it works, briefly

The voxel mod asks itself for a character's mesh once per character per frame,
and then draws it. We replace both ends of that.

**The mesh** is built from your sprite sheet. We read the opaque pixels, group
them into horizontal runs, and emit geometry for the runs instead of one quad
per pixel, which is what keeps a character inside the mesh budget. Face shading
comes from the host's own table, so our characters catch the light exactly like
the props around them.

**The animation** never touches that mesh. The voxel mod builds a fresh
transform matrix for every character every frame, and we multiply a small one
into it. That is why a room of identical NPCs can each move differently even
though they share a single mesh, and why turning all of it on costs less than
this machine can measure against a 16.7 ms frame.

We attach by capability, never by version number. The mod asks the voxel mod
what it can do and believes the answer. Version numbers are logged and ignored,
because three forks now version independently and a hard version gate kept
rejecting hosts whose API was perfectly intact.

## Tests

```
luajit mods/voxel_characters/tests/voxel_chars_test.lua     480 checks
bash mods/voxel_characters/tools/render/check.sh            the offline ruler, checking itself
bash mods/voxel_characters/tools/ingame/run.sh <dir>        drives the real game, 11 screenshots
bash mods/voxel_characters/tools/ingame/clip.sh <dir> <k=v> side by side video of any option
```

All from the gen1recomp root. The offline harness measures geometry in two
seconds against a mocked host. The in game tools boot the real game with no one
touching it and photograph or film the result, which is the only way to judge
anything that happens over time.

## Credits

This mod exists because the Dramatic Shape Voxel Mod lineage exports a
namespace we can call into at runtime. **DramaticShape** wrote the original.
**absol89** maintains the Battle Art Voxel Fork and **artyrambles** the
Dramaless Shape Voxel Mod, and both are accepted here as equal hosts. None is
treated as more official than another.

Built on [gen1recomp](https://github.com/bryanthaboi/gen1recomp) by
**bryanthaboi**.

The community found most of what is fixed in here. **Pikon** found black faces
and side blinking by watching a video frame by frame. **ty_mcdk** pointed at
3D Dot Game Heroes, which is where CARVED came from. **Rob** asked what the mod
actually covered and revealed the description was underselling it.
**Ferretonin** reported that CARVED loses detail, which is true and now
documented instead of denied. **AngelusRole**, **TwoTracks** and
**Tyler Durden** each hit a different silent failure, and the `STATUS` row
exists because of them. **Colonel_Aureliano** found the first person spikes and
a menu option that changed nothing on screen. **absol** asked for Dramaless
Shape support and got it in 1.5.0.

This mod contains no code from any of the above. It calls their exported API at
runtime, on your machine.
