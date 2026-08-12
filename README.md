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

The one exception is two short sound effects for the `DEMO FX` option, which is
off by default. They are the only thing here that is not from your own game
files, and the section on that option says so.

## Install

**You need two mods: a voxel mod, and this one.** This mod does nothing on its
own, because it works by extending a voxel mod that is already running.

1. **Install a voxel mod first.** Any of these works:
   - **Dramatic Shape Voxel Mod** by DramaticShape, the original
   - **Battle Art Voxel Fork** by absol89
   - **Dramaless Shape Voxel Mod** by artyrambles

2. **Download `voxel_characters-1.6.0.zip`** from the
   [latest release](https://github.com/last-swagger/gen1recomp-voxel-characters/releases/latest).
   Do not unzip it.

3. **In game: `MODS`, then `Import mod .zip`.** Pick the file you downloaded.

4. **Enable Voxel Characters** in the mod list, and restart when it asks.

5. **Open `OPTIONS` and scroll down.** You are looking for a row that says
   `STATUS`. If it says `ACTIVE`, you are done, and everything below it is
   yours to play with.

You need gen1recomp `0.1.51` or newer.

**Updating later is easier.** From 1.6.0 on, the game's own `MODS` screen finds
new versions and installs them for you. Before 1.6.0 it never could, and that
was our fault: the release carried the package under a `.modpkg` name, and the
in game updater only looks at assets ending in `.zip`
(`src/mods/ModUpdate.lua`). Every release from 1.0.0 to 1.6.0 was invisible to
it, which is a large part of why so many people asked how to install this by
hand. **absol** worked it out after hitting the same thing on their own fork.

### It is installed and nothing looks different

Open `OPTIONS`, scroll to the `STATUS` row, and read it. That row exists
because three different people hit three different problems that all looked
identical from the outside, and none of them could tell which one they had.

| STATUS says | What happened |
|---|---|
| `NO HOST` | No voxel mod is running that this one can attach to. Install one, or enable it. |
| `OFF` | `VOXEL CHARS` is set to `OFF`. Set it to `3`. |
| `ACTIVE` | It is working. If you still see no difference, your camera is at the flat 2D rung. Press `3` to cycle the voxel camera. |
| `FIRST PERSON` | On purpose. We are handing back the flat card while a first person camera is blending, which is the default. Set the `FIRST PERSON` option to `SOLID` to keep the body through the blend. |
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

The mod adds ONE entry to the game's own `OPTIONS`, called `CHARACTERS`, and
everything below lives behind it. On a host too old to register a screen they
appear on the main list instead, which is where they were before 1.7.0.

From the overworld, **backslash** opens `CHARACTERS` directly, so trying an
option out costs one key instead of six. It does nothing anywhere else: a
menu pushed on top of a battle or a dialog is how a shortcut like this one
corrupts a save.

There are 20 rows under `OPTIONS`, all of them inside `CHARACTERS`. The first
two are read only, and the third is a button rather than a setting.

**Anything new starts turned off.** Two things are on out of the box, `BLINK`
and `BREATH`, and both earned it: they were shipped off, people used them, and
nobody wanted them back off. `BREATH` is on at its lowest level, which is under
a pixel of movement. If you want the mod to change nothing at all, both are one
button away.

```
STATUS         read only, see above
LIFE           read only, the animation channel
CAMERA FIT     press A to set the thickness this camera can afford

VOXEL CHARS    OFF / 1 / 2 / 3 / 5 / 10          default 3      how thick
SIDE COLOR     BODY / OUTLINE                    default BODY   what the new faces are painted with
SHAPE          SLAB / CARVED / CARVED+           default SLAB   how the body is built
GROUND SHADE   OFF / ON                          default OFF    contact shadow at the feet
BLINK          OFF / ON                          default ON     they blink
TOP EDGE       OFF / ON                          default ON     darkens exposed top faces

FRONT SHAPE    OFF / LOW / MED / HIGH            default OFF    false roundness on the front
TOP DOME       OFF / LOW / HIGH                  default OFF    a domed head instead of a flat lid
STEP WEIGHT    OFF / LOW / HIGH                  default OFF    the body follows the step

BREATH         OFF / SUBTLE / NORMAL / STRONG    default SUBTLE they breathe
SWAY           OFF / SUBTLE / NORMAL             default OFF    idle weight shift
MOTION LAG     OFF / SUBTLE / NORMAL             default OFF    the body arrives after the step
FOOTFALL       OFF / SUBTLE / NORMAL             default OFF    it compresses on each step
ATTENTION      OFF / SUBTLE / CLEAR              default OFF    they lean toward you, never turn
HD SPRITE      OFF / ON                          default OFF    a higher-resolution sheet, not from your ROM

FIRST PERSON   CARD / SOLID                      default CARD   solid through the first person blend

DEMO FX        OFF / FIREBALL / BOLT             default OFF    a capability demo, not a Gen 1 feature
```

**If you only try one thing, try `BREATH: SUBTLE`.** It is half a pixel of
movement and it is the difference between a diorama of statues and a town.

Every character breathes on their own clock, so a room full of people does not
pulse in unison. A few sheets have their own temperament: someone asleep
breathes slowly and does not sway, a swimmer sways more, a guard at attention
barely moves. Item balls and boulders do not breathe at all, for reasons that
should be obvious the moment you picture the alternative.

### ATTENTION leans, and never turns

A character that notices you inclines toward you. It does not rotate to face
you, and that is a hard rule rather than a shortcut: the side faces of a solid
carry **0% of the artist's art**, because the artist drew these characters from
the front and never from the side. The only reason nobody has ever seen that is
that this game never turns a character. One that turned to look at you would
show you the invented surface and nothing else, which is the opposite of being
noticed.

So the levels are a lean, measured as head displacement: `SUBTLE` is half a
world pixel and `CLEAR` is one. `SWAY: NORMAL` is 0.45 for comparison, so
`SUBTLE` is about the size of a breath. It also needs to decide slowly, or it
reads as twitching instead of attention, so there is hysteresis on the way in
and on the way out.

### PART LAG is held back, and the measurements say why

It does not ship in 1.7.0. It is in the code and it is not in the menu, because
neither of its two levels turned out to be worth offering.

`HIGH` (0.16 s of delay) is visible and looks wrong: the body reads as coming
apart rather than as the head arriving late. `LOW` (0.08 s) was then measured
against the clip tool's own guard and does not clear it -- the two sides of the
comparison differ from each other LESS than one side differs from itself, which
means the effect is smaller than the animation's own frame-to-frame variation.
An option whose only choices are "looks wrong" and "cannot be seen" is not a
choice.

Kept rather than deleted, because a measured negative is a result: the four
bands are cut from the CELL and not from the figure, and
`tools/measure_regions.py` found that a walking frame sits one row lower in its
cell than a standing one. `AUTHORED REGIONS` was built to cut along the figure
instead, and is held with it, since it exists only to refine where `PART LAG`
cuts.

### FIRST PERSON: SOLID is worth its transition, and nothing after it

Since 1.3.0 this mod has handed back the flat card the moment a first person
camera starts blending. That was a fix, not laziness: **Colonel_Aureliano**
reported black spikes, and the cause is proximity rather than camera. The voxel
shader pulls every vertex toward the eye, so on a solid the near corners cross
the near plane before the far ones and what is left on screen is a spike. A
flat card survives because all of its vertices cross together.

`SOLID` keeps the body and removes the spikes by capping that pull instead of
giving up the volume. **Be clear about what it buys, because it is easy to
oversell.** Measured across eight blend values, reproducing byte for byte over
four runs, the effect grows through the transition, peaks at blend 0.74 at 5.9%
of the frame, and is **exactly zero by blend 0.83**, because the host hides your
own card as the blend completes. That is deliberate on the host's side.

So this is not a solid body you can walk around in first person. There is
nothing to see at a settled first person view either way. What it is worth is
the entry and the exit: your own body used to collapse to a flat card exactly
when the camera came closest to it, and now it does not.

### DEMO FX is a demo, and the name is the honest part

Turn it on and the character throws a small effect from its hand every time a
foot lands. Two kinds: `FIREBALL` travels and fades, `BOLT` flashes and is gone.

**This is not a Gen 1 feature and it is not pretending to be one.** It exists to
show that this mod can own character effects with a position and a lifetime,
rather than only bending the body. It touches nothing: no save data, no battles,
no link play, no encounters, no gameplay of any kind. Switch it off and the next
frame is exactly what it was before.

**It makes a sound, and this is the one place the mod ships something of its
own.** Two short effects live in `sfx/`, a whoosh for the fireball and a crack
for the bolt. Everywhere else in this mod every pixel on screen is the artist's,
read from your own game files; these two files are not, and saying so plainly is
part of shipping them. They are generated by a script in `tools/`, and a gate
re-derives them on every run to check the files in the package really are what
that script produces.

One sound per effect, at the moment the effect leaves the hand, and nothing at
all when the option is off.

Where the effect comes out of is not a guess. The mod knows where the
character's hand is, and when a foot lands, and it uses both.

### CAMERA FIT, and why thickness is not one number

Press `3` in game and the camera tilts through the voxel mod's ladder. How much
of a character you see from the front, versus how much you see of its top, moves
a lot along that ladder. And the top is the part the artist never drew.

Rendered on `red`, share of the drawn pixels that is the artist's own art:

```
              rung 15   rung 35   rung 50   rung 75
  depth  1     76.3      88.4      92.8      97.6
  depth  2     62.2      80.0      86.9      95.5
  depth  3     52.4      73.4      81.6      93.3
  depth  5     40.1      62.9      73.8      89.1
  depth 10     26.0      49.6      62.1      81.0
```

The default this mod ships, rung 35 at depth 3, sits at 73.4%. Take that as the
bar, and the thickest setting each camera can afford is **1, 3, 5 and 10**. Set
that way, every camera lands in the same place: roughly three quarters art.

`CAMERA FIT` is a button, not a setting. It reads the camera you are on, shows
what it would do, and applies it when you press A. It never changes anything on
its own, because a mod quietly undoing your choice every time you press `3` is
worse than a mod that lets you keep a setting you like.

**The one worth knowing:** on the most upright camera you can run the thickest
setting in the menu and still have more of the artist's art on screen than the
default has today. If you play there, you are leaving volume on the table.

### SHAPE is not a quality ladder

It is a choice between two different things, and the menu order is historical,
not a ranking.

**SLAB** takes the sprite and gives it thickness, like a cookie cutter. The
artist's front face stays flat and whole, which is exactly what this game's
camera spends its time looking at. This is the mode this game wants.

**CARVED** builds a real volume by intersecting the three views the game already
has of each character: front, back and side. Its silhouette is correct from any
angle. It looks like 3D Dot Game Heroes.

It also loses detail here, and the reason is measurable rather than a matter of
taste. On `red`, SLAB emits 104 quads with 16 of them facing up; CARVED emits
1068 with **216** facing up. Upward facing surface is surface the artist never
drew, and a camera looking down is looking straight at it.

That is the same law that killed three earlier attempts at variable depth in
this mod: any change in depth creates a step, every step exposes an upward face,
and upward faces carry no art. **In this game, flat geometry with varied shading
wins.** Which is what `FRONT SHAPE` and `TOP DOME` are: they buy the reading of
volume with shading alone, leaving the silhouette pixel identical.

There is a second, harder limit on CARVED worth knowing: a shape built from
silhouettes cannot reconstruct a dent. An armpit, the gap between an arm and the
body, the space between the legs, none survive, because none appears in any
silhouette. And the side view is a separate drawing rather than a projection of
the same object, so the three views do not fully agree with each other.

**CARVED+** is CARVED with tone relief added back.

**So when would you pick CARVED?** When you care about the silhouette from
angles this game never uses, or when you want an actual volume rather than a
thick card. It is the only one of the two that produces something a 3D pipeline
outside this game could start from.

## What it does not do

- **Battles.** They go through a different drawing path with only two views of
  each character, front and back. No side view means no depth information, so
  there is nothing to build a body out of.
- **First person, by default.** Handed back as a flat card on purpose, because
  a solid picks up spikes as the camera enters it. `FIRST PERSON: SOLID` keeps
  the body through the blend, and buys nothing at a settled first person view,
  where the host hides your card anyway.
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
bash  mods/voxel_characters/tools/bateria.sh                the whole battery, in order
bash  mods/voxel_characters/tools/bateria.sh --rapido       the half that needs no game
luajit mods/voxel_characters/tests/voxel_chars_test.lua     620 checks
bash mods/voxel_characters/tools/render/check.sh            the offline ruler, checking itself
bash mods/voxel_characters/tools/ingame/run.sh <dir>        drives the real game, 11 screenshots
bash mods/voxel_characters/tools/ingame/clip.sh <dir> <k=v> side by side video of any option
bash mods/voxel_characters/tools/release_check.sh           asks the GAME whether a release is installable
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
