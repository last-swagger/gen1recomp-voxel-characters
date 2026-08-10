# Execution state

Durable state for autonomous execution of `ROADMAP_V2.md`. Written so that a
session that starts cold, or a second orchestrator, can pick up without asking
anyone. Updated as work lands, not as work is planned.

**Started 2026-08-10.** Branch `vida-v2`, nothing pushed.

## The two constraints that shape all scheduling

1. **LOVE is exclusive per machine.** `tools/tools_bin.sh` holds a lock, so only
   one tool per machine can render at a time. Two workstreams that both need
   LOVE must be on different machines, or serialised.
2. **A file has one owner at a time.** Isolated file scope is what made three
   parallel batches land with zero conflicts before. Every dispatch says
   explicitly what it may NOT touch.

## Compute pool

| Resource | Has LOVE | Used for |
|---|---|---|
| Mac Studio (this session) | yes | orchestration, LOVE work, integration |
| MacBook Pro (`ssh mbp`) | yes | second LOVE workstream, full battery |
| Subagents (Studio) | no | text-only work: translation, tests, scripts |
| `codex`, `gemini` CLI | no | independent review, second opinion |

MBP dispatch goes through the GUI session (`osascript` into Terminal), never
plain ssh: the CLI keeps credentials in the login Keychain and an ssh session
cannot unlock it. Symptom is "OAuth session expired", which is not an expired
token.

## The judge works now (2026-08-10, late)

Kim made 106 choices. The loop that followed is the clearest example in this
repository of why using a tool beats reviewing it:

| step | model | best column | margin | spread |
|---|---|---|---|---|
| as built | 73.7% | 63.2% | +10.5 | not measured |
| composition by AREA not quad count | 73.6% | 70.6% | +3.0 | 6.4 |
| plus four tonal features | **78.7%** | 69.6% | **+9.1** | **4.0** |

The first row was the model leaning on an artefact: composition features were
fractions of QUAD COUNT, so FRONT SHAPE inflated them by splitting runs without
moving a vertex. Fixing it did not make the model worse, it made the baseline
honest.

The middle row was measured with cross validation replacing a 19-sample
holdout whose learning curve swung 26 points on its own. That change is what
made the third row provable rather than hopeful.

**What it says, over 45 sheets, comparing best against worst inside each
sheet:** `top_edge on` (8), `blink on` (7), `front_shape 0.22` (6),
`top_dome 0.15` (4), `slab over carved_plus` (4). FRONT SHAPE and TOP DOME both
ship OFF. `depth`, `ground_shade` and `side_color` win in both directions,
which is the model saying it depends on the character.

## Blocked on Kim, not worked around

| Item | What is needed | Why nobody else can |
|---|---|---|
| 1. Feed the judge | 30 A/B picks | It is his preference. That is the whole input. |
| 3. Release identity | PAT for `last-swagger` | Credential. `release_check.sh` is red on purpose. |
| Visual judgement | His eye on FOOTFALL, CAMERA FIT, FRONT SHAPE, TOP DOME, STEP WEIGHT | Taste, and he is the one who ships it. |

Everything else in the roadmap is executable without him.

## Workstreams

| # | Item | Owner | State | Evidence |
|---|---|---|---|---|
| A | 19. Split the harness | MBP | **landed** 1b50c21 | ruler output identical on all 31 lines except the one the floor showed varies |
| B | 2. en-US, `main.lua` | subagent | **landed** f9d9c6b | comments-only gate, 603/603, volume +2% |
| C | 2. en-US, tests | subagent | **landed** a13408e | comments-only gate proves every test name byte identical |
| D | 2. en-US, in-game drivers | subagent | **landed** c59d82f | gate on all ten, volume +4 to +8% |
| E | 14/18. mutants, battery, hooks | this session | **landed** 3e59cee | battery caught a flaky gate on its first run |
| F | 13. Wind and weather | subagent | **closed** 6d001e0 | nothing publishes weather; verified in host source |
| G | Adversarial review | subagent + codex | **findings fixed** 6c1d4db | 2 blocking, both reproduced, both fixed |
| H | 24. Menu gate was flaky | this session | **landed** b5438b1 | failed 3 of 5, now 4 of 4 with 2-4x margin |
| I | 4. Trailer: time of day | this session | verifying | day vs night measured at 14 dB PSNR |
| J | 2. en-US, `tools/` | MBP | **nearly done** | ruler output identical after translating the ruler itself |
| K | 16. MOTION LAG direction | subagent | **landed** e6e7913 | the surviving mutant now dies; 603 -> 607 |
| L | 24. First-person gate | this session | **landed** ee70241 | discarded on blends but not on its own floor |
| M | 21.1 release.sh | this session | **landed** bb49937 | rehearsed end to end; refuses without a changelog section |

## Three gates were intermittent, and the battery is what exposed all three

None of them had ever been caught, because each was run by hand, and a human
who sees a red re-runs it. A green rerun ends the investigation.

| Gate | Failure rate | Cause | Fix |
|---|---|---|---|
| menu M8 | 3 of 5 | measured PHASE: two photographs a fixed 46 frames apart, so the number depended on where in the breathing cycle they landed | sweep a full period, keep the largest difference |
| probe_fp P4 | 2 of 4 | used a sample whose own control floor was half the frame, so the signal was that movement plus the option | discard a sample whose floor exceeds 5% |
| (both) | | thresholds were NOT lowered in either case | the number was never the problem |

**And in both cases the fix was verified by measuring again, four runs each,
not by running it once and seeing green.** probe_fp's discard was additionally
proved by forcing its limit to -1 and confirming every sample is dropped with
the right message: a branch nothing exercises looks exactly like one that
works.

