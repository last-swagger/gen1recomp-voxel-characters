# Handoff, 2026-08-10

Where the work is, what is proven, what is waiting on a person, and how to run
everything. Written for a session that starts with none of today's context.

## State in one paragraph

**v1.6.0 is released and installable from inside the game.** Branch `vida-v2`
carries 56 unreleased commits on top of it. Most of today was not features: an
adversarial audit by four agents found roughly forty checks that passed for
reasons unrelated to what they claimed, and fixing those exposed a real defect
in shipped behaviour. Nothing on the branch is pushed.

## Run everything

From the **repo root**, never from the mod directory. That is not style: a
relative path from the wrong directory makes LOVE open a window that waits for a
key, which from a script is a ten minute timeout with an empty log.

```
luajit mods/voxel_characters/tests/voxel_chars_test.lua     603 checks, the maths
luajit mods/voxel_characters/tools/lint_asserts.lua         checks that do not check
bash mods/voxel_characters/tools/folga_locais.sh            LuaJIT local headroom
bash mods/voxel_characters/tools/render/check.sh            the ruler checks itself
python3 tools/modkit.py validate mods/voxel_characters      packaging

POKEPORT_VERSION=blue POKEPORT_DRIVER=<driver> love .
  tools/ingame/probe_life.lua    10 pixel checks of the life channel
  tools/ingame/menu.lua          8 checks pressing real keys
  tools/ingame/probe_fp.lua      4 checks of first person
  tools/ingame/probe_draw.lua    8 checks that position arrives clean
  tools/ingame/probe_grid.lua    3 checks that the host grid stays off characters

bash mods/voxel_characters/tools/ingame/run.sh <dir>        15 photos + a control
bash mods/voxel_characters/tools/ingame/clip.sh <dir> <k=v> side by side video
bash mods/voxel_characters/tools/ingame/trailer.sh <dir>    the 49 second trailer
bash mods/voxel_characters/tools/release_check.sh           does the GAME accept it?
bash mods/voxel_characters/tools/sala_de_teste.sh <host>    the whole battery, remotely
bash mods/voxel_characters/tools/juiz/rodada.sh 30          one round of the judge
```

Green today: 603/603, ruler OK with 15 checks, every in-game gate passing.
`release_check.sh` is RED on purpose, see below.

The core repo's own suite is red with 18 pre-existing failures, verified against
a baseline without this mod. Ignore it.

## What is waiting on Kim, and nothing else moves without it

1. **Thirty A/B picks.** `bash mods/voxel_characters/tools/juiz/rodada.sh 30`
   prepares the most informative pairs and prints the line that opens the
   laboratory with them. This is the only input no agent can produce, and every
   generator idea downstream depends on it.
2. **A personal access token for the `last-swagger` account.** All nine releases
   are signed by the personal account, a release author cannot be edited after
   creation, and `release_check.sh` fails until the next release is signed
   correctly. It is red on purpose.
3. **His eye** on FOOTFALL, the CAMERA FIT criterion, and the three shape
   options he has never seen on a real screen.

## The defect that today found in shipped behaviour

**The life channel was animating in the camera's axis, not the character's.**
The builder bakes `Rx(corr)` into every vertex and the host cancels it, so
post-multiplying our transform landed it in mesh space, tilted by the pitch. The
world saw `Rx(t)·L·Rx(-t)` instead of `L`.

With BREATH SUBTLE, which ships ON: 7% of the advertised head rise at rung 15,
**33% at the default rung 35**, 59% at 50, 93% at 75, plus up to 0.079 px of
fore and aft drift nobody asked for. MOTION LAG was worst: its `kz` term came
out 82% vertical at the default rung, so "inertia" was largely bobbing.

Fixed by conjugating. No gate caught it because every life test asserted on the
MATRIX and none composed it with the rotation baked into the vertex. That test
exists now and measures world displacement at all four rungs.

## Two questions the measurements answered, and one they sharpened

