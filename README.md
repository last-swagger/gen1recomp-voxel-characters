# Voxel Characters

The voxel world is 3D. The people in it are flat cards.

This mod fixes that, and then keeps going: it builds each character a real body
out of their own pixels, and then gives that body something to do. They breathe.
They shift their weight. They lean into a step and settle when they stop.

Nothing here is drawn by us. Every pixel on screen is the artist's, read from
your own game files at runtime. We only decide where those pixels sit in space
and how they move.

It is a companion mod. It contains no code from any voxel mod, ships no
character art, and modifies nothing on disk. Turn it off and the original flat
card is back on the next frame.

Two exceptions, both stated where they live: the sound effects for `DEMO FX`,
and the sheet used by `HD SPRITE`. Both options are off by default.

## Install

**You need two mods: a voxel mod, and this one.** This mod does nothing on its
own, because it works by extending a voxel mod that is already running.

1. **Install a voxel mod first.** Any of these works, and none is treated as
   more official than another:
   - **Dramatic Shape Voxel Mod** by DramaticShape, the original
   - **PotatoVoxel** by ShaneMcGovernIE
   - **Battle Art Voxel Fork** by absol89
   - **Dramaless Shape Voxel Mod** by artyrambles

   Only ONE at a time.

2. **Download the `.zip`** from the
   [latest release](https://github.com/last-swagger/gen1recomp-voxel-characters/releases/latest).
   Do not unzip it.

3. **In game: `MODS`, then `Import mod .zip`.** Pick the file you downloaded.

4. **Enable Voxel Characters** in the mod list, and restart when it asks.

5. **Open `OPTIONS`, and open the `CHARACTERS` row.** The first line says
   `STATUS`. If it reads `ACTIVE`, you are done.

You need gen1recomp `0.1.51` or newer. From 1.6.0 on the game's own `MODS`
screen finds new versions for you; earlier releases were invisible to it
because the package was named `.modpkg` and the updater only reads `.zip`.
**absol** worked that out.

### It is installed and nothing looks different

Read the `STATUS` row. It exists because three people hit three different
problems that looked identical from the outside.

| STATUS says | What happened |
|---|---|
| `NO HOST` | No voxel mod is running that this one can attach to. Install one, or enable it. |
| `OFF` | `VOXEL CHARS` is set to `OFF`. Set it to `3`. |
| `ACTIVE` | It is working. If you still see no difference, your camera is at the flat 2D rung. Press `3` to cycle the voxel camera. |
| `FIRST PERSON` | On purpose. We hand back the flat card while a first person camera is blending. Set `FIRST PERSON` to `SOLID` to keep the body through it. |
| `REPLACED` | Another mod took over the same drawing function after we did. |
| `MASK ERROR` / `BUILD ERROR` / `DRAW ERROR` | Something went wrong reading or building sprites. Characters fall back to flat cards instead of breaking. |

A second row, `LIFE`, reports the animation channel the same way. `NO CHANNEL`
means your voxel mod is too old for it; everything else still works and the
animation rows simply do not appear.

**A version conflict** declared in a voxel mod's manifest is that mod's file,
not ours. Say so in the community thread and we will sort it out with whoever
maintains that fork.

## What you can turn on

The mod adds ONE entry to the game's own `OPTIONS`, called `CHARACTERS`, and
everything lives behind it. From the overworld, **backslash** opens it
directly. It does nothing anywhere else, because a menu pushed on top of a
battle or a dialog is how a shortcut like that corrupts a save.

With [Modern UI](https://github.com/) installed the screen wears that mod's
design, and gains a `WHAT EACH ONE DOES` row that explains every option in
game. That row is hidden without Modern UI: the explanations are full
sentences, and the native 160x144 renderer would run them off the edge.

There are 22 rows under `OPTIONS`, all of them inside `CHARACTERS`. The first
two are read only, and the next two are buttons rather than settings.

**Anything new starts turned off.** Two things are on out of the box, `BLINK`
and `BREATH`, and both earned it: they shipped off, people used them, and
nobody wanted them back off. `BREATH` is on at its lowest level, under a pixel
of movement.

```
STATUS         read only, see above
LIFE           read only, the animation channel
CAMERA FIT     press A to set the thickness this camera can afford
SETTINGS       browse with left/right, press A to apply a whole set

VOXEL CHARS    OFF / 1 / 2 / 3 / 5 / 10          default 3      how thick
SIDE COLOR     BODY / OUTLINE                    default BODY   what the new faces are painted with
SHAPE          SLAB / CARVED / CARVED+           default SLAB   how the body is built
GROUND SHADE   OFF / ON                          default OFF    contact shadow at the feet
BLINK          OFF / ON                          default ON     they blink
V-GRID CHARS   OFF / ON                          default OFF    debug: shows where the geometry is

TOP EDGE       OFF / ON                          default ON     darkens exposed top faces
FRONT SHAPE    OFF / LOW / MED / HIGH            default OFF    false roundness on the front
TOP DOME       OFF / LOW / HIGH                  default OFF    a domed head instead of a flat lid
STEP WEIGHT    OFF / LOW / HIGH                  default OFF    the body follows the step
                                                 those four need SHAPE: SLAB

BREATH         OFF / SUBTLE / NORMAL / STRONG    default SUBTLE they breathe
SWAY           OFF / SUBTLE / NORMAL             default OFF    idle weight shift
MOTION LAG     OFF / SUBTLE / NORMAL             default OFF    the body arrives after the step
FOOTFALL       OFF / SUBTLE / NORMAL             default OFF    it compresses on each step
ATTENTION      OFF / SUBTLE / CLEAR              default OFF    they lean toward you, never turn
HD SPRITE      OFF / ON                          default OFF    a higher-resolution sheet, not from your ROM

FIRST PERSON   CARD / SOLID                      default CARD   solid through the first person blend

DEMO FX        OFF / FIREBALL / BOLT             default OFF    a capability demo, not a Gen 1 feature
```

**`SETTINGS` applies a whole set at once**, because a menu with twenty two rows
is a menu nobody configures twice. `DEFAULT` is what ships. `LIVED IN` is read
off a save after somebody played with the menu until they stopped changing
things -- four of its choices disagree with the shipped defaults, and that is
why it is worth having. `STILL` stops all motion, for judging shape or for any
comparison where movement would swamp what you are comparing. `SHOWCASE` turns
every motion on at a level that reads on video. None of them touch `HD SPRITE`
or `DEMO FX`, which are experiments you switch on deliberately.

**Some options only mean something next to another one**, and the menu says so
rather than pretending. A row that cannot do anything shows what to change
instead of a value, and refuses to move. It never offers a setting that would
silently do nothing.

**If you only try one thing, try `BREATH: SUBTLE`.** Half a pixel of movement,
and the difference between a diorama of statues and a town. Every character
breathes on their own clock, and a few have their own temperament: someone
asleep breathes slowly and does not sway, a swimmer sways more, a guard at
attention barely moves. Item balls and boulders do not breathe.

## Things worth knowing before you judge an option

These are measured rather than argued. The full reasoning for each lives in
`CHANGELOG.md` under the release that changed it.

**`SHAPE` is not a quality ladder.** SLAB gives the sprite thickness and keeps
the artist's front face flat and whole, which is what this game's camera looks
at. CARVED builds a real volume from the front, back and side views: correct
from any angle, and it looks like 3D Dot Game Heroes. On `red`, SLAB emits 104
quads with 16 facing up; CARVED emits 1068 with **216** facing up, and upward
facing surface is surface the artist never drew. A shape built from silhouettes
also cannot reconstruct a dent, so armpits and the gap between the legs do not
survive. **In this game, flat geometry with varied shading wins** -- which is
exactly what `FRONT SHAPE` and `TOP DOME` are. Pick CARVED when you want a real
volume, or a silhouette that holds up at angles this game never uses.

**Thickness is not one number.** How much of a character you see from the front
versus from above changes a lot along the camera ladder, and the top is the part
nobody drew. Share of drawn pixels that is the artist's own art, on `red`:

```
              rung 15   rung 35   rung 50   rung 75
  depth  1     76.3      88.4      92.8      97.6
  depth  3     52.4      73.4      81.6      93.3
  depth  5     40.1      62.9      73.8      89.1
  depth 10     26.0      49.6      62.1      81.0
```

The shipped default, rung 35 at depth 3, sits at 73.4%. Take that as the bar and
the thickest each camera can afford is **1, 3, 5 and 10** -- which is what
`CAMERA FIT` applies when you press A on it. It never changes anything on its
own. On the most upright camera you can run the thickest setting and still have
more art on screen than the default does.

**`ATTENTION` leans and never turns**, and that is a hard rule. The side faces
of a solid carry **0% of the artist's art**, because these characters were drawn
from the front and never from the side. One that turned to look at you would
show you the invented surface and nothing else.

**`FIRST PERSON: SOLID` buys the transition, not the destination.** Measured
across eight blend values, the effect peaks at blend 0.74 at 5.9% of the frame
and is **exactly zero by 0.83**, because the host hides your own card as the
blend completes. What it fixes is real: your body used to collapse to a flat
card exactly as the camera came closest to it.

**`V-GRID CHARS` rides the world's wireframe rather than competing with it.**
Press `5` for the voxel grid and characters join it; with the grid off the row
says so and does nothing, because the wireframe is a separate compiled shader
the renderer only binds when the world asks for it. The voxel mod deliberately
keeps seams off characters and is right to -- a grid over a 16x16 sprite lands
a line every couple of pixels. Turn this on to see where the mod actually
placed geometry.

**`HD SPRITE` is an experiment, and the first option that draws pixels your ROM
does not contain.** A higher resolution sheet, enlarged by an LLM from the real
one. It invents no shape: the silhouette matches the original almost exactly.
What it invents is detail inside each original pixel, and the game's own
colouring classifies every pixel into four shades, so most of that detail does
not survive to the screen. Off by default, and it only affects sheets that ship
a file.

**`PART LAG` does not ship**, and the measured negative is why it is kept in the
code rather than deleted. `HIGH` looks wrong -- the body reads as coming apart.
`LOW` does not clear the clip tool's own guard: the two sides of the comparison
differ from each other less than one side differs from itself, so the effect is
smaller than the animation's own variation. An option whose only choices are
"looks wrong" and "cannot be seen" is not a choice.

**`DEMO FX` is not a Gen 1 feature and does not pretend to be one.** It exists
to show this mod can own an effect with a position and a lifetime. It touches no
save data, no battles, no encounters. It ships two short sounds in `sfx/`, the
only files here not read from your own game -- generated by a script in
`tools/`, and re-derived by a gate on every run to prove the shipped files are
what that script produces.

## What it does not do

- **Battles.** A different drawing path, with only front and back views. No side
  view means no depth to build a body from.
- **First person, by default.** Handed back as a flat card on purpose.
- **Furniture, terrain, buildings.** That is the voxel mod's job.

It does cover item balls on the ground, because the game draws those as
characters too.

## How it works, briefly

The voxel mod asks itself for a character's mesh once per character per frame,
and then draws it. We replace both ends of that.

**The mesh** is built from your sprite sheet: opaque pixels grouped into
horizontal runs, geometry emitted per run rather than per pixel, which is what
keeps a character inside the mesh budget. Face shading comes from the host's own
table, so our characters catch the light like the props around them.

**The animation** never touches that mesh. The voxel mod builds a fresh
transform for every character every frame and we multiply a small one into it.
That is why a room of identical NPCs can each move differently while sharing one
mesh.

We attach **by capability, never by version number**. The mod asks the voxel mod
what it can do and believes the answer. Versions are logged and ignored, because
several forks now version independently and a hard gate kept rejecting hosts
whose API was perfectly intact.

## Tests

```
bash  mods/voxel_characters/tools/bateria.sh                the whole battery, in order
bash  mods/voxel_characters/tools/bateria.sh --rapido       the half that needs no game
luajit mods/voxel_characters/tests/voxel_chars_test.lua     the unit suite
bash mods/voxel_characters/tools/render/check.sh            the offline ruler, checking itself
bash mods/voxel_characters/tools/ingame/run.sh <dir>        drives the real game, screenshots
bash mods/voxel_characters/tools/ingame/clip.sh <dir> <k=v> side by side video of any option
bash mods/voxel_characters/tools/release_check.sh           asks the GAME whether a release is installable
```

All from the gen1recomp root. The offline harness measures geometry in two
seconds against a mocked host. The in game tools boot the real game with nobody
touching it and photograph or film the result, which is the only way to judge
anything that happens over time.

## Credits

This mod exists because the Dramatic Shape Voxel Mod lineage exports a namespace
we can call into at runtime. **DramaticShape** wrote the original.
**ShaneMcGovernIE** maintains PotatoVoxel, **absol89** the Battle Art Voxel
Fork and **artyrambles** the Dramaless Shape Voxel Mod. All are accepted as
equal hosts.

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