## Roadmap items closed or advanced, 2026-08-10

| Item | Was | Now |
|---|---|---|
| 2. en-US | not started, ~3900 lines | `main.lua`, tests, in-game drivers, harness modules done. Remaining: shell scripts and `tools/juiz`, in flight. |
| 4. Trailer | 6/10, four things missing | Two landed and both cost one line: time of day per shot, camera movement within a shot. Two remain. |
| 13. Weather | "depends on mods we do not control" | **Closed.** Nothing publishes weather; the host says so in its own changelog. |
| 14. Mutation testing | "worth a script" | **Built, and its first run found a hole in the suite.** |
| 18. Battery skill/hook | seven commands to remember | **One command**, plus a pre-commit hook. |
| 19. Split the harness | 2723 lines, six jobs | **1415 lines**, graded by output equality against a measured floor. |
| 21.1 release.sh | missing | **Built**, rehearsal by default. Publishing still blocked on the token. |
| 24. Flaky gates | one known instance | **Second instance found and fixed**; the menu gate was measuring phase. |
| 26. Explainer card | did not exist | **Built**, four ruler checks, two blocking defects found by review and fixed. |

## What is still open, and why

- **1 and 3 are Kim's**, and nothing here can substitute: thirty A/B picks and a
  personal access token.
- **9, 10, 11** are visual changes. They need his eye before they mean
  anything, and the house rule is that a new visual change ships off by default
  anyway.
- **0** is measured and gated at 41 locals of headroom. Not urgent, and the
  gate will say so the day it becomes urgent.
- **16** turned out to be mostly covered: there is an absolute safety ceiling
  that sweeps every life option at maximum and requires no term to exceed 3
  pixels of world. The remaining hole is that the ceiling test writes those
  maxima by hand instead of reading them from the mod's own OPTIONS table, so a
  new, stronger level would not be covered by it.

## The pattern worth carrying forward

**Every defect found today was found by running something against real input,
not by review of the idea.** The comment gate looked right three times and was
wrong three times. The battery found a flaky gate on its first full run that
months of running the pieces by hand had not, because a human who sees a red
re-runs it and a green rerun ends the investigation.

**Independent review earned its cost twice.** A different model family
(codex) found a false pass in the comment gate that nineteen of my own
adversarial cases missed. A Claude reviewer found two blocking defects in the
card tool, both with a reproduction, both in the artefact that goes into
release notes.

**And an agent following the documented command literally found the worst
defect of the day**: the comment gate exited 0 without comparing a byte when
given the path spelling the docs used.

## What landed

- **26. Explainer card** (4c5ecc7): `mode=card` plus `card.sh` and a recipe.
  Refuses identical halves. Four ruler checks.
- **26b. Neighbour AO** (593bafc): measured and closed. Zero pixels head on.
- **14/18. Battery, mutants, comment gate** (3e59cee): one command for the
  battery in the order that makes a failure mean something, five declared
  mutants, a pre-commit hook.
- **The comment gate, twice fixed** (6d001e0, f1ec189). Both fixes matter more
  than the tool: see below.
- **13. Weather** (6d001e0): investigated, closed. Nothing publishes weather,
  and the host says so in its own changelog. Time of day IS settable, which
  turns item 4's "variety in time of day" into one call.

## Two defects found in my own gate, in the order they matter

1. **False PASS on a bare CR.** LuaJIT accepts a lone `\r` as a line break; the
   comment stripper only looked for `\n`, so a comment swallowed the next line
   of real code and two files with different code compared equal. Found by an
   independent review (codex) after nineteen hand-written adversarial cases
   missed it. Different model, different blind spot: worth repeating.
2. **False ALARM on every real translation.** It compared line k to line k,
   which assumed a translation preserves line count. It does not. Against the
   real in-progress translation it reported 2697 changed lines, all of them the
   same code one row lower. **This is the worse of the two**: a gate that
   misses something gets found out; a gate that cries wolf on correct input
   gets waived by the second day and is not there when it matters.

Both are permanent test cases now, 27/27. And the lesson that produced the
second one: the nineteen invented cases were all one line long, which is
exactly why every one of them passed.

## Also learned, and it cost time three times today

**The offline suite only runs from the repo root**, because its
`require("tests.love_stub")` resolves against the current directory. From
anywhere else it dies without counting a check, and `tail -1` reduces that to a
hex address that says nothing. `mutantes.sh` invoked it with no `cd`, which
would have reported every mutant as killed: the report claiming the tests are
perfect at the exact moment it measured nothing. Fixed in both tools and
verified from a foreign directory. **The real fix belongs in the test file**
(resolve the stub relative to `arg[0]`), and is queued behind workstream C.

## Decisions taken without asking

- **Item 2 starts with `main.lua` and the tests, not the harness**, because
  workstream A is rewriting the harness and two owners on one file is the one
  thing that reliably produces conflicts. The roadmap already recommended this
  order for a different reason.
- **A comments-only diff is verified mechanically, not by review.**
  `tools/so_comentarios.lua` strips comments and string literals from both
  sides and requires the remainder to be byte identical. A translation that
  touches code fails the gate rather than depending on someone noticing.
- **The harness split is graded by output equality, not by structure.** The
  ruler's 19 result lines before and after must match. A split that is tidy and
  changes a number is a regression.

## Assumptions logged

- The MBP's git identity is fixed, but commits arriving from it are still
  amended to `last-swagger` before being kept, because old commits are not.
- Nothing is pushed, tagged or released. Local commits on `vida-v2` are routine
  and are what every workstream produces.