**The host grid is not ours to add.** Measured: the grid changes 54700 samples
with the mod on and 54701 with it off. `VoxelScene.drawCast` wraps the character
pass in `Voxel3D.seams(false)` deliberately, because "the seams are what makes
the WORLD read as built out of voxels, and the people walking around in it are
the one thing that should read as drawn instead". We already behave correctly by
inheritance. `probe_grid.lua` guards that contract now.

**A blocker I had invented does not exist.** The roadmap said `setDrawRange` is
sticky state on a mesh `ShadowMap.draw` renders outside our wrap. `setDrawRange`
appears nowhere in this repository, and the shadow pass draws
`SpriteBillboards.shadowQuad`, the flat card, never our mesh. That fiction
blocked per-part motion for two sessions.

**First person sharpened rather than closed.** Head on, depth is invisible: the
SLAB silhouette is exactly the flat card at every depth. The cost appears only
at an angle (at yaw 30: art 94.7, 85.7, 78.5, 65.2 percent for depths 1, 3, 5,
10). But the host yaws first-person cards to face the eye, so a settled
first-person view is head-on. **So what does FIRST PERSON: SOLID buy at full
blend?** The probe measures at 0.58, mid-transition. Nobody has measured 1.0
with a character guaranteed in frame.

## Two machines

`ssh mbp` reaches the MacBook Pro, which runs the whole battery. Work is
dispatched to its `claude` CLI through the GUI session:

```
osascript -e 'tell application "Terminal" to do script "bash /tmp/mbp_runner.sh"'
```

**Not over plain ssh**, because the CLI keeps its credentials in the login
Keychain and an ssh session cannot unlock it. The symptom is "OAuth session
expired", which looks like an expired token and is not.

Code moves by `git bundle --all` plus `scp` plus `git fetch`, so nothing is
pushed. **Say explicitly in any spec that the git repo is
`mods/voxel_characters` itself**, a nested repo with its own remote: an agent
told only "branch vida-v2" looked at the outer repo, found the mod untracked,
and correctly refused to guess.

Its commits arrive authored as the machine's git identity. Amend to
`last-swagger` before keeping them; the identity on that machine is fixed now
but old commits are not.

## The traps that cost the most time, so they cost none next time

**LOVE answers an error with a window and waits for a key.** From a script that
is indistinguishable from heavy work. Every entry point now installs an error
handler that prints and exits, and `tools/love.sh` refuses a bad game path,
because that particular failure happens in LOVE's boot before any of our files
load and no handler can catch it.

**Do not screenshot the screen to read that window.** It was tried, and
`screencapture` takes whatever is in front. On a working machine that is
personal messages, twice. The images were deleted and the idea abandoned; the
fix never needed a picture.

**A measurement needs a floor from the same procedure.** This came up four
separate times today: the clip guard, the in-game photo control, V8's cost
benchmark, and the first-person transition. A threshold chosen as a fraction of
the frame passed a neutralised mod by a single sample. Two runs of the same
thing, changing nothing, measure what the scene does on its own.

**`VoxelState.setLevel` does not command anything.** The engine's Pipelines owns
the camera rung and rewrites `Voxel.level` every frame. The symptom of calling
the wrong one is "the blend never rose", which reads as the camera not existing.

**Only one LOVE at a time.** `run.sh`, `clip.sh` and `trailer.sh` all start with
`pkill -x love`. `tools/tools_bin.sh` now holds a lock; starting a second tool
refuses instead of destroying the first one's measurement.

## Standing rules that are not obvious from the code

- **Kim posts to Discord. Never me.** I prepare drafts.
- **Everything that is a project artefact is en-US**: comments, tests, commits,
  README, docs, trailer captions, release notes. Portuguese is for the
  conversation only. Over 3500 comment lines are still Portuguese; converting
  them is roadmap item 2 and has not started.
- **Every visual change new to the mod ships off.** Once the community has seen
  and approved one, on by default becomes the conservative choice.
- **Releases credit reporters by name and public text has no em dashes.**
- Local commits on a feature branch are routine. **Push, tag and release need
  Kim's word.**
- **Do not raise a threshold to make a light green.** Today V7 was left red at
  36 against 40, and the axis fix made it pass at full magnitude. The threshold
  was never the problem.
