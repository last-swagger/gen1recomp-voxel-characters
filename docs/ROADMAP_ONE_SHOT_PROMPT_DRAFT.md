# Roadmap one-shot prompt draft

This is a working draft for a future one-shot prompt that should generate the
next complete Voxel Characters roadmap. It is not the roadmap itself. Its job is
to carry the research, constraints, open questions, and editorial instructions
that the roadmap generator must obey.

## How to use this draft

Give the future agent the files listed below, then paste the prompt at the end
of this document.

Minimum context files:

- `README.md`
- `CHANGELOG.md`
- `manifest.json`
- `main.lua`
- `docs/ROADMAP.md`
- `docs/ROADMAP_V2.md`
- `docs/HANDOFF.md`
- `docs/TRAPS.md`
- `docs/EXECUTION_STATE.md`
- `tests/voxel_chars_test.lua`
- `tools/bateria.sh`
- `tools/release_check.sh`
- `tools/juiz/juiz.sh`
- `tools/juiz/calibra.sh`
- `tools/render/README.md`
- `tools/render/card.sh`
- `tools/ingame/clip.sh`
- `tools/ingame/trailer.sh`

The repository is the nested git repo at `mods/voxel_characters`, not the outer
Gen1Recomp checkout.

## What the generated roadmap must be

Write `docs/ROADMAP_V3.md`, or a ready-to-paste full replacement for it.

The output should be a public project artifact in en-US. It should preserve the
project's voice: measured, concrete, skeptical of its own claims, and willing to
say "this is closed" when measurement killed an idea. It should not read like a
generic product plan.

The roadmap should be useful to three readers:

- Kim, deciding what to build or ask an agent to build next.
- A cold AI session, deciding where to start without re-learning every trap.
- A contributor, understanding why some visually tempting ideas are refused.

The roadmap should not be a diary dump. Keep the important reversals, but turn
them into decisions and lessons. Move run commands, operational traps, and daily
state into references unless they materially affect priority.

## What the previous autonomous prompt was missing

Kim supplied a previous "Autonomous Orchestrator - Continuous Execution Mode"
prompt that was strong on autonomy but too generic for this project. Preserve
its useful execution rules, but anchor them in Voxel Characters' actual traps,
tools, and validation culture.

The generated roadmap should therefore be both:

- a product/technical roadmap, explaining what should be built and why
- an execution contract, explaining how an autonomous agent should keep moving
  through that roadmap without repeatedly spending Kim's attention

The old prompt's core lessons to keep:

- Do not wait for Kim when repository evidence, experiments, docs, another
  model, or a reversible engineering decision can resolve the question.
- Treat the roadmap as a dependency graph, not a checklist.
- Use the available compute pool: local machine, MacBook Pro, CLI agents,
  subagents, tools, hooks and tests.
- Parallelize independent workstreams, but keep one owner per file or subsystem
  when conflicts would cost more than parallelism saves.
- Do not treat agent reports as truth. Integrate only after review and
  validation.
- Maintain durable execution state in the repository, because long work will
  cross context compaction, failed commands, remote-machine state and handoffs.
- Keep moving until the roadmap is complete or genuinely externally blocked.

But the generated V3 roadmap should improve on that old prompt in two ways:

1. It must name project-specific brakes. Autonomous work here has produced
   false greens, flaky gates, wrong measurements, and visually worse outputs
   that satisfied numeric constraints. Autonomy is useful only when paired with
   the project's verification culture.
2. It must say what belongs to Kim. His taste, pairwise choices, Discord posts,
   release approval and credentials cannot be simulated by more agents.

## Autonomous execution contract to include

The generated roadmap should include a short section or appendix called
something like "Execution Contract" for future loop/overnight runs.

It should cover:

- **Dependency graph:** for each roadmap tier, identify prerequisites, tasks
  that can run in parallel, and tasks that are blocked on Kim.
- **Workstream ownership:** assign work by file/subsystem where possible. Do
  not let two agents rewrite the same file at the same time.
- **Uncertainty ladder:** inspect code/docs, run experiments, consult another
  agent, cross-check against runtime/tests, make a reversible decision, document
  it, and only then escalate.
