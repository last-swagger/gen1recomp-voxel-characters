# Roadmap towards v2

Everything open, ordered by what I would build first, with what each item
actually changes once it lands. Written to be the input to a specification, so
each item says what it unblocks and what it costs, not just what it is.

Ordering rule: an item comes earlier when finishing it makes later items
cheaper or safer, not when it is more exciting. Three of the first four are
unglamorous on purpose.

---

## Tier 0 — nothing else is worth much until these land

### 1. Feed the judge

**State:** the machinery exists and is proven. `Laboratorio.command` shows two
variants, one key records a pick, `tools/juiz/juiz.sh` measures every variant
and fits a Bradley-Terry model. Its self-test recovers a known rule from 200
synthetic picks at 92.5% out of sample against 75% for the best single column.
What is missing is real picks.

**What changes:** this is the only thing in the project that can rank art
without a person in the loop, and it is a precondition for every generator idea
we have. We measured that an AI redraw satisfied every numeric constraint we
own and produced worse art; until a judge exists, any agent iterating against
our gates converges on something that scores well and looks wrong.

**Cost:** thirty to sixty of Kim's picks, roughly twenty minutes. Then the model
either beats the best single feature out of sample or it does not, and both
answers are useful: beating it means we can score candidates, failing means the
thing that decides preference is not in the feature list, which tells us what to
measure next.

### 2. Convert the project to en-US

**State:** decided, not started. Over 3500 comment lines are in Portuguese, plus
README, CHANGELOG, docs and test names.

**What changes:** the repository stops being closed to the community that feeds
it. This project exists because of outside reports and pull requests, so a
language barrier costs exactly the most valuable input we have.

**Cost:** high and irreducible. Almost every comment here explains a defect that
was paid for and why a decision went the way it did, so machine translation
would destroy the value that makes them worth keeping. It has to be read and
rewritten file by file. Suggested order: `main.lua` first (it is what a
contributor opens), then the tools, then the tests, then the docs.

### 3. Release identity and format

**State:** guarded, blocked on a token. `release_check.sh` now fails when the
author is not `last-swagger` and warns when the body is over 40 lines or has no
media. The nine published releases are signed by the personal account.

**What changes:** the project stops publishing under the wrong name, and the
release page starts being something a player can read in fifteen seconds. A
release author cannot be edited after creation, so this only fixes forward.

**Cost:** a personal access token from the `last-swagger` account, then an hour
to wire it into a `release.sh` that builds, signs, attaches the media the clip
and trailer tools produce, and verifies with the game's own parser.

---

## Tier 1 — the quality of what already exists

### 4. Trailer, from 6/10 to something we would post

**State:** it records, and the obvious defects are fixed (English captions, no
wall pushing, first person shown as a before and after pair).

**What changes:** it becomes the artefact that carries every release and every
Discord post, which is the difference between a feature existing and a feature
being seen. Concretely still missing: camera movement inside a shot instead of a
static frame, variety in time of day, a shot that holds on one face long enough
to read the blink, and a recorded mod set that excludes other people's mods so
nothing on screen is theirs.

**Cost:** low per improvement, and each one is a line in the shot list rather
than code.

### 5. Grid mode

**State:** not started. The host has a grid toggle and our characters ignore it.

**What changes:** our solids stop looking like they belong to a different mod
when the player turns the grid on. Two questions decide the shape of the work,
and both are measurements rather than opinions: does the host expose the grid
state where we can read it, and does its grid apply per mesh or per scene. If
per mesh, we can follow it for free; if per scene, we need our own.

**Cost:** small if the state is readable, and the answer arrives in an hour.

### 6. First-person depth

**State:** the mode works and is measured. The depth it uses is the overworld's.

**What changes:** first person stops inheriting a number that was tuned for a
camera looking down. The law that governs the overworld inverts here: top faces
go nearly invisible, and the side silhouette, which carries no art at all, is
exposed at arm's length. The number belongs in `CAMERA FIT`'s table alongside
the four rungs already measured.

**Cost:** one measurement pass with the harness, same method as the existing
table.

### 7. Stop the tools killing each other

**State:** a hazard we hit today. `run.sh`, `clip.sh` and `trailer.sh` all begin
with `pkill -x love`, so starting one kills any measurement already running. The
truncated output reads like a short measurement rather than an interrupted one.

**What changes:** measurements stop being silently wrong when two things run at
once, which matters more now that the MacBook Pro can run the battery too. A
lock file plus a clear refusal is the whole fix.

**Cost:** an hour.

---

## Tier 2 — new capability

### 8. Judge v2: pixel features and the generator loop

**State:** the fitter reads mesh features only. The metric this project has
always judged by, the pixel share of the frame that is the artist's work, needs
a provenance render per variant.

