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

### My angle changed, or the picture looks stretched

Not this mod, and worth saying plainly because the two get installed together.
Measured: with our characters off against on, **1.2% of the frame changes** and
all of it sits where the characters are. The ground, the buildings and the sky
come out pixel for pixel identical. If we moved the camera, everything would
move.

What you are almost certainly seeing is the game's own **`TILT`** -- the
perspective tilt for the overworld, `OFF / 15 / 35 / 50`, saved in your options.
A voxel mod sets it to `0` when it loads and takes the row off the menu, so
there is nowhere left to put it back. That is the voxel mod's decision, made on
purpose: its own 3D camera and the engine's tilt are two perspectives of the
same ground, and running both is not a look anybody chose.

**It is not lost.** The value is still in your save. Turn the voxel mod off and
the `TILT` row comes back at whatever you had it on.

The stretching is the same story from the other side: the flat game draws a
160x144 picture scaled inside your window, and a voxel mod draws a 3D scene that
fills it. Nothing was resized -- you are looking at a different picture.

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

There are 23 rows under `OPTIONS`, all of them inside `CHARACTERS`. The first
two are read only, and the next two are buttons rather than settings.

**The defaults are somebody's choice, not a safe minimum.** They were set by
playing with the menu until there was nothing left to change: `SIDE COLOR:
OUTLINE`, `SHAPE: SLAB` at depth `3`, `GROUND SHADE: ON`, `TOP EDGE: ON`,
`FRONT SHAPE: HIGH` and `BREATH: SUBTLE`.

Anything nobody has judged yet still ships off. That rule protects a person who
did not choose; the list above is what the person who DID choose arrived at.
`SETTINGS: DEFAULT` puts all of it back at any time, and `SETTINGS: STILL`
stops every movement if you want the shape and nothing else.

```
STATUS         read only, see above
LIFE           read only, the animation channel
CAMERA FIT     press A to set the thickness this camera can afford
SETTINGS       browse with left/right, press A to apply a whole set

VOXEL CHARS    OFF / 1 / 2 / 3 / 5 / 10          default 3      how thick
SIDE COLOR     BODY / OUTLINE                    default OUTLINE what the new faces are painted with
SHAPE          SLAB / CARVED / CARVED+           default SLAB   how the body is built
GROUND SHADE   OFF / ON                          default ON     contact shadow at the feet
BLINK          OFF / ON                          default ON     they blink
BLINK DETECT   OFF / ON                          default OFF    finds the eyes on sheets we never measured
V-GRID CHARS   OFF / ON                          default ON     joins the world grid on key 5

TOP EDGE       OFF / ON                          default ON     darkens exposed top faces
                                                 little effect under SIDE COLOR: OUTLINE
FRONT SHAPE    OFF / LOW / MED / HIGH            default HIGH   false roundness on the front
TOP DOME       OFF / LOW / HIGH                  default OFF    a domed head instead of a flat lid
                                                 little effect under SIDE COLOR: OUTLINE
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

**`SETTINGS` applies a whole set at once**, because a menu with twenty three rows
is a menu nobody configures twice. `DEFAULT` is what ships. `LIVED IN` is read
off a save after somebody played with the menu until they stopped changing
things -- four of its choices disagree with the shipped defaults, and that is
why it is worth having. `STILL` stops all motion, for judging shape or for any
comparison where movement would swamp what you are comparing. `SHOWCASE` turns
every motion on at a level that reads on video. None of them touch `HD SPRITE`
or `DEMO FX`, which are experiments you switch on deliberately.

**Two rows say `LITTLE EFFECT` under the shipped `SIDE COLOR: OUTLINE`, and
they mean it literally.** `TOP EDGE` and `TOP DOME` shade the top faces, and
OUTLINE paints those faces with the sprite's outline, which on all 67 sheets is
exactly black -- no shade multiplier lifts black. Measured: byte-identical at
every level on 56 of the 67 sheets. Eleven do respond, `seel` by 35% of the
figure, which is why the rows still work and are not locked. Switch `SIDE
COLOR` to `BODY` and they move 18-22% of the character.

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
exactly what `FRONT SHAPE` and `TOP DOME` are. **CARVED is also retired as a direction**, for the same reason and with one
exception worth stating. Measured, it loses to SLAB at this game's camera, and
that is not close. It stays in the menu, and the code stays, because it is the
only one of the two that builds an actual volume -- a SLAB is a thick card and
means nothing outside this camera. If this ever goes somewhere the camera turns,
CARVED is the only starting point there is. That is a reason not to delete it,
not a reason to invest in it now.

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

**`HD SPRITE` was an experiment and it is retired.** A higher resolution sheet,
enlarged from the real one by an LLM. It invented no shape -- the silhouette
matched the original almost exactly -- and what it did invent was detail INSIDE
each original pixel. That detail cannot reach the screen: this game colours by
sorting every pixel into one of four shades, so anything finer is discarded on
the way out. Looked at in the game, the difference was not worth having.

It still ships, off, because a measured negative is a result and deleting it
would turn "we measured this and it did not pay" into "nobody tried". Do not
expect work on it. Five of the ten unit bugs found in this mod's history were
reachable only through it, and so was half a second of freeze on the first
walking step.

**Thin lines flicker on a breathing character, and that is accepted rather than
unnoticed.** Moving pixel art through a 3D transform lands the boundary between
two sprite rows on its neighbour for an instant, and the darkest tone on all 67
sheets is exactly black, so the neighbour is usually black. Measured on a
STANDING character over 48 frames with only `BREATH: SUBTLE` on: 532 pixels swing
more than 0.15 in luminance, the worst by 0.915, and they form thin horizontal
bands on the figure and nowhere else in the room. `BREATH: OFF` removes it
completely -- 0.0%, not "less".

It was looked at and judged acceptable. Two mitigations exist and neither ships:
snapping the animation to whole screen pixels (kills it, makes the movement
harder), and overlapping adjacent row quads (costs geometry, softens the row
separation). Written down so the next person measures the same thing and stops,
instead of fixing what nobody asked to have fixed.

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
luajit mods/voxel_characters/tools/hd_equivalence.lua       HD SPRITE must paint the ROM's picture
bash mods/voxel_characters/tools/render/check.sh            the offline ruler, checking itself
bash mods/voxel_characters/tools/ingame/run.sh <dir>        drives the real game, screenshots
bash mods/voxel_characters/tools/ingame/clip.sh <dir> <k=v> side by side video of any option
bash mods/voxel_characters/tools/ingame/hosts.sh            boots EVERY voxel host installed, on Blue and Gold
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