- **Definition of done:** an item is not done when code lands or an agent says
  done. It is done when the relevant gates, review, docs and runtime evidence
  demonstrate it.
- **Review discipline:** meaningful implementation needs diff review,
  spec comparison, tests, edge cases, integration points, failure behavior and
  adversarial review when the item is risky.
- **Persistent state:** update `docs/EXECUTION_STATE.md` or its successor with
  status, owners, dependencies, assumptions, evidence, blockers and next
  actions.
- **Failure recovery:** failed commands are not stopping points. Inspect,
  hypothesize, fix or choose another approach, then retest.
- **Anti-idle rule:** while LOVE, another machine, or another agent is running,
  use the time for independent review, next specs, docs, tests or research.

For this project, the contract must also include these local constraints:

- LOVE is exclusive per visible machine unless the controlled runner changes
  that.
- Visual tools should prefer the controlled runner once it exists, so Kim's
  main display and the MBP do not get hijacked by flashing windows.
- The full battery is more trustworthy than hand-running pieces, because it
  exposes intermittency.
- Mutation tests and same-procedure floors are part of verification, not polish.
- A critic/generator loop is not autonomous until calibrated against Kim's
  choices.

## Project thesis

Voxel Characters is a companion mod for the Dramatic Shape lineage of voxel
mods. The voxel world is 3D; overworld people are normally flat cards. This mod
builds each overworld character a body from the character's own runtime sprite
pixels, then gives that body controlled life: blink, breath, sway, motion lag,
footfall, and shape/shading options.

Current v1 product promise:

- No shipped character art.
- No disk mutation.
- Every on-screen character pixel remains traceable to the player's own game
  files unless a feature explicitly and honestly says otherwise.
- The mod chooses where the original pixels sit in space and how they move.
- Turning it off returns the host's flat card on the next frame.

The central aesthetic rule is not "more 3D is better." The rule is: preserve the
read of the original sprite while buying just enough volume and life for the
character to belong in the voxel world.

## Strategic permission to break the promise

The v1 promises are not sacred. They were useful because they kept the project
honest while it proved that runtime sprite pixels could carry convincing volume
and life. For v2, Kim is explicitly willing to break any of them if doing so is
the path to the roadmap's higher purpose: characters that feel alive, authored,
and worth looking at in the voxel world.

The promise with the most upside to break is **no shipped character art**. It is
also the one that should be treated most deliberately, because it changes the
mod's identity from "purely derives from your ROM" to "adds an authored
character presentation layer." That is not a defect if the roadmap names it
plainly and earns it.

The generated roadmap should therefore treat shipped art as a legitimate v2
research axis, not as a forbidden idea. Possible forms:

- Small shipped overlays: eyes, highlights, facial details, rim accents,
  material masks, or region masks that guide shading without replacing the
  sprite.
- Per-sheet authored metadata: region maps for head, body, hair, bag, feet,
  living vs object, responsiveness, and deformation weights.
- Optional enhanced sprite assets: artist-made additions that improve faces,
  side surfaces, or readable motion, with fallback to pure runtime generation.
- Training/reference assets for a generator or critic, if the output is judged
  against Kim's picks and in-game footage rather than numeric gates alone.
- A separate "authored mode" that can coexist with the v1 pure mode, so the
  old promise remains available while v2 is free to chase a stronger result.

Breaking a promise still needs a gate. The roadmap should ask:

- What player-visible gain does this buy that runtime-only geometry cannot?
- Is the shipped art optional, fallback-safe, and clearly disclosed?
- Does it improve Kim's pairwise judge results and real in-game clips?
- Does it create a maintenance burden per sheet, per host fork, or per game
  version?
- Does it make the mod feel more like itself, or just like a generic remaster?

This is the key reframing: **preserving original pixels is a constraint that
served v1, not the purpose of v2.** If the constraint blocks a more alive,
better-directed character, the roadmap should be allowed to break it.

## What is released

v1.6.0 is released. It is installable from inside the game and visible to the
updater because releases now carry a `.zip` asset, not only `.modpkg`.