**What changes:** the judge gains the feature it most needs to beat, and once it
beats it, candidates can be generated and scored without a person, with the
person only seeing the top few. That is the loop Kim described: v1, v2, v3, each
generation informed by the last.

**Cost:** medium. The provenance render exists; feeding one variant per row
through it is the work.

### 9. Per-part secondary motion

**State:** blocked, with the blockers named from our own code rather than
guessed. Body-wide inertia already ships. Real hair and bag lag needs the mesh
split into regions drawn with their own matrices, and two things stand in the
way: the cut line has no cap faces, so slicing shows the inside of the back
wall, and `setDrawRange` is sticky state on a mesh that `ShadowMap.draw` renders
outside our wrap, so a forgotten range truncates the shadow.

**What changes:** characters stop moving as one rigid piece, which is the
difference between a breathing statue and something that reads as alive. It is
also the groundwork for anything rig-shaped later.

**Cost:** high, and it needs a design decision before code. The good news is
that emission is already top-to-bottom row by row in both builders, so "the top
N rows" is already a contiguous prefix.

### 10. Attention and anticipation

**State:** designed, not started, with one hard rule already settled: never
rotate in Y. Side faces carry 0.0% art and the only reason nobody sees that
today is that the game never turns a character.

**What changes:** NPCs stop being scenery. A character that notices the player
is the cheapest possible step from "the world has depth" to "the world has
people in it", and it needs hysteresis so it reads as attention rather than as
twitching.

### 11. Laboratory: regions and host settings

**State:** the lab shows one character, every mesh option, all 67 sheets, and
records A/B picks.

**What changes:** it becomes the tool that makes rigging tractable, by drawing
the region boundaries and cap faces we would need to cut along, and it becomes
the place to see our characters under the host's own settings (grid, shading,
camera) rather than only under ours. Both are things Kim asked for and both pay
off exactly when items 5 and 9 start.

---

## Tier 3 — parked, with the reason recorded

### 12. Battle rendering probe

Paused by Kim, kept visible because an earlier note read as closing it and did
not. "Battle art is dead" answered whether battle sprites can enrich the
*overworld* character, where it still holds. Rendering the battle itself is a
different question, and three of the arguments that killed variable depth do not
survive the change of camera: the top-face law was measured under a camera that
looks down, the AI depth map's 52% art was measured there too, and the missing
side view is the one view a battle never shows. **The cheap first step is a
capability probe of the battle path**, the same step 1 the overworld got: find
out whether there is a seam to patch before designing what goes through it.

### 13. Weather and wind

Roadmapped rather than built because it depends on mods we do not control. The
mechanism already ships: wind is one more shear term in `lifeApply`, exactly
like `SWAY`. What is missing is a source, and the first question is whether the
host or another mod exposes a wind or weather state we can read.

---

## Cross-cutting: testing, practices, and the harness itself

These are not features, and skipping them is how the features above go wrong.

### 14. Mutation testing as a habit

Twice in one session a suite passed while asserting nothing real. `close()`
returns a boolean and I passed it a message as if it were an assertion, so six
checks ran and counted nothing; the count went from 552 to 558 when they were
repaired. The habit that caught it is cheap: break the thing on purpose and
confirm the suite notices. **What changes:** green stops being taken on faith.
Worth a script that mutates a named line, runs the suite and reports how many
checks died.

### 15. A check for assertions that assert nothing

The `close()` bug is mechanically detectable: a call to a predicate helper whose
result is discarded. A small linter over the test file would have found all six
instantly. **What changes:** the failure mode that produced the most convincing
wrong result in this project becomes impossible to reintroduce.

### 16. Tests that ask "how much", not "did it change"

MOTION LAG sheared the body 45 degrees and passed 465 offline checks and eight
in-game checks, because every one of them asked whether something changed and
none asked by how much. The magnitude bounds added afterwards are the pattern.
**What changes:** every option with a number in the menu gets a test tying that
number to a physical quantity and an absolute ceiling no future level can break.

### 17. Both machines running gates

The MacBook Pro runs the whole battery with the same numbers. Right now it is
idle while this machine measures. **What changes:** a full battery in half the
wall-clock, and a second opinion on anything that smells machine-specific.

### 18. A skill and a hook for the battery

The battery is seven commands run from the repo root, and the order matters.
**What changes:** one command runs it, a pre-commit hook runs the offline suite,
and neither depends on remembering. Also the place to encode "check the ruler
before trusting a measurement", which is a rule that has already been forgotten
once per session.

### 19. Retire what the harness outgrew

`tools/render/main.lua` is over 2000 lines and now holds the contact sheet, the
self-test, the metrics, the laboratory, the A/B mode and the feature extractor.
It works and it is well covered, but it is one file doing six jobs. **What
changes:** splitting it makes each job testable on its own; not splitting it
makes the next feature harder than the last. Worth doing before item 8 adds a
seventh.