README-visible options include:

- `VOXEL CHARS`
- `SIDE COLOR`
- `SHAPE`
- `GROUND SHADE`
- `BLINK`
- `TOP EDGE`
- `FRONT SHAPE`
- `TOP DOME`
- `STEP WEIGHT`
- `BREATH`
- `SWAY`
- `MOTION LAG`
- `FOOTFALL`

The public README states that `BLINK` and `BREATH` are on by default, with
`BREATH` at `SUBTLE`.

## Current branch and state

The active repo is `mods/voxel_characters`, branch `vida-v2`.

Treat all local changes as deliberate user work. Do not rewrite files just to
make the prompt cleaner. The generated roadmap should reconcile state from the
docs; it should not assume the outer Gen1Recomp repo knows anything about this
mod's git history.

Known local state observed while drafting this prompt:

- Branch: `vida-v2`
- Recent commits include work on critic calibration, lab host settings, lock
  reentrancy, trailer completion, generator loop, and execution state.
- At the time of reading, local modifications existed in `main.lua`,
  `tools/ingame/clip.lua`, and `tools/ingame/clip.sh`.

## Proven technical facts to preserve

### Mesh and rendering channel

The host asks for a mesh per character frame and draws it with
`Voxel3D.draw(mesh, texture, model, pull, sunModel)`.

A stable per-instance identity can be derived at draw time from the model
matrix. `model[12] - 8` returns world `py` exactly in tested host lineages and
is stable under mirror, camera rung, walking, and camera movement. This is why
the life channel can desynchronise identical NPCs even when they share a mesh.

The animation channel should not rewrite static vertex buffers per frame. The
better path already exists: multiply a small transform into the per-instance
model matrix. This avoids the old static-buffer risk entirely and made the
measured runtime cost smaller than the ruler's noise floor.

The instance tracker advances phase by clock, not by position. Position seeds
identity; it does not drive breathing speed.

### Shape limits

Every unit of depth exposes surface the original artist did not draw.

Measured on `red.png` in the earlier roadmap:

```text
flat card    100% of drawn pixels are artist work
SLAB          73%
CARVED        31%
```

The exact values depend on camera and measurement setup, but the law is stable:
top and side faces spend invented surface.

Shape-from-silhouette cannot reconstruct concavities such as armpits, gaps
between arms and torso, or spaces between legs. It returns the largest volume
compatible with the silhouettes.

SLAB is not inferior to CARVED for this game. SLAB preserves the front face and
works with the camera the game actually uses. CARVED is useful when
camera-independent volume matters, but it creates many more upward-facing faces
and trades away the clean read of the sprite.

### First person

FIRST PERSON: SOLID is valuable only during the transition. At full first-person
blend, the host hides the player's own card and the measured effect goes to
zero by blend 0.83. The release notes must not imply a solid body you can walk
around at settled first person.

The effect peaks during the transition, where it still matters: the player's
own body used to collapse to a flat card exactly when the camera came closest.

### Grid

The host grid is not ours to add. The host deliberately disables seams around
the character pass with `Voxel3D.seams(false)`, because the world should read as
voxel-built and the people should read as drawn. Measurements showed the grid
does not touch the character mesh. Preserve this as a closed decision unless a
new measurement overturns it.

### Weather and wind

No weather source exists to consume. The host has day/night but not weather.
`DayNight.shearAt(t)` is shadow shear, not wind, even though its units resemble
the life channel's shear input.

Do not call a sun or moon shadow vector "wind." If wind is ever wanted, it must
be invented as this mod's own state with its own reason to vary.

Time of day, however, is readable and settable, and it already unblocked trailer
shot variety.

### Battle art

Using battle art to enrich overworld characters is closed: battle sprites do not
have a walk cycle and exist in the wrong view set for overworld motion. The
separate question of rendering battles themselves remains parked, not killed.
The cheap first step for battles is a capability probe of the battle path.

### Yaw

Never rotate characters in Y until side-face art is solved. Side faces carry
0.0% of the artist's art. Attention and anticipation must use lean, scale,
shear, timing, hysteresis, and spring response, not yaw.

### Per-part motion

Body-wide inertia ships. Real hair, bag, or head lag is not a draw-range trick.
It needs region identity in the mesh and per-region state at draw time.

Known blockers:

- Interior cut rows have no cap faces unless the builders emit them.
- SLAB emission is not a simple contiguous prefix split, because side runs are
  accumulated and emitted after scanning.
- The mesh is shared between instances, so state cannot live on the mesh object.
- Existing life state is per character, not per region.
- `ourMeshes` knows a mesh is ours; it does not know which vertices are hair,
  head, body, bag, or cap.

Also preserve the correction: the old shadow blocker was invented. The shadow
pass draws the original flat `SpriteBillboards.shadowQuad`, not this mod's slab.

### Judge and critic

The judge exists because numeric gates alone can reward worse art. An AI redraw
once satisfied the numeric constraints and produced a worse result. Human
pairwise picks are the missing ground truth.

The judge should be treated as a gating system, not as a magic taste oracle.
The critic/generator loop cannot drive work until the critic beats a simple
baseline on Kim's own previous picks.

Important measured state from `EXECUTION_STATE.md`:

```text
model with four tonal features: 78.7%
best single column baseline:    69.6%
margin:                         +9.1
spread:                          4.0
```

But also preserve the later critic calibration warning:

```text
round 1   critic 42.9%   always-B 57.1%
round 2   critic 62.5%   always-B 62.5%
```

Interpretation: the judge improved after better features and more honest cross
validation; the visual critic is not yet good enough to steer autonomous
generation.

### Release assets and communication

Release work should include media. The project now has:

- side-by-side clips
- a trailer tool
- an explainer card format
- release checks that validate the package through the game's own updater path

Kim posts to Discord. Agents prepare drafts and artifacts.

## Known contradictions to reconcile

The generated roadmap must explicitly resolve or footnote these, not silently
choose the easier version:

1. `ROADMAP_V2.md` says "DONE: the judge is fed and it works," but
   `EXECUTION_STATE.md` still lists "30 A/B picks" as blocked on Kim while also
   saying Kim made 106 choices. The likely resolution is that the first judge
   dataset exists, but another round of picks is still needed for the next
   calibration/generator phase.
2. `ROADMAP_V2.md` says "DONE: the project is en-US," while
   `EXECUTION_STATE.md` says remaining shell scripts and `tools/juiz` were still
   in flight. The roadmap should distinguish "the decision is done" from "all
   files are translated."
3. `ROADMAP_V2.md` says item 4's four trailer defects all landed, while
   `EXECUTION_STATE.md` may lag or mention verification. Use the newest commit
   history and current files if available.
4. `ROADMAP.md` keeps old Portuguese correction text and older claims about
   emission order that `ROADMAP_V2.md` corrects. Prefer the corrected V2
   version and keep the earlier text only as history.
5. Item numbering is confusing: risk item `0` appears after tier 3, and item
   `20` exists twice. A V3 roadmap should keep the facts but make the structure
   readable.

## Open work to prioritize

Use this as the starting set. Reorder if the source files show newer evidence.

### Authored character layer

This is the new strategic opening. The roadmap should not assume v2 must remain
pure runtime derivation. It should define the smallest experiment that tests
whether shipped or authored character material beats the current promise.

Recommended first experiments:

- one or two shipped overlay/mask types, not a full replacement art pack
- one living character and one object sheet, so the rule does not accidentally
  make item balls or boulders alive
- pure-runtime mode kept as the control
- A/B clips and judge pairs built from the same scenes
- a release-note disclosure draft that says exactly what is now authored

The question is not "can we ship art?" Kim already authorises that. The question
is "which authored layer buys visible life without making the mod feel like a
generic remaster?"

### Release identity and release pipeline

The project needs the next real release to be authored by `last-swagger`, with a
zip asset visible to the in-game updater, release media attached, and
`release_check.sh` green. Publishing remains blocked on Kim's personal access
token and explicit permission.

The roadmap should separate:

- rehearsal/build verification, which agents can do
- actual publishing/tagging, which needs Kim

### Judge v2 and generator loop

The loop should not be "generate endlessly and trust the critic." It should be:

1. Gather or reuse Kim pairwise picks.
2. Extract mesh and pixel/provenance features.
3. Train or update the judge.
4. Calibrate a visual critic against held-out Kim picks.
5. If the critic beats baseline by a meaningful margin, let it pre-filter.
6. Show Kim only finalists or uncertain pairs.

Roadmap this as a research loop with gates, not as a feature.

### Per-part secondary motion

This is high-value but high-risk. The V3 roadmap should define the smallest
honest research step, not jump straight to "hair and bag physics."

Recommended first step:

- Add region labels to the builder output for one mode and one sheet.
- Visualize those regions in the lab.
- Prove cap faces are correct at region boundaries.
- Prove blink and UV edits still localize after emission changes.
- Only then draw two regions with separate matrices.

### Attention and anticipation

This is probably the next player-visible feature with a strong value/risk
ratio, but it must obey the no-yaw rule.

Define it as posture response:

- lean toward player, not rotate toward player
- hysteresis between notice and release radii
- damped spring, no snap
- personality multipliers for responsiveness
- no effect for item balls, boulders, and other non-living sheets
- conservative default off

### Laboratory

The lab should become the decision surface for the next visual work:

- region overlays
- cap-face visualization
- host settings such as grid, shade, camera rung, first-person blend
- A/B recording
- reproducible recipes for variants

Tie the lab to items 9, 10, and judge/generator work.

### Battle rendering probe

Keep it parked, but make the parked state actionable. The first milestone is
not "make battle sprites voxel." It is:

- find the battle draw path
- identify whether a safe patch seam exists
- render a harmless probe
- decide from evidence whether battle rendering deserves a roadmap

### Local headroom and file structure

LuaJIT chunk local headroom is real but not urgent. Keep the gate. Do not
propose a broad refactor unless headroom drops toward the floor or a concrete
feature needs it.

### Controlled visual runner

The visual tools are useful partly because they are visible: they film the game,
exercise real menus, and make bad states obvious. But on Kim's main machine and
on the MacBook, a wall of flashing LOVE windows also steals the computer from
the person using it.

The roadmap should include a controlled execution environment for render,
clip, trailer, and in-game gates. This is both a workflow improvement and a
measurement improvement: fewer foreground windows means fewer accidental
interruptions, fewer occluded-vsync traps, and fewer "rerun it because I was
using the machine" results.

Research order:

- **Headless first:** run non-interactive LOVE gates under Linux LOVE in Docker
  with `xvfb` and software GL/Mesa, writing screenshots, videos and logs to a
  mounted output directory.
- **Inspectable second:** expose the same runner through VNC/noVNC or a saved
  mp4/GIF stream, so Kim can watch it when useful without it flashing on the
  main display.
- **Mac-native fallback:** for cases where Linux LOVE or software GL changes
  output, run in a separate macOS user session, Space, display, or remote MBP
  screen rather than the active desktop.
- **Final visual judgement:** do not bless final screenshots or trailer shots
  only from a different renderer until the Docker/macOS delta has been measured.

The goal is not "hide the tools." The goal is "let the tools be visual without
owning the primary screen."

### Tests and gates

Preserve the hard-learned testing rules:

- A gate is not verification until it fails on input that should fail.
- Do not lower thresholds to make flaky gates green.
- Measure a floor with the same procedure before trusting a pixel or timing
  threshold.
- Run the full battery as one command to expose intermittency.
- Mutation testing is not optional for visual math and test helpers.
- Tests should ask "how much" and "which direction," not only "did it change."
- Every roadmap item should state what evidence would make it done.

### Autonomous orchestration

The old mega prompt's autonomy rules should become local project practice, not
a standalone wall of generic instructions. Add a roadmap item or appendix that
turns them into Voxel Characters conventions:

- dependency-aware scheduling for tiers and workstreams
- persistent state updates after each meaningful batch of work
- a standard "blocked on Kim" table that agents are not allowed to work around
- a standard "reversible decision" rule for implementation choices
- adversarial review for visual math, release tooling, gates and any change
  that weakens or breaks a v1 promise
- anti-idle behavior during long LOVE runs, remote MBP runs, Docker jobs or
  delegated agent work

## Refused ideas, and promises that can be renegotiated

Do not roadmap these unless new measurements overturn the recorded evidence:

- adding voxel grid seams to characters
- calling day/night shadow shear "wind"
- using battle art to improve overworld walking characters
- turning characters in yaw to face the player
- geometry bevels that break silhouette IoU
- trusting an uncalibrated visual critic
- per-frame static-buffer rewrites when model-matrix animation works
- lowering a threshold to hide a flaky gate
- publishing from an agent without Kim's word

These are no longer absolute non-goals, but they need an explicit v2 argument:

- shipped character art
- authored region masks
- procedural or AI-assisted character detail
- higher-resolution or enhanced character presentation
- breaking the pure-runtime promise when the result is visibly better

## Style rules for the generated roadmap

- Public artifact: write in en-US.
- No em dashes in release/public-facing copy if the roadmap discusses that
  standing rule.
- Keep concrete measurements, commands, and file references where they decide a
  point.
- Prefer "State / What changes / Cost / Gate" for each item.
- Distinguish "done", "closed by measurement", "parked", "blocked on Kim", and
  "open implementation".
- Do not phrase closed items as backlog tasks.
- Do not bury important corrections. If an old premise was wrong and the
  correction changes the plan, say so.
- Avoid generic roadmap language like "enhance immersion" unless tied to a
  specific observable behavior.

## Desired roadmap shape

Recommended structure:

1. Title and one-paragraph thesis.
2. Current state: v1.6.0 released, `vida-v2` unreleased, what is proven.
3. Decisions already closed by measurement.
4. Blocking inputs from Kim.
5. Tier 0: release safety and project foundations.
6. Tier 1: visual judgement and tooling loops.
7. Tier 2: next player-visible capability.
8. Tier 3: research probes.
9. Parked/refused ideas with reasons.
10. Autonomous execution contract.
11. Testing rules and operational constraints.
12. Appendix: commands and source files.

## The one-shot prompt

Paste this prompt into the future agent after providing the context files:

```text
You are helping write the next full roadmap for Voxel Characters, a nested
Gen1Recomp mod repo at mods/voxel_characters.

Your task is to produce docs/ROADMAP_V3.md as a public en-US project artifact.
It should be a roadmap, not a diary, but it must preserve the measurements and
corrections that determine priority. The mod's voice is concrete, technical,
skeptical, and measured. Do not write a generic product plan.

Read and reconcile these source files:

- README.md
- CHANGELOG.md
- manifest.json
- main.lua
- docs/ROADMAP.md
- docs/ROADMAP_V2.md
- docs/HANDOFF.md
- docs/TRAPS.md
- docs/EXECUTION_STATE.md
- tests/voxel_chars_test.lua
- tools/bateria.sh
- tools/release_check.sh
- tools/juiz/juiz.sh
- tools/juiz/calibra.sh
- tools/render/README.md
- tools/render/card.sh
- tools/ingame/clip.sh
- tools/ingame/trailer.sh

Important: docs disagree in places because the same day of work changed the
facts. Do not silently average them. Resolve contradictions explicitly from the
newest evidence, commit history if available, and current files. In particular:

1. The judge is both described as done and still blocked on new Kim picks.
   Resolve this as "initial judge dataset works; next generator/critic phase
   still needs fresh or targeted picks" unless the files prove otherwise.
2. The en-US project conversion is described as done, but state files mention
   remaining scripts/tools. Distinguish decision complete from file coverage.
3. Item 20 appears twice and item 0 appears late. Keep the facts, repair the
   structure.
4. ROADMAP.md contains older claims that ROADMAP_V2.md corrects. Prefer the
   corrected version and retain only useful history.

Roadmap facts you must preserve:

- Voxel Characters v1 does not ship character art or mutate game files. It
  builds body geometry from runtime sprite pixels and animates transforms.
- Kim is explicitly willing to break any v1 product promise in v2 if that is
  what best serves the roadmap's higher goal. The most valuable promise to
  challenge is "no shipped character art."
- The central aesthetic rule is not "more 3D is better." Preserve the original
  sprite read while buying enough volume and life for the voxel world, unless
  an authored v2 layer proves it can do better by eye and by judge.
- Depth creates top/side surface the artist never drew. SLAB is often the right
  answer for this game; CARVED is not a quality ladder.
- The life channel works by per-instance model-matrix transforms, not by
  rewriting static buffers per frame.
- `model[12] - 8` proved to be stable world py for instance identity in the
  tested host lineages.
- FIRST PERSON: SOLID is valuable during transition and zero at settled full
  blend; do not imply otherwise.
- The host grid deliberately does not draw seams over characters. Treat this as
  closed.
- There is no weather source to read. Day/night shadow shear is not wind.
- Battle art does not help overworld walking characters; battle rendering
  itself is only parked pending a draw-path probe.
- Never rotate characters in Y until side-face art exists.
- Per-part secondary motion requires region identity and builder changes; it is
  not a draw-range trick.
- The judge/generator loop must be calibrated against Kim's choices before any
  critic drives autonomous work.
- Release publishing needs Kim's explicit approval and the `last-swagger`
  credential; rehearsal and verification can be automated.
- V3 should include an autonomous execution contract, adapted from Kim's older
  orchestrator prompt but grounded in this mod's tools, traps and gates.

Open work to organize:

- authored character layer: shipped overlays, masks, metadata, or enhanced mode
  as a legitimate v2 research axis
- release identity and one-command release pipeline
- judge v2, pixel/provenance features, generator and critic calibration
- per-part secondary motion research
- attention and anticipation with no yaw, using spring/hysteresis
- laboratory as the visual decision surface for regions and host settings
- battle rendering capability probe
- LuaJIT local-headroom gate and only-if-needed refactor
- remaining en-US/project accessibility work if current files show it is not
  actually complete
- controlled visual runner: Docker/xvfb/noVNC or macOS-isolated execution for
  LOVE gates, clips and trailer tools
- autonomous orchestration contract: dependency graph, workstream ownership,
  persistent state, definition of done and anti-idle loop rules
- testing and operational gates: battery, mutation tests, same-procedure
  floors, and full-run intermittency

Do not roadmap these as open work unless new evidence overturns them:

- voxel grid seams on characters
- weather/wind from host state
- battle art as overworld input
- yaw-facing NPC attention
- geometry bevels that break silhouette IoU
- trusting an uncalibrated critic
- lowering thresholds to make a flaky gate pass

Do treat these as legitimate v2 research axes, not forbidden territory:

- shipped character art, especially small authored overlays or masks
- optional enhanced mode beside the pure runtime mode
- per-sheet authored metadata for regions, deformation and personality
- procedural or AI-assisted detail, but only if calibrated against Kim's picks
- higher-resolution character presentation, if it improves the in-game read
  without making characters feel disconnected from the voxel world

Write the roadmap with this structure unless the source files demand a better
one:

1. Title and thesis.
2. Current state.
3. Decisions closed by measurement.
4. Inputs blocked on Kim.
5. Tier 0: release safety and project foundations.
6. Tier 1: judge, lab, and communication tooling.
7. Tier 2: next player-visible capabilities.
8. Tier 3: research probes and parked work.
9. Autonomous execution contract.
10. Cross-cutting testing rules and operational constraints.
11. Appendix: commands and files.

For each roadmap item, include:

- State
- What changes
- Cost or risk
- Gate/evidence required before it counts as done

Also include an execution contract for future loop/overnight runs:

- roadmap as dependency graph
- what can be parallelized
- what is blocked on Kim
- available compute pool and controlled visual runner
- uncertainty ladder before escalating to Kim
- definition of done
- persistent execution state file
- review/adversarial-review requirements
- anti-idle rule while commands, agents or remote machines run
- rule that delegated reports must be verified before integration

The output should be ready to save as docs/ROADMAP_V3.md. Keep the language
clear enough for contributors, but do not flatten the project's technical
judgement. This roadmap should help a cold agent build the right next thing
without re-learning the same traps.
```
